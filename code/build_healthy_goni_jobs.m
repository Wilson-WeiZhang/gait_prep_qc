function jobs = build_healthy_goni_jobs(raw_base)
%% build_healthy_goni_jobs — Auto-discover all healthy EEG+Goni session pairs
%
% Scans raw_data/SUB_* for EEG .vhdr + Goni .txt files.
% EEG and Goni may be in different sub-directories under the same session prefix.
% Groups multi-file sessions (same SUB+sess prefix) as multi-segment.
%
% Input:
%   raw_base - path to raw_data/ directory (e.g., '/home/wilson/gait/raw_data')
%
% Output:
%   jobs - struct array, each with:
%     .label      - 'SUB_XX_sessNN'
%     .segments   - struct array: .eeg_vhdr, .goni_txt, .dir_name
%     .n_segments - number of segments (1 = single-file, 2+ = multi-file)

subs = dir(fullfile(raw_base, 'SUB_*'));
subs = subs([subs.isdir]);
jobs = struct('label', {}, 'segments', {}, 'n_segments', {});

for s = 1:length(subs)
    sub_name = subs(s).name;
    sub_dir = fullfile(raw_base, sub_name);
    sub_num = str2double(regexp(sub_name, '\d+', 'match', 'once'));

    sess_dirs = dir(sub_dir);
    sess_dirs = sess_dirs([sess_dirs.isdir] & ~ismember({sess_dirs.name}, {'.','..'}));
    if isempty(sess_dirs), continue; end

    % Collect all EEG files and all Goni files separately, grouped by session key
    eeg_map = containers.Map();   % sess_key -> {vhdr_paths, dir_names}
    goni_map = containers.Map();  % sess_key -> {goni_paths, dir_names}

    for d = 1:length(sess_dirs)
        dname = sess_dirs(d).name;
        tok = regexp(dname, '^(sess\d+)', 'tokens');
        if isempty(tok), continue; end
        sess_key = tok{1}{1};
        full_dir = fullfile(sub_dir, dname);

        % Collect EEG files
        vhdrs = dir(fullfile(full_dir, 'EEG', '*.vhdr'));
        for v = 1:length(vhdrs)
            entry.path = fullfile(vhdrs(v).folder, vhdrs(v).name);
            entry.dir_name = dname;
            if ~eeg_map.isKey(sess_key)
                eeg_map(sess_key) = entry;
            else
                existing = eeg_map(sess_key);
                % Dedup by filename
                [~, new_fn] = fileparts(entry.path);
                is_dup = false;
                for ex = 1:length(existing)
                    [~, ex_fn] = fileparts(existing(ex).path);
                    if strcmp(new_fn, ex_fn), is_dup = true; break; end
                end
                if ~is_dup
                    existing(end+1) = entry; %#ok<AGROW>
                    eeg_map(sess_key) = existing;
                end
            end
        end

        % Collect Goni files (prefer *enggunit*, fallback to *.txt)
        gonis = dir(fullfile(full_dir, 'Goniometer', '*enggunit*'));
        if isempty(gonis)
            gonis = dir(fullfile(full_dir, 'Goniometer', '*.txt'));
        end
        % Exclude .log files that might match *.txt pattern
        if ~isempty(gonis)
            keep = ~endsWith({gonis.name}, '.log') & ~endsWith({gonis.name}, '.cnt');
            gonis = gonis(keep);
        end
        for g = 1:length(gonis)
            entry.path = fullfile(gonis(g).folder, gonis(g).name);
            entry.dir_name = dname;
            if ~goni_map.isKey(sess_key)
                goni_map(sess_key) = entry;
            else
                existing = goni_map(sess_key);
                [~, new_fn] = fileparts(entry.path);
                is_dup = false;
                for ex = 1:length(existing)
                    [~, ex_fn] = fileparts(existing(ex).path);
                    if strcmp(new_fn, ex_fn), is_dup = true; break; end
                end
                if ~is_dup
                    existing(end+1) = entry; %#ok<AGROW>
                    goni_map(sess_key) = existing;
                end
            end
        end
    end

    % Build jobs: pair EEG and Goni by session key
    all_keys = unique([eeg_map.keys(), goni_map.keys()]);
    for k = 1:length(all_keys)
        sk = all_keys{k};
        if ~eeg_map.isKey(sk) || ~goni_map.isKey(sk)
            continue;  % Need both EEG and Goni
        end

        eegs = eeg_map(sk);
        gonis_list = goni_map(sk);

        % Pair EEG and Goni: each EEG file pairs with one Goni file
        % For single-file sessions: 1 EEG + 1 Goni
        % For multi-file: N EEG + N Goni (matched by order)
        n_segs = max(length(eegs), length(gonis_list));
        segs = struct('eeg_vhdr', {}, 'goni_txt', {}, 'dir_name', {});

        for si = 1:n_segs
            ei = min(si, length(eegs));
            gi = min(si, length(gonis_list));
            seg.eeg_vhdr = eegs(ei).path;
            seg.goni_txt = gonis_list(gi).path;
            seg.dir_name = eegs(ei).dir_name;
            segs(si) = seg;
        end

        % Sort segments by dir_name
        [~, sort_idx] = sort({segs.dir_name});
        segs = segs(sort_idx);

        job.label = sprintf('SUB_%02d_%s', sub_num, sk);
        job.segments = segs;
        job.n_segments = length(segs);

        if isempty(jobs)
            jobs = job;
        else
            jobs(end+1) = job; %#ok<AGROW>
        end
    end
end

n_single = sum([jobs.n_segments] == 1);
n_multi = sum([jobs.n_segments] > 1);
fprintf('Built %d jobs (%d single-file, %d multi-file)\n', length(jobs), n_single, n_multi);
end
