%% extract_goni_healthy.m — Goniometer extraction & alignment for healthy subjects
%
% For each of the 13 healthy sessions:
%   1. Load goniometer txt file (via load_goniometer)
%   2. Load raw EEG (.vhdr) for accurate marker times
%   3. Extract ALL marker onset times from both systems
%   4. Align via IOI cross-correlation (no periodic S10 in healthy data)
%   5. Validate alignment quality (residuals, IOI consistency)
%   6. Extract goni segments for each trial type (S1→S2, S4→S5, S7→S8)
%   7. Save per-session .mat
%
% Alignment method:
%   Healthy data sends TTL triggers to BOTH EEG and goni simultaneously.
%   The goni Stim channel encodes these as bit-coded values (2, 8, 16).
%   Total onset count in goni = total EEG markers (including S11/S12) ≈ 302.
%   We align by matching the full IOI sequence via cross-correlation.

clear; clc;

eeglab_path = '/Users/zw/Desktop/eeglab-eeglab2024.2';
addpath(eeglab_path); eeglab nogui;

proj_dir  = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(proj_dir, 'code'));

raw_base = '/Users/zw/Library/CloudStorage/OneDrive-NanyangTechnologicalUniversity/gait_data';
out_dir  = fullfile(proj_dir, 'goni_data', 'healthy');
qc_dir   = fullfile(proj_dir, 'goni_data', 'healthy', 'qc');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
if ~exist(qc_dir, 'dir'), mkdir(qc_dir); end

%% Session definitions: {output_label, subject_dir, session_dir, vhdr_file, goni_file}
jobs = {
    'SUB_01_sess01', 'SUB_01', 'sess01_03Feb2026-144711.289', 'a2walk_cbcr_0001.vhdr', 'a2walk-001_sess1.txt'
    'SUB_01_sess02', 'SUB_01', 'sess02_03Mar2026-110348.260',  'a2walk_cbcr_0011.vhdr', 'a2walk-001-sess2.txt'
    'SUB_02_sess01', 'SUB_02', 'sess01_04Feb2026-143559.469',  'a2walk_cbcr_0002.vhdr', 'a2walk-002-sess1_enggunit.txt'
    'SUB_02_sess02', 'SUB_02', 'sess02_12Feb2026-145209.994',  'a2walk_cbcr_0005.vhdr', 'a2walk-sub02-sess02.txt'
    'SUB_03_sess01', 'SUB_03', 'sess01_09Feb2026-133251.469',  'a2walk_cbcr_0003.vhdr', 'SUB-003_sess-01_9Feb2026.txt'
    'SUB_03_sess02', 'SUB_03', 'sess02_23Feb2026-141731.155',  'a2walk_cbcr_0008.vhdr', 'a2walk-sub03-sess02_enggunit.txt'
    'SUB_04_sess01', 'SUB_04', 'sess01_10Feb2026-142255.777',  'a2walk_cbcr_0004.vhdr', 'sub04-sess01-enggunit.txt'
    'SUB_05_sess01', 'SUB_05', 'sess01_13Feb2026-160457.607',  'a2walk_cbcr_0006.vhdr', 'a2walk-sub005-sess01-enggunit.txt'
    'SUB_06_sess01', 'SUB_06', 'sess01_20Feb2026-170215.438',  'a2walk_cbcr_0007.vhdr', 'a2walk-sub006-sess01-enggunit.txt'
    'SUB_06_sess02', 'SUB_06', 'sess02_23Feb2026-163134.447',  'a2walk_cbcr_0009.vhdr', 'a2walk-sub06-sess2_enggunit.txt'
    'SUB_07_sess01', 'SUB_07', 'sess01_25Feb2026-144151.090',  'a2walk_cbcr_0010.vhdr', 'a2walk-sub07-sess01_enggunit.txt'
    'SUB_08_sess01', 'SUB_08', 'sess01_04Mar2026-142529.832',  'a2walk_cbcr_0012.vhdr', 'a2walk-008-sess1.txt'
    'SUB_09_sess01', 'SUB_09', 'sess01_05Mar2026-144517.256',  'a2walk_cbcr_0014.vhdr', 'a2walk-009-sess1_enggunit.txt'
};

n_jobs = size(jobs, 1);
fprintf('=== Goniometer extraction: %d healthy sessions ===\n\n', n_jobs);

summary = cell(n_jobs, 1);

for j = 1:n_jobs
    label    = jobs{j, 1};
    sub_dir  = jobs{j, 2};
    sess_dir = jobs{j, 3};
    vhdr_fn  = jobs{j, 4};
    goni_fn  = jobs{j, 5};

    fprintf('\n============================================================\n');
    fprintf('[%d/%d] %s\n', j, n_jobs, label);
    fprintf('============================================================\n');

    sess_path = fullfile(raw_base, sub_dir, sess_dir);
    vhdr_path = fullfile(sess_path, 'EEG', vhdr_fn);
    goni_path = fullfile(sess_path, 'Goniometer', goni_fn);

    % Check files exist
    if ~exist(vhdr_path, 'file')
        fprintf('  ERROR: vhdr not found: %s\n', vhdr_path);
        continue;
    end
    if ~exist(goni_path, 'file')
        fprintf('  ERROR: goni not found: %s\n', goni_path);
        continue;
    end

    %% 1. Load goniometer
    goni = load_goniometer(goni_path);

    %% 2. Load raw EEG for marker times
    [eeg_dir, ~, ~] = fileparts(vhdr_path);
    EEG = pop_loadbv(eeg_dir, vhdr_fn);
    eeg_srate = EEG.srate;

    %% 3. Extract ALL EEG marker onset times (including S11, S12)
    eeg_times = [];
    eeg_types = {};
    eeg_nums  = [];
    for e = 1:length(EEG.event)
        evt = EEG.event(e);
        if ~startsWith(evt.type, 'S'), continue; end
        num = str2double(regexprep(evt.type, '\D', ''));
        if isnan(num), continue; end
        eeg_times(end+1) = evt.latency / eeg_srate;
        eeg_types{end+1} = strtrim(evt.type);
        eeg_nums(end+1)  = num;
    end
    fprintf('  EEG markers: %d total\n', length(eeg_times));

    %% 4. Extract goni Stim onsets (0 -> nonzero transitions)
    stim = goni.stim;
    goni_rising = find(stim(1:end-1) == 0 & stim(2:end) > 0) + 1;
    goni_times  = ((goni_rising(:)' - 1) / goni.srate);  % force row
    goni_vals   = stim(goni_rising(:)');
    fprintf('  Goni stim onsets: %d total\n', length(goni_times));

    %% 5. Align via IOI cross-correlation
    [offset, align_info] = align_ioi(eeg_times, goni_times, label);

    %% 6. Post-alignment validation
    validate_alignment(eeg_times, goni_times, offset, label, qc_dir);

    %% 7. Extract trial segments
    % Trial markers in EEG (exclude S11, S12)
    trial_eeg_times = eeg_times(eeg_nums ~= 11 & eeg_nums ~= 12);
    trial_eeg_nums  = eeg_nums(eeg_nums ~= 11 & eeg_nums ~= 12);
    trial_eeg_types = eeg_types(eeg_nums ~= 11 & eeg_nums ~= 12);

    % For SUB_01 sess01: rest = R1+S4→R1+S5, but R events start with 'R' not 'S'
    % so they're not in our list. S4→S5 pairs include rest trials in that session.
    % We handle this by extracting all S1→S2, S4→S5, S7→S8 pairs.

    pairs = {1, 2, 'imagine'; 4, 5, 'walk'; 7, 8, 'rest'};
    trials = struct('type', {}, 'start_eeg_sec', {}, 'end_eeg_sec', {}, ...
        'dur_sec', {}, 'goni_start_idx', {}, 'goni_end_idx', {}, ...
        'joint_angles', {}, 'goni_labels', {});

    for p = 1:size(pairs, 1)
        s_start = pairs{p, 1};
        s_end   = pairs{p, 2};
        ttype   = pairs{p, 3};

        start_times = trial_eeg_times(trial_eeg_nums == s_start);
        end_times   = trial_eeg_times(trial_eeg_nums == s_end);

        for i = 1:length(start_times)
            t1 = start_times(i);
            % Find next end marker after this start
            next_ends = end_times(end_times > t1);
            if isempty(next_ends), continue; end
            t2 = next_ends(1);

            % Check no intervening start marker
            intervening = start_times(start_times > t1 & start_times < t2);
            if ~isempty(intervening), continue; end

            dur = t2 - t1;
            if dur < 3 || dur > 60, continue; end

            % Convert to goni indices using offset
            g1 = round((t1 + offset) * goni.srate) + 1;
            g2 = round((t2 + offset) * goni.srate) + 1;
            g1 = max(1, g1);
            g2 = min(goni.n_samples, g2);
            if g1 >= g2, continue; end

            t_idx = length(trials) + 1;
            trials(t_idx).type          = ttype;
            trials(t_idx).start_eeg_sec = t1;
            trials(t_idx).end_eeg_sec   = t2;
            trials(t_idx).dur_sec       = dur;
            trials(t_idx).goni_start_idx = g1;
            trials(t_idx).goni_end_idx   = g2;
            trials(t_idx).joint_angles   = goni.data(g1:g2, :);
            trials(t_idx).goni_labels    = goni.labels;
        end
    end

    % Count by type
    n_imagine = sum(strcmp({trials.type}, 'imagine'));
    n_walk    = sum(strcmp({trials.type}, 'walk'));
    n_rest    = sum(strcmp({trials.type}, 'rest'));
    fprintf('  Trials extracted: %d imagine, %d walk, %d rest (total %d)\n', ...
        n_imagine, n_walk, n_rest, length(trials));

    %% 8. Save
    result = struct();
    result.label       = label;
    result.goni_file   = goni_path;
    result.goni_labels = goni.labels;
    result.goni_srate  = goni.srate;
    result.eeg_srate   = eeg_srate;
    result.offset_sec  = offset;
    result.align_info  = align_info;
    result.trials      = trials;
    result.n_imagine   = n_imagine;
    result.n_walk      = n_walk;
    result.n_rest      = n_rest;
    result.n_total     = length(trials);

    out_file = fullfile(out_dir, sprintf('%s_goni.mat', label));
    save(out_file, '-struct', 'result', '-v7.3');
    fprintf('  Saved: %s\n', out_file);

    summary{j} = sprintf('%s: offset=%.3fs, match=%.0f%%, residual=%.1fms, trials=%d/%d/%d', ...
        label, offset, align_info.match_frac*100, align_info.mean_residual_ms, ...
        n_imagine, n_walk, n_rest);
end

%% Summary
fprintf('\n\n============================================================\n');
fprintf('=== SUMMARY ===\n');
fprintf('============================================================\n');
for j = 1:n_jobs
    if ~isempty(summary{j})
        fprintf('  %s\n', summary{j});
    end
end
fprintf('\nGoni data saved to: %s\n', out_dir);
fprintf('QC files saved to:  %s\n', qc_dir);


%% =====================================================================
%  LOCAL FUNCTIONS
%  =====================================================================

function [offset, info] = align_ioi(eeg_times, goni_times, label)
%% align_ioi — Align EEG and goni using IOI pattern matching
%
% Both systems receive the same TTL trigger sequence. We find the time
% offset by matching inter-onset-interval (IOI) patterns.
%
% Strategy:
%   1. If counts match, try direct 1:1 alignment (fast path)
%   2. If direct fails or counts differ, use anchor-search:
%      - For a subset of anchor pairs (eeg_i, goni_j), compute candidate offset
%      - Count how many event pairs match within tolerance
%      - Pick the offset with the most matches

n_eeg  = length(eeg_times);
n_goni = length(goni_times);
eeg_times  = eeg_times(:)';
goni_times = goni_times(:)';

fprintf('  Alignment: EEG=%d events, Goni=%d events\n', n_eeg, n_goni);

if n_eeg == 0 || n_goni == 0
    error('No events found (EEG=%d, Goni=%d)', n_eeg, n_goni);
end

eeg_ioi  = diff(eeg_times);
goni_ioi = diff(goni_times);

%% Try direct 1:1 alignment if counts match
if n_eeg == n_goni
    offsets_all = goni_times - eeg_times;
    offset_try = median(offsets_all);
    residuals_try = abs(offsets_all - offset_try) * 1000;

    if max(residuals_try) < 100  % all within 100ms → clean direct match
        offset = offset_try;
        info.method = 'direct';
        info.n_eeg  = n_eeg;
        info.n_goni = n_goni;
        info.n_matched = n_eeg;
        info.match_frac = 1.0;
        info.mean_residual_ms = mean(residuals_try);
        info.max_residual_ms  = max(residuals_try);
        fprintf('  Direct match: offset=%.3fs, residual mean=%.1fms max=%.1fms\n', ...
            offset, info.mean_residual_ms, info.max_residual_ms);
        return;
    end
    fprintf('  Direct match failed (max_residual=%.0fms). Using anchor search...\n', ...
        max(residuals_try));
end

%% Substring IOI alignment + anchor search
%  1. Take a block of consecutive EEG IOIs and slide along goni IOIs
%     to find the positional mapping between sequences
%  2. From the best position, compute the time offset
%  3. Validate by counting matched event pairs

eeg_ioi  = diff(eeg_times);
goni_ioi = diff(goni_times);

% Use a substring of ~100 IOIs from the middle of the shorter sequence
sub_len = min(100, min(length(eeg_ioi), length(goni_ioi)) - 10);
sub_start = max(1, round((length(eeg_ioi) - sub_len) / 2));
sub_ioi = eeg_ioi(sub_start : sub_start + sub_len - 1);

% Slide substring along goni IOIs
n_slides = length(goni_ioi) - sub_len + 1;
best_cost = Inf;
best_goni_start = 1;

for s = 1:n_slides
    seg = goni_ioi(s : s + sub_len - 1);
    cost = sum(abs(sub_ioi - seg));
    if cost < best_cost
        best_cost = cost;
        best_goni_start = s;
    end
end

% The EEG IOI starting at sub_start maps to goni IOI starting at best_goni_start
% So eeg event (sub_start) maps to goni event (best_goni_start)
% Offset = goni_time(best_goni_start) - eeg_time(sub_start)
offset_from_ioi = goni_times(best_goni_start) - eeg_times(sub_start);

fprintf('  IOI substring: eeg_pos=%d→goni_pos=%d, cost=%.3f, offset=%.3fs\n', ...
    sub_start, best_goni_start, best_cost, offset_from_ioi);

% Validate: count matches with this offset
TOL = 0.15;  % 150ms tolerance (generous for validation)
eeg_shifted = eeg_times + offset_from_ioi;
best_n = 0;
best_errors = [];
for i = 1:n_eeg
    [min_err, ~] = min(abs(goni_times - eeg_shifted(i)));
    if min_err < TOL
        best_n = best_n + 1;
        best_errors(end+1) = min_err * 1000;
    end
end
best_offset = offset_from_ioi;

offset = best_offset;
info.method = 'anchor_search';
info.n_eeg  = n_eeg;
info.n_goni = n_goni;
info.n_matched = best_n;
info.match_frac = best_n / min(n_eeg, n_goni);
info.mean_residual_ms = mean(best_errors);
info.max_residual_ms  = max(best_errors);

fprintf('  Anchor search: offset=%.3fs, matched=%d/%d (%.0f%%), residual mean=%.1fms max=%.1fms\n', ...
    offset, best_n, min(n_eeg, n_goni), info.match_frac*100, ...
    info.mean_residual_ms, info.max_residual_ms);

if info.match_frac < 0.9
    warning('Low match rate (%.0f%%). Check %s manually.', info.match_frac*100, label);
end
end


function validate_alignment(eeg_times, goni_times, offset, label, qc_dir)
%% Post-alignment validation: check every EEG marker maps to a goni onset
eeg_in_goni = eeg_times(:)' + offset;
goni_times_row = goni_times(:)';
TOL = 0.1;  % 100ms

n_eeg = length(eeg_times);
matched    = false(1, n_eeg);
errors_ms  = nan(1, n_eeg);

for i = 1:n_eeg
    [min_err, ~] = min(abs(goni_times_row - eeg_in_goni(i)));
    if min_err < TOL
        matched(i) = true;
        errors_ms(i) = min_err * 1000;
    end
end

n_match = sum(matched);
fprintf('  Validation: %d/%d EEG events matched (%.1f%%)\n', n_match, n_eeg, n_match/n_eeg*100);
if n_match > 0
    fprintf('  Alignment error: mean=%.1fms, max=%.1fms, std=%.1fms\n', ...
        nanmean(errors_ms), nanmax(errors_ms), nanstd(errors_ms));
end

% Check for consecutive IOI mismatches (would indicate split/gap issue)
if n_match >= 2
    matched_idx = find(matched);
    eeg_gaps  = diff(eeg_times(matched_idx));
    goni_match_times = nan(size(matched_idx));
    for k = 1:length(matched_idx)
        [~, bi] = min(abs(goni_times_row - eeg_in_goni(matched_idx(k))));
        goni_match_times(k) = goni_times_row(bi);
    end
    goni_gaps = diff(goni_match_times);
    gap_diff_ms = abs(eeg_gaps - goni_gaps) * 1000;

    bad_gaps = find(gap_diff_ms > 50);
    if isempty(bad_gaps)
        fprintf('  IOI consistency: OK (max gap diff=%.1fms)\n', max(gap_diff_ms));
    else
        fprintf('  IOI consistency: %d problematic gaps (>50ms):\n', length(bad_gaps));
        for k = 1:min(5, length(bad_gaps))
            i = bad_gaps(k);
            fprintf('    gap %d->%d: EEG=%.3fs, Goni=%.3fs, diff=%.1fms\n', ...
                matched_idx(i), matched_idx(i+1), eeg_gaps(i), goni_gaps(i), gap_diff_ms(i));
        end
    end
end

%% Save QC report
if ~isempty(qc_dir)
    if ~exist(qc_dir, 'dir'), mkdir(qc_dir); end
    fname = fullfile(qc_dir, sprintf('align_qc_%s.txt', label));
    fid = fopen(fname, 'w');
    fprintf(fid, 'Alignment QC: %s\n', label);
    fprintf(fid, 'Offset: %.6f sec\n', offset);
    fprintf(fid, 'EEG events: %d, Goni events: %d\n', n_eeg, length(goni_times));
    fprintf(fid, 'Matched: %d/%d (%.1f%%)\n', n_match, n_eeg, n_match/n_eeg*100);
    if n_match > 0
        fprintf(fid, 'Error mean=%.3fms, max=%.3fms, std=%.3fms\n', ...
            nanmean(errors_ms), nanmax(errors_ms), nanstd(errors_ms));
    end
    fprintf(fid, '\n%5s %12s %12s %10s %7s\n', 'idx', 'eeg_t(s)', 'goni_t(s)', 'err(ms)', 'match');
    fprintf(fid, '%s\n', repmat('-', 1, 50));
    for i = 1:n_eeg
        if matched(i)
            [~, bi] = min(abs(goni_times_row - eeg_in_goni(i)));
            fprintf(fid, '%5d %12.3f %12.3f %10.1f %7s\n', ...
                i, eeg_times(i), goni_times_row(bi), errors_ms(i), 'YES');
        else
            fprintf(fid, '%5d %12.3f %12s %10s %7s\n', ...
                i, eeg_times(i), '-', '-', 'NO');
        end
    end
    fclose(fid);
    fprintf('  QC saved: %s\n', fname);
end

% Hard fail if match rate too low
if n_match / n_eeg < 0.9
    error('Alignment quality too low: %d/%d matched (%.1f%%). Check %s manually.', ...
        n_match, n_eeg, n_match/n_eeg*100, label);
end
end
