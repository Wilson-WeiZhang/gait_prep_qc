function plot_goni_qc()
%PLOT_GONI_QC Generate goniometer QC plots for all sessions (healthy + patient)
%
% Output: gait_prep_qc/result/qc_figs/goni_qc/goni_qc_<LABEL>.png

set(0, 'DefaultFigureVisible', 'off');

% --- Paths ---
code_dir = fileparts(mfilename('fullpath'));
utils_dir = fullfile(code_dir, 'utils');
addpath(code_dir);
addpath(utils_dir);

if ismac
    base_dir  = fileparts(fileparts(code_dir));  % gait_prep_qc/
    goni_dir  = fullfile(base_dir, 'result', 'goni_healthy');
    out_dir   = fullfile(base_dir, 'result', 'qc_figs', 'goni_qc');
else
    goni_dir  = '/home/wilson/gait/gait_prep_qc/result/goni_healthy';
    out_dir   = '/home/wilson/gait/gait_prep_qc/result/qc_figs/goni_qc';
end

if ~exist(out_dir, 'dir'), mkdir(out_dir); end

% --- Find all _goni.mat files ---
files = dir(fullfile(goni_dir, '*_goni.mat'));
if isempty(files)
    error('No *_goni.mat files found in %s', goni_dir);
end
fprintf('Found %d goni files\n', numel(files));

% --- Colors ---
col_ok      = [0.2 0.4 0.8];
col_problem = [0.9 0.1 0.1];
col_skip    = [0.6 0.6 0.6];

% --- Joint definitions ---
walker_joints  = {'LHipW X', 'LKneW X', 'LAnkW X'};
walker_alt     = {'RHipW X', 'RKneW X', 'RAnkW X'};
subject_joints = {'LHipS X', 'LKneS X', 'LAnkS X'};
subject_alt    = {'RHipS X', 'RKneS X', 'RAnkS X'};
joint_names    = {'Hip', 'Knee', 'Ankle'};

% --- Process each session ---
for fi = 1:numel(files)
    fname = files(fi).name;
    fpath = fullfile(goni_dir, fname);

    % Derive session label from filename (strip _goni.mat)
    label = regexprep(fname, '_goni\.mat$', '');

    try
        G = load(fpath);

        % --- Detect format ---
        is_healthy = isfield(G.trials(1), 'start_eeg_sec');

        % --- Goni labels ---
        if isfield(G, 'goni_labels')
            goni_labels = G.goni_labels;
        else
            goni_labels = G.trials(1).goni_labels;
        end

        % --- Separate trials by condition ---
        n_trials = numel(G.trials);
        mi_idx   = [];
        walk_idx = [];
        for k = 1:n_trials
            tp = G.trials(k).type;
            if strcmpi(tp, 'imagine')
                mi_idx(end+1) = k; %#ok<AGROW>
            elseif strcmpi(tp, 'walk')
                walk_idx(end+1) = k; %#ok<AGROW>
            end
        end

        % --- QC status lookup ---
        if is_healthy && isfield(G, 'qc')
            qc_status = {G.qc.status};  % cell array of strings
        else
            qc_status = repmat({'ok'}, 1, n_trials);
        end

        % --- Count problems in MI trials ---
        n_mi_prob = sum(strcmp(qc_status(mi_idx), 'problem'));

        % --- Create figure ---
        fig = figure('Position', [0 0 1400 800]);

        % 3 rows (joint) × 2 cols (MI / Walk)
        for j = 1:3  % joints: Hip, Knee, Ankle
            % --- MI panel (col 1) ---
            ax = subplot(3, 2, (j-1)*2 + 1);
            hold(ax, 'on');

            % Find walker channel index
            w_idx = find_goni_idx(goni_labels, walker_joints{j});
            if w_idx == 0
                w_idx = find_goni_idx(goni_labels, walker_alt{j});
            end

            mean_buf = {};
            for k = mi_idx
                if w_idx == 0 || ~isfield(G.trials(k), 'joint_angles')
                    continue;
                end
                data = G.trials(k).joint_angles;
                if size(data, 2) < w_idx, continue; end
                t = (0:size(data,1)-1) / G.goni_srate;
                col = get_color(qc_status{k}, col_ok, col_problem, col_skip);
                plot(ax, t, data(:, w_idx), 'Color', [col 0.3], 'LineWidth', 0.5);
                if strcmp(qc_status{k}, 'ok') || strcmp(qc_status{k}, 'problem')
                    mean_buf{end+1} = data(:, w_idx); %#ok<AGROW>
                end
            end
            add_mean_line(ax, mean_buf, col_ok);
            if j == 1
                title(ax, sprintf('MI (Walker)  —  %d trials (%d prob)', ...
                    numel(mi_idx), n_mi_prob), 'FontSize', 9);
            end
            ylabel(ax, sprintf('%s (°)', joint_names{j}));
            if j == 3, xlabel(ax, 'Time (s)'); end
            box(ax, 'off');

            % --- Walk panel (col 2) ---
            ax2 = subplot(3, 2, (j-1)*2 + 2);
            hold(ax2, 'on');

            s_idx = find_goni_idx(goni_labels, subject_joints{j});
            if s_idx == 0
                s_idx = find_goni_idx(goni_labels, subject_alt{j});
            end

            mean_buf2 = {};
            for k = walk_idx
                if s_idx == 0 || ~isfield(G.trials(k), 'joint_angles')
                    continue;
                end
                data = G.trials(k).joint_angles;
                if size(data, 2) < s_idx, continue; end
                t = (0:size(data,1)-1) / G.goni_srate;
                col = get_color(qc_status{k}, col_ok, col_problem, col_skip);
                plot(ax2, t, data(:, s_idx), 'Color', [col 0.3], 'LineWidth', 0.5);
                if strcmp(qc_status{k}, 'ok') || strcmp(qc_status{k}, 'problem')
                    mean_buf2{end+1} = data(:, s_idx); %#ok<AGROW>
                end
            end
            add_mean_line(ax2, mean_buf2, col_ok);
            if j == 1
                title(ax2, sprintf('Walk (Subject)  —  %d trials', numel(walk_idx)), 'FontSize', 9);
            end
            if j == 3, xlabel(ax2, 'Time (s)'); end
            box(ax2, 'off');
        end

        % --- Super title ---
        sgtitle(fig, sprintf('%s  |  MI: %d trials (%d problems)  |  Walk: %d trials', ...
            label, numel(mi_idx), n_mi_prob, numel(walk_idx)), ...
            'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');

        % --- Save ---
        out_file = fullfile(out_dir, sprintf('goni_qc_%s.png', label));
        exportgraphics(fig, out_file, 'Resolution', 150);
        close(fig);
        fprintf('  Saved: %s\n', out_file);

    catch ME
        fprintf('  ERROR [%s]: %s\n', label, ME.message);
        close all;
    end
end

fprintf('Done. Figures saved to: %s\n', out_dir);
end

% -------------------------------------------------------------------------
function col = get_color(status, col_ok, col_problem, col_skip)
switch lower(status)
    case 'ok'
        col = col_ok;
    case 'problem'
        col = col_problem;
    otherwise  % skip or unknown
        col = col_skip;
end
end

% -------------------------------------------------------------------------
function add_mean_line(ax, buf, col)
%ADD_MEAN_LINE Overlay thick mean trace on current axes.
% Interpolates all traces to common length, then reuses the x-axis span
% already set by individual trial plots (in seconds).
if isempty(buf), return; end
lens = cellfun(@numel, buf);
n_max = max(lens);
mat = nan(n_max, numel(buf));
for i = 1:numel(buf)
    x_orig = linspace(0, 1, lens(i));
    x_new  = linspace(0, 1, n_max);
    mat(:, i) = interp1(x_orig, double(buf{i}), x_new, 'linear');
end
mn = mean(mat, 2, 'omitnan');
% Match x-axis already drawn by trial plots (seconds)
xl = get(ax, 'XLim');
t  = linspace(xl(1), xl(2), n_max);
plot(ax, t, mn, 'Color', [col 0.8], 'LineWidth', 2);
end
