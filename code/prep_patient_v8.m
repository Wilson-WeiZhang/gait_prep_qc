function prep_patient_v8(input_file, out_dir, max_step, out_label, skip_trim, marker_set, opts)
%% prep_patient_v8 -- Patient EEG preprocessing pipeline V8
%
% Pipeline (V8, 2026-04-13, unified with healthy):
%   Step 0 (if .set from merge): already loaded
%   Step 1: Load -> chanlocs -> 59ch whitelist -> Resample 250Hz
%           -> BP 1-40Hz -> Trim -> save step1_ica.set
%           -> BP 0.1-40Hz -> Trim -> save step1.set
%   Step 2: (on step1_ica) Extract task+rest segments ->
%           Bad ch detection -> Interpolate -> +Cz zero-fill -> CAR (60ch) ->
%           ASR(k=20, S2S+Walk2min only) -> AMICA(1 model, 1000 iter)
%           -> save step2.set
%   Step 3: Transfer ICA to step1.set (0.1Hz) -> same bad ch interp + +Cz+CAR
%           -> ICLabel -> reject artifact>0.8 -> save step3.set (0.1-40Hz, 60ch)
%   Step 4: Epoch by trial type -> save epochs.mat
%
% Usage:
%   prep_patient_v7('/path/to/file.vhdr', '/path/to/output/')
%   prep_patient_v7('/path/to/merged.set', '/out/', 4, 'P01_Sess01', true, 'patient_legacy')
%   prep_patient_v7('/path/to/file.vhdr', '/out/', 2)  % bad REF: stop at step2
%   prep_patient_v7('/path/to/file.vhdr', '/out/', 4, 'P02_Sess04', false, ...
%       'patient', struct('corr_thresh', 0.7, 'bad_ch_limit', 15, ...
%       'ica_method', 'runica', 'test_bad_ch_thresholds', [0.8 0.7 0.6]))
%
% Input:
%   input_file -- .vhdr or .set (merged)
%   out_dir    -- output directory
%   max_step   -- stop after this step (1–4). Default: 4. Use 2 for bad REF.
%   out_label  -- custom label. Default: derived from filename
%   skip_trim  -- skip S11-S12 trimming. Default: false
%   marker_set -- 'patient' (standard) or 'patient_legacy' (Sub01 Sess01-02)
%   opts       -- optional overrides:
%                .corr_thresh (default 0.8)
%                .bad_ch_limit (default 10)
%                .ica_method ('amica' default, or 'runica')
%                .amica_num_mod (default 1)
%                .amica_max_iter (default 1000)
%                .test_bad_ch_thresholds (default [])
%
% Trial definitions:
%   patient:        MI (S1->S2), S2S (S4->S5), Walk2min (S7 + 120s fixed)
%   patient_legacy: MI (S1->S2) only
%   ASR targets: S2S + Walk2min
%
% Dependencies: EEGLAB 2024.2, clean_rawdata, AMICA, ICLabel

%% ======================== Setup ========================
if nargin < 3 || isempty(max_step),   max_step = 4;        end
if nargin < 5 || isempty(skip_trim),  skip_trim = false;    end
if nargin < 6 || isempty(marker_set), marker_set = 'patient'; end
if nargin < 7 || isempty(opts),       opts = struct();      end

bp_ica_lo = 1;    bp_ica_hi = 40;
bp_out_lo = 0.1;  bp_out_hi = 40;

opts = normalize_opts(opts);

corr_thresh          = opts.corr_thresh;
bad_ch_limit         = opts.bad_ch_limit;
ica_method           = opts.ica_method;
amica_num_mod        = opts.amica_num_mod;
amica_max_iter       = opts.amica_max_iter;
test_bad_ch_thresholds = opts.test_bad_ch_thresholds;

switch marker_set
    case 'patient'
        trial_defs = {
            'S  1', 'S  2', 'MI',       false
            'S  4', 'S  5', 'S2S',      true
            'S  7', 120,    'Walk2min', true
        };
    case 'patient_legacy'
        trial_defs = {
            'S  1', 'S  2', 'MI', false
        };
    otherwise
        error('Unknown marker_set: %s', marker_set);
end
n_trial_types = size(trial_defs, 1);

% 59 brain channels: same montage as healthy, but swap FCz/Cz role
% Healthy: online ref = FCz (excluded), Cz = data channel (included)
% Patient: online ref = Cz (excluded), FCz = data channel (included)
brain_whitelist = {'Fp1','Fz','F3','F7','FC5','FC1','C3','T7','CP5','CP1', ...
    'Pz','P3','P7','O1','Oz','O2','P4','P8','CP6','CP2', ...
    'C4','T8','FC6','FC2','F4','F8','Fp2', ...
    'AF7','AF3','AFz','F1','F5','FT7','FC3','FCz','C1','C5','TP7', ...
    'CP3','P1','P5','PO7','PO3','POz','PO4','PO8','P6','P2', ...
    'CPz','CP4','TP8','C6','C2','FC4','FT8','F6','AF8','AF4','F2'};
% Cz (online ref) zero-filled back after interp -> 60ch identical to healthy
brain_whitelist_full = [brain_whitelist, {'Cz'}];  % 60ch

if ispc
    eeglab_path = 'C:\Users\Admin\OneDrive - Nanyang Technological University\matlabsoft\eeglab-eeglab2024.2';
elseif ismac
    eeglab_path = '/Users/zw/Desktop/eeglab-eeglab2024.2';
else
    eeglab_path = '/home/wilson/eeglab2024';
end
addpath(eeglab_path); eeglab nogui;

if ~exist(out_dir, 'dir'), mkdir(out_dir); end

[in_dir, in_name, in_ext] = fileparts(input_file);
if nargin < 4 || isempty(out_label)
    label = in_name;
else
    label = out_label;
end

fprintf('\n============================================================\n');
fprintf('=== %s -- Patient V8 (%s, max_step=%d, ICA=%s, corr=%.2f) ===\n', ...
    label, marker_set, max_step, upper(ica_method), corr_thresh);
fprintf('============================================================\n');

file_step1_ica = fullfile(out_dir, [label '_step1_ica.set']);
file_step1     = fullfile(out_dir, [label '_step1.set']);
file_step2     = fullfile(out_dir, [label '_step2.set']);
file_step3     = fullfile(out_dir, [label '_step3.set']);
file_step4     = fullfile(out_dir, [label '_epochs.mat']);

% Early exit
if max_step >= 4 && exist(file_step4, 'file')
    fprintf('  Already done: %s\n', file_step4); return;
elseif max_step == 3 && exist(file_step3, 'file')
    fprintf('  Already done: %s\n', file_step3); return;
elseif max_step == 2 && exist(file_step2, 'file')
    fprintf('  Already done: %s\n', file_step2); return;
elseif max_step == 1 && exist(file_step1, 'file')
    fprintf('  Already done: %s\n', file_step1); return;
end

%% ========== STEP 1: Load -> Resample -> Dual BP -> Trim ==========

need_step1 = ~exist(file_step1_ica, 'file') || ~exist(file_step1, 'file');

if need_step1
    fprintf('\n--- Step 1: Load + Dual High-Pass ---\n');

    if strcmpi(in_ext, '.set')
        EEG_raw = pop_loadset('filename', [in_name in_ext], 'filepath', in_dir);
    else
        EEG_raw = pop_loadbv(in_dir, [in_name in_ext]);
    end
    EEG_raw = eeg_checkset(EEG_raw);
    fprintf('  Loaded: %d ch x %d pts @ %d Hz (%.1f s)\n', ...
        EEG_raw.nbchan, EEG_raw.pnts, EEG_raw.srate, EEG_raw.xmax);

    dipfit_dir = fileparts(which('pop_dipfit_settings'));
    eloc_file  = fullfile(dipfit_dir, 'standard_BEM', 'elec', 'standard_1005.elc');
    EEG_raw = pop_chanedit(EEG_raw, 'lookup', eloc_file);
    EEG_raw = eeg_checkset(EEG_raw);

    all_labels = {EEG_raw.chanlocs.labels};
    brain_keep = find(ismember(all_labels, brain_whitelist));
    non_brain  = setdiff(1:EEG_raw.nbchan, brain_keep);
    if ~isempty(non_brain)
        fprintf('  Removing %d non-brain ch: %s\n', ...
            length(non_brain), strjoin(all_labels(non_brain), ', '));
        EEG_raw = pop_select(EEG_raw, 'channel', brain_keep);
        EEG_raw = eeg_checkset(EEG_raw);
    end
    fprintf('  Brain channels: %d\n', EEG_raw.nbchan);

    fprintf('  Resample -> 250 Hz\n');
    EEG_raw = pop_resample(EEG_raw, 250);
    EEG_raw = eeg_checkset(EEG_raw);

    % --- Branch A: 1-40 Hz (ICA) ---
    if ~exist(file_step1_ica, 'file')
        EEG_ica = EEG_raw;
        fprintf('  BP %g–%d Hz (ICA copy)\n', bp_ica_lo, bp_ica_hi);
        EEG_ica = pop_eegfiltnew(EEG_ica, 'locutoff', bp_ica_lo, 'hicutoff', bp_ica_hi);
        EEG_ica = eeg_checkset(EEG_ica);
        EEG_ica = trim_data(EEG_ica, skip_trim);
        pop_saveset(EEG_ica, 'filename', [label '_step1_ica.set'], ...
            'filepath', out_dir, 'savemode', 'onefile');
        fprintf('  Saved: %s (%d pts)\n', file_step1_ica, EEG_ica.pnts);
        clear EEG_ica;
    end

    % --- Branch B: 0.1-40 Hz (output) ---
    if ~exist(file_step1, 'file')
        fprintf('  BP %g–%d Hz (output copy)\n', bp_out_lo, bp_out_hi);
        EEG_raw = pop_eegfiltnew(EEG_raw, 'locutoff', bp_out_lo, 'hicutoff', bp_out_hi);
        EEG_raw = eeg_checkset(EEG_raw);
        EEG_raw = trim_data(EEG_raw, skip_trim);
        pop_saveset(EEG_raw, 'filename', [label '_step1.set'], ...
            'filepath', out_dir, 'savemode', 'onefile');
        fprintf('  Saved: %s (%d pts)\n', file_step1, EEG_raw.pnts);
    end
    clear EEG_raw;
else
    fprintf('\n--- Step 1: Checkpoints exist ---\n');
end

if max_step < 2, fprintf('\n=== %s step 1 done ===\n', label); return; end

%% ========== STEP 2: Bad ch -> Interp -> CAR -> ASR -> ICA (on 1Hz data) ==========

if exist(file_step2, 'file')
    fprintf('\n--- Step 2: Loading checkpoint ---\n');
    EEG_seg = pop_loadset('filename', [label '_step2.set'], 'filepath', out_dir);
    EEG_seg = eeg_checkset(EEG_seg);
    fprintf('  Loaded step2: %d ch x %d pts, %d ICs\n', ...
        EEG_seg.nbchan, EEG_seg.pnts, size(EEG_seg.icaweights, 1));
else
    fprintf('\n--- Step 2: Artifact cleaning + ICA (on 1Hz data) ---\n');

    EEG = pop_loadset('filename', [label '_step1_ica.set'], 'filepath', out_dir);
    EEG = eeg_checkset(EEG);

    brain_chanlocs = EEG.chanlocs;
    brain_labels   = {EEG.chanlocs.labels};
    srate = EEG.srate;

    % --- (a) Bad channel detection (BEFORE baseline correction) ---
    % Extract all task segments without baseline correction for clean_rawdata.
    % Baseline correction destroys inter-channel correlation structure,
    % causing false positives in clean_rawdata's ChannelCriterion.
    [EEG_raw_seg, ~, ~, ~] = extract_segments_no_bl(EEG, trial_defs, srate);

    if ~isempty(test_bad_ch_thresholds)
        for test_corr = test_bad_ch_thresholds
            EEG_test = clean_rawdata(EEG_raw_seg, 5, 'off', test_corr, 4, 'off', 'off');
            n_bad_test = EEG_raw_seg.nbchan - EEG_test.nbchan;
            fprintf('  corr=%.1f -> %d bad channels\n', test_corr, n_bad_test);
        end
    end

    EEG_clean = clean_rawdata(EEG_raw_seg, 5, 'off', corr_thresh, 4, 'off', 'off');
    clean_labels = {EEG_clean.chanlocs.labels};
    bad_mask     = ~ismember(brain_labels, clean_labels);
    bad_labels   = brain_labels(bad_mask);
    n_bad        = sum(bad_mask);
    clear EEG_clean EEG_raw_seg;

    if n_bad > bad_ch_limit
        error('prep_patient_v7:tooManyBadCh', ...
            'Too many bad channels (%d/59, limit=%d, corr=%.2f): %s', ...
            n_bad, bad_ch_limit, corr_thresh, strjoin(bad_labels, ', '));
    elseif n_bad > 0
        fprintf('  Bad channels (%d): %s\n', n_bad, strjoin(bad_labels, ', '));
    else
        bad_labels = {};
        fprintf('  No bad channels detected.\n');
    end

    % --- (b) Extract task+rest segments (with baseline correction) ---
    [EEG_seg, trial_type_id, n_seg, total_dur] = extract_segments(EEG, trial_defs, srate);
    clear EEG;

    % Remove bad channels from segment data
    if n_bad > 0
        keep_idx = find(~bad_mask);
        EEG_seg = pop_select(EEG_seg, 'channel', keep_idx);
        EEG_seg = eeg_checkset(EEG_seg);
    end

    % --- (c) Interpolate ---
    n_interp = 0;
    if n_bad > 0
        interp_mask = ismember(brain_labels, bad_labels);
        target_locs = [EEG_seg.chanlocs, brain_chanlocs(interp_mask)];
        EEG_seg = pop_interp(EEG_seg, target_locs, 'spherical');
        EEG_seg = eeg_checkset(EEG_seg);
        n_interp = n_bad;
        fprintf('  Interpolated %d channels\n', n_interp);
    end

    % --- (d) Reorder ---
    EEG_seg = reorder_channels(EEG_seg, brain_whitelist);

    % --- (d2) Restore online reference (Cz) as zero-filled channel ---
    fprintf('  Adding zero-filled Cz (online reference)\n');
    dipfit_dir = fileparts(which('pop_dipfit_settings'));
    eloc_all = readlocs(fullfile(dipfit_dir, 'standard_BEM', 'elec', 'standard_1005.elc'));
    cz_match = find(strcmpi({eloc_all.labels}, 'Cz'), 1);
    EEG_seg.nbchan = EEG_seg.nbchan + 1;
    EEG_seg.data(end+1, :) = 0;
    EEG_seg.chanlocs(end+1) = eloc_all(cz_match);
    EEG_seg.chanlocs(end).labels = 'Cz';
    EEG_seg = eeg_checkset(EEG_seg);
    EEG_seg = reorder_channels(EEG_seg, brain_whitelist_full);

    % --- (e) Average re-reference (with Cz) ---
    fprintf('  Average re-reference (with Cz, %d ch)\n', EEG_seg.nbchan);
    EEG_seg = pop_reref(EEG_seg, []);
    EEG_seg = eeg_checkset(EEG_seg);

    n_brain = EEG_seg.nbchan;
    formula_rank = n_brain - n_interp;  % No -1: Cz zero-fill absorbs avgref rank loss
    numerical_rank = rank(double(EEG_seg.data'));
    data_rank = min(formula_rank, numerical_rank);
    fprintf('  Data rank: %d (formula=%d, numerical=%d, brain=%d, interp=%d)\n', ...
        data_rank, formula_rank, numerical_rank, n_brain, n_interp);

    % --- (f) ASR on movement segments only (S2S + Walk2min) ---
    [EEG_seg, n_asr, asr_log] = apply_asr(EEG_seg, trial_defs, srate);

    % --- (g) ICA ---
    switch ica_method
        case 'amica'
            fprintf('  AMICA: %d ch x %d pts, %d model(s), %d iter, rank %d\n', ...
                EEG_seg.nbchan, EEG_seg.pnts, amica_num_mod, amica_max_iter, data_rank);

            amica_outdir = fullfile(out_dir, [label '_amicatmp']);
            if ~exist(amica_outdir, 'dir'), mkdir(amica_outdir); end

            EEG_seg = pop_runamica(EEG_seg, ...
                'num_mod',  amica_num_mod, ...
                'maxiter',  amica_max_iter, ...
                'pcakeep',  data_rank, ...
                'outdir',   amica_outdir);
            EEG_seg = eeg_checkset(EEG_seg);
            n_comp = size(EEG_seg.icaweights, 1);
            fprintf('  AMICA done: %d components\n', n_comp);

            if exist(amica_outdir, 'dir'), rmdir(amica_outdir, 's'); end

        case 'runica'
            fprintf('  runica: %d ch x %d pts, rank %d\n', ...
                EEG_seg.nbchan, EEG_seg.pnts, data_rank);
            EEG_seg = pop_runica(EEG_seg, 'icatype', 'runica', 'extended', 1, 'pca', data_rank);
            EEG_seg = eeg_checkset(EEG_seg);
            n_comp = size(EEG_seg.icaweights, 1);
            fprintf('  runica done: %d components\n', n_comp);

        otherwise
            error('prep_patient_v7:badIcaMethod', 'Unsupported ICA method: %s', ica_method);
    end

    % Metadata
    EEG_seg.etc.step2_meta.bad_ch_labels     = bad_labels;
    EEG_seg.etc.step2_meta.brain_chanlocs    = brain_chanlocs;
    EEG_seg.etc.step2_meta.n_trial_segs      = n_seg;
    EEG_seg.etc.step2_meta.trial_type_id     = trial_type_id;
    EEG_seg.etc.step2_meta.trial_defs        = trial_defs;
    EEG_seg.etc.step2_meta.trial_dur_sec     = total_dur;
    EEG_seg.etc.step2_meta.n_ch_interpolated = n_interp;
    EEG_seg.etc.step2_meta.data_rank         = data_rank;
    EEG_seg.etc.step2_meta.corr_thresh       = corr_thresh;
    EEG_seg.etc.step2_meta.bad_ch_limit      = bad_ch_limit;
    EEG_seg.etc.step2_meta.n_asr_segments    = n_asr;
    EEG_seg.etc.step2_meta.asr_log           = asr_log;
    EEG_seg.etc.step2_meta.ica_method        = ica_method;
    EEG_seg.etc.step2_meta.amica_num_mod     = amica_num_mod;
    EEG_seg.etc.step2_meta.amica_max_iter    = amica_max_iter;
    EEG_seg.etc.step2_meta.marker_set        = marker_set;
    EEG_seg.etc.step2_meta.test_bad_ch_thresholds = test_bad_ch_thresholds;

    pop_saveset(EEG_seg, 'filename', [label '_step2.set'], ...
        'filepath', out_dir, 'savemode', 'onefile');
    fprintf('  Saved: %s\n', file_step2);
end

if max_step < 3, fprintf('\n=== %s step 2 done ===\n', label); return; end

%% ========== STEP 3: Transfer ICA to 0.1Hz -> ICLabel -> Reject ==========

if exist(file_step3, 'file')
    fprintf('\n--- Step 3: Loading checkpoint ---\n');
    EEG_out = pop_loadset('filename', [label '_step3.set'], 'filepath', out_dir);
    EEG_out = eeg_checkset(EEG_out);
    fprintf('  Loaded step3: %d ch x %d pts\n', EEG_out.nbchan, EEG_out.pnts);
else
    fprintf('\n--- Step 3: ICA transfer to 0.1Hz + ICLabel ---\n');

    EEG_out = pop_loadset('filename', [label '_step1.set'], 'filepath', out_dir);
    EEG_out = eeg_checkset(EEG_out);
    fprintf('  Loaded 0.1Hz data: %d ch x %d pts\n', EEG_out.nbchan, EEG_out.pnts);

    bad_labels     = EEG_seg.etc.step2_meta.bad_ch_labels;
    brain_chanlocs = EEG_seg.etc.step2_meta.brain_chanlocs;

    if ~isempty(bad_labels)
        % Must REMOVE bad channels first, then interpolate back
        % (pop_interp skips channels already present in montage)
        keep_mask = ~ismember({EEG_out.chanlocs.labels}, bad_labels);
        EEG_out = pop_select(EEG_out, 'channel', find(keep_mask));
        EEG_out = eeg_checkset(EEG_out);
        interp_mask = ismember({brain_chanlocs.labels}, bad_labels);
        target_locs = [EEG_out.chanlocs, brain_chanlocs(interp_mask)];
        EEG_out = pop_interp(EEG_out, target_locs, 'spherical');
        EEG_out = eeg_checkset(EEG_out);
        fprintf('  Interpolated %d bad ch on 0.1Hz copy\n', length(bad_labels));
    end

    EEG_out = reorder_channels(EEG_out, brain_whitelist);

    % Restore Cz as zero-filled (0.1Hz copy)
    fprintf('  Adding zero-filled Cz (online reference, 0.1Hz)\n');
    dipfit_dir = fileparts(which('pop_dipfit_settings'));
    eloc_all = readlocs(fullfile(dipfit_dir, 'standard_BEM', 'elec', 'standard_1005.elc'));
    cz_match = find(strcmpi({eloc_all.labels}, 'Cz'), 1);
    EEG_out.nbchan = EEG_out.nbchan + 1;
    EEG_out.data(end+1, :) = 0;
    EEG_out.chanlocs(end+1) = eloc_all(cz_match);
    EEG_out.chanlocs(end).labels = 'Cz';
    EEG_out = eeg_checkset(EEG_out);
    EEG_out = reorder_channels(EEG_out, brain_whitelist_full);

    fprintf('  Average re-reference (with Cz, 0.1Hz, %d ch)\n', EEG_out.nbchan);
    EEG_out = pop_reref(EEG_out, []);
    EEG_out = eeg_checkset(EEG_out);

    % Transfer ICA
    EEG_out.icaweights  = EEG_seg.icaweights;
    EEG_out.icasphere   = EEG_seg.icasphere;
    EEG_out.icawinv     = EEG_seg.icawinv;
    EEG_out.icachansind = EEG_seg.icachansind;
    EEG_out = eeg_checkset(EEG_out);
    fprintf('  ICA weights transferred (%d components)\n', size(EEG_out.icaweights, 1));

    % ICLabel
    EEG_out = iclabel(EEG_out);
    ic_classes = EEG_out.etc.ic_classification.ICLabel.classifications;

    artifact_thresh = 0.8;
    artifact_cols   = [2 3 4 5 6];
    artifact_max    = max(ic_classes(:, artifact_cols), [], 2);
    rej_idx  = find(artifact_max > artifact_thresh);
    n_rej    = length(rej_idx);

    label_names = {'Brain','Muscle','Eye','Heart','LineNoise','ChanNoise','Other'};
    rej_labels  = cell(n_rej, 1);
    for k = 1:n_rej
        [~, mc] = max(ic_classes(rej_idx(k), :));
        rej_labels{k} = label_names{mc};
    end

    fprintf('  Rejecting %d / %d ICs (artifact > %.1f)\n', ...
        n_rej, size(ic_classes, 1), artifact_thresh);
    if n_rej > 0
        fprintf('    Categories: %s\n', strjoin(rej_labels, ', '));
        EEG_out = pop_subcomp(EEG_out, rej_idx, 0);
        EEG_out = eeg_checkset(EEG_out);
    end

    % Clear ICA fields
    EEG_out.icaweights = []; EEG_out.icasphere = [];
    EEG_out.icawinv = []; EEG_out.icachansind = []; EEG_out.icaact = [];
    EEG_out = eeg_checkset(EEG_out);

    EEG_out.etc.step3_meta.rejected_ics    = rej_idx(:)';
    EEG_out.etc.step3_meta.ic_labels       = rej_labels;
    EEG_out.etc.step3_meta.n_ics_rejected  = n_rej;
    EEG_out.etc.step3_meta.artifact_thresh = artifact_thresh;
    EEG_out.etc.step3_meta.step2_meta      = EEG_seg.etc.step2_meta;
    if strcmp(ica_method, 'amica')
        pipeline_desc = sprintf( ...
            'V8: 59ch->250Hz->dualHP(1/0.1-40)->badch(corr=%.2f)->interp->+Cz->CAR(60ch)->ASR(k=20)->AMICA(%dm,%di)->transfer->ICLabel(>0.8)', ...
            corr_thresh, amica_num_mod, amica_max_iter);
    else
        pipeline_desc = sprintf( ...
            'V8: 59ch->250Hz->dualHP(1/0.1-40)->badch(corr=%.2f)->interp->+Cz->CAR(60ch)->ASR(k=20)->runica(rank=%d)->transfer->ICLabel(>0.8)', ...
            corr_thresh, EEG_seg.etc.step2_meta.data_rank);
    end
    EEG_out.etc.step3_meta.pipeline = pipeline_desc;

    pop_saveset(EEG_out, 'filename', [label '_step3.set'], ...
        'filepath', out_dir, 'savemode', 'onefile');
    fprintf('  Saved: %s\n', file_step3);
end

clear EEG_seg;

if max_step < 4, fprintf('\n=== %s step 3 done ===\n', label); return; end

%% ========== STEP 4: Epoch by trial type -> save .mat ==========

fprintf('\n--- Step 4: Epoch + Export ---\n');

out_srate = EEG_out.srate;

epochs = struct();
epochs.srate    = out_srate;
epochs.chanlocs = EEG_out.chanlocs;
epochs.meta     = EEG_out.etc;

for t = 1:n_trial_types
    smk  = trial_defs{t, 1};
    emk  = trial_defs{t, 2};
    name = trial_defs{t, 3};
    [epochs.(name), epochs.([name '_info'])] = extract_epochs(EEG_out, smk, emk, out_srate);
    fprintf('  %s: %d epochs\n', name, length(epochs.(name)));
end

save(file_step4, 'epochs', '-v7.3');
fprintf('  Saved: %s\n', file_step4);

fprintf('\n=== %s done! ===\n', label);
end


%% ======================== Local Functions ========================

function EEG = trim_data(EEG, skip_trim)
    if skip_trim
        fprintf('  Trim: SKIPPED\n');
        return;
    end
    evt_types = {EEG.event.type};
    evt_lats  = [EEG.event.latency];
    s11 = find(strcmp(evt_types, 'S 11'), 1, 'first');
    s12 = find(strcmp(evt_types, 'S 12'), 1, 'last');
    if ~isempty(s11) && ~isempty(s12)
        i1 = max(1, round(evt_lats(s11)));
        i2 = min(EEG.pnts, round(evt_lats(s12)));
        fprintf('  Trim S11–S12: %.1f–%.1f s (%.1f s)\n', ...
            (i1-1)/EEG.srate, (i2-1)/EEG.srate, (i2-i1)/EEG.srate);
        EEG = pop_select(EEG, 'point', [i1 i2]);
        EEG = eeg_checkset(EEG);
    elseif ~isempty(s11)
        i1 = max(1, round(evt_lats(s11)));
        fprintf('  Trim S11–end (no S12): %.1f s onward\n', (i1-1)/EEG.srate);
        EEG = pop_select(EEG, 'point', [i1 EEG.pnts]);
        EEG = eeg_checkset(EEG);
    else
        fprintf('  No S11/S12 found, keeping full recording.\n');
    end
end

function [EEG_seg, trial_type_id, n_seg, total_dur] = extract_segments(EEG, trial_defs, srate)
    n_trial_types = size(trial_defs, 1);
    baseline_sec  = 1.0;
    bl_ranges     = zeros(0, 2);
    trial_ranges  = zeros(0, 2);
    trial_type_id = [];
    n_seg = 0; total_dur = 0;

    evt_types = {EEG.event.type};
    evt_lats  = [EEG.event.latency];
    boundary_lats = evt_lats(strcmp(evt_types, 'boundary'));
    n_boundary_skip = 0;

    for td = 1:n_trial_types
        smk = trial_defs{td, 1};
        emk = trial_defs{td, 2};
        s_lats = evt_lats(strcmp(evt_types, smk));
        if ischar(emk)
            e_lats = evt_lats(strcmp(evt_types, emk));
        else
            e_lats = s_lats + emk * srate;
        end

        n_this = 0;
        for i = 1:length(s_lats)
            sl = s_lats(i);
            if ischar(emk)
                nxt = e_lats(e_lats > sl);
                if isempty(nxt), continue; end
                nxt = nxt(1);
                if any(s_lats > sl & s_lats < nxt), continue; end
            else
                nxt = e_lats(i);
                if round(nxt) > EEG.pnts
                    fprintf('  Trial SKIP: %s #%d -- data too short for %ds\n', ...
                        trial_defs{td, 3}, i, emk);
                    continue;
                end
            end
            dur = (nxt - sl) / srate;
            if dur < 3 || dur > 300, continue; end

            % Reject segments spanning a boundary event (file join / data break)
            if any(boundary_lats > sl & boundary_lats < nxt)
                fprintf('  SKIP %s #%d: spans boundary event (%.1f–%.1f s)\n', ...
                    trial_defs{td, 3}, i, sl/srate, nxt/srate);
                n_boundary_skip = n_boundary_skip + 1;
                continue;
            end

            i1 = max(1, round(sl));
            i2 = min(EEG.pnts, round(nxt));
            t_start = (i1 - 1) / srate;
            t_end   = (i2 - 1) / srate;
            t_bl    = max(0, t_start - baseline_sec);

            bl_ranges(end+1, :)    = [t_bl, t_end];       %#ok<AGROW>
            trial_ranges(end+1, :) = [t_start, t_end];    %#ok<AGROW>
            trial_type_id(end+1)   = td;                   %#ok<AGROW>
            n_seg = n_seg + 1;
            total_dur = total_dur + dur;
            n_this = n_this + 1;
        end
        fprintf('  %s: %d trials\n', trial_defs{td, 3}, n_this);
    end
    if n_boundary_skip > 0
        fprintf('  WARNING: %d segments skipped (boundary crossing)\n', n_boundary_skip);
    end
    fprintf('  Total: %d segments, %.1f s (%.1f min)\n', n_seg, total_dur, total_dur/60);

    if n_seg == 0
        error('prep_patient_v7:noSegments', 'No valid trial segments found.');
    end

    % Baseline correction
    for s = 1:n_seg
        bl_s1 = max(1, round(bl_ranges(s, 1) * srate) + 1);
        tr_s1 = max(1, round(trial_ranges(s, 1) * srate) + 1);
        tr_s2 = min(EEG.pnts, round(trial_ranges(s, 2) * srate) + 1);
        if tr_s1 > bl_s1
            bl_mean = mean(EEG.data(:, bl_s1:tr_s1-1), 2);
        else
            bl_mean = mean(EEG.data(:, tr_s1:min(tr_s1+round(baseline_sec*srate)-1, tr_s2)), 2);
        end
        EEG.data(:, tr_s1:tr_s2) = EEG.data(:, tr_s1:tr_s2) - bl_mean;
    end

    [trial_ranges, sort_ord] = sortrows(trial_ranges, 1);
    trial_type_id = trial_type_id(sort_ord);

    EEG_seg = pop_select(EEG, 'time', trial_ranges);
    if isempty(EEG_seg.chanlocs) || ...
            (isstruct(EEG_seg.chanlocs) && isfield(EEG_seg.chanlocs,'labels') && ...
             all(cellfun(@isempty, {EEG_seg.chanlocs.labels})))
        EEG_seg.chanlocs = EEG.chanlocs;
        EEG_seg.chaninfo = EEG.chaninfo;
    end
    EEG_seg = eeg_checkset(EEG_seg, 'eventconsistency');
    fprintf('  Segmented: %d ch x %d pts, %d events\n', ...
        EEG_seg.nbchan, EEG_seg.pnts, length(EEG_seg.event));
end

function [EEG_seg, trial_type_id, n_seg, total_dur] = extract_segments_no_bl(EEG, trial_defs, srate)
% Same as extract_segments but WITHOUT baseline correction.
% Used for bad channel detection where inter-channel correlation must be preserved.
    n_trial_types = size(trial_defs, 1);
    trial_ranges  = zeros(0, 2);
    trial_type_id = [];
    n_seg = 0; total_dur = 0;

    evt_types = {EEG.event.type};
    evt_lats  = [EEG.event.latency];
    boundary_lats = evt_lats(strcmp(evt_types, 'boundary'));

    for td = 1:n_trial_types
        smk = trial_defs{td, 1};
        emk = trial_defs{td, 2};
        s_lats = evt_lats(strcmp(evt_types, smk));
        if ischar(emk)
            e_lats = evt_lats(strcmp(evt_types, emk));
        else
            e_lats = s_lats + emk * srate;
        end

        n_this = 0;
        for i = 1:length(s_lats)
            sl = s_lats(i);
            if ischar(emk)
                nxt = e_lats(e_lats > sl);
                if isempty(nxt), continue; end
                nxt = nxt(1);
                if any(s_lats > sl & s_lats < nxt), continue; end
            else
                nxt = e_lats(i);
                if round(nxt) > EEG.pnts, continue; end
            end
            dur = (nxt - sl) / srate;
            if dur < 3 || dur > 300, continue; end
            if any(boundary_lats > sl & boundary_lats < nxt), continue; end

            i1 = max(1, round(sl));
            i2 = min(EEG.pnts, round(nxt));
            t_start = (i1 - 1) / srate;
            t_end   = (i2 - 1) / srate;

            trial_ranges(end+1, :) = [t_start, t_end];    %#ok<AGROW>
            trial_type_id(end+1)   = td;                   %#ok<AGROW>
            n_seg = n_seg + 1;
            total_dur = total_dur + dur;
            n_this = n_this + 1;
        end
        fprintf('  %s: %d trials (no BL)\n', trial_defs{td, 3}, n_this);
    end

    if n_seg == 0
        error('extract_segments_no_bl:noSegments', 'No valid trial segments found.');
    end

    [trial_ranges, sort_ord] = sortrows(trial_ranges, 1);
    trial_type_id = trial_type_id(sort_ord);

    EEG_seg = pop_select(EEG, 'time', trial_ranges);
    if isempty(EEG_seg.chanlocs) || ...
            (isstruct(EEG_seg.chanlocs) && isfield(EEG_seg.chanlocs,'labels') && ...
             all(cellfun(@isempty, {EEG_seg.chanlocs.labels})))
        EEG_seg.chanlocs = EEG.chanlocs;
        EEG_seg.chaninfo = EEG.chaninfo;
    end
    EEG_seg = eeg_checkset(EEG_seg, 'eventconsistency');
    fprintf('  Segmented (no BL): %d ch x %d pts\n', EEG_seg.nbchan, EEG_seg.pnts);
end

function EEG = reorder_channels(EEG, whitelist)
    cur_labels = {EEG.chanlocs.labels};
    [~, reorder_idx] = ismember(whitelist, cur_labels);
    reorder_idx = reorder_idx(reorder_idx > 0);
    if length(reorder_idx) == EEG.nbchan
        EEG.data     = EEG.data(reorder_idx, :);
        EEG.chanlocs = EEG.chanlocs(reorder_idx);
        EEG = eeg_checkset(EEG);
        fprintf('  Reordered %d channels\n', EEG.nbchan);
    else
        missing = whitelist(~ismember(whitelist, cur_labels));
        extra   = cur_labels(~ismember(cur_labels, whitelist));
        error('reorder_channels:mismatch', ...
            'Channel mismatch (%d matched vs %d expected). Missing: {%s}. Extra: {%s}', ...
            length(reorder_idx), EEG.nbchan, strjoin(missing, ', '), strjoin(extra, ', '));
    end
end

function [EEG_seg, n_asr, asr_log] = apply_asr(EEG_seg, trial_defs, srate)
    n_trial_types = size(trial_defs, 1);
    evt_types = {EEG_seg.event.type};
    evt_lats  = [EEG_seg.event.latency];
    n_asr = 0;
    asr_log = struct('type', {}, 'index', {}, 'dur_sec', {}, 'status', {}, 'error_msg', {});

    for td = 1:n_trial_types
        if ~trial_defs{td, 4}, continue; end
        smk = trial_defs{td, 1};
        emk = trial_defs{td, 2};

        s_lats = evt_lats(strcmp(evt_types, smk));
        if ischar(emk)
            e_lats = evt_lats(strcmp(evt_types, emk));
        else
            e_lats = s_lats + emk * srate;
        end

        for i = 1:length(s_lats)
            sl = s_lats(i);
            if ischar(emk)
                nxt = e_lats(e_lats > sl);
                if isempty(nxt), continue; end
                nxt = nxt(1);
            else
                nxt = e_lats(i);
                if round(nxt) > EEG_seg.pnts, continue; end
            end
            i1 = max(1, round(sl));
            i2 = min(EEG_seg.pnts, round(nxt));
            dur = (i2 - i1) / srate;
            if dur < 3, continue; end

            seg_data = EEG_seg.data(:, i1:i2);
            EEG_tmp = eeg_emptyset();
            EEG_tmp.data     = seg_data;
            EEG_tmp.nbchan   = size(seg_data, 1);
            EEG_tmp.pnts     = size(seg_data, 2);
            EEG_tmp.srate    = srate;
            EEG_tmp.xmax     = (EEG_tmp.pnts - 1) / srate;
            EEG_tmp.times    = (0:EEG_tmp.pnts-1) / srate * 1000;
            EEG_tmp.trials   = 1;
            EEG_tmp.chanlocs = EEG_seg.chanlocs;
            EEG_tmp = eeg_checkset(EEG_tmp);

            try
                EEG_tmp = clean_rawdata(EEG_tmp, 'off', 'off', 'off', 'off', 20, 'off');
                EEG_seg.data(:, i1:i2) = EEG_tmp.data;
                n_asr = n_asr + 1;
                fprintf('  ASR %s #%d: %.1f s\n', trial_defs{td, 3}, i, dur);
                asr_log(end+1) = struct('type', trial_defs{td, 3}, 'index', i, ...
                    'dur_sec', dur, 'status', 'ok', 'error_msg', '');
            catch ME_asr
                fprintf('  ASR SKIP %s #%d (%.1f s): %s\n', trial_defs{td, 3}, i, dur, ME_asr.message);
                asr_log(end+1) = struct('type', trial_defs{td, 3}, 'index', i, ...
                    'dur_sec', dur, 'status', 'skip', 'error_msg', ME_asr.message);
            end
        end
    end
    n_skip = sum(strcmp({asr_log.status}, 'skip'));
    fprintf('  ASR total: %d cleaned, %d skipped (k=20)\n', n_asr, n_skip);
end

function [trials, info] = extract_epochs(EEG, smk, emk, srate)
    evt_types = {EEG.event.type};
    evt_lats  = [EEG.event.latency];
    boundary_lats = evt_lats(strcmp(evt_types, 'boundary'));
    s_lats = evt_lats(strcmp(evt_types, smk));
    if ischar(emk)
        e_lats = evt_lats(strcmp(evt_types, emk));
    else
        e_lats = s_lats + emk * srate;
    end
    trials = {};
    info = struct('trial_idx', {}, 'start_lat', {}, 'end_lat', {}, 'dur_sec', {});
    for i = 1:length(s_lats)
        sl = s_lats(i);
        if ischar(emk)
            nxt = e_lats(e_lats > sl);
            if isempty(nxt), continue; end
            nxt = nxt(1);
            if any(s_lats > sl & s_lats < nxt), continue; end
        else
            nxt = sl + emk * srate;
            if round(nxt) > EEG.pnts, continue; end
        end
        i1 = max(1, round(sl));
        i2 = min(EEG.pnts, round(nxt));
        dur = (i2 - i1) / srate;
        if dur < 3 || dur > 300, continue; end
        if any(boundary_lats > sl & boundary_lats < nxt), continue; end
        trials{end+1} = EEG.data(:, i1:i2); %#ok<AGROW>
        info(end+1) = struct('trial_idx', i, 'start_lat', sl, 'end_lat', nxt, 'dur_sec', dur);
    end
end

function opts = normalize_opts(opts)
    if ~isstruct(opts)
        error('prep_patient_v7:badOpts', 'opts must be a struct.');
    end

    defaults = struct( ...
        'corr_thresh', 0.8, ...
        'bad_ch_limit', 10, ...
        'ica_method', 'amica', ...
        'amica_num_mod', 1, ...
        'amica_max_iter', 1000, ...
        'test_bad_ch_thresholds', []);

    fn = fieldnames(defaults);
    for i = 1:numel(fn)
        key = fn{i};
        if ~isfield(opts, key) || isempty(opts.(key))
            opts.(key) = defaults.(key);
        end
    end

    if isstring(opts.ica_method)
        opts.ica_method = char(opts.ica_method);
    end
    opts.ica_method = lower(opts.ica_method);
end
