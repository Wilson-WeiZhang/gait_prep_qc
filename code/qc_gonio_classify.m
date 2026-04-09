%% qc_gonio_classify.m — Classify flagged goni trials as expected vs real problem
%
% Reruns QC with condition-aware logic:
%   MI (label=0):   Walker should walk, Subject flat → flag only if Walker flat
%   Walk (label=2): Subject should walk, Walker flat → flag only if Subject flat
%   Rest (label=1): all flat expected → never a real problem
%
% Output: summary table + per-subject text report
%
% Usage (Windows):
%   cd('C:\Users\Admin\OneDrive\gait\code'); qc_gonio_classify

clear; clc;

if ispc
    root_dir = 'C:\Users\Admin\OneDrive - Nanyang Technological University\gait_data';
    eeglab_path = 'C:\Users\Admin\OneDrive - Nanyang Technological University\matlabsoft\eeglab-eeglab2024.2';
    out_dir = 'C:\Users\Admin\OneDrive\gait\result\qc\gonio_qc_v3';
else
    root_dir = '/Users/zw/Library/CloudStorage/OneDrive-NanyangTechnologicalUniversity/gait_data';
    eeglab_path = '/Users/zw/Desktop/eeglab-eeglab2024.2';
    out_dir = '/Users/zw/Library/CloudStorage/OneDrive-Personal/gait/result/qc/gonio_qc_v3';
end

addpath(eeglab_path);
eeglab nogui;
addpath(fileparts(mfilename('fullpath')));

if ~exist(out_dir, 'dir'), mkdir(out_dir); end

%% Thresholds (same as qc_gonio_subject)
ABS_THRESH = 0.25;   % vs baseline median
DROP_THRESH = 0.50;  % vs rolling median
PREV_WIN = 5;
PEAK_MIN = 1;

%% Summary collector
all_results = {};

for sub_id = 1:19
    fprintf('\n========== SUB_%02d ==========\n', sub_id);
    try
        res = classify_subject(sub_id, root_dir, out_dir, ...
            ABS_THRESH, DROP_THRESH, PREV_WIN, PEAK_MIN);
        all_results{end+1} = res; %#ok<SAGROW>
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
    end
end

%% Write grand summary
write_grand_summary(all_results, out_dir);
fprintf('\n=== Done. Output: %s ===\n', out_dir);


%% =========================================================
function res = classify_subject(sub_id, root_dir, out_dir, ABS_THRESH, DROP_THRESH, PREV_WIN, PEAK_MIN)

sub_folder = sprintf('SUB_%02d', sub_id);
sub_str = sprintf('sub%02d', sub_id);
sub_dir = fullfile(root_dir, sub_folder);

sesslist = dir(sub_dir);
sesslist = sesslist([sesslist.isdir] & ~ismember({sesslist.name}, {'.','..'}));

res.subject = sub_str;
res.sessions = {};

report_file = fullfile(out_dir, sprintf('%s_classify.txt', sub_str));
fid = fopen(report_file, 'w');

for isess = 1:numel(sesslist)
    sess_name = sesslist(isess).name;
    sess_dir = fullfile(sub_dir, sess_name);
    eeg_dir = fullfile(sess_dir, 'EEG');
    goni_dir = fullfile(sess_dir, 'Goniometer');

    if ~exist(eeg_dir,'dir') || ~exist(goni_dir,'dir')
        continue;
    end

    hdr = dir(fullfile(eeg_dir, '*.vhdr'));
    ghdr = dir(fullfile(goni_dir, '*.txt'));
    if isempty(hdr) || isempty(ghdr), continue; end

    try
        data = load_raw_session(hdr(1), ghdr(1));
    catch ME
        fprintf(fid, 'Session %s: load failed — %s\n\n', sess_name, ME.message);
        continue;
    end

    C = data.goni.c;
    X = data.goni.x;
    events = data.event;
    n_trials = numel(events);

    % Identify Walker vs Subject channel groups
    w_idx = []; s_idx = [];
    for i = 1:numel(C)
        ch = to_str_local(C, i);
        if contains(ch, 'W'), w_idx(end+1) = i; end %#ok<AGROW>
        if contains(ch, 'S'), s_idx(end+1) = i; end %#ok<AGROW>
    end

    % Per-trial, per-group metrics
    n_real_problem = 0;
    n_expected = 0;
    n_clean = 0;
    problem_trials = [];

    % Compute baseline from first 10 valid trials, per group
    [base_w, base_s] = compute_baseline(X, events, w_idx, s_idx, 10);

    fprintf(fid, '=== %s (%d trials) ===\n', sess_name, n_trials);

    for k = 1:n_trials
        label = events(k).label;
        s = max(1, round(double(events(k).gtstart)));
        e = min(size(X,1), round(double(events(k).gtstop)));
        if e <= s, continue; end
        seg = X(s:e, :);

        cond_name = label2cond(label);

        % Compute metrics per group
        w_std = mean_ch_std(seg, w_idx);
        s_std = mean_ch_std(seg, s_idx);

        % Determine if the "active" group is flat
        switch label
            case 0  % MI: Walker should be active
                active_std = w_std;
                active_base = base_w;
                expected_flat = 'Subject';
            case 2  % Walk: Subject should be active
                active_std = s_std;
                active_base = base_s;
                expected_flat = 'Walker';
            case 1  % Rest: all flat expected
                n_expected = n_expected + 1;
                continue;
            otherwise
                n_clean = n_clean + 1;
                continue;
        end

        % Is the active group abnormally flat?
        if active_base > 0 && active_std < ABS_THRESH * active_base
            n_real_problem = n_real_problem + 1;
            problem_trials(end+1) = k; %#ok<AGROW>
            fprintf(fid, '  Trial %3d [%s] *** PROBLEM *** active(%s) std=%.2f vs base=%.2f\n', ...
                k, cond_name, flip_group(expected_flat), active_std, active_base);
        else
            n_clean = n_clean + 1;
        end
    end

    sess_res.name = sess_name;
    sess_res.n_trials = n_trials;
    sess_res.n_mi = sum([events.label] == 0);
    sess_res.n_walk = sum([events.label] == 2);
    sess_res.n_rest = sum([events.label] == 1);
    sess_res.n_real_problem = n_real_problem;
    sess_res.n_expected = n_expected;
    sess_res.n_clean = n_clean;
    sess_res.problem_trials = problem_trials;
    res.sessions{end+1} = sess_res;

    fprintf(fid, '  Summary: %d trials | %d MI | %d Walk | %d Rest | %d REAL PROBLEMS | %d expected-flat | %d clean\n\n', ...
        n_trials, sess_res.n_mi, sess_res.n_walk, sess_res.n_rest, ...
        n_real_problem, n_expected, n_clean);
    fprintf('  %s: %d trials, %d REAL PROBLEMS\n', sess_name, n_trials, n_real_problem);
end

fclose(fid);
end

%% =========================================================
function [base_w, base_s] = compute_baseline(X, events, w_idx, s_idx, n_base)
% Use first n_base MI trials for Walker baseline, first n_base Walk trials for Subject baseline
w_stds = [];
s_stds = [];
for k = 1:numel(events)
    s = max(1, round(double(events(k).gtstart)));
    e = min(size(X,1), round(double(events(k).gtstop)));
    if e <= s, continue; end
    seg = X(s:e, :);
    if events(k).label == 0 && numel(w_stds) < n_base
        w_stds(end+1) = mean_ch_std(seg, w_idx); %#ok<AGROW>
    end
    if events(k).label == 2 && numel(s_stds) < n_base
        s_stds(end+1) = mean_ch_std(seg, s_idx); %#ok<AGROW>
    end
    if numel(w_stds) >= n_base && numel(s_stds) >= n_base
        break;
    end
end
base_w = median(w_stds);
base_s = median(s_stds);
if isempty(w_stds), base_w = 0; end
if isempty(s_stds), base_s = 0; end
end

%% =========================================================
function v = mean_ch_std(seg, ch_idx)
if isempty(ch_idx)
    v = 0;
    return;
end
stds = zeros(1, numel(ch_idx));
for i = 1:numel(ch_idx)
    stds(i) = std(seg(:, ch_idx(i)), 'omitnan');
end
v = mean(stds);
end

%% =========================================================
function s = label2cond(label)
switch label
    case 0, s = 'MI';
    case 1, s = 'Rest';
    case 2, s = 'Walk';
    otherwise, s = sprintf('L%d', label);
end
end

%% =========================================================
function s = flip_group(expected_flat)
if strcmp(expected_flat, 'Subject')
    s = 'Walker';
else
    s = 'Subject';
end
end

%% =========================================================
function s = to_str_local(C, i)
if iscell(C)
    x = C{i};
else
    x = C(i);
end
if isstring(x), s = char(x);
elseif ischar(x), s = x;
elseif isnumeric(x), s = num2str(x);
else, s = char(string(x));
end
end

%% =========================================================
function write_grand_summary(all_results, out_dir)
fid = fopen(fullfile(out_dir, 'GRAND_SUMMARY.txt'), 'w');
fprintf(fid, '%-8s %-45s %6s %4s %4s %4s %8s %8s\n', ...
    'Subject', 'Session', 'Trials', 'MI', 'Walk', 'Rest', 'PROBLEMS', 'Clean');
fprintf(fid, '%s\n', repmat('-', 1, 95));

total_problems = 0;
for i = 1:numel(all_results)
    r = all_results{i};
    for j = 1:numel(r.sessions)
        ss = r.sessions{j};
        marker = '';
        if ss.n_real_problem > 0
            marker = ' <<<';
        end
        fprintf(fid, '%-8s %-45s %6d %4d %4d %4d %8d %8d%s\n', ...
            r.subject, ss.name, ss.n_trials, ss.n_mi, ss.n_walk, ss.n_rest, ...
            ss.n_real_problem, ss.n_clean, marker);
        total_problems = total_problems + ss.n_real_problem;
    end
end
fprintf(fid, '\nTotal real problems across all subjects: %d\n', total_problems);
fclose(fid);
fprintf('\nGrand summary: %s\n', fullfile(out_dir, 'GRAND_SUMMARY.txt'));
end

%% =========================================================
function data = load_raw_session(eeg_hdr, goni_txt)
data.eeg = eeg_label_local(eeg_hdr);
data.goni = g_label_local(goni_txt);

eeg_tstart = data.eeg.event.tstamp(find(data.eeg.event.label==11, 1, 'last'));
goni_tstart = find(data.goni.y~=0, 1);
if isempty(eeg_tstart), error('No EEG trigger 11'); end
if isempty(goni_tstart), error('No goni stim onset'); end

dev = eeg_tstart - goni_tstart;
data.goni.t = (1:size(data.goni.x,1)) + dev;
data.event = get_events_local(data.eeg.event, dev);
end

%% =========================================================
function data = eeg_label_local(hdr)
EEG = pop_loadbv(hdr.folder, hdr.name);
event = [];
iev = 0;
for idx = 1:size(EEG.event,2)
    if strcmp(EEG.event(idx).code, 'Stimulus') || strcmp(EEG.event(idx).code, 'Response')
        iev = iev+1;
        event.label(iev) = str2double(EEG.event(idx).type(2:end));
        event.tstamp(iev) = EEG.event(idx).latency;
        event.evtype{iev} = EEG.event(idx).type;
    end
end
data.event = event;
end

%% =========================================================
function data = g_label_local(hdr)
filename = fullfile(hdr.folder, hdr.name);
params = getrowinfo_local(hdr);
g_hdr = importfile_hdr_local(filename, params);
g_data = table2array(readtable(filename));
g_data = g_data(~isnan(sum(g_data,2)),:);

istim = find(contains(g_hdr, 'Stim'), 1);
if isempty(istim), error('No Stim column in %s', hdr.name); end

keep_cols = true(1,size(g_data,2));
keep_cols(istim) = false;
data.x = g_data(:,keep_cols);
data.c = cellstr(string(g_hdr(keep_cols)));
data.y = g_data(:,istim);
end

%% =========================================================
function param_rows = getrowinfo_local(hdr)
filename = fullfile(hdr.folder, hdr.name);
fid = fopen(filename, 'r');
cleanup = onCleanup(@() fclose(fid));
numRows = 0;
param_rows = [];
while ~feof(fid)
    tline = fgetl(fid);
    numRows = numRows + 1;
    if ischar(tline) && contains(tline, 'C')
        param_rows = [param_rows numRows]; %#ok<AGROW>
    end
end
if numel(param_rows) < 2
    error('Could not infer gonio header block');
end
param_rows = param_rows([1 end]) - 1;
end

%% =========================================================
function data = importfile_hdr_local(filename, dataLines)
opts = delimitedTextImportOptions("NumVariables", 24);
opts.DataLines = dataLines;
opts.Delimiter = "	";
data = readmatrix(filename, opts);
end

%% =========================================================
function event = get_events_local(eeg_event, dev)
tstamps = [eeg_event.tstamp].';
labels = [eeg_event.label].';

hasEvtype = isfield(eeg_event,'evtype') && ~isempty({eeg_event.evtype});
hasR = false;
if hasEvtype
    evtype = [eeg_event.evtype].';
    hasR = any(contains(evtype, "R"));
end

if hasR
    isRepeated = [false; diff(tstamps) == 0];
    tstamps = tstamps(~isRepeated);
    labels = labels(~isRepeated);
    evtype = evtype(~isRepeated);

    rIdx = find(contains(evtype, "R"));
    nPairs = floor(numel(rIdx)/2);
    if nPairs > 0
        rest_start = rIdx(1:2:2*nPairs);
        rest_end = rIdx(2:2:2*nPairs);
        labels(rest_start) = 7;
        labels(rest_end) = 8;
    end
end

keep = labels < 10;
labels = labels(keep);
tstamps = tstamps(keep);

event = struct('label',{},'code',{},'etstart',{},'etstop',{},'gtstart',{},'gtstop',{});
idx = 1;
transitions = [1 2 0 1; 7 8 1 2; 4 5 2 3];
codes = {'gaitimagery', 'rest', 'gaitexecution'};

for i = 2:length(labels)
    dt = tstamps(i) - tstamps(i-1);
    if dt <= 2000, continue; end
    match_idx = find(labels(i-1)==transitions(:,1) & labels(i)==transitions(:,2), 1);
    if ~isempty(match_idx)
        event(idx).label = transitions(match_idx, 3);
        event(idx).code = codes{transitions(match_idx, 4)};
        event(idx).etstart = tstamps(i-1);
        event(idx).etstop = tstamps(i);
        event(idx).gtstart = tstamps(i-1) - dev;
        event(idx).gtstop = tstamps(i) - dev;
        idx = idx + 1;
    end
end
end
