%% run_qc_gonio.m — Run goniometer QC (all channels, all trials)
% Detects OS and uses appropriate paths.
% Windows: matlab -batch "cd('C:\Users\Admin\OneDrive\gait\code'); run_qc_gonio"
% Mac:     matlab -batch "cd('~/Library/CloudStorage/OneDrive-Personal/gait/code'); run_qc_gonio"

clear; clc;

if ispc
    root_dir = 'C:\Users\Admin\OneDrive - Nanyang Technological University\gait_data';
    eeglab_path = 'C:\Users\Admin\OneDrive - Nanyang Technological University\matlabsoft\eeglab-eeglab2024.2';
    out_dir = 'C:\Users\Admin\OneDrive\gait\result\qc\gonio_qc_v2';
else
    root_dir = '/Users/zw/Library/CloudStorage/OneDrive-NanyangTechnologicalUniversity/gait_data';
    eeglab_path = '/Users/zw/Desktop/eeglab-eeglab2024.2';
    out_dir = '/Users/zw/Library/CloudStorage/OneDrive-Personal/gait/result/qc/gonio_qc_v2';
end

% Add EEGLAB
addpath(eeglab_path);
eeglab nogui;

% Add code directory (for qc_gonio_subject)
addpath(fileparts(mfilename('fullpath')));

% Run for all 19 subjects
for sub_id = 1:19
    fprintf('\n========== SUB_%02d ==========\n', sub_id);
    try
        qc_gonio_subject(sub_id, out_dir, ...
            'RootDir', root_dir, ...
            'EEGLABPath', eeglab_path, ...
            'DoPlotRaw', false);
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
    end
end

fprintf('\n=== All done. Output: %s ===\n', out_dir);
