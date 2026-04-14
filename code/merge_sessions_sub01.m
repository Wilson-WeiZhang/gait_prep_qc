%% merge_sessions_sub01.m
% Concatenate all EEG recordings from Subject 01, Sessions 01-05,
% into a single EEGLAB dataset (.set), with a session boundary marker
% added at the first sample of each session.

clear; clc;

%% Paths
eeglab_path = '/Users/zw/Desktop/eeglab-eeglab2024.2';
addpath(eeglab_path);
eeglab nogui;

base_dir = fileparts(mfilename('fullpath'));  % _code folder
subj_dir = fullfile(base_dir, '..', 'SUBJECT-01');

out_dir = fullfile(base_dir, '..');
out_file = 'RESTORE2_001_allSess.set';

%% Define all .vhdr files per session (ordered by recording time)
sessions = struct();

sessions(1).name = 'Sess01';
sessions(1).vhdr = {
    fullfile(subj_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-133011.065', 'EEG', 'RESTORE2-0001.vhdr')
    fullfile(subj_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-133538.139', 'EEG', 'RESTORE2-0008.vhdr')
    fullfile(subj_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-134657.811', 'EEG', 'RESTORE2-0009.vhdr')
    fullfile(subj_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-135645.822', 'EEG', 'RESTORE2-0010.vhdr')
    fullfile(subj_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-140930.111', 'EEG', 'RESTORE2-0011.vhdr')
    fullfile(subj_dir, 'RESTORE2_001_Sess01', 'sess01_30Oct2025-143017.711', 'EEG', 'RESTORE2-0012.vhdr')
};

sessions(2).name = 'Sess02';
sessions(2).vhdr = {
    fullfile(subj_dir, 'RESTORE2_001_Sess02', 'sess02_13Nov2025-151356.773', 'EEG', 'RESTORE2-0013.vhdr')
    fullfile(subj_dir, 'RESTORE2_001_Sess02', 'sess02_13Nov2025-152740.938', 'EEG', 'RESTORE2-0014.vhdr')
    fullfile(subj_dir, 'RESTORE2_001_Sess02', 'sess02_13Nov2025-153915.611', 'EEG', 'RESTORE2-0015.vhdr')
};

sessions(3).name = 'Sess03';
sessions(3).vhdr = {
    fullfile(subj_dir, 'RESTORE2_001_Sess03', 'sess03_22Dec2025-123350.818', 'EEG', 'gait-ttsh-S0031.vhdr')
};

sessions(4).name = 'Sess04';
sessions(4).vhdr = {
    fullfile(subj_dir, 'RESTORE2_001_Sess04', 'sess04_20Jan2026-113202.009', 'EEG', 'RESTORE2-0016.vhdr')
    fullfile(subj_dir, 'RESTORE2_001_Sess04', 'sess04_20Jan2026-120842.115', 'EEG', 'RESTORE2-0018.vhdr')
};

sessions(5).name = 'Sess05';
sessions(5).vhdr = {
    fullfile(subj_dir, 'RESTORE2_001_Sess05', 'sess03_20Feb2026-115928.609', 'EEG', 'RESTORE2-0020.vhdr')
};

%% Load and concatenate
EEG_all = [];

for s = 1:length(sessions)
    fprintf('\n=== Loading %s (%d files) ===\n', sessions(s).name, length(sessions(s).vhdr));

    % Load all recordings within this session
    EEG_sess = [];
    for f = 1:length(sessions(s).vhdr)
        vhdr_file = sessions(s).vhdr{f};
        [fpath, fname, ~] = fileparts(vhdr_file);
        fprintf('  Loading %s ...\n', fname);
        EEG_tmp = pop_loadbv(fpath, [fname '.vhdr']);
        EEG_tmp = eeg_checkset(EEG_tmp);

        if isempty(EEG_sess)
            EEG_sess = EEG_tmp;
        else
            % Concatenate recordings within the same session
            EEG_sess = pop_mergeset(EEG_sess, EEG_tmp);
            EEG_sess = eeg_checkset(EEG_sess);
        end
    end

    fprintf('  %s: %d channels, %d points (%.1f sec)\n', ...
        sessions(s).name, EEG_sess.nbchan, EEG_sess.pnts, EEG_sess.xmax);

    % Record the sample offset where this session starts in the merged data
    if isempty(EEG_all)
        sess_start_sample = 1;
    else
        sess_start_sample = EEG_all.pnts + 1;
    end

    % Concatenate sessions
    if isempty(EEG_all)
        EEG_all = EEG_sess;
    else
        EEG_all = pop_mergeset(EEG_all, EEG_sess);
        EEG_all = eeg_checkset(EEG_all);
    end

    % Add session boundary marker at the first sample of this session
    n_events = length(EEG_all.event);
    EEG_all.event(n_events + 1).type    = sessions(s).name;
    EEG_all.event(n_events + 1).latency = sess_start_sample;
    EEG_all.event(n_events + 1).duration = 0;
    EEG_all.event(n_events + 1).urevent = n_events + 1;
    EEG_all = eeg_checkset(EEG_all, 'eventconsistency');
end

%% Set dataset info
EEG_all.setname = 'RESTORE2_001_allSess';
EEG_all.subject = 'Sub01';
EEG_all.comments = sprintf('Merged Sessions 01-05 for Subject 01\nSession markers: Sess01..Sess05');

%% Sort events by latency
[~, idx] = sort([EEG_all.event.latency]);
EEG_all.event = EEG_all.event(idx);
EEG_all = eeg_checkset(EEG_all);

%% Save
fprintf('\n=== Saving merged dataset ===\n');
fprintf('Total: %d channels, %d points (%.1f sec), %d events\n', ...
    EEG_all.nbchan, EEG_all.pnts, EEG_all.xmax, length(EEG_all.event));

pop_saveset(EEG_all, 'filename', out_file, 'filepath', out_dir);
fprintf('Saved to: %s\n', fullfile(out_dir, out_file));

%% Print session boundary summary
fprintf('\n=== Session boundaries ===\n');
for i = 1:length(EEG_all.event)
    if startsWith(EEG_all.event(i).type, 'Sess')
        fprintf('  %s  @ sample %d  (%.1f sec)\n', ...
            EEG_all.event(i).type, round(EEG_all.event(i).latency), ...
            EEG_all.event(i).latency / EEG_all.srate);
    end
end

fprintf('\nDone!\n');
