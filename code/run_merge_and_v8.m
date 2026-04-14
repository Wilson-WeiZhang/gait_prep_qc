%% run_merge_and_v8.m — Merge multi-file sessions then run V8 pipeline
%
% 7 healthy sessions have split EEG recordings that need merging before V8.
% This script: (1) merges .vhdr files via pop_mergeset, (2) saves merged .set,
% (3) runs prep_healthy_v8 on the merged file.
%
% Run on aa:
%   cd ~/gait/code && ~/matlab/bin/matlab -batch "run_merge_and_v8"

clear; clc;

%% Setup
eeglab_path = '/home/wilson/eeglab2024';
addpath(eeglab_path); eeglab nogui;
addpath('/home/wilson/gait/gait_prep_qc/code');
addpath('/home/wilson/gait/gait_prep_qc/code/utils');

raw_base = '/home/wilson/gait/raw_data';
merge_dir = '/home/wilson/gait/merged_eeg';
out_dir = '/home/wilson/gait/prep_data_v8';

if ~exist(merge_dir, 'dir'), mkdir(merge_dir); end
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

%% Define multi-file sessions: {label, {vhdr_paths}}
jobs = {
    'SUB_04_sess02', {
        fullfile(raw_base, 'SUB_04/sess02_11Mar2026-141250.957/EEG/a2walk_cbcr_0017.vhdr')
        fullfile(raw_base, 'SUB_04/sess02_11Mar2026-143125.403/EEG/a2walk_cbcr_0018.vhdr')
    }
    'SUB_09_sess02', {
        fullfile(raw_base, 'SUB_09/sess02_23Mar2026-135433.557/EEG/a2walk_cbcr_0026.vhdr')
        fullfile(raw_base, 'SUB_09/sess02_23Mar2026-142441.410/EEG/a2walk_cbcr_0027.vhdr')
    }
    'SUB_10_sess01', {
        fullfile(raw_base, 'SUB_10/sess01_06Mar2026-140341.688/EEG/a2walk_cbcr_0015.vhdr')
        fullfile(raw_base, 'SUB_10/sess01_06Mar2026-141209.252/EEG/a2walk_cbcr_0016.vhdr')
    }
    'SUB_12_sess01', {
        fullfile(raw_base, 'SUB_12/sess01_17Mar2026-105800.701/EEG/imgait_s1_0004.vhdr')
        fullfile(raw_base, 'SUB_12/sess01_17Mar2026-112420.855/EEG/imgait_s1_0005.vhdr')
    }
    'SUB_16_sess01', {
        fullfile(raw_base, 'SUB_16/sess01_18Mar2026-135057.650/EEG/a2walk_cbcr_0022.vhdr')
        fullfile(raw_base, 'SUB_16/sess01_18Mar2026-143726.758/EEG/a2walk_cbcr_0023.vhdr')
    }
    'SUB_22_sess01', {
        fullfile(raw_base, 'SUB_22/sess01_30Mar2026-153954.902/EEG/a2walk_cbcr_0034.vhdr')
        fullfile(raw_base, 'SUB_22/sess01_30Mar2026-161720.228/EEG/a2walk_cbcr_0035.vhdr')
        fullfile(raw_base, 'SUB_22/sess01_30Mar2026-17/EEG/a2walk_cbcr_0035.vhdr')
    }
    'SUB_28_sess01', {
        fullfile(raw_base, 'SUB_28/sess01_07Apr2026-155122.402 (block-1)/EEG/a2walk_cbcr_0044.vhdr')
        fullfile(raw_base, 'SUB_28/sess01_07Apr2026-164148.666 (block-2)/EEG/a2walk_cbcr_0045.vhdr')
        fullfile(raw_base, 'SUB_28/sess01_07Apr2026-165711.346 (block-3)/EEG/a2walk_cbcr_0046.vhdr')
    }
};

n_jobs = size(jobs, 1);
fprintf('=== Merge + V8: %d sessions ===\n\n', n_jobs);

%% Process each session
for j = 1:n_jobs
    label = jobs{j, 1};
    vhdrs = jobs{j, 2};

    fprintf('\n========== [%d/%d] %s (%d files) ==========\n', j, n_jobs, label, length(vhdrs));

    merged_file = fullfile(merge_dir, [label '_merged.set']);

    %% Step A: Merge (skip if already done)
    if exist(merged_file, 'file')
        fprintf('  Merged file exists, skip merge\n');
    else
        % Load and merge
        datasets = [];
        for f = 1:length(vhdrs)
            vhdr = vhdrs{f};
            [fdir, fname, ~] = fileparts(vhdr);
            fprintf('  Loading file %d: %s\n', f, fname);

            if ~exist(vhdr, 'file')
                fprintf('  ERROR: file not found: %s\n', vhdr);
                break;
            end

            EEG_tmp = pop_loadbv(fdir, [fname '.vhdr']);
            EEG_tmp = eeg_checkset(EEG_tmp);
            fprintf('    %d ch x %d pts @ %d Hz (%.1f s), %d events\n', ...
                EEG_tmp.nbchan, EEG_tmp.pnts, EEG_tmp.srate, EEG_tmp.xmax, length(EEG_tmp.event));

            if isempty(datasets)
                datasets = EEG_tmp;
            else
                datasets(end+1) = EEG_tmp; %#ok<AGROW>
            end
        end

        if length(datasets) ~= length(vhdrs)
            fprintf('  SKIP: not all files loaded\n');
            continue;
        end

        % Merge
        fprintf('  Merging %d datasets...\n', length(datasets));
        EEG_merged = pop_mergeset(datasets, 1:length(datasets));
        EEG_merged = eeg_checkset(EEG_merged);
        fprintf('  Merged: %d ch x %d pts @ %d Hz (%.1f s), %d events\n', ...
            EEG_merged.nbchan, EEG_merged.pnts, EEG_merged.srate, ...
            EEG_merged.xmax, length(EEG_merged.event));

        % Save merged
        pop_saveset(EEG_merged, 'filename', [label '_merged.set'], 'filepath', merge_dir);
        fprintf('  Saved: %s\n', merged_file);
        clear datasets EEG_tmp EEG_merged;
    end

    %% Step B: Run V8
    fprintf('  Running V8 pipeline...\n');
    try
        prep_healthy_v8(merged_file, out_dir, 4, label);
        fprintf('  V8 DONE: %s\n', label);
    catch ME
        fprintf('  V8 FAILED: %s — %s\n', label, ME.message);
    end
end

fprintf('\n\n=== All done ===\n');
