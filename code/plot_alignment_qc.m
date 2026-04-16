%% plot_alignment_qc.m -- Alignment QC figures for all sessions (healthy + patient)
%
% For each session, plots EEG and Goni on two axes:
%   Top axis (EEG clock): solid bars = trial durations, dashed lines = IOI
%   Bottom axis (Goni clock): same trials mapped via alignment offset
%   Color-coded by condition (MI=blue, Walk=green, Rest=gray)
%   Lines connecting corresponding trials show the alignment mapping
%
% Usage:
%   cd gait_prep_qc/code && matlab -batch "plot_alignment_qc"

clear; clc;
set(0, 'DefaultFigureVisible', 'off');

code_dir = fileparts(mfilename('fullpath'));
addpath(code_dir);
addpath(fullfile(code_dir, 'utils'));

if ismac
    goni_dir = fullfile(fileparts(code_dir), 'result', 'goni_healthy');
elseif ispc
    goni_dir = fullfile(fileparts(code_dir), 'result', 'goni_healthy');
else
    goni_dir = '/home/wilson/gait/gait_prep_qc/result/goni_healthy';
end

fig_dir = fullfile(goni_dir, 'qc', 'alignment_figs');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

files = dir(fullfile(goni_dir, '*_goni.mat'));
fprintf('=== Generating alignment QC figures: %d sessions ===\n', length(files));

colors = struct('imagine', [0.2 0.4 0.8], 'walk', [0.2 0.7 0.3], 'rest', [0.6 0.6 0.6]);

for fi = 1:length(files)
    fname = files(fi).name;
    label = strrep(fname, '_goni.mat', '');
    G = load(fullfile(goni_dir, fname));

    if isempty(G.trials)
        fprintf('  [%d/%d] %s: no trials, skip\n', fi, length(files), label);
        continue;
    end

    % --- Normalize healthy vs patient goni format ---
    is_patient = startsWith(label, 'P0');
    if isfield(G.trials, 'start_eeg_sec')
        % Healthy format
        eeg_s = [G.trials.start_eeg_sec];
        eeg_ends_raw = [G.trials.end_eeg_sec];
        durs_raw = [G.trials.dur_sec];
    elseif isfield(G.trials, 's1_eeg_sec')
        % Patient format
        eeg_s = [G.trials.s1_eeg_sec];
        eeg_ends_raw = [G.trials.s2_eeg_sec];
        durs_raw = [G.trials.dur];
    else
        fprintf('  [%d/%d] %s: unknown trial format, skip\n', fi, length(files), label);
        continue;
    end

    % Reconstruct per-trial offset from trial data: offset_i = goni_start/srate - eeg_start
    goni_s = [G.trials.goni_start_idx] / G.goni_srate;
    raw_offsets = goni_s - eeg_s;

    % Use each trial's own offset directly (no grouping needed)
    per_trial_offset = raw_offsets;
    offset = median(raw_offsets);  % for display only

    % Extract trial info
    types = {G.trials.type};
    eeg_starts = eeg_s;
    eeg_ends = eeg_ends_raw;
    durs = durs_raw;
    n_trials = length(G.trials);

    % Goni times (from goni indices)
    goni_starts = [G.trials.goni_start_idx] / G.goni_srate;
    goni_ends = [G.trials.goni_end_idx] / G.goni_srate;

    % Sort by EEG start time
    [eeg_starts, si] = sort(eeg_starts);
    eeg_ends = eeg_ends(si);
    goni_starts = goni_starts(si);
    goni_ends = goni_ends(si);
    types = types(si);
    durs = durs(si);

    % Per-trial offset (each trial's own, from extraction)
    sorted_offsets = per_trial_offset(si);
    % Convert goni times to EEG clock using each trial's own offset
    goni_starts_eeg = goni_starts - sorted_offsets;
    goni_ends_eeg = goni_ends - sorted_offsets;

    % Offset range = indicator of clock jumps within session
    offset_range_ms = (max(sorted_offsets) - min(sorted_offsets)) * 1000;
    n_unique_offsets = length(unique(round(sorted_offsets * 10)));  % distinct offset values (100ms resolution)

    % X-axis range (shared)
    t_min = min([eeg_starts, goni_starts_eeg]) - 10;
    t_max = max([eeg_ends, goni_ends_eeg]) + 10;

    % === Figure ===
    fig = figure('Visible', 'off', 'Position', [50 50 1600 500]);

    % --- Top: EEG timeline (solid bars + IOI dashes) ---
    ax1 = subplot(3, 1, 1);
    hold on;
    for t = 1:n_trials
        if isfield(colors, types{t})
            c = colors.(types{t});
        else
            c = [0.5 0.5 0.5];  % unknown condition type
        end
        patch([eeg_starts(t) eeg_ends(t) eeg_ends(t) eeg_starts(t)], ...
              [0.2 0.2 0.8 0.8], c, 'EdgeColor', 'none', 'FaceAlpha', 0.7);
    end
    for t = 2:n_trials
        plot([eeg_ends(t-1) eeg_starts(t)], [0.5 0.5], ':', 'Color', [0.4 0.4 0.4], 'LineWidth', 0.5);
    end
    hold off;
    ylim([0 1]); xlim([t_min t_max]); set(ax1, 'YTick', []);
    ylabel('EEG');
    title(sprintf('EEG timeline: %d trials (solid=trial, dotted=IOI)', n_trials));

    % --- Middle: Goni timeline (mapped to EEG clock) ---
    ax2 = subplot(3, 1, 2);
    hold on;
    for t = 1:n_trials
        if isfield(colors, types{t})
            c = colors.(types{t});
        else
            c = [0.5 0.5 0.5];
        end
        patch([goni_starts_eeg(t) goni_ends_eeg(t) goni_ends_eeg(t) goni_starts_eeg(t)], ...
              [0.2 0.2 0.8 0.8], c, 'EdgeColor', 'none', 'FaceAlpha', 0.7);
    end
    for t = 2:n_trials
        plot([goni_ends_eeg(t-1) goni_starts_eeg(t)], [0.5 0.5], ':', 'Color', [0.4 0.4 0.4], 'LineWidth', 0.5);
    end
    hold off;
    ylim([0 1]); xlim([t_min t_max]); set(ax2, 'YTick', []);
    ylabel('Goni');
    title('Goni timeline (mapped to EEG clock)');

    % Link x-axes
    linkaxes([ax1 ax2], 'x');

    % --- Bottom: Per-trigger alignment residual from QC txt files ---
    % Color-coded by segment; filled=matched, x=unmatched.
    % Multi-segment: correct errors by subtracting per-segment offset drift.
    ax3 = subplot(3, 1, 3);
    hold on;

    % Detect segment boundaries from trial data
    if isfield(G.trials, 'segment')
        trial_segs = [G.trials.segment];
    else
        trial_segs = ones(1, n_trials);  % patient: single segment
    end
    trial_segs_sorted = trial_segs(si);
    unique_segs = unique(trial_segs_sorted);
    n_segs = length(unique_segs);

    % Per-segment offset (median of trial offsets within each segment)
    unique_segs = double(unique_segs);
    seg_offset_map = containers.Map(unique_segs, zeros(1, n_segs));
    seg_boundary_t = [];
    for segi = 1:n_segs
        mask = trial_segs_sorted == unique_segs(segi);
        seg_offset_map(unique_segs(segi)) = median(sorted_offsets(mask));
        if segi > 1
            prev_mask = trial_segs_sorted == unique_segs(segi-1);
            prev_last = max(eeg_starts(prev_mask));
            this_first = min(eeg_starts(mask));
            seg_boundary_t(end+1) = (prev_last + this_first) / 2;
        end
    end

    % Read per-trigger data from align_qc_*.txt files
    qc_dir = fullfile(goni_dir, 'qc');
    qc_files = dir(fullfile(qc_dir, sprintf('align_qc_%s_seg*.txt', label)));
    all_eeg_t = [];
    all_err = [];
    all_match = {};
    for qi = 1:length(qc_files)
        fid = fopen(fullfile(qc_dir, qc_files(qi).name));
        for skip = 1:6, fgetl(fid); end
        while ~feof(fid)
            line = fgetl(fid);
            if ~ischar(line) || isempty(strtrim(line)), continue; end
            parts = strsplit(strtrim(line));
            if length(parts) >= 4
                all_eeg_t(end+1) = str2double(parts{2});
                all_err(end+1) = str2double(parts{3});
                all_match{end+1} = parts{4};
            end
        end
        fclose(fid);
    end

    % Segment color palette (distinct hues for up to 5 segments)
    seg_cmap = [0.2 0.4 0.8; 0.9 0.4 0.1; 0.2 0.7 0.3; 0.7 0.2 0.7; 0.5 0.5 0.1];
    drift_from_trial = (n_segs > 1);  % true = segments from trial data (extraction handled)

    if ~isempty(all_eeg_t)
        matched_mask = strcmp(all_match, 'YES');

        % Auto-detect drift phases from QC errors when trial.segment=1
        % (catches drift not handled by extraction, e.g. SUB_19_sess02)
        if n_segs == 1 && sum(matched_mask) > 30
            m_idx = find(matched_mask);
            m_t = all_eeg_t(m_idx);
            m_e = all_err(m_idx);
            [m_t_s, si_m] = sort(m_t);
            m_e_s = m_e(si_m);

            % Running median (window=21)
            win = min(21, length(m_e_s));
            half_w = floor(win/2);
            sm_e = m_e_s;
            for i = (half_w+1):(length(m_e_s)-half_w)
                sm_e(i) = median(m_e_s(i-half_w:i+half_w));
            end

            % Detect jumps > 25ms in smoothed error
            err_range = max(sm_e) - min(sm_e);
            if err_range > 40
                diff_sm = diff(sm_e);
                jump_idx = find(abs(diff_sm) > 20);
                if ~isempty(jump_idx)
                    % Merge close jumps (within 15 triggers)
                    merged_idx = jump_idx(1);
                    for ji = 2:length(jump_idx)
                        if jump_idx(ji) - merged_idx(end) > 15
                            merged_idx(end+1) = jump_idx(ji);
                        end
                    end
                    % Convert to time boundaries
                    auto_boundary_t = zeros(1, length(merged_idx));
                    for bi = 1:length(merged_idx)
                        idx = merged_idx(bi);
                        auto_boundary_t(bi) = (m_t_s(idx) + m_t_s(min(idx+1, end))) / 2;
                    end
                    seg_boundary_t = auto_boundary_t;
                    n_auto = length(auto_boundary_t) + 1;
                    unique_segs = 1:n_auto;  % double to avoid int32 type issues
                    n_segs = n_auto;
                    % Compute per-phase median error for display
                    seg_offset_map = containers.Map(unique_segs, zeros(1, n_auto));
                    for segi = 1:n_segs
                        if segi == 1
                            phase_mask = m_t_s <= auto_boundary_t(1);
                        elseif segi == n_segs
                            phase_mask = m_t_s > auto_boundary_t(end);
                        else
                            phase_mask = m_t_s > auto_boundary_t(segi-1) & m_t_s <= auto_boundary_t(segi);
                        end
                        seg_offset_map(segi) = median(m_e_s(phase_mask));  % median error (ms), not offset
                    end
                    drift_from_trial = false;  % auto-detected, no error correction
                end
            end
        end

        % Assign each trigger to a segment by time
        trig_seg = ones(size(all_eeg_t)) * unique_segs(1);
        for bi = 1:length(seg_boundary_t)
            trig_seg(all_eeg_t > seg_boundary_t(bi)) = unique_segs(bi + 1);
        end

        % Correct errors only for trial-based multi-segment (extraction handled drift)
        plot_err = all_err;
        if drift_from_trial
            global_offset = median(sorted_offsets);
            for ti = 1:length(all_eeg_t)
                if matched_mask(ti)
                    seg_off = seg_offset_map(trig_seg(ti));
                    drift_ms = abs(seg_off - global_offset) * 1000;
                    plot_err(ti) = abs(all_err(ti) - drift_ms);
                end
            end
        end

        % Plot triggers: color by segment/phase, shape by matched status
        leg_h = []; leg_s = {};
        for segi = 1:n_segs
            seg_mask = trig_seg == unique_segs(segi);
            sc = seg_cmap(mod(segi-1, size(seg_cmap,1)) + 1, :);

            % Matched: filled circles
            m = seg_mask & matched_mask;
            if any(m)
                h = scatter(all_eeg_t(m), plot_err(m), 22, sc, 'filled', 'MarkerFaceAlpha', 0.8);
                leg_h(end+1) = h;
                if n_segs > 1 && drift_from_trial
                    seg_off_ms = seg_offset_map(unique_segs(segi)) * 1000;
                    leg_s{end+1} = sprintf('Seg%d (%.0fms) %d ok', segi, seg_off_ms, sum(m));
                elseif n_segs > 1
                    med_err = seg_offset_map(unique_segs(segi));
                    leg_s{end+1} = sprintf('Phase%d (~%.0fms) %d ok', segi, med_err, sum(m));
                else
                    leg_s{end+1} = sprintf('Matched (%d)', sum(m));
                end
            end
            % Unmatched: x markers
            u = seg_mask & ~matched_mask;
            if any(u)
                h = scatter(all_eeg_t(u), plot_err(u), 30, sc, 'x', 'LineWidth', 1.3);
                leg_h(end+1) = h;
                if n_segs > 1
                    if drift_from_trial, pfx = 'Seg'; else, pfx = 'Phase'; end
                    leg_s{end+1} = sprintf('%s%d unmatched (%d)', pfx, segi, sum(u));
                else
                    leg_s{end+1} = sprintf('Unmatched (%d)', sum(u));
                end
            end
        end

        yline(0, '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.5);

        % Segment/phase boundary lines
        for bi = 1:length(seg_boundary_t)
            if drift_from_trial
                lbl = sprintf('seg%d|%d', bi, bi+1);
            else
                lbl = sprintf('phase%d|%d', bi, bi+1);
            end
            xline(seg_boundary_t(bi), '--', lbl, ...
                'Color', [0.8 0.1 0.1], 'LineWidth', 1.8, 'FontSize', 8, ...
                'LabelOrientation', 'horizontal', 'LabelVerticalAlignment', 'top');
        end

        if ~isempty(leg_h)
            legend(leg_h, leg_s, 'Location', 'northeast', 'FontSize', 7);
        end

        matched_err = plot_err(matched_mask);
        mean_res = mean(abs(matched_err));
        max_res = max(abs(matched_err));
        n_matched = sum(matched_mask);
        n_total = length(all_eeg_t);
    else
        mean_res = 0; max_res = 0; n_matched = 0; n_total = 0;
    end
    hold off;
    xlabel('EEG time (s)');
    ylabel('Error (ms)');
    xlim([t_min t_max]);
    linkaxes([ax1 ax2 ax3], 'x');
    title(sprintf('Trigger alignment error: %d/%d matched, mean=%.1fms, max=%.1fms', ...
        n_matched, n_total, mean_res, max_res));

    % Legend
    axes(ax1);
    h1 = patch(NaN, NaN, colors.imagine, 'EdgeColor', 'none');
    h2 = patch(NaN, NaN, colors.walk, 'EdgeColor', 'none');
    h3 = patch(NaN, NaN, colors.rest, 'EdgeColor', 'none');
    legend([h1 h2 h3], {'MI', 'Walk', 'Rest'}, 'Location', 'northeast', 'FontSize', 8);

    if n_segs == 1
        sgtitle(sprintf('%s  |  %d trials, %d/%d matched, mean=%.1fms, max=%.1fms', ...
            strrep(label, '_', ' '), n_trials, n_matched, n_total, mean_res, max_res), ...
            'FontSize', 11, 'FontWeight', 'bold');
    elseif drift_from_trial
        seg_offsets_ms = zeros(1, n_segs);
        for segi = 1:n_segs, seg_offsets_ms(segi) = seg_offset_map(unique_segs(segi)) * 1000; end
        offset_str = strjoin(arrayfun(@(x) sprintf('%.0f', x), seg_offsets_ms, 'UniformOutput', false), '/');
        sgtitle(sprintf('%s  |  %d trials, %d segs [%sms], %d/%d matched, mean=%.1fms, max=%.1fms', ...
            strrep(label, '_', ' '), n_trials, n_segs, offset_str, n_matched, n_total, mean_res, max_res), ...
            'FontSize', 11, 'FontWeight', 'bold');
    else
        % Auto-detected drift phases: seg_offset_map stores median error (ms)
        phase_errs = zeros(1, n_segs);
        for segi = 1:n_segs, phase_errs(segi) = seg_offset_map(unique_segs(segi)); end
        phase_str = strjoin(arrayfun(@(x) sprintf('~%.0f', x), phase_errs, 'UniformOutput', false), '/');
        sgtitle(sprintf('%s  |  %d trials, %d drift phases [%sms], %d/%d matched', ...
            strrep(label, '_', ' '), n_trials, n_segs, phase_str, n_matched, n_total), ...
            'FontSize', 11, 'FontWeight', 'bold');
    end

    % Save
    out_file = fullfile(fig_dir, sprintf('align_%s.png', label));
    print(fig, out_file, '-dpng', '-r150');
    close(fig);

    fprintf('  [%d/%d] %s: %d trials, %d offsets, range=%.0fms\n', ...
        fi, length(files), label, n_trials, n_unique_offsets, offset_range_ms);
end

fprintf('\n=== Done: %s ===\n', fig_dir);
