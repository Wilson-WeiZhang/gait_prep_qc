%% run_prep_v7 — Batch preprocessing V8 on aa server
%
% V8 changes (2026-04-10):
%   - AMICA 2000 iter (was 1000)
%   - No baseline correction for ICA training segments
%   - ICA weights preserved in etc for source analysis
%
% Runs V8 preprocessing for all healthy sessions (single-file first).
% Multi-file sessions (SUB_10/12/16/22/28 sess01) need merge → separate script.
%
% Usage on aa server:
%   cd ~/gait/code
%   matlab -batch "run_prep_v7"

%% ======================== Configuration ========================

base_dir = '/home/wilson/gait';
out_dir  = fullfile(base_dir, 'prep_data_v8');

if ~exist(out_dir, 'dir'), mkdir(out_dir); end

%% ======================== Job Table ========================
% {relative_path_to_vhdr, out_label}

healthy_jobs = {
    % --- sess01 (single file) ---
    'raw_data/SUB_01/sess01/EEG/a2walk_cbcr_0001.vhdr',                          'SUB_01_sess01'
    'raw_data/SUB_02/sess01/EEG/a2walk_cbcr_0002.vhdr',                          'SUB_02_sess01'
    'raw_data/SUB_03/sess01/EEG/a2walk_cbcr_0003.vhdr',                          'SUB_03_sess01'
    'raw_data/SUB_04/sess01/EEG/a2walk_cbcr_0004.vhdr',                          'SUB_04_sess01'
    'raw_data/SUB_05/sess01/EEG/a2walk_cbcr_0006.vhdr',                          'SUB_05_sess01'
    'raw_data/SUB_06/sess01/EEG/a2walk_cbcr_0007.vhdr',                          'SUB_06_sess01'
    'raw_data/SUB_07/sess01/EEG/a2walk_cbcr_0010.vhdr',                          'SUB_07_sess01'
    'raw_data/SUB_08/sess01/EEG/a2walk_cbcr_0012.vhdr',                          'SUB_08_sess01'
    'raw_data/SUB_09/sess01/EEG/a2walk_cbcr_0014.vhdr',                          'SUB_09_sess01'
    'raw_data/SUB_11/sess01_13Mar2026-112655.296/EEG/imgait_s1_0002.vhdr',       'SUB_11_sess01'
    'raw_data/SUB_13/sess01_17Mar2026-142059.765/EEG/a2walk_cbcr_0019.vhdr',     'SUB_13_sess01'
    'raw_data/SUB_14/sess01_17Mar2026-155932.255/EEG/a2walk_cbcr_0020.vhdr',     'SUB_14_sess01'
    'raw_data/SUB_15/sess01_18Mar2026-110703.858/EEG/a2walk_cbcr_0021.vhdr',     'SUB_15_sess01'
    'raw_data/SUB_17/sess01_19Mar2026-115002.367/EEG/a2walk_cbcr_0024.vhdr',     'SUB_17_sess01'
    'raw_data/SUB_18/sess01_19Mar2026-141410.387/EEG/a2walk_cbcr_0025.vhdr',     'SUB_18_sess01'
    'raw_data/SUB_19/sess01_20Mar2026-120846.138/EEG/imgait_s1_0006.vhdr',       'SUB_19_sess01'
    'raw_data/SUB_20/sess01_25Mar2026-101650.914/EEG/a2walk_cbcr_0030.vhdr',     'SUB_20_sess01'
    'raw_data/SUB_21/sess01_27Mar2026-102428.881/EEG/a2walk_cbcr_0032.vhdr',     'SUB_21_sess01'
    'raw_data/SUB_23/sess01_31Mar2026-101043.449/EEG/a2walk_cbcr_0036.vhdr',     'SUB_23_sess01'
    'raw_data/SUB_24/sess01_31Mar2026-143133.686/EEG/a2walk_cbcr_0037.vhdr',     'SUB_24_sess01'
    'raw_data/SUB_25/sess01_31Mar2026-175305.595/EEG/a2walk_cbcr_0038.vhdr',     'SUB_25_sess01'
    'raw_data/SUB_26/sess01_02Apr2026-135750.364/EEG/a2walk_cbcr_0040.vhdr',     'SUB_26_sess01'
    'raw_data/SUB_27/sess01_07Apr2026-105117.844/EEG/a2walk_cbcr_0042.vhdr',     'SUB_27_sess01'
    % --- sess02 (single file) ---
    'raw_data/SUB_01/sess02/EEG/a2walk_cbcr_0011.vhdr',                          'SUB_01_sess02'
    'raw_data/SUB_02/sess02/EEG/a2walk_cbcr_0005.vhdr',                          'SUB_02_sess02'
    'raw_data/SUB_03/sess02/EEG/a2walk_cbcr_0008.vhdr',                          'SUB_03_sess02'
    'raw_data/SUB_06/sess02/EEG/a2walk_cbcr_0009.vhdr',                          'SUB_06_sess02'
    'raw_data/SUB_07/sess02_25Mar2026-142246.857/EEG/a2walk_cbcr_0031.vhdr',     'SUB_07_sess02'
    'raw_data/SUB_10/sess02_27Mar2026-152131.295/EEG/a2walk_cbcr_0033.vhdr',     'SUB_10_sess02'
    'raw_data/SUB_12/sess02_24Mar2026-104358.535/EEG/a2walk_cbcr_0028.vhdr',     'SUB_12_sess02'
    'raw_data/SUB_15/sess02_24Mar2026-155801.233/EEG/a2walk_cbcr_0029.vhdr',     'SUB_15_sess02'
};
% NOTE: Multi-file sessions EXCLUDED (need merge first):
%   SUB_10_sess01 (2 files), SUB_12_sess01 (2 files), SUB_16_sess01 (2 files)
%   SUB_22_sess01 (3 files), SUB_28_sess01 (3 files)
%   SUB_04_sess02 (2 files), SUB_09_sess02 (2 files)

%% ======================== Build jobs ========================

jobs = {};
for i = 1:size(healthy_jobs, 1)
    jobs{end+1} = {
        fullfile(base_dir, healthy_jobs{i, 1}), ...
        healthy_jobs{i, 2}, ...
        'healthy', 4, false, 'healthy', struct()
    }; %#ok<SAGROW>
end

n_jobs = length(jobs);
fprintf('=== V8 Batch: %d healthy jobs ===\n', n_jobs);

%% ======================== Print job summary ========================

for j = 1:n_jobs
    job = jobs{j};
    fprintf('  [%2d] %s\n', j, job{2});
end

%% ======================== Parallel execution (2 workers) ========================

code_dir = fileparts(mfilename('fullpath'));
addpath(code_dir);

n_workers = 4;

% Start parallel pool with limited workers
p = gcp('nocreate');
if isempty(p)
    p = parpool('local', n_workers);
elseif p.NumWorkers ~= n_workers
    delete(p);
    p = parpool('local', n_workers);
end

results = cell(n_jobs, 1);
statuses = zeros(n_jobs, 1);  % 0=pending, 1=success, -1=error

% diary doesn't work inside parfor; use per-job logging
logfile_main = fullfile(out_dir, sprintf('run_prep_v7b_%s.log', datestr(now, 'yyyymmdd_HHMMSS')));
fid_main = fopen(logfile_main, 'w');
fprintf(fid_main, '=== V8 Batch: %d jobs, %d workers ===\n', n_jobs, n_workers);
for j = 1:n_jobs
    fprintf(fid_main, '  [%2d] %s\n', j, jobs{j}{2});
end
fclose(fid_main);

parfor j = 1:n_jobs
    job = jobs{j};
    input_file = job{1};
    out_label  = job{2};
    max_step   = job{4};

    fprintf('\n>>> Starting [%d/%d]: %s <<<\n', j, n_jobs, out_label);
    t_start = tic;

    try
        prep_healthy_v8(input_file, out_dir, max_step, out_label);
        statuses(j) = 1;
        results{j} = sprintf('OK (%.1f min)', toc(t_start)/60);
    catch ME
        statuses(j) = -1;
        results{j} = sprintf('ERROR: %s', ME.message);
        fprintf('!!! FAILED [%d] %s: %s\n', j, out_label, ME.message);
    end

    fprintf('>>> Done [%d/%d]: %s — %s <<<\n', j, n_jobs, out_label, results{j});
end

%% ======================== Summary ========================

fprintf('\n\n========================================\n');
fprintf('=== V8 Preprocessing Summary ===\n');
fprintf('========================================\n');
n_ok  = sum(statuses == 1);
n_err = sum(statuses == -1);
for j = 1:n_jobs
    status_str = {'PENDING', 'OK', 'ERROR'};
    fprintf('  [%2d] %-15s  %s  %s\n', j, jobs{j}{2}, ...
        status_str{statuses(j)+2}, results{j});
end
fprintf('----------------------------------------\n');
fprintf('  Total: %d OK, %d ERROR, %d jobs\n', n_ok, n_err, n_jobs);
fprintf('  Output: %s\n', out_dir);
fprintf('========================================\n');

% Append summary to log file
fid_main = fopen(logfile_main, 'a');
fprintf(fid_main, '\n========================================\n');
fprintf(fid_main, '=== V8 Preprocessing Summary ===\n');
for j = 1:n_jobs
    status_str = {'PENDING', 'OK', 'ERROR'};
    fprintf(fid_main, '  [%2d] %-15s  %s  %s\n', j, jobs{j}{2}, ...
        status_str{statuses(j)+2}, results{j});
end
fprintf(fid_main, 'Total: %d OK, %d ERROR\n', n_ok, n_err);
fclose(fid_main);
