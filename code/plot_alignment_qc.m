%% plot_alignment_qc.m -- Alignment QC figures for all healthy sessions
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

    % Reconstruct per-trial offset from trial data: offset_i = goni_start/srate - eeg_start
    % For multi-segment sessions, each segment has its own offset.
    % Group trials by segment, compute median offset per segment,
    % then assign each trial its segment's offset.
    eeg_s = [G.trials.start_eeg_sec];
    goni_s = [G.trials.goni_start_idx] / G.goni_srate;
    raw_offsets = goni_s - eeg_s;

    % Use each trial's own offset directly (no grouping needed)
    % Each trial was aligned independently via its own trigger pair
    per_trial_offset = raw_offsets;
    offset = median(raw_offsets);  % for display only

    % Extract trial info
    types = {G.trials.type};
    eeg_starts = [G.trials.start_eeg_sec];
    eeg_ends = [G.trials.end_eeg_sec];
    durs = [G.trials.dur_sec];
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
    n_unique_offsets = length(unique(round(sorted_offsets * 1000)));  % distinct offset values (1ms resolution)

    % X-axis range (shared)
    t_min = min([eeg_starts, goni_starts_eeg]) - 10;
    t_max = max([eeg_ends, goni_ends_eeg]) + 10;

    % === Figure ===
    fig = figure('Visible', 'off', 'Position', [50 50 1600 500]);

    % --- Top: EEG timeline (solid bars + IOI dashes) ---
    ax1 = subplot(3, 1, 1);
    hold on;
    for t = 1:n_trials
        c = colors.(types{t});
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
        c = colors.(types{t});
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

    % --- Bottom: Offset vs EEG time (shows discrete jumps) ---
    ax3 = subplot(3, 1, 3);
    hold on;
    bar_colors = zeros(n_trials, 3);
    for t = 1:n_trials, bar_colors(t,:) = colors.(types{t}); end
    scatter(eeg_starts, sorted_offsets * 1000, 20, bar_colors, 'filled');
    hold off;
    xlabel('EEG time (s)');
    ylabel('Offset (ms)');
    xlim([t_min t_max]);
    linkaxes([ax1 ax2 ax3], 'x');
    if n_unique_offsets == 1
        title(sprintf('Offset: %.1fms (constant across session)', sorted_offsets(1)*1000));
    else
        title(sprintf('Offset: %d distinct values, range=%.0fms (clock jumps)', ...
            n_unique_offsets, offset_range_ms));
    end

    % Legend
    axes(ax1);
    h1 = patch(NaN, NaN, colors.imagine, 'EdgeColor', 'none');
    h2 = patch(NaN, NaN, colors.walk, 'EdgeColor', 'none');
    h3 = patch(NaN, NaN, colors.rest, 'EdgeColor', 'none');
    legend([h1 h2 h3], {'MI', 'Walk', 'Rest'}, 'Location', 'northeast', 'FontSize', 8);

    if n_unique_offsets == 1
        sgtitle(sprintf('%s  |  offset=%.1fms', ...
            strrep(label, '_', ' '), sorted_offsets(1)*1000), 'FontSize', 11, 'FontWeight', 'bold');
    else
        sgtitle(sprintf('%s  |  %d offsets, range=%.0fms', ...
            strrep(label, '_', ' '), n_unique_offsets, offset_range_ms), 'FontSize', 11, 'FontWeight', 'bold');
    end

    % Save
    out_file = fullfile(fig_dir, sprintf('align_%s.png', label));
    print(fig, out_file, '-dpng', '-r150');
    close(fig);

    fprintf('  [%d/%d] %s: %d trials, %d offsets, range=%.0fms\n', ...
        fi, length(files), label, n_trials, n_unique_offsets, offset_range_ms);
end

fprintf('\n=== Done: %s ===\n', fig_dir);
