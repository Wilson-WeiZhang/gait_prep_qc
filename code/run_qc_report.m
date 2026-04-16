%% run_qc_report.m -- Generate all QC reports
%
% Master runner: calls IC topoplot, goni QC, alignment QC, and XLSX report
% in sequence. Adds EEGLAB to path once.
%
% Usage:
%   cd ~/gait/gait_prep_qc/code && ~/matlab/bin/matlab -batch "run_qc_report"

clear; clc;
set(0, 'DefaultFigureVisible', 'off');

% EEGLAB
if ~exist('eeglab', 'file')
    if ismac
        addpath('/Users/zw/Desktop/eeglab-eeglab2024.2');
    else
        addpath('/home/wilson/eeglab2024');
    end
    eeglab nogui;
end

code_dir = fileparts(mfilename('fullpath'));
addpath(code_dir);
addpath(fullfile(code_dir, 'utils'));

t0 = tic;

fprintf('\n========================================\n');
fprintf('  QC Report Generation\n');
fprintf('  %s\n', datestr(now));
fprintf('========================================\n\n');

fprintf('=== Step 1/4: IC Topoplots ===\n');
try
    plot_ic_topo;
    fprintf('  Step 1 complete.\n\n');
catch ME
    fprintf('  Step 1 FAILED: %s\n\n', ME.message);
end

fprintf('=== Step 2/4: Goni QC Plots ===\n');
try
    plot_goni_qc;
    fprintf('  Step 2 complete.\n\n');
catch ME
    fprintf('  Step 2 FAILED: %s\n\n', ME.message);
end

fprintf('=== Step 3/4: Alignment QC Plots ===\n');
try
    plot_alignment_qc;
    fprintf('  Step 3 complete.\n\n');
catch ME
    fprintf('  Step 3 FAILED: %s\n\n', ME.message);
end

fprintf('=== Step 4/4: QC Report Table ===\n');
try
    generate_qc_report;
    fprintf('  Step 4 complete.\n\n');
catch ME
    fprintf('  Step 4 FAILED: %s\n\n', ME.message);
end

fprintf('========================================\n');
fprintf('  All done in %.1f minutes\n', toc(t0)/60);
fprintf('========================================\n');
