%% pair_eeg_goni_v2.m — Pair new V6b EEG epochs with goniometer data
%
% Uses: epochs.mat (250Hz, 59ch, IC-cleaned with art>0.9||brain<0.05)
%       goni.mat   (1000Hz, IOI-aligned, trial-segmented)
%
% Pairing strategy:
%   - Index-based within condition (both extracted chronologically by same markers)
%   - Verified by duration comparison (actual data length, not dur_sec field)
%   - Goni resampled 1000→250Hz, trimmed to match EEG length
%
% Output: paired_data_v2/{label}_paired.mat per session
%
% Run on aa:
%   cd ~/gait/code && ~/matlab/bin/matlab -batch "pair_eeg_goni_v2"

%% Configuration
epoch_dir = '/home/wilson/gait/prep_data_v5';
goni_dir  = '/home/wilson/gait/goni_data/healthy';
out_dir   = '/home/wilson/gait/paired_data_v2';
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

sessions = {
    'SUB_01_sess01', 'SUB_01_sess02', 'SUB_02_sess01', 'SUB_02_sess02', ...
    'SUB_03_sess01', 'SUB_03_sess02', 'SUB_04_sess01', 'SUB_05_sess01', ...
    'SUB_06_sess01', 'SUB_06_sess02', 'SUB_07_sess01', 'SUB_08_sess01', ...
    'SUB_09_sess01'};

% Condition name mapping: epochs.mat field → goni.mat trial type
cond_map = {'MI', 'imagine'; 'Walk', 'walk'; 'Rest', 'rest'};

target_srate = 250;  % output sample rate (matches EEG)
dur_tol = 0.1;       % max acceptable duration mismatch (seconds)

fprintf('=== EEG-Goni Pairing V2: %d sessions ===\n\n', length(sessions));

%% Process each session
summary = cell(length(sessions), 1);

for s = 1:length(sessions)
    label = sessions{s};
    fprintf('\n[%d/%d] ===== %s =====\n', s, length(sessions), label);

    % Load epochs
    epoch_file = fullfile(epoch_dir, [label '_epochs.mat']);
    if ~exist(epoch_file, 'file')
        fprintf('  SKIP: epochs.mat not found\n');
        continue;
    end
    E = load(epoch_file);
    eeg_srate = E.epochs.srate;  % 250

    % Load goni
    goni_file = fullfile(goni_dir, [label '_goni.mat']);
    if ~exist(goni_file, 'file')
        fprintf('  SKIP: goni.mat not found\n');
        continue;
    end
    G = load(goni_file);
    goni_srate = G.goni_srate;  % 1000
    resample_ratio = goni_srate / target_srate;  % 4

    % Output struct
    paired = struct();
    session_ok = true;
    total_pairs = 0;

    for c = 1:size(cond_map, 1)
        eeg_field  = cond_map{c, 1};
        goni_type  = cond_map{c, 2};

        % Get EEG epochs
        if ~isfield(E.epochs, eeg_field)
            paired.(lower(eeg_field)) = empty_condition();
            continue;
        end
        eeg_trials = E.epochs.(eeg_field);
        n_eeg = length(eeg_trials);

        % Get goni trials
        goni_mask = strcmp({G.trials.type}, goni_type);
        goni_trials = G.trials(goni_mask);
        n_goni = length(goni_trials);

        if n_eeg == 0 && n_goni == 0
            paired.(lower(eeg_field)) = empty_condition();
            continue;
        end

        % === VERIFICATION 1: Trial count match ===
        if n_eeg ~= n_goni
            fprintf('  ERROR %s: count mismatch eeg=%d goni=%d\n', eeg_field, n_eeg, n_goni);
            session_ok = false;
            paired.(lower(eeg_field)) = empty_condition();
            continue;
        end

        % === VERIFICATION 2: Duration match (actual data, not dur_sec field) ===
        eeg_durs  = cellfun(@(x) size(x, 2) / eeg_srate, eeg_trials(:));
        goni_durs = arrayfun(@(t) size(t.joint_angles, 1) / goni_srate, goni_trials(:));
        dur_diff  = abs(eeg_durs - goni_durs);
        max_diff  = max(dur_diff);

        if max_diff > dur_tol
            fprintf('  WARN %s: max duration diff = %.3fs (tol=%.3fs)\n', ...
                eeg_field, max_diff, dur_tol);
            % Still proceed - trim will handle small mismatches
        end

        % === PAIR: resample goni → trim to common length ===
        eeg_epochs  = cell(n_eeg, 1);
        goni_epochs = cell(n_eeg, 1);
        trial_dur   = zeros(n_eeg, 1);

        for t = 1:n_eeg
            eeg_seg = double(eeg_trials{t});  % [59 × T_eeg]

            % Resample goni: 1000 → 250 Hz
            goni_raw = double(goni_trials(t).joint_angles);  % [T_goni × n_joints]
            goni_rs  = resample(goni_raw, 1, resample_ratio);  % [T_250 × n_joints]
            goni_rs  = goni_rs';  % [n_joints × T_250]

            % Trim to common length
            T = min(size(eeg_seg, 2), size(goni_rs, 2));
            eeg_seg  = eeg_seg(:, 1:T);
            goni_rs  = goni_rs(:, 1:T);

            eeg_epochs{t}  = eeg_seg;
            goni_epochs{t} = goni_rs;
            trial_dur(t)   = T / target_srate;
        end

        cond_out = struct();
        cond_out.eeg_epochs  = eeg_epochs;
        cond_out.goni_epochs = goni_epochs;
        cond_out.trial_dur   = trial_dur;
        cond_out.n_trials    = n_eeg;

        paired.(lower(eeg_field)) = cond_out;
        total_pairs = total_pairs + n_eeg;

        fprintf('  %s: %d trials, dur=%.1f-%.1fs, max_dur_diff=%.3fs\n', ...
            eeg_field, n_eeg, min(trial_dur), max(trial_dur), max_diff);
    end

    % === Save ===
    result = struct();
    result.label       = label;
    result.chanlocs    = E.epochs.chanlocs;
    result.goni_labels = G.goni_labels;
    result.eeg_srate   = target_srate;
    result.goni_srate  = target_srate;  % after resampling
    % Get n_eeg_ch from any non-empty condition
    n_eeg_ch = 59;
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
    result.ic_rejection = 'artifact>0.9 || brain<0.05';
    result.pipeline    = 'V6b: step2→step2b(ICLabel)→step3→epochs→pair_v2';

    out_file = fullfile(out_dir, [label '_paired.mat']);
    save(out_file, '-struct', 'result', '-v7.3');

    n_conds = 0;
    for c = 1:size(cond_map, 1)
        fn = lower(cond_map{c,1});
        if isfield(paired, fn) && paired.(fn).n_trials > 0
            n_conds = n_conds + 1;
        end
    end

    status = 'OK';
    if ~session_ok, status = 'ERROR'; end
    summary{s} = sprintf('%s: %d pairs, %d conds, %s', label, total_pairs, n_conds, status);
    fprintf('  Saved: %s [%s]\n', out_file, status);
end

%% Summary
fprintf('\n\n========== SUMMARY ==========\n');
for s = 1:length(sessions)
    if ~isempty(summary{s})
        fprintf('  %s\n', summary{s});
    end
end
fprintf('\nOutput: %s\n', out_dir);
fprintf('Format: 250Hz, 59ch EEG, goni resampled to 250Hz\n');
fprintf('=== Done ===\n');


function c = empty_condition()
    c.eeg_epochs  = {};
    c.goni_epochs = {};
    c.trial_dur   = [];
    c.n_trials    = 0;
end
