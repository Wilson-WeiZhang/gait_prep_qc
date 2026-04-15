%% extract_goni_all_healthy.m — Goni extraction + IOI alignment + QC for all healthy
%
% Handles both single-file and multi-file sessions via per-segment IOI.
% Output: per-session .mat + grand QC summary
%
% Usage on aa:
%   cd ~/gait/gait_prep_qc/code
%   matlab -batch "extract_goni_all_healthy"

clear; clc;

%% Platform paths
if ispc
    eeglab_path = 'C:\Users\Admin\OneDrive - Nanyang Technological University\matlabsoft\eeglab-eeglab2024.2';
    raw_base = 'C:\Users\Admin\OneDrive - Nanyang Technological University\gait_data';
    out_base = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'result', 'goni_healthy');
elseif ismac
    eeglab_path = '/Users/zw/Desktop/eeglab-eeglab2024.2';
    raw_base = '/Users/zw/Library/CloudStorage/OneDrive-NanyangTechnologicalUniversity/gait_data';
    out_base = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'result', 'goni_healthy');
else  % aa server
    eeglab_path = '/home/wilson/eeglab2024';
    raw_base = '/home/wilson/gait/raw_data';
    out_base = '/home/wilson/gait/gait_prep_qc/result/goni_healthy';
end

addpath(eeglab_path); eeglab nogui;
code_dir = fileparts(mfilename('fullpath'));
addpath(code_dir);
addpath(fullfile(code_dir, 'utils'));

if ~exist(out_base, 'dir'), mkdir(out_base); end
qc_dir = fullfile(out_base, 'qc');
if ~exist(qc_dir, 'dir'), mkdir(qc_dir); end

%% Build job table
jobs = build_healthy_goni_jobs(raw_base);
n_jobs = length(jobs);
fprintf('\n=== Goni extraction: %d sessions ===\n', n_jobs);

%% Process
summary = {};

for j = 1:n_jobs
    job = jobs(j);
    label = job.label;

    % Skip if output already exists
    out_file = fullfile(out_base, sprintf('%s_goni.mat', label));
    if exist(out_file, 'file')
        fprintf('[%d/%d] %s — already done, skip\n', j, n_jobs, label);
        summary{end+1} = sprintf('%-18s  SKIP (exists)', label); %#ok<AGROW>
        continue;
    end

    fprintf('\n========== [%d/%d] %s (%d segments) ==========\n', ...
        j, n_jobs, label, job.n_segments);

    try
        all_trials = struct('type',{},'segment',{},'start_eeg_sec',{},'end_eeg_sec',{}, ...
            'dur_sec',{},'goni_start_idx',{},'goni_end_idx',{},'joint_angles',{},'goni_labels',{});
        all_align_info = cell(job.n_segments, 1);
        all_goni_srate = 1000;

        %% Pre-load all EEG markers and goni data per segment
        seg_eeg = cell(job.n_segments, 1);
        seg_eeg_nums = cell(job.n_segments, 1);
        seg_goni = cell(job.n_segments, 1);
        seg_goni_times = cell(job.n_segments, 1);

        for seg_i = 1:job.n_segments
            s = job.segments(seg_i);
            fprintf('  --- Loading segment %d ---\n', seg_i);

            % Load EEG markers
            [eeg_dir, vhdr_name, ~] = fileparts(s.eeg_vhdr);
            EEG = pop_loadbv(eeg_dir, [vhdr_name '.vhdr']);
            eeg_srate = EEG.srate;

            et = []; en = []; r1_times = [];
            for e = 1:length(EEG.event)
                evt = EEG.event(e);
                if startsWith(evt.type, 'S')
                    num = str2double(regexprep(evt.type, '\D', ''));
                    if isnan(num), continue; end
                    et(end+1) = evt.latency / eeg_srate; %#ok<AGROW>
                    en(end+1) = num; %#ok<AGROW>
                elseif startsWith(evt.type, 'R')
                    num = str2double(regexprep(evt.type, '\D', ''));
                    if num == 1
                        r1_times(end+1) = evt.latency / eeg_srate; %#ok<AGROW>
                    end
                end
            end
            seg_eeg{seg_i} = et;
            seg_eeg_nums{seg_i} = en;

            % Load Goni
            goni = load_goniometer(s.goni_txt);
            all_goni_srate = goni.srate;
            stim = goni.stim;
            goni_rising = find(stim(1:end-1) == 0 & stim(2:end) > 0) + 1;
            gt = (goni_rising(:)' - 1) / goni.srate;

            % Filter spurious stim onsets (IOI < 50ms = noise)
            if length(gt) > 1
                goni_ioi_raw = diff(gt);
                keep = [true, goni_ioi_raw >= 0.05];
                n_spurious = sum(~keep);
                if n_spurious > 0
                    fprintf('  Filtered %d spurious goni stim (IOI < 50ms)\n', n_spurious);
                    gt = gt(keep);
                end
            end

            seg_goni{seg_i} = goni;
            seg_goni_times{seg_i} = gt;
            fprintf('  EEG: %d markers, Goni: %d stim\n', length(et), length(gt));
        end

        %% Multi-segment: assume goni files are in correct folders (1:1 with EEG)
        % SUB_12_sess01 goni files were swapped in raw data -- fixed 2026-04-13
        goni_assign = 1:job.n_segments;

        %% Process each segment with assigned goni
        for seg_i = 1:job.n_segments
            gi = goni_assign(seg_i);
            seg_label = sprintf('%s_seg%d', label, seg_i);
            fprintf('  --- Segment %d (goni=%d) ---\n', seg_i, gi);

            eeg_times = seg_eeg{seg_i};
            eeg_nums = seg_eeg_nums{seg_i};
            goni = seg_goni{gi};
            goni_times = seg_goni_times{gi};

            if length(eeg_times) < 15 || length(goni_times) < 15
                fprintf('  WARNING: too few events (EEG=%d, Goni=%d), skipping segment %d\n', ...
                    length(eeg_times), length(goni_times), seg_i);
                all_align_info{seg_i} = struct('method','skip','n_matched',0,'match_frac',0);
                continue;
            end

            %% IOI Alignment (per-segment try-catch so one bad segment doesn't kill session)
            try
                [offset, align_info] = align_ioi(eeg_times, goni_times, seg_label);
                [~, match_frac, ~, ~] = validate_alignment(eeg_times, goni_times, offset, seg_label, qc_dir);
                align_info.match_frac = match_frac;
                all_align_info{seg_i} = align_info;
            catch seg_err
                fprintf('  WARNING: alignment failed for segment %d: %s\n', seg_i, seg_err.message);
                all_align_info{seg_i} = struct('method','failed','n_matched',0,'match_frac',0);
                continue;
            end

            %% Special case: per-segment offsets for clock-drift sessions
            % See gait_prep_qc/note/align_special_cases.md for details
            offset_segments = get_special_offsets(label, offset);

            %% Extract trials
            trial_mask = eeg_nums ~= 11 & eeg_nums ~= 12 & eeg_nums ~= 10;
            trial_times = eeg_times(trial_mask);
            trial_nums = eeg_nums(trial_mask);

            % SUB_01_sess01 special case: no S7/S8 markers, rest encoded as R1+S4->S5
            % Use R1 co-occurrence to split S4->S5 into walk vs rest
            has_r1_rest = ~isempty(r1_times) && ...
                          ~any(trial_nums == 7) && ~any(trial_nums == 8);
            if has_r1_rest
                fprintf('  ** Special case: using R1 markers to separate walk/rest from S4->S5 **\n');
            end

            pairs = {1, 2, 'imagine'; 4, 5, 'walk'; 7, 8, 'rest'};
            for p = 1:size(pairs, 1)
                s_start = pairs{p,1}; s_end = pairs{p,2}; ttype = pairs{p,3};

                % Skip S7->S8 extraction if this session has no S7/S8
                if s_start == 7 && has_r1_rest, continue; end

                start_t = trial_times(trial_nums == s_start);
                end_t = trial_times(trial_nums == s_end);

                for i = 1:length(start_t)
                    t1 = start_t(i);
                    next_ends = end_t(end_t > t1);
                    if isempty(next_ends), continue; end
                    t2 = next_ends(1);
                    if any(start_t > t1 & start_t < t2), continue; end
                    dur = t2 - t1;
                    if dur < 3 || dur > 60, continue; end

                    % Reclassify S4->S5 as rest if R1 co-occurs (within 50ms)
                    actual_type = ttype;
                    if has_r1_rest && s_start == 4
                        if any(abs(r1_times - t1) < 0.05)
                            actual_type = 'rest';
                        end
                    end

                    trial_offset = lookup_offset(offset_segments, t1);
                    g1 = max(1, round((t1 + trial_offset) * goni.srate) + 1);
                    g2 = min(goni.n_samples, round((t2 + trial_offset) * goni.srate) + 1);
                    if g1 >= g2, continue; end

                    t_idx = length(all_trials) + 1;
                    all_trials(t_idx).type = actual_type;
                    all_trials(t_idx).segment = seg_i;
                    all_trials(t_idx).start_eeg_sec = t1;
                    all_trials(t_idx).end_eeg_sec = t2;
                    all_trials(t_idx).dur_sec = dur;
                    all_trials(t_idx).goni_start_idx = g1;
                    all_trials(t_idx).goni_end_idx = g2;
                    all_trials(t_idx).joint_angles = goni.data(g1:g2, :);
                    all_trials(t_idx).goni_labels = goni.labels;
                end
            end
        end

        if isempty(all_trials)
            error('No trials extracted');
        end

        n_im = sum(strcmp({all_trials.type}, 'imagine'));
        n_wk = sum(strcmp({all_trials.type}, 'walk'));
        n_rs = sum(strcmp({all_trials.type}, 'rest'));
        fprintf('  Trials: %d imagine, %d walk, %d rest\n', n_im, n_wk, n_rs);

        %% QC
        qc = qc_goni_trial(all_trials, all_trials(1).goni_labels);
        n_prob = sum(strcmp({qc.status}, 'problem'));
        fprintf('  QC: %d problems\n', n_prob);

        %% Save
        result.label = label;
        result.n_segments = job.n_segments;
        result.align_info = all_align_info;
        result.trials = all_trials;
        result.qc = qc;
        result.goni_labels = all_trials(1).goni_labels;
        result.goni_srate = all_goni_srate;
        result.n_imagine = n_im;
        result.n_walk = n_wk;
        result.n_rest = n_rs;
        result.n_problems = n_prob;

        save(out_file, '-struct', 'result', '-v7.3');
        fprintf('  Saved: %s\n', out_file);

        summary{end+1} = sprintf('%-18s %2d seg  %3d/%3d/%3d  %2d prob  %.0f%%', ...
            label, job.n_segments, n_im, n_wk, n_rs, n_prob, ...
            all_align_info{1}.match_frac * 100); %#ok<AGROW>

    catch ME
        fprintf('  !!! FAILED: %s\n', ME.message);
        summary{end+1} = sprintf('%-18s  FAILED: %s', label, ME.message); %#ok<AGROW>
    end
end

%% Grand Summary
fprintf('\n\n========================================\n');
fprintf('=== GRAND SUMMARY ===\n');
fprintf('========================================\n');
fid = fopen(fullfile(out_base, 'goni_qc_summary.txt'), 'w');
fprintf(fid, '%-18s %5s  %3s/%3s/%3s  %5s  %6s\n', 'Session', 'Segs', 'MI', 'Wlk', 'Rst', 'Probs', 'Match');
fprintf(fid, '%s\n', repmat('-', 1, 60));
for i = 1:length(summary)
    fprintf('  %s\n', summary{i});
    fprintf(fid, '%s\n', summary{i});
end
fclose(fid);
fprintf('\nSummary: %s\n', fullfile(out_base, 'goni_qc_summary.txt'));


%% ========== Helper functions ==========

function segs = get_special_offsets(label, default_offset)
%% Return per-segment offset table for clock-drift sessions.
%  Normal sessions: single segment covering all EEG times.
%  Special cases: multiple segments with different offsets.
%  See gait_prep_qc/note/align_special_cases.md
%
%  Each row: [eeg_time_boundary, offset_for_times_below_this_boundary]
%  Last row boundary = Inf (catch-all).

switch label
    case 'SUB_07_sess02'
        % Clock drift: +0.244s after ~1700s EEG time
        segs = [1700, -28.085; Inf, -27.841];
        fprintf('  ** Special case: SUB_07_sess02 per-segment offsets (2 segments) **\n');

    case 'SUB_27_sess01'
        % Initial offset mismatch + late drift
        % Seg A (EEG 0-260s): -11.840
        % Seg B (260-1695s):   -9.424
        % Seg C (1695s+):      -9.167
        segs = [260, -11.840; 1695, -9.424; Inf, -9.167];
        fprintf('  ** Special case: SUB_27_sess01 per-segment offsets (3 segments) **\n');

    case 'SUB_19_sess02'
        % Clock drift: 3 phases (signed errors: -99ms / +13ms / +84ms)
        % Seg A (EEG 0-610s):    28.258
        % Seg B (610-2090s):     28.370
        % Seg C (2090s+):        28.441
        segs = [610, 28.258; 2090, 28.370; Inf, 28.441];
        fprintf('  ** Special case: SUB_19_sess02 per-segment offsets (3 segments) **\n');

    otherwise
        segs = [Inf, default_offset];
end
end

function off = lookup_offset(segs, eeg_time)
%% Find the correct offset for a given EEG time from segment table.
for k = 1:size(segs, 1)
    if eeg_time < segs(k, 1)
        off = segs(k, 2);
        return;
    end
end
off = segs(end, 2);
end
