%% extract_goniometer_all.m
% Load goniometer data for all sessions, align with EEG via Stim/S10 trigger,
% extract joint angles for each gait imagery trial, and save.
%
% For each session:
%   1. Load all goniometer enggunit.txt files (multiple recordings per session)
%   2. Load corresponding EEG to get event markers
%   3. Align time using Stim channel onset (goni) vs S10 marker (EEG)
%   4. Extract joint angle segments matching each gait imagery trial (S1->S2)
%   5. Save per-session .mat with trial-aligned joint angles

clear; clc;

eeglab_path = 'C:\Users\Admin\OneDrive - Nanyang Technological University\matlabsoft\eeglab-eeglab2024.2';
addpath(eeglab_path);
eeglab nogui;

proj_dir  = fileparts(fileparts(mfilename('fullpath')));
out_dir   = fullfile(proj_dir, 'goni_data');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

sub01_dir = fullfile(proj_dir, 'raw_data', 'SUBJECT-01');
sub02_dir = fullfile(proj_dir, 'raw_data', 'SUBJECT-02');

%% Define sessions: {label, subj, session_dir, {eeg_vhdr_files}, {goni_enggunit_files}}
% Only sessions with enggunit.txt files
jobs = {
    'Sub01_Sess01', 'Sub01', {
        fullfile(sub01_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-133011.065')
        fullfile(sub01_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-134657.811')
        fullfile(sub01_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-135645.822')
        fullfile(sub01_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-140930.111')
        fullfile(sub01_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-143017.711')
    }
    'Sub01_Sess02', 'Sub01', {
        fullfile(sub01_dir, 'RESTORE2_001_Sess02', 'sess02_13Nov2025-151356.773')
        fullfile(sub01_dir, 'RESTORE2_001_Sess02', 'sess02_13Nov2025-152740.938')
        fullfile(sub01_dir, 'RESTORE2_001_Sess02', 'sess02_13Nov2025-153915.611')
    }
    'Sub01_Sess03', 'Sub01', {
        fullfile(sub01_dir, 'RESTORE2_001_Sess03', 'sess03_22Dec2025-123350.818')
    }
    'Sub01_Sess04', 'Sub01', {
        fullfile(sub01_dir, 'RESTORE2_001_Sess04', 'sess04_20Jan2026-113202.009')
        fullfile(sub01_dir, 'RESTORE2_001_Sess04', 'sess04_20Jan2026-120842.115')
    }
    'Sub01_Sess05', 'Sub01', {
        fullfile(sub01_dir, 'RESTORE2_001_Sess05', 'sess03_20Feb2026-115928.609')
    }
    'Sub02_Sess01', 'Sub02', {
        fullfile(sub02_dir, 'RESTORE2_002_Sess01', 'sess01_05Jan2026-155815.425')
    }
    'Sub02_Sess02', 'Sub02', {
        fullfile(sub02_dir, 'RESTORE2_002_Sess02', 'sess02_29Jan2026-131634.955')
    }
    'Sub02_Sess03', 'Sub02', {
        fullfile(sub02_dir, 'sess03_02Mar2026-140612.038')
    }
};

n_jobs = size(jobs, 1);

for j = 1:n_jobs
    label    = jobs{j, 1};
    subj     = jobs{j, 2};
    rec_dirs = jobs{j, 3};

    fprintf('\n============================================\n');
    fprintf('=== %s ===\n', label);
    fprintf('============================================\n');

    session_goni = struct('recordings', {{}});

    for r = 1:length(rec_dirs)
        rec_dir = rec_dirs{r};
        [~, rec_name] = fileparts(rec_dir);

        % --- Find goniometer file ---
        goni_dir = fullfile(rec_dir, 'Goniometer');
        goni_files = dir(fullfile(goni_dir, '*eng*unit*.txt'));
        if isempty(goni_files)
            fprintf('  [%s/%s] No enggunit file, skipping.\n', label, rec_name);
            continue;
        end
        goni_file = fullfile(goni_files(1).folder, goni_files(1).name);
        fprintf('  [%s/%s] Goni: %s\n', label, rec_name, goni_files(1).name);

        % --- Load goniometer ---
        goni = load_goniometer(goni_file);

        % --- Find EEG file ---
        eeg_dir = fullfile(rec_dir, 'EEG');
        vhdr_files = dir(fullfile(eeg_dir, '*.vhdr'));
        if isempty(vhdr_files)
            fprintf('  [%s/%s] No .vhdr file, skipping.\n', label, rec_name);
            continue;
        end
        vhdr_file = fullfile(vhdr_files(1).folder, vhdr_files(1).name);

        % --- Load EEG (header + events only) ---
        EEG = pop_loadbv(eeg_dir, vhdr_files(1).name);

        % --- Extract EEG events ---
        eeg_events = struct('type', {}, 'latency', {}, 'label', {});
        for e = 1:length(EEG.event)
            evt = EEG.event(e);
            if strcmp(evt.code, 'Stimulus') || strcmp(evt.code, 'Response')
                eeg_events(end+1).type = evt.type;
                eeg_events(end).latency = evt.latency;
                num = str2double(regexprep(evt.type, '\D', ''));
                eeg_events(end).label = num;
            end
        end
        eeg_srate = EEG.srate;

        % --- Align: S10 in EEG vs first Stim onset in goniometer ---
        % EEG: find first S10 marker (latency in samples at eeg_srate)
        eeg_labels = [eeg_events.label];
        s10_idx = find(eeg_labels == 10, 1, 'first');
        if isempty(s10_idx)
            fprintf('  [%s/%s] No S10 marker in EEG, trying S11...\n', label, rec_name);
            s10_idx = find(eeg_labels == 11, 1, 'first');
        end
        if isempty(s10_idx)
            fprintf('  [%s/%s] No S10/S11 marker, cannot align. Skipping.\n', label, rec_name);
            continue;
        end
        eeg_t0_samples = eeg_events(s10_idx).latency;  % in EEG samples
        eeg_t0_sec = eeg_t0_samples / eeg_srate;

        % Goniometer: find first Stim onset
        if ~isempty(goni.stim)
            goni_t0_idx = find(goni.stim ~= 0, 1, 'first');
            if isempty(goni_t0_idx)
                fprintf('  [%s/%s] Stim channel all zeros, cannot align. Skipping.\n', label, rec_name);
                continue;
            end
            goni_t0_sec = (goni_t0_idx - 1) / goni.srate;
        else
            fprintf('  [%s/%s] No Stim channel, cannot align. Skipping.\n', label, rec_name);
            continue;
        end

        % Time offset: to convert EEG time -> goni index
        % eeg_sec -> goni_sec = eeg_sec - eeg_t0_sec + goni_t0_sec
        offset_sec = goni_t0_sec - eeg_t0_sec;
        fprintf('  [%s/%s] Alignment: EEG_S10=%.2fs, Goni_Stim=%.2fs, offset=%.2fs\n', ...
            label, rec_name, eeg_t0_sec, goni_t0_sec, offset_sec);

        % --- Find gait imagery trials (S1->S2 pairs) ---
        s1_indices = find(eeg_labels == 1);
        s2_indices = find(eeg_labels == 2);
        trials = struct('s1_eeg_sec', {}, 's2_eeg_sec', {}, 'dur', {}, ...
            'goni_start_idx', {}, 'goni_end_idx', {}, 'joint_angles', {});

        for i = 1:length(s1_indices)
            s1_lat = eeg_events(s1_indices(i)).latency / eeg_srate;
            % Find next S2 after this S1
            next_s2 = s2_indices(find([eeg_events(s2_indices).latency] / eeg_srate > s1_lat, 1, 'first'));
            if isempty(next_s2), continue; end
            s2_lat = eeg_events(next_s2).latency / eeg_srate;

            % Check no intervening S1
            intervening = s1_indices(find([eeg_events(s1_indices).latency] / eeg_srate > s1_lat & ...
                [eeg_events(s1_indices).latency] / eeg_srate < s2_lat));
            if ~isempty(intervening), continue; end

            dur = s2_lat - s1_lat;
            if dur < 3 || dur > 60, continue; end  % sanity check

            % Convert to goniometer indices
            goni_start = round((s1_lat + offset_sec) * goni.srate) + 1;
            goni_end   = round((s2_lat + offset_sec) * goni.srate) + 1;

            % Bounds check
            goni_start = max(1, goni_start);
            goni_end   = min(goni.n_samples, goni_end);

            if goni_start >= goni_end, continue; end

            t_idx = length(trials) + 1;
            trials(t_idx).s1_eeg_sec    = s1_lat;
            trials(t_idx).s2_eeg_sec    = s2_lat;
            trials(t_idx).dur           = dur;
            trials(t_idx).goni_start_idx = goni_start;
            trials(t_idx).goni_end_idx   = goni_end;
            trials(t_idx).joint_angles   = goni.data(goni_start:goni_end, :);
        end

        fprintf('  [%s/%s] Extracted %d gait imagery trials with joint angles\n', ...
            label, rec_name, length(trials));

        % Store recording data
        rec_data.rec_name    = rec_name;
        rec_data.goni_file   = goni_file;
        rec_data.goni_labels = goni.labels;
        rec_data.goni_srate  = goni.srate;
        rec_data.eeg_srate   = eeg_srate;
        rec_data.offset_sec  = offset_sec;
        rec_data.trials      = trials;
        rec_data.n_trials    = length(trials);
        session_goni.recordings{end+1} = rec_data;
    end

    % --- Save session-level goniometer data ---
    session_goni.label = label;
    session_goni.subject = subj;
    session_goni.n_recordings = length(session_goni.recordings);

    total_trials = 0;
    for r = 1:length(session_goni.recordings)
        total_trials = total_trials + session_goni.recordings{r}.n_trials;
    end
    session_goni.total_trials = total_trials;

    out_file = fullfile(out_dir, sprintf('%s_goniometer.mat', label));
    save(out_file, '-struct', 'session_goni', '-v7.3');
    fprintf('  [%s] Saved: %s (%d recordings, %d total trials)\n', ...
        label, out_file, session_goni.n_recordings, total_trials);
end

fprintf('\n====== All sessions done! ======\n');
fprintf('Goniometer data saved to: %s\n', out_dir);
