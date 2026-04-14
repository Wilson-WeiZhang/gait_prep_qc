%% run_full_pipeline.m -- End-to-end healthy EEG + Goni pipeline
%
% Runs all steps for healthy subjects:
%   Phase 1: EEG preprocessing (V8) -- step1 through step4 (epochs)
%   Phase 2: V8 QC report (ICLabel brain probability check)
%   Phase 3: Goni extraction + alignment + QC
%   Phase 4: EEG-Goni pairing
%
% For new subjects: place raw data in raw_data/SUB_XX/sessNN_{date}/EEG+Goniometer/
% Then run this script. It skips sessions that already have final output.
%
% Usage on aa:
%   cd ~/gait/gait_prep_qc/code && ~/matlab/bin/matlab -batch "run_full_pipeline"
%
% To run only specific phases, set phase_start before calling:
%   phase_start = 3;  % skip EEG preprocessing, start from goni extraction
%   run_full_pipeline

if ~exist('phase_start', 'var'), phase_start = 1; end

%% Setup paths
if ismac
    eeglab_path = '/Users/zw/Desktop/eeglab-eeglab2024.2';
    raw_base = '/Users/zw/Library/CloudStorage/OneDrive-NanyangTechnologicalUniversity/gait_data';
    prep_dir = '';  % V8 preprocessing runs on aa only
    goni_out = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'result', 'goni_healthy');
else  % aa server
    eeglab_path = '/home/wilson/eeglab2024';
    raw_base = '/home/wilson/gait/raw_data';
    prep_dir = '/home/wilson/gait/prep_data_v8';
    goni_out = '/home/wilson/gait/gait_prep_qc/result/goni_healthy';
end

addpath(eeglab_path); eeglab nogui;
code_dir = fileparts(mfilename('fullpath'));
addpath(code_dir);
addpath(fullfile(code_dir, 'utils'));

%% ========== Phase 1: EEG V8 preprocessing ==========
if phase_start <= 1 && ~isempty(prep_dir)
    fprintf('\n\n==============================\n');
    fprintf('=== PHASE 1: EEG V8 Preprocessing ===\n');
    fprintf('==============================\n');

    % Find all sessions with raw EEG but no epochs
    vhdrs = dir(fullfile(raw_base, 'SUB_*', 'sess*', 'EEG', '*.vhdr'));
    sessions_done = {};
    epoch_files = dir(fullfile(prep_dir, '*_epochs_bp.mat'));
    for i = 1:length(epoch_files)
        sessions_done{end+1} = strrep(epoch_files(i).name, '_epochs_bp.mat', '');
    end

    n_new = 0;
    for i = 1:length(vhdrs)
        vhdr_path = fullfile(vhdrs(i).folder, vhdrs(i).name);
        % Extract label from path
        parts = strsplit(vhdrs(i).folder, filesep);
        sub_idx = find(startsWith(parts, 'SUB_'), 1, 'last');
        if isempty(sub_idx), continue; end
        sub = parts{sub_idx};
        sess_dir = parts{sub_idx + 1};
        sess = regexp(sess_dir, '(sess\d+)', 'tokens', 'once');
        if isempty(sess), continue; end
        label = sprintf('%s_%s', sub, sess{1});

        if ismember(label, sessions_done)
            continue;  % already has epochs
        end

        fprintf('\n--- V8: %s ---\n', label);
        try
            prep_healthy_v8(vhdr_path, prep_dir, 4, label);
            n_new = n_new + 1;
        catch ME
            fprintf('  FAILED: %s\n', ME.message);
        end
    end

    % Also handle multi-file sessions via merge
    merged_dir = fullfile(fileparts(prep_dir), 'merged_eeg');
    merged_files = dir(fullfile(merged_dir, '*_merged.set'));
    for i = 1:length(merged_files)
        label = strrep(merged_files(i).name, '_merged.set', '');
        if ismember(label, sessions_done), continue; end
        fprintf('\n--- V8 (merged): %s ---\n', label);
        try
            prep_healthy_v8(fullfile(merged_files(i).folder, merged_files(i).name), prep_dir, 4, label);
            n_new = n_new + 1;
        catch ME
            fprintf('  FAILED: %s\n', ME.message);
        end
    end

    fprintf('\nPhase 1 done: %d new sessions processed\n', n_new);
end

%% ========== Phase 2: V8 QC Report ==========
if phase_start <= 2 && ~isempty(prep_dir)
    fprintf('\n\n==============================\n');
    fprintf('=== PHASE 2: V8 QC Report ===\n');
    fprintf('==============================\n');
    try
        report_v8_summary;
    catch ME
        fprintf('  Report failed: %s\n', ME.message);
    end
end

%% ========== Phase 3: Goni Extraction + Alignment + QC ==========
if phase_start <= 3
    fprintf('\n\n==============================\n');
    fprintf('=== PHASE 3: Goni Extraction ===\n');
    fprintf('==============================\n');
    extract_goni_all_healthy;
end

%% ========== Phase 4: EEG-Goni Pairing ==========
if phase_start <= 4 && ~isempty(prep_dir)
    fprintf('\n\n==============================\n');
    fprintf('=== PHASE 4: EEG-Goni Pairing ===\n');
    fprintf('==============================\n');
    pair_eeg_goni_v2;
end

fprintf('\n\n=== PIPELINE COMPLETE ===\n');
