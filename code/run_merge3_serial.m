% Run V6 pipeline for SUB_10, SUB_12, SUB_16 in SERIAL mode
% These failed in parfor due to transparency violation after merge

addpath(genpath('~/eeglab2024'));
eeglab nogui;
addpath('~/gait/code');

out_dir = fullfile(getenv('HOME'), 'gait', 'prep_data_v5');
raw_base = fullfile(getenv('HOME'), 'gait', 'raw_data');
subs = {'SUB_10', 'SUB_12', 'SUB_16'};

for si = 1:length(subs)
    sub = subs{si};
    sub_dir = fullfile(raw_base, sub);
    sess = 'sess01';
    prefix = sprintf('%s_%s', sub, sess);

    fprintf('\n\n===== Processing %s (serial) =====\n', prefix);

    d = dir(sub_dir);
    d = d([d.isdir] & ~startsWith({d.name}, '.'));
    d = d(contains({d.name}, sess));

    fprintf('  Found %d recordings\n', length(d));

    EEG_all = [];
    for ri = 1:length(d)
        eeg_dir = fullfile(sub_dir, d(ri).name, 'EEG');
        vhdr = dir(fullfile(eeg_dir, '*.vhdr'));
        if isempty(vhdr), continue; end

        fprintf('  Loading rec %d: %s\n', ri, vhdr(1).name);
        EEG_tmp = pop_loadbv(char(eeg_dir), vhdr(1).name);

        if isempty(EEG_all)
            EEG_all = EEG_tmp;
        else
            EEG_all = pop_mergeset(EEG_all, EEG_tmp);
        end
    end

    fprintf('  Merged: %d ch, %d pts, %.1f min\n', ...
        EEG_all.nbchan, EEG_all.pnts, EEG_all.xmax/60);

    % Save merged
    merged_file = [prefix '_merged.set'];
    pop_saveset(EEG_all, 'filename', merged_file, 'filepath', char(out_dir));
    fprintf('  Saved merged\n');

    merged_path = fullfile(out_dir, merged_file);

    % Run prep_3step
    try
        % prep_3step(input_file, out_dir, max_step, out_label, skip_trim, num_models, marker_set)
        prep_3step(char(merged_path), char(out_dir), 3, prefix, false, 2, 'healthy');
        fprintf('  SUCCESS: %s completed all steps\n', prefix);
    catch ME
        fprintf('  ERROR %s: %s\n', prefix, ME.message);
        for k = 1:min(5, length(ME.stack))
            fprintf('    %s line %d\n', ME.stack(k).name, ME.stack(k).line);
        end
    end
end

fprintf('\n===== ALL DONE =====\n');
