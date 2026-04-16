%% generate_qc_report.m — Comprehensive QC summary table (XLSX + CSV)
%
% One row per session. Discovers sessions from union of:
%   - *_step2.set in prep_data_v8/
%   - *_goni.mat in goni_healthy/
%
% Usage on aa:
%   cd ~/gait/gait_prep_qc/code
%   matlab -batch "generate_qc_report"

clear; clc;

%% Platform paths
if ismac
    eeglab_path = '/Users/zw/Desktop/eeglab-eeglab2024.2';
    eeg_dir     = '/Users/zw/Library/CloudStorage/OneDrive-Personal/gait/prep_data/healthy';
    goni_dir    = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'result', 'goni_healthy');
    out_dir     = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'result');
else  % aa server
    eeglab_path = '/home/wilson/eeglab2024';
    eeg_dir     = '/home/wilson/gait/prep_data_v8';
    goni_dir    = '/home/wilson/gait/gait_prep_qc/result/goni_healthy';
    out_dir     = '/home/wilson/gait/gait_prep_qc/result';
end

addpath(eeglab_path); eeglab nogui;

%% Hardcoded known issues
notes_map = containers.Map();
notes_map('P01_Sess03')   = 'bad REF (Cz), step2 only, EXCLUDED';
notes_map('P01_Sess04')   = 'bad REF (Cz), step2 only, EXCLUDED';
notes_map('P02_Sess01')   = 'bad REF (Cz), step2 only, EXCLUDED';
notes_map('P02_Sess02')   = 'bad REF (Cz), step2 only, EXCLUDED';
notes_map('SUB_07_sess02') = 'clock drift (2 segments)';
notes_map('SUB_19_sess02') = 'V8 QC FAIL (3-phase drift)';
notes_map('SUB_27_sess01') = 'clock drift (3 segments)';
notes_map('SUB_28_sess01') = 'low trial count';
notes_map('SUB_10_sess01') = 'goni partial alignment';
notes_map('SUB_26_sess01') = '11 frontal bad channels';

excluded_sessions = {'P01_Sess03','P01_Sess04','P02_Sess01','P02_Sess02'};

%% Discover sessions
% From step2.set
step2_files = dir(fullfile(eeg_dir, '*_step2.set'));
labels_eeg = cellfun(@(f) strrep(f, '_step2.set', ''), {step2_files.name}, 'UniformOutput', false);

% From _goni.mat
goni_files = dir(fullfile(goni_dir, '*_goni.mat'));
labels_goni = cellfun(@(f) strrep(f, '_goni.mat', ''), {goni_files.name}, 'UniformOutput', false);

% Union
all_labels = union(labels_eeg, labels_goni);
all_labels = sort(all_labels);
n_sess = length(all_labels);
fprintf('Discovered %d sessions (EEG: %d, Goni: %d, union: %d)\n', ...
    n_sess, length(labels_eeg), length(labels_goni), n_sess);

%% ICLabel class names
icl_names = {'Brain','Muscle','Eye','Heart','LineNoise','ChanNoise','Other'};

%% Build table row by row
rows = {};

for i = 1:n_sess
    label = all_labels{i};
    row = struct();
    row.Label         = label;
    row.Error_Message = '';

    try
        %% Parse label into SubjectID + Session + Type
        parts = strsplit(label, '_');
        if startsWith(label, 'SUB_')
            row.SubjectID = [parts{1} '_' parts{2}];
            row.Session   = parts{3};
            row.Type      = 'healthy';
        elseif startsWith(label, 'P0')
            row.SubjectID = parts{1};
            row.Session   = parts{2};
            row.Type      = 'patient';
        else
            row.SubjectID = label;
            row.Session   = '';
            row.Type      = 'unknown';
        end

        %% EEG status
        has_step3 = exist(fullfile(eeg_dir, [label '_step3.set']), 'file') == 2;
        has_step2 = exist(fullfile(eeg_dir, [label '_step2.set']), 'file') == 2;

        if has_step3
            row.V8_Status = 'step3';
        elseif has_step2
            row.V8_Status = 'step2';
        else
            row.V8_Status = 'none';
        end

        %% Load step2 for bad_ch, IC counts, ICLabel
        row.N_Bad_Ch      = NaN;
        row.Bad_Ch_Names  = '';
        row.N_ICs_Total   = NaN;
        icl_counts        = nan(1, 7);

        if has_step2
            EEG = pop_loadset('filename', [label '_step2.set'], 'filepath', eeg_dir);

            % Bad channels
            if isfield(EEG, 'etc') && isfield(EEG.etc, 'step2_meta') && ...
                    isfield(EEG.etc.step2_meta, 'bad_ch_labels')
                bad_ch = EEG.etc.step2_meta.bad_ch_labels;
                row.N_Bad_Ch     = length(bad_ch);
                row.Bad_Ch_Names = strjoin(bad_ch, ',');
            else
                row.N_Bad_Ch     = 0;
                row.Bad_Ch_Names = '';
            end

            % IC count
            if ~isempty(EEG.icaweights)
                row.N_ICs_Total = size(EEG.icaweights, 1);
            end

            % ICLabel on-the-fly
            try
                EEG = iclabel(EEG);
                cls = EEG.etc.ic_classification.ICLabel.classifications;  % [n_IC x 7]
                [~, max_idx] = max(cls, [], 2);
                for c = 1:7
                    icl_counts(c) = sum(max_idx == c);
                end
            catch ME_icl
                icl_counts = nan(1, 7);
                warning('ICLabel failed for %s: %s', label, ME_icl.message);
            end
        end

        row.ICL_Brain      = icl_counts(1);
        row.ICL_Muscle     = icl_counts(2);
        row.ICL_Eye        = icl_counts(3);
        row.ICL_Heart      = icl_counts(4);
        row.ICL_LineNoise  = icl_counts(5);
        row.ICL_ChanNoise  = icl_counts(6);
        row.ICL_Other      = icl_counts(7);

        %% N_ICs_Rejected from step3
        row.N_ICs_Rejected = NaN;
        if has_step3
            try
                EEG3 = pop_loadset('filename', [label '_step3.set'], 'filepath', eeg_dir);
                if isfield(EEG3, 'etc') && isfield(EEG3.etc, 'step3_meta') && ...
                        isfield(EEG3.etc.step3_meta, 'n_ics_rejected')
                    row.N_ICs_Rejected = EEG3.etc.step3_meta.n_ics_rejected;
                end
            catch
                % leave NaN
            end
        end

        %% Goni trial counts + problems
        row.Goni_N_Cond1    = NaN;
        row.Goni_N_Cond2    = NaN;
        row.Goni_N_Cond3    = NaN;
        row.Goni_N_Cond4    = NaN;
        row.Goni_N_Problems = NaN;

        goni_file = fullfile(goni_dir, [label '_goni.mat']);
        if exist(goni_file, 'file') == 2
            G = load(goni_file);

            % Trial counts by condition
            if isfield(G, 'n_imagine')
                n_mi   = G.n_imagine;
                n_walk = getFieldOrDefault(G, 'n_walk', 0);
                n_rest = getFieldOrDefault(G, 'n_rest', 0);
                n_oth  = 0;
            elseif isfield(G, 'trials')
                types  = {G.trials.type};
                n_mi   = sum(strcmp(types, 'imagine'));
                n_walk = sum(strcmp(types, 'walk'));
                n_rest = sum(strcmp(types, 'rest'));
                n_oth  = sum(~ismember(types, {'imagine','walk','rest'}));
            else
                n_mi = NaN; n_walk = NaN; n_rest = NaN; n_oth = NaN;
            end
            row.Goni_N_Cond1 = n_mi;
            row.Goni_N_Cond2 = n_walk;
            row.Goni_N_Cond3 = n_rest;
            row.Goni_N_Cond4 = n_oth;

            % Problems
            if isfield(G, 'qc') && isstruct(G.qc) && isfield(G.qc, 'status')
                row.Goni_N_Problems = sum(strcmp({G.qc.status}, 'problem'));
            elseif isfield(G, 'n_problems')
                row.Goni_N_Problems = G.n_problems;
            else
                if strcmp(row.Type, 'patient')
                    row.Goni_N_Problems = 0;  % patient QC not tracked
                else
                    row.Goni_N_Problems = 0;
                end
            end
        end

        %% Alignment info from QC txt files
        row.Align_Method     = 'N/A';
        row.Align_Match_Frac = NaN;
        row.Align_Mean_Err_ms = NaN;

        if strcmp(row.Type, 'healthy')
            row.Align_Method = 'IOI';
        elseif strcmp(row.Type, 'patient')
            row.Align_Method = 'S10_Stim';
        end

        qc_dir_path = fullfile(goni_dir, 'qc');
        qc_pattern  = fullfile(qc_dir_path, sprintf('align_qc_%s_seg*.txt', label));
        qc_files    = dir(qc_pattern);

        if ~isempty(qc_files)
            n_matched_all = 0;
            n_total_all   = 0;
            err_ms_all    = [];

            for qi = 1:length(qc_files)
                fid = fopen(fullfile(qc_dir_path, qc_files(qi).name), 'r');
                if fid < 0, continue; end

                % Skip 6 header lines
                for h = 1:6
                    fgetl(fid);
                end

                while ~feof(fid)
                    line = fgetl(fid);
                    if ~ischar(line) || isempty(strtrim(line)), continue; end
                    tokens = strsplit(strtrim(line));
                    if length(tokens) < 4, continue; end
                    % Format: idx  eeg_time  error_ms  matched(YES/NO)
                    n_total_all = n_total_all + 1;
                    matched_str = tokens{4};
                    err_val = str2double(tokens{3});
                    if strcmpi(matched_str, 'YES')
                        n_matched_all = n_matched_all + 1;
                        if ~isnan(err_val)
                            err_ms_all(end+1) = abs(err_val); %#ok<AGROW>
                        end
                    end
                end
                fclose(fid);
            end

            if n_total_all > 0
                row.Align_Match_Frac = n_matched_all / n_total_all;
            end
            if ~isempty(err_ms_all)
                row.Align_Mean_Err_ms = mean(err_ms_all);
            end
        end

        %% Notes
        if isKey(notes_map, label)
            row.Notes = notes_map(label);
        else
            row.Notes = '';
        end

        % Patient without QC: add note
        if strcmp(row.Type, 'patient') && isnan(row.Goni_N_Problems)
            if isempty(row.Notes)
                row.Notes = 'patient: goni problem count unknown';
            else
                row.Notes = [row.Notes '; patient: goni problem count unknown'];
            end
        end

        %% QC Verdict
        if ismember(label, excluded_sessions)
            row.QC_Verdict = 'EXCLUDED';
        elseif strcmp(row.V8_Status, 'none') || (~isnan(row.N_Bad_Ch) && row.N_Bad_Ch > 15)
            row.QC_Verdict = 'FAIL';
        elseif (strcmp(row.V8_Status, 'step2') && ~ismember(label, excluded_sessions)) || ...
                (~isnan(row.N_Bad_Ch) && row.N_Bad_Ch > 8) || ...
                (~isnan(row.Goni_N_Problems) && row.Goni_N_Problems > 3) || ...
                (~isnan(row.Align_Mean_Err_ms) && row.Align_Mean_Err_ms > 30)
            row.QC_Verdict = 'WARN';
        else
            row.QC_Verdict = 'PASS';
        end

    catch ME
        row.Error_Message = ME.message;
        % Fill missing fields with defaults
        default_fields = {'SubjectID','Session','Type','V8_Status','Bad_Ch_Names', ...
            'Notes','QC_Verdict','Align_Method'};
        for f = default_fields
            if ~isfield(row, f{1}), row.(f{1}) = ''; end
        end
        default_nan = {'N_Bad_Ch','N_ICs_Total','N_ICs_Rejected','ICL_Brain','ICL_Muscle', ...
            'ICL_Eye','ICL_Heart','ICL_LineNoise','ICL_ChanNoise','ICL_Other', ...
            'Goni_N_Cond1','Goni_N_Cond2','Goni_N_Cond3','Goni_N_Cond4', ...
            'Goni_N_Problems','Align_Match_Frac','Align_Mean_Err_ms'};
        for f = default_nan
            if ~isfield(row, f{1}), row.(f{1}) = NaN; end
        end
        row.QC_Verdict = 'ERROR';
        fprintf('[ERROR] %s: %s\n', label, ME.message);
    end

    rows{end+1} = row; %#ok<AGROW>
    fprintf('[%d/%d] %-20s  V8=%-6s  BadCh=%-3s  Goni=%s/%s/%s  Verdict=%s\n', ...
        i, n_sess, label, row.V8_Status, num2str(row.N_Bad_Ch), ...
        num2str(row.Goni_N_Cond1), num2str(row.Goni_N_Cond2), num2str(row.Goni_N_Cond3), ...
        row.QC_Verdict);
end

%% Assemble table
T = struct2table(vertcat(rows{:}));

%% Write output
out_xlsx = fullfile(out_dir, 'qc_report.xlsx');
out_csv  = fullfile(out_dir, 'qc_report.csv');

try
    writetable(T, out_xlsx);
    fprintf('\nSaved: %s\n', out_xlsx);
catch ME_xlsx
    fprintf('[WARN] XLSX write failed (%s), writing CSV only\n', ME_xlsx.message);
end

writetable(T, out_csv);
fprintf('Saved: %s\n', out_csv);

%% Summary
fprintf('\n=== QC Summary (%d sessions) ===\n', n_sess);
verdicts = T.QC_Verdict;
for v = {'PASS','WARN','FAIL','EXCLUDED','ERROR'}
    cnt = sum(strcmp(verdicts, v{1}));
    fprintf('  %-10s: %d\n', v{1}, cnt);
end

%% Assert expected count
expected = 49;
assert(n_sess == expected, ...
    'Session count mismatch: expected %d, found %d', expected, n_sess);
fprintf('\nAssertion PASSED: %d sessions as expected.\n', n_sess);

%% Helper
function val = getFieldOrDefault(S, fname, default)
    if isfield(S, fname)
        val = S.(fname);
    else
        val = default;
    end
end
