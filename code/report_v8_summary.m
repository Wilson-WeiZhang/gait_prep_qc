%% report_v8_summary — Per-session V8 preprocessing summary
out_dir = '/home/wilson/gait/prep_data_v8';
addpath('/home/wilson/eeglab2024'); eeglab nogui;

files = dir(fullfile(out_dir, '*_step3.set'));
fprintf('%-18s %3s %8s %4s %3s %3s %3s %3s %3s %3s\n', ...
    'Session', 'Ch', 'BadCh', 'ICs', 'Rej', 'B70', 'B80', 'B90', 'MI', 'Wlk');
fprintf('%s\n', repmat('-', 1, 75));

for i = 1:length(files)
    fname = files(i).name;
    sess = strrep(fname, '_step3.set', '');
    EEG = pop_loadset('filename', fname, 'filepath', out_dir);
    
    meta = EEG.etc.step3_meta;
    bad_ch = meta.step2_meta.bad_ch_labels;
    n_bad = length(bad_ch);
    bad_str = '';
    if n_bad > 0, bad_str = strjoin(bad_ch, ','); end
    
    % IC stats
    n_rej = meta.n_ics_rejected;
    
    % Load step2 for ICLabel
    EEG2 = pop_loadset('filename', strrep(fname, 'step3', 'step2'), 'filepath', out_dir);
    EEG2 = iclabel(EEG2);
    bp = EEG2.etc.ic_classification.ICLabel.classifications(:,1);
    n_ics = length(bp);
    
    % Count trials from events
    evt = {EEG.event.type};
    n_mi = sum(strcmp(evt, 'S  1'));
    n_wk = sum(strcmp(evt, 'S  4'));
    
    fprintf('%-18s %3d %2d %-5s %4d %3d %3d %3d %3d %3d %3d\n', ...
        sess, EEG.nbchan, n_bad, bad_str, n_ics, n_rej, ...
        sum(bp>0.7), sum(bp>0.8), sum(bp>0.9), n_mi, n_wk);
end
