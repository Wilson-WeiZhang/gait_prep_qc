%% run_test_p02_sess04.m — Quick test: P02_Sess04 with runica (not AMICA)
%
% Purpose: Test V7 pipeline on P02_Sess04 which has known issues:
%   - Stronger eSCS stimulation → 33 bad channels at corr=0.8
%   - Need to test with relaxed threshold (corr=0.7 or 0.6)
%
% Uses runica instead of AMICA for speed.
% Run on aa: cd ~/gait/code; matlab -batch "run_test_p02_sess04"

clear; clc;

eeglab_path = '/home/wilson/eeglab2024';
addpath(eeglab_path); eeglab nogui;

proj_dir = '/home/wilson/gait';
addpath(fullfile(proj_dir, 'code'));

raw_file = fullfile(proj_dir, 'raw_data', 'patient', 'SUBJECT-02', ...
    'RESTORE2_002_Sess04', 'sess04_06Apr2026-115201.751', 'EEG', 'RESTORE2-0027.vhdr');
out_dir = fullfile(proj_dir, 'prep_data_v7');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

label = 'P02_Sess04';

%% Settings
bp_ica_lo = 1;    bp_ica_hi = 40;
bp_out_lo = 0.1;  bp_out_hi = 40;
corr_thresh = 0.7;  % relaxed from 0.8 (default) due to eSCS artifact
bad_ch_limit = 15;   % relaxed from 10

brain_whitelist = {'Fp1','Fz','F3','F7','FC5','FC1','C3','T7','CP5','CP1', ...
    'Pz','P3','P7','O1','Oz','O2','P4','P8','CP6','CP2', ...
    'Cz','C4','T8','FC6','FC2','F4','F8','Fp2', ...
    'AF7','AF3','AFz','F1','F5','FT7','FC3','C1','C5','TP7', ...
    'CP3','P1','P5','PO7','PO3','POz','PO4','PO8','P6','P2', ...
    'CPz','CP4','TP8','C6','C2','FC4','FT8','F6','AF8','AF4','F2'};

trial_defs = {
    'S  1', 'S  2', 'MI',       false
    'S  4', 'S  5', 'S2S',      true
    'S  7', 120,    'Walk2min', true
};

file_step1_ica = fullfile(out_dir, [label '_step1_ica.set']);
file_step1     = fullfile(out_dir, [label '_step1.set']);
file_step2     = fullfile(out_dir, [label '_step2_runica.set']);
file_step3     = fullfile(out_dir, [label '_step3_runica.set']);

%% STEP 1: Load → 59ch → 250Hz → dual BP → trim
if ~exist(file_step1_ica, 'file') || ~exist(file_step1, 'file')
    fprintf('\n--- Step 1: Load + Dual HP ---\n');
    EEG_raw = pop_loadbv(fileparts(raw_file), 'RESTORE2-0027.vhdr');
    EEG_raw = eeg_checkset(EEG_raw);
    fprintf('  Loaded: %d ch x %d pts @ %d Hz\n', EEG_raw.nbchan, EEG_raw.pnts, EEG_raw.srate);

    % Chanlocs
    dipfit_dir = fileparts(which('pop_dipfit_settings'));
    eloc_file = fullfile(dipfit_dir, 'standard_BEM', 'elec', 'standard_1005.elc');
    EEG_raw = pop_chanedit(EEG_raw, 'lookup', eloc_file);

    % 59ch whitelist
    all_labels = {EEG_raw.chanlocs.labels};
    brain_keep = find(ismember(all_labels, brain_whitelist));
    EEG_raw = pop_select(EEG_raw, 'channel', brain_keep);
    fprintf('  %d brain channels\n', EEG_raw.nbchan);

    % Resample
    EEG_raw = pop_resample(EEG_raw, 250);

    % Branch A: 1-40Hz for ICA
    if ~exist(file_step1_ica, 'file')
        EEG_ica = pop_eegfiltnew(EEG_raw, 'locutoff', bp_ica_lo, 'hicutoff', bp_ica_hi);
        % Trim S11-S12
        evt_types = {EEG_ica.event.type};
        evt_lats = [EEG_ica.event.latency];
        s11 = find(strcmp(evt_types, 'S 11'), 1, 'first');
        s12 = find(strcmp(evt_types, 'S 12'), 1, 'last');
        if ~isempty(s11) && ~isempty(s12)
            EEG_ica = pop_select(EEG_ica, 'point', [round(evt_lats(s11)) round(evt_lats(s12))]);
        elseif ~isempty(s11)
            EEG_ica = pop_select(EEG_ica, 'point', [round(evt_lats(s11)) EEG_ica.pnts]);
        end
        pop_saveset(EEG_ica, 'filename', [label '_step1_ica.set'], 'filepath', out_dir, 'savemode', 'onefile');
        fprintf('  Saved step1_ica: %d pts\n', EEG_ica.pnts);
        clear EEG_ica;
    end

    % Branch B: 0.1-40Hz for output
    if ~exist(file_step1, 'file')
        EEG_out = pop_eegfiltnew(EEG_raw, 'locutoff', bp_out_lo, 'hicutoff', bp_out_hi);
        evt_types = {EEG_out.event.type};
        evt_lats = [EEG_out.event.latency];
        s11 = find(strcmp(evt_types, 'S 11'), 1, 'first');
        s12 = find(strcmp(evt_types, 'S 12'), 1, 'last');
        if ~isempty(s11) && ~isempty(s12)
            EEG_out = pop_select(EEG_out, 'point', [round(evt_lats(s11)) round(evt_lats(s12))]);
        elseif ~isempty(s11)
            EEG_out = pop_select(EEG_out, 'point', [round(evt_lats(s11)) EEG_out.pnts]);
        end
        pop_saveset(EEG_out, 'filename', [label '_step1.set'], 'filepath', out_dir, 'savemode', 'onefile');
        fprintf('  Saved step1: %d pts\n', EEG_out.pnts);
        clear EEG_out;
    end
    clear EEG_raw;
else
    fprintf('Step 1 checkpoints exist.\n');
end

%% STEP 2: Bad ch → Interp → CAR → ASR → runica
if ~exist(file_step2, 'file')
    fprintf('\n--- Step 2: Bad ch + ICA (runica) ---\n');
    EEG = pop_loadset('filename', [label '_step1_ica.set'], 'filepath', out_dir);

    brain_chanlocs = EEG.chanlocs;
    brain_labels = {EEG.chanlocs.labels};
    srate = EEG.srate;

    % (a) Bad ch detection (no baseline correction)
    % Extract segments without BL for clean_rawdata
    evt_types = {EEG.event.type};
    evt_lats = [EEG.event.latency];
    seg_ranges = [];
    for td = 1:size(trial_defs, 1)
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
                if round(nxt) > EEG.pnts, continue; end
            end
            dur = (nxt - sl) / srate;
            if dur < 3 || dur > 300, continue; end
            seg_ranges(end+1, :) = [(round(sl)-1)/srate, (min(round(nxt), EEG.pnts)-1)/srate]; %#ok
        end
    end
    seg_ranges = sortrows(seg_ranges, 1);
    EEG_seg_nbl = pop_select(EEG, 'time', seg_ranges);
    EEG_seg_nbl.chanlocs = EEG.chanlocs;
    EEG_seg_nbl = eeg_checkset(EEG_seg_nbl);

    % Test multiple thresholds
    for test_corr = [0.8, 0.7, 0.6]
        EEG_test = clean_rawdata(EEG_seg_nbl, 5, 'off', test_corr, 4, 'off', 'off');
        n_bad_test = EEG_seg_nbl.nbchan - EEG_test.nbchan;
        fprintf('  corr=%.1f → %d bad channels\n', test_corr, n_bad_test);
    end

    % Use relaxed threshold
    fprintf('  Using corr=%.1f for this session\n', corr_thresh);
    EEG_clean = clean_rawdata(EEG_seg_nbl, 5, 'off', corr_thresh, 4, 'off', 'off');
    clean_labels = {EEG_clean.chanlocs.labels};
    bad_mask = ~ismember(brain_labels, clean_labels);
    bad_labels = brain_labels(bad_mask);
    n_bad = sum(bad_mask);
    clear EEG_clean EEG_seg_nbl;

    if n_bad > bad_ch_limit
        error('Too many bad channels (%d/%d, limit=%d): %s', ...
            n_bad, length(brain_labels), bad_ch_limit, strjoin(bad_labels, ', '));
    end
    fprintf('  Bad channels (%d): %s\n', n_bad, strjoin(bad_labels, ', '));

    % (b) Extract segments WITH baseline correction
    baseline_sec = 1.0;
    trial_ranges = [];
    bl_ranges = [];
    trial_type_id = [];
    for td = 1:size(trial_defs, 1)
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
            t_start = (max(1, round(sl)) - 1) / srate;
            t_end = (min(EEG.pnts, round(nxt)) - 1) / srate;
            t_bl = max(0, t_start - baseline_sec);
            bl_ranges(end+1, :) = [t_bl, t_end]; %#ok
            trial_ranges(end+1, :) = [t_start, t_end]; %#ok
            trial_type_id(end+1) = td; %#ok
            n_this = n_this + 1;
        end
        fprintf('  %s: %d trials\n', trial_defs{td, 3}, n_this);
    end

    % Baseline correction
    for s = 1:size(trial_ranges, 1)
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
    EEG_seg.chanlocs = EEG.chanlocs;
    EEG_seg.chaninfo = EEG.chaninfo;
    EEG_seg = eeg_checkset(EEG_seg);
    clear EEG;

    % (c) Remove + interpolate bad channels
    if n_bad > 0
        keep_idx = find(~bad_mask);
        EEG_seg = pop_select(EEG_seg, 'channel', keep_idx);
        EEG_seg = eeg_checkset(EEG_seg);
        interp_mask = ismember({brain_chanlocs.labels}, bad_labels);
        target_locs = [EEG_seg.chanlocs, brain_chanlocs(interp_mask)];
        EEG_seg = pop_interp(EEG_seg, target_locs, 'spherical');
        EEG_seg = eeg_checkset(EEG_seg);
        fprintf('  Interpolated %d channels\n', n_bad);
    end

    % (d) Reorder
    cur_labels = {EEG_seg.chanlocs.labels};
    [~, reorder_idx] = ismember(brain_whitelist, cur_labels);
    reorder_idx = reorder_idx(reorder_idx > 0);
    EEG_seg.data = EEG_seg.data(reorder_idx, :);
    EEG_seg.chanlocs = EEG_seg.chanlocs(reorder_idx);
    EEG_seg = eeg_checkset(EEG_seg);

    % (e) Avgref
    EEG_seg = pop_reref(EEG_seg, []);
    EEG_seg = eeg_checkset(EEG_seg);

    n_brain = EEG_seg.nbchan;
    data_rank = n_brain - n_bad - 1;
    fprintf('  Data rank: %d (brain=%d, interp=%d)\n', data_rank, n_brain, n_bad);

    % (f) ASR on movement segments only
    evt_types2 = {EEG_seg.event.type};
    evt_lats2 = [EEG_seg.event.latency];
    n_asr = 0;
    for td = 1:size(trial_defs, 1)
        if ~trial_defs{td, 4}, continue; end
        smk = trial_defs{td, 1};
        emk = trial_defs{td, 2};
        s_lats = evt_lats2(strcmp(evt_types2, smk));
        if ischar(emk)
            e_lats = evt_lats2(strcmp(evt_types2, emk));
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
            EEG_tmp.data = seg_data;
            EEG_tmp.nbchan = size(seg_data, 1);
            EEG_tmp.pnts = size(seg_data, 2);
            EEG_tmp.srate = srate;
            EEG_tmp.xmax = (EEG_tmp.pnts - 1) / srate;
            EEG_tmp.times = (0:EEG_tmp.pnts-1) / srate * 1000;
            EEG_tmp.trials = 1;
            EEG_tmp.chanlocs = EEG_seg.chanlocs;
            EEG_tmp = eeg_checkset(EEG_tmp);
            try
                EEG_tmp = clean_rawdata(EEG_tmp, 'off', 'off', 'off', 'off', 20, 'off');
                EEG_seg.data(:, i1:i2) = EEG_tmp.data;
                n_asr = n_asr + 1;
            catch ME
                fprintf('  ASR skip: %s\n', ME.message);
            end
        end
    end
    fprintf('  ASR: %d segments cleaned\n', n_asr);

    % (g) runica (fast)
    fprintf('  runica: %d ch, rank %d ...\n', EEG_seg.nbchan, data_rank);
    EEG_seg = pop_runica(EEG_seg, 'icatype', 'runica', 'extended', 1, 'pca', data_rank);
    EEG_seg = eeg_checkset(EEG_seg);
    fprintf('  runica done: %d ICs\n', size(EEG_seg.icaweights, 1));

    % Metadata
    EEG_seg.etc.step2_meta.bad_ch_labels = bad_labels;
    EEG_seg.etc.step2_meta.brain_chanlocs = brain_chanlocs;
    EEG_seg.etc.step2_meta.n_ch_interpolated = n_bad;
    EEG_seg.etc.step2_meta.data_rank = data_rank;
    EEG_seg.etc.step2_meta.corr_thresh = corr_thresh;
    EEG_seg.etc.step2_meta.ica_method = 'runica';
    EEG_seg.etc.step2_meta.trial_type_id = trial_type_id;
    EEG_seg.etc.step2_meta.trial_defs = trial_defs;

    pop_saveset(EEG_seg, 'filename', [label '_step2_runica.set'], ...
        'filepath', out_dir, 'savemode', 'onefile');
    fprintf('  Saved: %s\n', file_step2);
else
    fprintf('Step 2 checkpoint exists, loading...\n');
    EEG_seg = pop_loadset('filename', [label '_step2_runica.set'], 'filepath', out_dir);
end

%% STEP 3: Transfer ICA → ICLabel → reject
if ~exist(file_step3, 'file')
    fprintf('\n--- Step 3: ICA transfer + ICLabel ---\n');
    EEG_out = pop_loadset('filename', [label '_step1.set'], 'filepath', out_dir);

    bad_labels = EEG_seg.etc.step2_meta.bad_ch_labels;
    brain_chanlocs = EEG_seg.etc.step2_meta.brain_chanlocs;

    % Same processing as step2: remove bad → interp → reorder → avgref
    if ~isempty(bad_labels)
        keep_mask = ~ismember({EEG_out.chanlocs.labels}, bad_labels);
        EEG_out = pop_select(EEG_out, 'channel', find(keep_mask));
        interp_mask = ismember({brain_chanlocs.labels}, bad_labels);
        target_locs = [EEG_out.chanlocs, brain_chanlocs(interp_mask)];
        EEG_out = pop_interp(EEG_out, target_locs, 'spherical');
        fprintf('  Interpolated %d bad ch on 0.1Hz\n', length(bad_labels));
    end

    cur_labels = {EEG_out.chanlocs.labels};
    [~, reorder_idx] = ismember(brain_whitelist, cur_labels);
    reorder_idx = reorder_idx(reorder_idx > 0);
    EEG_out.data = EEG_out.data(reorder_idx, :);
    EEG_out.chanlocs = EEG_out.chanlocs(reorder_idx);
    EEG_out = pop_reref(EEG_out, []);
    EEG_out = eeg_checkset(EEG_out);

    % Transfer ICA
    EEG_out.icaweights = EEG_seg.icaweights;
    EEG_out.icasphere = EEG_seg.icasphere;
    EEG_out.icawinv = EEG_seg.icawinv;
    EEG_out.icachansind = EEG_seg.icachansind;
    EEG_out = eeg_checkset(EEG_out);

    % ICLabel
    EEG_out = iclabel(EEG_out);
    ic_classes = EEG_out.etc.ic_classification.ICLabel.classifications;
    artifact_cols = [2 3 4 5 6];
    artifact_max = max(ic_classes(:, artifact_cols), [], 2);
    rej_idx = find(artifact_max > 0.9);

    label_names = {'Brain','Muscle','Eye','Heart','LineNoise','ChanNoise','Other'};
    for k = 1:length(rej_idx)
        [~, mc] = max(ic_classes(rej_idx(k), :));
        fprintf('  Reject IC%d: %s (%.2f)\n', rej_idx(k), label_names{mc}, artifact_max(rej_idx(k)));
    end
    fprintf('  Rejecting %d / %d ICs\n', length(rej_idx), size(ic_classes, 1));

    if ~isempty(rej_idx)
        EEG_out = pop_subcomp(EEG_out, rej_idx, 0);
    end
    EEG_out.icaweights = []; EEG_out.icasphere = [];
    EEG_out.icawinv = []; EEG_out.icachansind = []; EEG_out.icaact = [];
    EEG_out = eeg_checkset(EEG_out);

    EEG_out.etc.step3_meta.rejected_ics = rej_idx(:)';
    EEG_out.etc.step3_meta.n_ics_rejected = length(rej_idx);
    EEG_out.etc.step3_meta.step2_meta = EEG_seg.etc.step2_meta;
    EEG_out.etc.step3_meta.pipeline = sprintf( ...
        'V7-test: 59ch->250Hz->dualHP(1/0.1-40)->badch(corr=%.1f)->interp->CAR->ASR(k=20)->runica->ICLabel(>0.9)', ...
        corr_thresh);

    pop_saveset(EEG_out, 'filename', [label '_step3_runica.set'], ...
        'filepath', out_dir, 'savemode', 'onefile');
    fprintf('  Saved: %s\n', file_step3);
end

fprintf('\n=== P02_Sess04 test done ===\n');
