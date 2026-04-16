%% plot_ic_topo.m -- ICA scalp topoplot figures for all V8-preprocessed EEG sessions
%
% Loads *_step2.set for each session, runs iclabel on-the-fly, plots top 20 ICs
% in a 4x5 grid, color-coded by ICLabel class.
%
% Usage (aa server):
%   cd /home/wilson/gait/gait_prep_qc/code && matlab -batch "plot_ic_topo"

clear; clc;
set(0, 'DefaultFigureVisible', 'off');

%% Paths
if ismac
    eeglab_path = '/Users/zw/Desktop/eeglab-eeglab2024.2';
    eeg_dir     = '/Users/zw/Library/CloudStorage/OneDrive-Personal/gait/prep_data/healthy';
    out_dir     = '/Users/zw/Library/CloudStorage/OneDrive-Personal/gait/gait_prep_qc/result/qc_figs/ic_topo';
elseif ispc
    eeglab_path = 'PLACEHOLDER';
    eeg_dir     = 'PLACEHOLDER';
    out_dir     = 'PLACEHOLDER';
else  % Linux (aa server)
    eeglab_path = '/home/wilson/eeglab2024';
    eeg_dir     = '/home/wilson/gait/prep_data_v8';
    out_dir     = '/home/wilson/gait/gait_prep_qc/result/qc_figs/ic_topo';
end

addpath(eeglab_path);
eeglab nogui;

if ~exist(out_dir, 'dir'), mkdir(out_dir); end

%% ICLabel class definitions
class_names  = {'Brain','Muscle','Eye','Heart','LinNz','ChNz','Other'};
class_colors = {[0.2 0.7 0.2], [1 0.5 0], [0.9 0.1 0.1], ...
                [0.8 0.2 0.6], [0.5 0.5 0.5], [0.3 0.3 0.3], [0.6 0.6 0.6]};

%% Find all step2 sets
files = dir(fullfile(eeg_dir, '*_step2.set'));
fprintf('=== Generating IC topo figures: %d sessions ===\n', length(files));

%% Main loop
for fi = 1:length(files)
    fname = files(fi).name;
    label = strrep(fname, '_step2.set', '');
    outfile = fullfile(out_dir, sprintf('ic_topo_%s.png', label));

    if exist(outfile, 'file')
        fprintf('  [%d/%d] %s: already exists, skip\n', fi, length(files), label);
        continue;
    end

    try
        EEG = pop_loadset('filename', fname, 'filepath', eeg_dir);

        % Run ICLabel on-the-fly
        try
            EEG = iclabel(EEG);
            ic_classes = EEG.etc.ic_classification.ICLabel.classifications;
            has_label = true;
        catch
            has_label = false;
        end

        n_ics = min(20, size(EEG.icaweights, 1));

        fig = figure('Position', [50 50 1600 1200], 'Visible', 'off', 'Color', 'w');

        for ic = 1:20
            ax = subplot(4, 5, ic);
            if ic > n_ics
                axis(ax, 'off');
                continue;
            end

            topoplot(EEG.icawinv(:, ic), EEG.chanlocs, ...
                'electrodes', 'off', 'style', 'map', 'shading', 'interp');

            if has_label
                [max_prob, max_cat] = max(ic_classes(ic, :));
                t = title(sprintf('IC%d %s:%.0f%%', ic, class_names{max_cat}, max_prob * 100), ...
                    'FontSize', 8);
                set(t, 'Color', class_colors{max_cat});
            else
                title(sprintf('IC%d (no label)', ic), 'FontSize', 8);
            end
        end

        sgtitle(strrep(label, '_', '\_'), 'FontSize', 11, 'FontWeight', 'bold');

        try
            exportgraphics(fig, outfile, 'Resolution', 150);
        catch
            print(fig, outfile, '-dpng', '-r150');
        end
        close(fig);

        fprintf('  [%d/%d] %s: saved (%d ICs)\n', fi, length(files), label, n_ics);

    catch ME
        fprintf('  [%d/%d] %s: ERROR -- %s\n', fi, length(files), label, ME.message);
        try, close(fig); catch; end
    end
end

fprintf('=== Done. Output: %s ===\n', out_dir);
