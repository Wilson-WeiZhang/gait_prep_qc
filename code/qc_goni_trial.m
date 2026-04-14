function qc = qc_goni_trial(trials, goni_labels)
%% qc_goni_trial — Condition-aware goniometer trial QC
%
% Checks if the "active" person's goni has signal during each trial:
%   MI (imagine):  Walker should walk → check Walker X channels
%   Walk:          Subject should walk → check Subject X channels
%   Rest:          Nobody moves → skip (always OK)
%
% Uses X-axis channels only (more reliable for gait detection).
%
% Input:
%   trials      - struct array with .type ('imagine'/'walk'/'rest'), .joint_angles [N x nCh]
%   goni_labels - cell array of channel labels (e.g., {'LHipW X', 'LKneS X', ...})
%
% Output:
%   qc - struct array (one per trial):
%     .trial_idx, .type, .status ('ok'/'problem'/'skip'), .reason,
%     .active_std, .baseline

ABS_THRESH = 0.25;  % trial std < 25% of baseline → flat
N_BASE = 10;

n_trials = length(trials);
qc = struct('trial_idx', {}, 'type', {}, 'status', {}, 'reason', {}, ...
    'active_std', {}, 'baseline', {});

% Find Walker X and Subject X channel indices by label
w_x_idx = [];
s_x_idx = [];
for i = 1:length(goni_labels)
    lbl = goni_labels{i};
    if contains(lbl, 'W') && endsWith(lbl, 'X')
        w_x_idx(end+1) = i; %#ok<AGROW>
    elseif contains(lbl, 'S') && endsWith(lbl, 'X')
        s_x_idx(end+1) = i; %#ok<AGROW>
    end
end
fprintf('  QC channels: %d Walker X, %d Subject X\n', length(w_x_idx), length(s_x_idx));

% Compute baselines from first N clean trials
w_stds = []; s_stds = [];
for k = 1:n_trials
    seg = trials(k).joint_angles;
    if strcmp(trials(k).type, 'imagine') && length(w_stds) < N_BASE
        w_stds(end+1) = mean_ch_std(seg, w_x_idx); %#ok<AGROW>
    elseif strcmp(trials(k).type, 'walk') && length(s_stds) < N_BASE
        s_stds(end+1) = mean_ch_std(seg, s_x_idx); %#ok<AGROW>
    end
end
base_w = 0; if ~isempty(w_stds), base_w = median(w_stds); end
base_s = 0; if ~isempty(s_stds), base_s = median(s_stds); end

for k = 1:n_trials
    qc(k).trial_idx = k;
    qc(k).type = trials(k).type;
    seg = trials(k).joint_angles;

    switch trials(k).type
        case 'imagine'
            active_std = mean_ch_std(seg, w_x_idx);
            baseline = base_w;
            if baseline > 0 && active_std < ABS_THRESH * baseline
                qc(k).status = 'problem';
                qc(k).reason = sprintf('Walker flat: std=%.2f vs base=%.2f', active_std, baseline);
            else
                qc(k).status = 'ok';
                qc(k).reason = '';
            end
        case 'walk'
            active_std = mean_ch_std(seg, s_x_idx);
            baseline = base_s;
            if baseline > 0 && active_std < ABS_THRESH * baseline
                qc(k).status = 'problem';
                qc(k).reason = sprintf('Subject flat: std=%.2f vs base=%.2f', active_std, baseline);
            else
                qc(k).status = 'ok';
                qc(k).reason = '';
            end
        case 'rest'
            qc(k).status = 'skip';
            qc(k).reason = 'rest';
            active_std = 0;
            baseline = 0;
    end
    qc(k).active_std = active_std;
    qc(k).baseline = baseline;
end
end

function v = mean_ch_std(seg, ch_idx)
if isempty(ch_idx), v = 0; return; end
stds = zeros(1, length(ch_idx));
for i = 1:length(ch_idx)
    stds(i) = std(seg(:, ch_idx(i)), 'omitnan');
end
v = mean(stds);
end
