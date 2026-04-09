%% run_prep_v7 — Batch preprocessing V7 on aa server (8 parallel workers)
%
% Runs 4 healthy sessions + 5 patient sessions in parallel using parfor.
% Output: ~/gait/prep_data_v7/
%
% Usage on aa server:
%   cd ~/gait/code
%   matlab -batch "run_prep_v7"

%% ======================== Configuration ========================

base_dir = '/home/wilson/gait';
out_dir  = fullfile(base_dir, 'prep_data_v7');

if ~exist(out_dir, 'dir'), mkdir(out_dir); end

%% ======================== Job Table ========================
% Columns: {input_file, out_label, group, max_step, skip_trim, marker_set}

jobs = {};

% --- Healthy (4 pilot sessions) ---
% Actual paths on aa: ~/gait/raw_data/SUB_XX/sessNN/EEG/*.vhdr
healthy_jobs = {
    'raw_data/SUB_01/sess01/EEG/a2walk_cbcr_0001.vhdr', 'SUB_01_sess01'
    'raw_data/SUB_05/sess01/EEG/a2walk_cbcr_0006.vhdr', 'SUB_05_sess01'
    'raw_data/SUB_07/sess01/EEG/a2walk_cbcr_0010.vhdr', 'SUB_07_sess01'
    'raw_data/SUB_09/sess01/EEG/a2walk_cbcr_0014.vhdr', 'SUB_09_sess01'
};

for i = 1:size(healthy_jobs, 1)
    jobs{end+1} = {
        fullfile(base_dir, healthy_jobs{i, 1}), ...
        healthy_jobs{i, 2}, ...
        'healthy', 4, false, 'healthy'
    }; %#ok<SAGROW>
end

% --- Patient (good REF, full pipeline) ---
% Sub01_Sess01: merged .set from V5 (4 files: 0009-0012), legacy markers, skip trim
jobs{end+1} = {
    fullfile(base_dir, '_archive/prep_data_v5/P01_Sess01_merged.set'), ...
    'P01_Sess01', 'patient', 4, true, 'patient_legacy'
};

% Sub01_Sess02: merged .set from V5 (3 files: 0013-0015), legacy markers, skip trim
jobs{end+1} = {
    fullfile(base_dir, '_archive/prep_data_v5/P01_Sess02_merged.set'), ...
    'P01_Sess02', 'patient', 4, true, 'patient_legacy'
};

% Sub01_Sess05: single file, standard markers
jobs{end+1} = {
    fullfile(base_dir, 'raw_data/patient/SUBJECT-01/RESTORE2_001_Sess05/sess03_20Feb2026-115928.609/EEG/RESTORE2-0020.vhdr'), ...
    'P01_Sess05', 'patient', 4, false, 'patient'
};

% Sub02_Sess03: single file, S11 yes S12 no → trim S11→end handled by code
jobs{end+1} = {
    fullfile(base_dir, 'raw_data/patient/SUBJECT-02/sess03_02Mar2026-140612.038/EEG/gait-ttsh-S0140.vhdr'), ...
    'P02_Sess03', 'patient', 4, false, 'patient'
};

% Sub02_Sess04: NEW session (06 Apr 2026), single file, standard markers, S11+S12 ✓
jobs{end+1} = {
    fullfile(base_dir, 'raw_data/patient/SUBJECT-02/RESTORE2_002_Sess04/sess04_06Apr2026-115201.751/EEG/RESTORE2-0027.vhdr'), ...
    'P02_Sess04', 'patient', 4, false, 'patient'
};

n_jobs = length(jobs);
fprintf('=== V7 Batch: %d jobs ===\n', n_jobs);

%% ======================== Print job summary ========================

for j = 1:n_jobs
    job = jobs{j};
    fprintf('  [%d] %s (%s, max_step=%d, skip_trim=%d, %s)\n', ...
        j, job{2}, job{3}, job{4}, job{5}, job{6});
end

%% ======================== Parallel execution ========================

% Start parallel pool with 8 workers
pool = gcp('nocreate');
if isempty(pool)
    pool = parpool('local', min(8, n_jobs));
elseif pool.NumWorkers < min(8, n_jobs)
    delete(pool);
    pool = parpool('local', min(8, n_jobs));
end
fprintf('  Parallel pool: %d workers\n', pool.NumWorkers);

% Add code directory to path on all workers
code_dir = fileparts(mfilename('fullpath'));
addpath(code_dir);

results = cell(n_jobs, 1);
statuses = zeros(n_jobs, 1);  % 0=pending, 1=success, -1=error

parfor j = 1:n_jobs
    job = jobs{j};
    input_file = job{1};
    out_label  = job{2};
    group      = job{3};
    max_step   = job{4};
    skip_trim  = job{5};
    marker_set = job{6};

    fprintf('\n>>> Starting [%d/%d]: %s <<<\n', j, n_jobs, out_label);
    t_start = tic;

    try
        if strcmp(group, 'healthy')
            prep_healthy_v7(input_file, out_dir, max_step, out_label);
        else
            prep_patient_v7(input_file, out_dir, max_step, out_label, skip_trim, marker_set);
        end
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
fprintf('=== V7 Preprocessing Summary ===\n');
fprintf('========================================\n');
n_ok  = sum(statuses == 1);
n_err = sum(statuses == -1);
for j = 1:n_jobs
    status_str = {'PENDING', 'OK', 'ERROR'};
    fprintf('  [%d] %-15s  %s  %s\n', j, jobs{j}{2}, ...
        status_str{statuses(j)+2}, results{j});
end
fprintf('----------------------------------------\n');
fprintf('  Total: %d OK, %d ERROR, %d jobs\n', n_ok, n_err, n_jobs);
fprintf('  Output: %s\n', out_dir);
fprintf('========================================\n');
