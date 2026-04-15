%% pair_eeg_goni_v8.m -- Pair V8 EEG epochs with goniometer data
%
% Uses: epochs_ica.mat (V8: 60ch, variable srate, ICLabel-cleaned)
%       goni.mat       (1000Hz, IOI-aligned, trial-segmented)
%
% Pairing: index-based within condition (both chronological by same markers)
% Verification: duration comparison (actual data length)
% Goni resampled to match EEG srate, trimmed to common length.
%
% Exclusions:
%   SUB_10_sess01 -- goni only 8 trials (hardware failure)
%
% Run on aa:
%   cd ~/gait/gait_prep_qc/code && ~/matlab/bin/matlab -batch "pair_eeg_goni_v8"

clear; clc;

%% Configuration
epoch_dir = '/home/wilson/gait/prep_data_v8';
goni_dir  = '/home/wilson/gait/gait_prep_qc/result/goni_healthy';
out_dir   = '/home/wilson/gait/paired_data_v8';
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

%% All 40 healthy sessions minus exclusions
all_sessions = {
    'SUB_01_sess01', 'SUB_01_sess02', ...
    'SUB_02_sess01', 'SUB_02_sess02', ...
    'SUB_03_sess01', 'SUB_03_sess02', ...
    'SUB_04_sess01', 'SUB_04_sess02', ...
    'SUB_05_sess01', ...
    'SUB_06_sess01', 'SUB_06_sess02', ...
    'SUB_07_sess01', 'SUB_07_sess02', ...
    'SUB_08_sess01', ...
    'SUB_09_sess01', 'SUB_09_sess02', ...
    'SUB_10_sess02', ...              % SUB_10_sess01 excluded (goni partial)
    'SUB_11_sess01', ...
    'SUB_12_sess01', 'SUB_12_sess02', ...
    'SUB_13_sess01', ...
    'SUB_14_sess01', ...
    'SUB_15_sess01', 'SUB_15_sess02', ...
    'SUB_16_sess01', 'SUB_16_sess02', ...
    'SUB_17_sess01', ...
    'SUB_18_sess01', ...
    'SUB_19_sess01', 'SUB_19_sess02', ...
    'SUB_20_sess01', ...
    'SUB_21_sess01', ...
    'SUB_22_sess01', ...
    'SUB_23_sess01', ...
    'SUB_24_sess01', ...
    'SUB_25_sess01', ...
    'SUB_26_sess01', ...              % 11 frontal bad ch, interpolated
    'SUB_27_sess01', ...
    'SUB_28_sess01', ...
};

cond_map = {'MI', 'imagine'; 'Walk', 'walk'; 'Rest', 'rest'};
dur_tol = 0.2;  % max acceptable duration mismatch (seconds)

fprintf('=== EEG-Goni Pairing V8: %d sessions ===\n\n', length(all_sessions));

%% Process
summary = cell(length(all_sessions), 1);

for s = 1:length(all_sessions)
    label = all_sessions{s};
    fprintf('\n[%d/%d] ===== %s =====\n', s, length(all_sessions), label);

    % Load V8 epochs
    epoch_file = fullfile(epoch_dir, [label '_epochs_ica.mat']);
    if ~exist(epoch_file, 'file')
        fprintf('  SKIP: epochs_ica.mat not found\n');
        summary{s} = sprintf('%s: SKIP (no epochs)', label);
        continue;
    end
    E = load(epoch_file);
    ep = E.epochs_ica;
    eeg_srate = ep.srate;

    % Load goni
    goni_file = fullfile(goni_dir, [label '_goni.mat']);
    if ~exist(goni_file, 'file')
        fprintf('  SKIP: goni.mat not found\n');
        summary{s} = sprintf('%s: SKIP (no goni)', label);
        continue;
    end
    G = load(goni_file);
    goni_srate = G.goni_srate;

    % Output struct
    paired = struct();
    session_ok = true;
    total_pairs = 0;

    for c = 1:size(cond_map, 1)
        eeg_field = cond_map{c, 1};
        goni_type = cond_map{c, 2};

        % EEG epochs: cell array of [ch x T]
        if ~isfield(ep, eeg_field) || isempty(ep.(eeg_field))
            paired.(lower(eeg_field)) = empty_condition();
            continue;
        end
        eeg_trials = ep.(eeg_field);
        n_eeg = length(eeg_trials);

        % Trial info (absolute timestamps)
        info_field = [eeg_field '_info'];
        has_info = isfield(ep, info_field) && length(ep.(info_field)) == n_eeg;

        % Goni trials
        goni_mask = strcmp({G.trials.type}, goni_type);
        goni_trials = G.trials(goni_mask);
        n_goni = length(goni_trials);

        if n_eeg == 0 && n_goni == 0
            paired.(lower(eeg_field)) = empty_condition();
            continue;
        end

        % Count match
        if n_eeg ~= n_goni
            fprintf('  ERROR %s: count mismatch eeg=%d goni=%d\n', eeg_field, n_eeg, n_goni);
            session_ok = false;
            paired.(lower(eeg_field)) = empty_condition();
            continue;
        end

        % Duration check
        eeg_durs  = cellfun(@(x) size(x, 2) / eeg_srate, eeg_trials(:));
        goni_durs = arrayfun(@(t) size(t.joint_angles, 1) / goni_srate, goni_trials(:));
        dur_diff  = abs(eeg_durs - goni_durs);
        max_diff  = max(dur_diff);

        if max_diff > dur_tol
            fprintf('  WARN %s: max duration diff = %.3fs (tol=%.3fs)\n', ...
                eeg_field, max_diff, dur_tol);
        end

        % Pair: resample goni to EEG srate, trim to common length
        eeg_epochs  = cell(n_eeg, 1);
        goni_epochs = cell(n_eeg, 1);
        trial_dur   = zeros(n_eeg, 1);

        tt = struct('trial', {}, 'start_sec', {}, 'end_sec', {}, 'dur_sec', {}, ...
                    'goni_start_sec', {}, 'goni_end_sec', {});

        for t = 1:n_eeg
            eeg_seg = double(eeg_trials{t});  % [60 x T_eeg]

            % Resample goni to EEG srate
            goni_raw = double(goni_trials(t).joint_angles);  % [T_goni x n_joints]
            [p, q] = rat(eeg_srate / goni_srate);
            goni_rs = resample(goni_raw, p, q);  % [T_rs x n_joints]
            goni_rs = goni_rs';  % [n_joints x T_rs]

            % Trim to common length
            T = min(size(eeg_seg, 2), size(goni_rs, 2));
            eeg_seg = eeg_seg(:, 1:T);
            goni_rs = goni_rs(:, 1:T);

            eeg_epochs{t}  = eeg_seg;
            goni_epochs{t} = goni_rs;
            trial_dur(t)   = T / eeg_srate;

            row.trial = t;
            row.dur_sec = T / eeg_srate;
            if has_info
                row.start_sec = ep.(info_field)(t).start_lat / eeg_srate;
                row.end_sec   = ep.(info_field)(t).end_lat   / eeg_srate;
            else
                row.start_sec = NaN;
                row.end_sec   = NaN;
            end
            row.goni_start_sec = goni_trials(t).start_eeg_sec;
            row.goni_end_sec   = goni_trials(t).end_eeg_sec;
            tt(end+1) = row; %#ok<AGROW>
        end

        cond_out = struct();
        cond_out.eeg_epochs  = eeg_epochs;
        cond_out.goni_epochs = goni_epochs;
        cond_out.trial_dur   = trial_dur;
        cond_out.trial_table = tt;
        cond_out.n_trials    = n_eeg;

        paired.(lower(eeg_field)) = cond_out;
        total_pairs = total_pairs + n_eeg;

        fprintf('  %s: %d trials, dur=%.1f-%.1fs, max_dur_diff=%.3fs\n', ...
            eeg_field, n_eeg, min(trial_dur), max(trial_dur), max_diff);
    end

    % Save
    result = struct();
    result.label       = label;
    result.chanlocs    = ep.chanlocs;
    result.goni_labels = G.goni_labels;
    result.eeg_srate   = eeg_srate;
    result.goni_srate  = eeg_srate;  % after resampling
    n_eeg_ch = 60;
    for c2 = 1:size(cond_map, 1)
        fn2 = lower(cond_map{c2,1});
        if isfield(paired, fn2) && paired.(fn2).n_trials > 0
            n_eeg_ch = size(paired.(fn2).eeg_epochs{1}, 1);
            break;
        end
    end
    result.n_eeg_ch    = n_eeg_ch;
    result.n_goni_ch   = length(G.goni_labels);
    result.paired      = paired;
    result.align_info  = G.align_info;
    result.ic_rejection = 'ICLabel > 0.8 non-brain';
    result.pipeline    = 'V8: dual HP, FCz 60ch, AMICA 1model, ICLabel>0.8';

    out_file = fullfile(out_dir, [label '_paired.mat']);
    save(out_file, '-struct', 'result', '-v7.3');

    status = 'OK';
    if ~session_ok, status = 'ERROR'; end
    summary{s} = sprintf('%s: %d pairs, %s', label, total_pairs, status);
    fprintf('  Saved: %s [%s]\n', out_file, status);
end

%% Summary
fprintf('\n\n========== SUMMARY ==========\n');
for s = 1:length(all_sessions)
    if ~isempty(summary{s})
        fprintf('  %s\n', summary{s});
    end
end
fprintf('\nOutput: %s\n', out_dir);
fprintf('Format: %dHz, 60ch EEG (V8), goni resampled to match\n', eeg_srate);
fprintf('=== Done ===\n');


function c = empty_condition()
    c.eeg_epochs  = {};
    c.goni_epochs = {};
    c.trial_dur   = [];
    c.trial_table = struct('trial', {}, 'start_sec', {}, 'end_sec', {}, ...
                           'dur_sec', {}, 'goni_start_sec', {}, 'goni_end_sec', {});
    c.n_trials    = 0;
end
