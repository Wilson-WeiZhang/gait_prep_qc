%% run_prep_p02_sess04.m — Preprocess P02_Sess04 (task + resting)
%
% Two recordings:
%   1. Task EEG (RESTORE2-0027.vhdr): MI + S2S + Walk2min → prep_3step, patient markers
%   2. Resting EEG (RESTORE2-0026.vhdr): 4 segments (EO/EC × 2) → V6-style pipeline
%
% REF impedance: all blue (< 10 kΩ) → full pipeline OK
%
% Run: cd('C:\Users\Admin\OneDrive\gait\code'); run_prep_p02_sess04

clear; clc;

proj_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(proj_dir, 'code'));

if ispc
    out_dir = fullfile(proj_dir, 'data', 'prep_eeg', 'patient');
else
    out_dir = fullfile(proj_dir, 'prep_data_v5');
end
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

if ispc
    eeglab_path = 'C:\Users\Admin\OneDrive - Nanyang Technological University\matlabsoft\eeglab-eeglab2024.2';
elseif ismac
    eeglab_path = '/Users/zw/Desktop/eeglab-eeglab2024.2';
else
    eeglab_path = '/home/wilson/eeglab2024';
end
addpath(eeglab_path); eeglab nogui;

if ispc
    sess_base = fullfile(proj_dir, 'data', 'raw_data', 'patient', ...
        'SUBJECT-02', 'RESTORE2_002_Sess04');
else
    sess_base = fullfile(proj_dir, 'raw_data', 'patient', ...
        'SUBJECT-02', 'RESTORE2_002_Sess04');
end

%% ========== 1. Task EEG ==========
fprintf('\n===== Task EEG: P02_Sess04 =====\n');

task_vhdr = fullfile(sess_base, ...
    'sess04_06Apr2026-115201.751', 'EEG', 'RESTORE2-0027.vhdr');

if ~exist(task_vhdr, 'file')
    error('Task EEG not found: %s', task_vhdr);
end

prep_3step(task_vhdr, out_dir, 4, 'P02_Sess04', false, 2, 'patient');

%% ========== 2. Resting EEG ==========
fprintf('\n===== Resting EEG: P02_Sess04 =====\n');

rest_vhdr = fullfile(sess_base, 'RestingEEG', 'RESTORE2-0026.vhdr');

if ~exist(rest_vhdr, 'file')
    error('Resting EEG not found: %s', rest_vhdr);
end

prep_resting_v6(rest_vhdr, out_dir, 'P02_Sess04_Resting');

fprintf('\n===== All done =====\n');


%% =========================================================
function prep_resting_v6(vhdr_file, out_dir, out_label)
% Resting EEG preprocessing following V6 pipeline standards.
%   59ch whitelist, 250Hz, 0.5-40Hz, clean_rawdata, ASR, runica, ICLabel
%
% Markers expected: eye_open → stop, eye_close → stop (×2 cycles)
% Output: _resting_clean.set + _resting_epochs.mat

brain_whitelist = {'Fp1','Fz','F3','F7','FC5','FC1','C3','T7','CP5','CP1', ...
    'Pz','P3','P7','O1','Oz','O2','P4','P8','CP6','CP2', ...
    'Cz','C4','T8','FC6','FC2','F4','F8','Fp2', ...
    'AF7','AF3','AFz','F1','F5','FT7','FC3','C1','C5','TP7', ...
    'CP3','P1','P5','PO7','PO3','POz','PO4','PO8','P6','P2', ...
    'CPz','CP4','TP8','C6','C2','FC4','FT8','F6','AF8','AF4','F2'};

%% Load
[fpath, fname, ~] = fileparts(vhdr_file);
EEG = pop_loadbv(fpath, [fname '.vhdr']);
EEG = eeg_checkset(EEG);
fprintf('Loaded: %d ch, %d pts, %.1f sec, %d Hz\n', EEG.nbchan, EEG.pnts, EEG.xmax, EEG.srate);

%% Chanlocs lookup
% Find elc file across common dipfit plugin names
eeglab_root = fileparts(which('eeglab'));
elc_file = '';
dipfit_dirs = dir(fullfile(eeglab_root, 'plugins', 'dipfit*'));
for dd = 1:numel(dipfit_dirs)
    candidate = fullfile(eeglab_root, 'plugins', dipfit_dirs(dd).name, 'standard_BEM', 'elec', 'standard_1005.elc');
    if exist(candidate, 'file'), elc_file = candidate; break; end
end
if isempty(elc_file), error('standard_1005.elc not found in any dipfit plugin'); end
EEG = pop_chanedit(EEG, 'lookup', elc_file);
EEG = eeg_checkset(EEG);

%% Select 59 brain channels (whitelist)
current_labels = {EEG.chanlocs.labels};
keep_idx = [];
for i = 1:numel(brain_whitelist)
    idx = find(strcmpi(current_labels, brain_whitelist{i}));
    if ~isempty(idx)
        keep_idx(end+1) = idx(1); %#ok<AGROW>
    end
end
EEG = pop_select(EEG, 'channel', keep_idx);
fprintf('Selected %d/%d brain channels\n', EEG.nbchan, numel(current_labels));

%% Resample 250 Hz
fprintf('Resampling -> 250 Hz ...\n');
EEG = pop_resample(EEG, 250);
EEG = eeg_checkset(EEG);

%% Bandpass 0.5-40 Hz
fprintf('Bandpass 0.5-40 Hz ...\n');
EEG = pop_eegfiltnew(EEG, 'locutoff', 0.5, 'hicutoff', 40);
EEG = eeg_checkset(EEG);

%% Parse resting markers: eye_open/eye_close → stop
evt_types = {EEG.event.type};
evt_lats  = [EEG.event.latency];
srate = EEG.srate;

% Find segment boundaries
seg_info = {};
for i = 1:numel(evt_types)
    if contains(evt_types{i}, 'eye_open') || contains(evt_types{i}, 'eye_close')
        % Find next 'stop'
        stop_idx = find(strcmp(evt_types, 'stop') & (1:numel(evt_types)) > i, 1);
        if ~isempty(stop_idx)
            seg_info{end+1} = struct( ...
                'type', evt_types{i}, ...
                'start_samp', round(evt_lats(i)), ...
                'end_samp', round(evt_lats(stop_idx)), ...
                'dur_sec', (evt_lats(stop_idx) - evt_lats(i)) / srate); %#ok<AGROW>
            fprintf('  Segment: %s, %.1f sec\n', evt_types{i}, seg_info{end}.dur_sec);
        end
    end
end

if numel(seg_info) ~= 4
    warning('Expected 4 resting segments, found %d', numel(seg_info));
end

% Label segments
trial_labels = cell(1, numel(seg_info));
eo_count = 0; ec_count = 0;
for i = 1:numel(seg_info)
    if contains(seg_info{i}.type, 'open')
        eo_count = eo_count + 1;
        if eo_count == 1, trial_labels{i} = 'EO_StimOff';
        else,             trial_labels{i} = 'EO_StimOn'; end
    else
        ec_count = ec_count + 1;
        if ec_count == 1, trial_labels{i} = 'EC_StimOff';
        else,             trial_labels{i} = 'EC_StimOn'; end
    end
end
fprintf('Trial labels: %s\n', strjoin(trial_labels, ', '));

%% Save step1 (before artifact rejection, for reference)
EEG_step1 = EEG;
pop_saveset(EEG_step1, 'filename', [out_label '_step1.set'], 'filepath', out_dir, 'savemode', 'onefile');
fprintf('Saved step1: %s_step1.set\n', out_label);

%% Bad channel detection + interpolation
orig_chanlocs = EEG.chanlocs;
n_ch_before = EEG.nbchan;
EEG = clean_rawdata(EEG, 5, -1, 0.8, 4, -1, 'off');
n_ch_after = EEG.nbchan;
n_bad = n_ch_before - n_ch_after;
if n_bad > 0
    bad_labels = setdiff({orig_chanlocs.labels}, {EEG.chanlocs.labels});
    fprintf('Bad channels (%d): %s\n', n_bad, strjoin(bad_labels, ', '));
    EEG = pop_interp(EEG, orig_chanlocs, 'spherical');
else
    fprintf('No bad channels.\n');
end

%% Reorder to whitelist order
reorder_idx = zeros(1, numel(brain_whitelist));
current_labels = {EEG.chanlocs.labels};
for i = 1:numel(brain_whitelist)
    idx = find(strcmpi(current_labels, brain_whitelist{i}));
    if ~isempty(idx), reorder_idx(i) = idx(1); end
end
reorder_idx = reorder_idx(reorder_idx > 0);
EEG.data = EEG.data(reorder_idx, :);
EEG.chanlocs = EEG.chanlocs(reorder_idx);
EEG.nbchan = numel(reorder_idx);
EEG = eeg_checkset(EEG);
fprintf('Reordered to %d whitelist channels\n', EEG.nbchan);

% NOTE: avgref deferred to after ICLabel rejection

%% ASR correction
fprintf('ASR (k=20) ...\n');
EEG_asr = clean_artifacts(EEG, ...
    'FlatlineCriterion', 'off', 'ChannelCriterion', 'off', ...
    'LineNoiseCriterion', 'off', 'BurstCriterion', 20, 'WindowCriterion', 'off');
var_before = mean(var(EEG.data, 0, 2));
var_after  = mean(var(EEG_asr.data, 0, 2));
fprintf('ASR variance reduction: %.1f%%\n', (1 - var_after/var_before) * 100);
EEG = EEG_asr;

%% ICA (runica — faster than AMICA for short resting data)
fprintf('ICA (runica) ...\n');
data_rank = sum(eig(cov(double(EEG.data'))) > 1e-7);
fprintf('Data rank = %d\n', data_rank);
EEG = pop_runica(EEG, 'icatype', 'runica', 'extended', 1, 'pca', data_rank);
EEG = eeg_checkset(EEG);
fprintf('ICA done: %d components.\n', size(EEG.icaweights, 1));

%% ICLabel + reject
EEG = iclabel(EEG);
ic_class = EEG.etc.ic_classification.ICLabel.classifications;
% Reject: artifact > 0.9 OR brain < 0.05
brain_prob = ic_class(:, 1);
artifact_prob = 1 - brain_prob;
reject_mask = (artifact_prob > 0.9) | (brain_prob < 0.05);
n_reject = sum(reject_mask);
fprintf('ICLabel: rejecting %d/%d ICs (%.0f%%)\n', n_reject, size(ic_class,1), 100*n_reject/size(ic_class,1));
EEG = pop_subcomp(EEG, find(reject_mask), 0);
EEG = eeg_checkset(EEG);

%% Average re-reference (after IC rejection)
fprintf('Average re-reference (post-ICA clean) ...\n');
EEG = pop_reref(EEG, []);
EEG = eeg_checkset(EEG);

%% Save clean continuous
EEG.setname = [out_label '_resting_clean'];
EEG.subject = 'P02';
pop_saveset(EEG, 'filename', [out_label '_resting_clean.set'], 'filepath', out_dir, 'savemode', 'onefile');
fprintf('Saved: %s_resting_clean.set\n', out_label);

%% Extract and save epochs
% Re-parse markers from clean EEG (latencies shifted after processing)
evt_types2 = {EEG.event.type};
evt_lats2  = round([EEG.event.latency]);

seg_starts = [];
seg_ends = [];
for i = 1:numel(evt_types2)
    if contains(evt_types2{i}, 'eye_open') || contains(evt_types2{i}, 'eye_close')
        stop_idx = find(strcmp(evt_types2, 'stop') & (1:numel(evt_types2)) > i, 1);
        if ~isempty(stop_idx)
            seg_starts(end+1) = evt_lats2(i); %#ok<AGROW>
            seg_ends(end+1) = evt_lats2(stop_idx); %#ok<AGROW>
        end
    end
end

n_seg = numel(seg_starts);
if n_seg > 0
    trial_lens = seg_ends - seg_starts + 1;
    min_len = min(trial_lens);
    fprintf('Resting segments: %d, min length: %.1f sec\n', n_seg, min_len/EEG.srate);

    n_ch = EEG.nbchan;
    epochs = zeros(n_ch, min_len, n_seg);
    for t = 1:n_seg
        epochs(:, :, t) = EEG.data(:, seg_starts(t):seg_starts(t)+min_len-1);
    end

    chanlocs = EEG.chanlocs;
    epoch_info = struct( ...
        'srate', EEG.srate, 'n_channels', n_ch, 'n_trials', n_seg, ...
        'n_timepoints', min_len, 'trial_labels', {trial_labels(1:n_seg)}, ...
        'subject', 'P02', 'session', 'Sess04', ...
        'pipeline', 'V6: 59ch whitelist, 250Hz, 0.5-40Hz, clean_rawdata, ASR(k=20), runica, ICLabel');

    save(fullfile(out_dir, [out_label '_resting_epochs.mat']), ...
        'epochs', 'chanlocs', 'epoch_info', '-v7.3');
    fprintf('Saved: %s_resting_epochs.mat [%d x %d x %d]\n', out_label, size(epochs));
else
    warning('No resting segments found after processing!');
end

fprintf('\n===== Resting preprocessing done =====\n');
end
