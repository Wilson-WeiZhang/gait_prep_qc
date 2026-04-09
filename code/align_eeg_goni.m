function [offset, match_info] = align_eeg_goni(s10_secs, goni_stim, goni_srate, label, qc_dir)
%% align_eeg_goni - Align EEG and Goniometer using S10/Stim triggers
%
% Strategy:
%   1. Extract Stim rising edges from goni
%   2. IEI consistency check (per-event gap matching)
%      - If count mismatch by 1: resolve by finding spurious event via IEI pattern
%   3. Try simple alignment (first S10 = first Stim)
%   4. If simple fails, brute-force search all S10 candidates
%
% Inputs:
%   s10_secs   - [N x 1] S10 marker times in EEG (seconds)
%   goni_stim  - [M x 1] Goni Stim channel (raw values)
%   goni_srate - Goni sampling rate (Hz)
%   label      - (optional) string label for QC file name
%   qc_dir     - (optional) path to save correspondence table (.txt)
%
% Outputs:
%   offset     - time offset: goni_time = eeg_time + offset
%   match_info - struct with validation details

if nargin < 4, label  = 'unknown'; end
if nargin < 5, qc_dir = '';        end

%% Extract Stim rising edges (threshold > 5 to remove noise, merge within 5ms)
stim_clean = goni_stim;
stim_clean(stim_clean < 5) = 0;
stim_diff = diff([0; stim_clean]);
rising_idx = find(stim_diff > 0);

if isempty(rising_idx)
    error('No Stim rising edges found in goniometer data');
end

merged = rising_idx(1);
for r = 2:length(rising_idx)
    if rising_idx(r) - merged(end) > 5  % 5ms at 1000Hz
        merged(end+1) = rising_idx(r);
    end
end
stim_secs = (merged - 1) / goni_srate;

%% IEI consistency check — resolves ±1 count mismatch via IEI pattern matching
[s10_secs, stim_secs] = check_iei(s10_secs, stim_secs, label);

%% Try simple alignment first: first Stim = first S10
offset_simple = stim_secs(1) - s10_secs(1);
[n_match_simple, errors_simple] = count_matches(s10_secs, stim_secs, offset_simple);
frac_simple = n_match_simple / length(stim_secs);

fprintf('  Simple align (S10 #1): %d/%d matched (%.0f%%), mean_err=%.1fms\n', ...
    n_match_simple, length(stim_secs), frac_simple*100, mean(abs(errors_simple)));

%% Accept if > 80% matched
if frac_simple > 0.8
    offset = offset_simple;
    match_info.method = 'simple';
    match_info.anchor_s10 = 1;
    match_info.n_matched = n_match_simple;
    match_info.n_stim = length(stim_secs);
    match_info.match_frac = frac_simple;
    match_info.errors_ms = errors_simple;
    match_info.stim_secs = stim_secs;
    fprintf('  -> Accepted simple alignment. Offset = %.3f sec\n', offset);
    validate_matched_iei(s10_secs, stim_secs, offset, label);
    write_trigger_table(s10_secs, stim_secs, offset, label, qc_dir);
    return;
end

%% Brute force: try each S10 as anchor
fprintf('  Simple alignment failed. Brute-force searching...\n');
best_n = 0;
best_s10 = 0;
best_offset = 0;
best_errors = [];

for s = 1:length(s10_secs)
    off = stim_secs(1) - s10_secs(s);
    [n_match, errs] = count_matches(s10_secs, stim_secs, off);
    if n_match > best_n
        best_n = n_match;
        best_s10 = s;
        best_offset = off;
        best_errors = errs;
    end
end

offset = best_offset;
match_info.method = 'brute_force';
match_info.anchor_s10 = best_s10;
match_info.n_matched = best_n;
match_info.n_stim = length(stim_secs);
match_info.match_frac = best_n / length(stim_secs);
match_info.errors_ms = best_errors;
match_info.stim_secs = stim_secs;

fprintf('  -> Best: S10 #%d (%.1fs), %d/%d matched (%.0f%%), offset=%.3fs\n', ...
    best_s10, s10_secs(best_s10), best_n, length(stim_secs), ...
    match_info.match_frac*100, offset);

validate_matched_iei(s10_secs, stim_secs, offset, label);
write_trigger_table(s10_secs, stim_secs, offset, label, qc_dir);

if match_info.match_frac < 0.5
    error('align_eeg_goni: brute-force alignment failed. Best match = %d/%d (%.0f%%). EEG S10=%d, Goni stim=%d. Manual inspection required.', ...
        best_n, length(stim_secs), match_info.match_frac*100, length(s10_secs), length(stim_secs));
elseif match_info.match_frac < 0.8
    warning('align_eeg_goni: low match rate %d/%d (%.0f%%). Proceed with caution.', ...
        best_n, length(stim_secs), match_info.match_frac*100);
end
end

% =========================================================================

function [s10_out, stim_out] = check_iei(s10_secs, stim_secs, label)
%% Per-event IEI consistency check.
%  For each event, its gap to the previous and next event must match between
%  EEG S10 and Goni stim. If counts differ by exactly 1, identify and remove
%  the spurious event via IEI pattern matching.
IEI_WARN_MS  = 500;   % per-interval mismatch: WARNING  (ms)
IEI_ERR_MS   = 3000;  % per-interval mismatch: ERROR    (ms)
IEI_STD_WARN = 5.0;   % IEI std > this => irregular markers (s)

s10_secs  = sort(s10_secs(:));
stim_secs = sort(stim_secs(:));
n_s10     = length(s10_secs);
n_stim    = length(stim_secs);

if n_s10 == 0 || n_stim == 0
    error('check_iei: empty input (S10=%d, stim=%d)', n_s10, n_stim);
end

% IEI stats for each side
report_iei_stats(s10_secs,  'EEG S10  ', label, IEI_STD_WARN);
report_iei_stats(stim_secs, 'Goni stim', label, IEI_STD_WARN);

s10_out  = s10_secs;
stim_out = stim_secs;

if n_s10 == n_stim
    %% Equal counts: compare sorted IEI distributions (no positional assumption before alignment)
    if n_s10 < 2, return; end
    iei_s10_sorted  = sort(diff(s10_secs));
    iei_stim_sorted = sort(diff(stim_secs));
    diff_ms = abs(iei_s10_sorted - iei_stim_sorted) * 1000;
    max_diff_ms = max(diff_ms);
    if max_diff_ms < IEI_WARN_MS
        fprintf('  IEI distrib: OK (max sorted diff=%.0fms)\n', max_diff_ms);
    elseif max_diff_ms < IEI_ERR_MS
        fprintf('  IEI distrib: WARNING sorted IEI max diff=%.0fms (check after alignment)\n', max_diff_ms);
    else
        fprintf('  IEI distrib: MISMATCH sorted IEI max diff=%.0fms — S10 and stim may not share source\n', max_diff_ms);
    end

elseif abs(n_s10 - n_stim) >= 1
    %% Off by N: iteratively remove spurious events from the longer side
    n_diff = abs(n_s10 - n_stim);
    fprintf('  Count mismatch (S10=%d stim=%d, diff=%d). Resolving via IEI pattern...\n', n_s10, n_stim, n_diff);
    if n_s10 > n_stim
        [s10_out, n_removed] = remove_spurious_iterative(s10_secs, stim_secs, n_diff, IEI_ERR_MS, 'EEG S10', label);
    else
        [stim_out, n_removed] = remove_spurious_iterative(stim_secs, s10_secs, n_diff, IEI_ERR_MS, 'Goni stim', label);
    end
    fprintf('  After IEI removal: EEG S10=%d, Goni stim=%d\n', length(s10_out), length(stim_out));
end
end

function [out, n_removed] = remove_spurious_iterative(longer, shorter, n_target, err_thresh, tag, label)
%% Iteratively remove up to n_target spurious events from 'longer' via IEI pattern.
out = longer;
n_removed = 0;
while length(out) > length(shorter)
    [best_i, best_ms] = find_spurious_by_iei(out, shorter);
    if best_ms < err_thresh
        fprintf('  IEI removal #%d: %s event #%d (t=%.1fs) spurious (residual=%.0fms) -> removed\n', ...
            n_removed+1, tag, best_i, out(best_i), best_ms);
        out(best_i) = [];
        n_removed = n_removed + 1;
    else
        fprintf('  IEI removal: stopped at step %d — best residual=%.0fms > threshold\n', n_removed+1, best_ms);
        break;
    end
end
end

function [best_i, best_max_ms] = find_spurious_by_iei(longer, shorter)
%% Try removing each event from 'longer'; find which removal minimises
%  the max pairwise IEI difference against 'shorter'.
best_i      = 1;
best_max_ms = Inf;
n           = length(longer);
iei_short   = diff(shorter);
for i = 1:n
    candidate = longer([1:i-1, i+1:n]);
    iei_cand  = diff(candidate);
    if length(iei_cand) == length(iei_short)
        max_ms = max(abs(iei_cand - iei_short)) * 1000;
        if max_ms < best_max_ms
            best_max_ms = max_ms;
            best_i      = i;
        end
    end
end
end

function report_iei_stats(secs, tag, label, std_warn)
if length(secs) < 2, return; end
iei = diff(secs);
fprintf('  IEI %-10s mean=%.1fs  std=%.2fs  n=%d\n', tag, mean(iei), std(iei), length(secs));
if std(iei) > std_warn
    warning('align_eeg_goni [%s]: %s IEI std=%.1fs is large (irregular markers?)', label, tag, std(iei));
end
end

% =========================================================================

function validate_matched_iei(s10_secs, stim_secs, offset, label)
%% Post-alignment IEI validation on matched pairs.
%  For each consecutive matched pair, check gap in EEG ≈ gap in Goni.
IEI_WARN_MS = 500;
IEI_ERR_MS  = 3000;

s10_in_goni = s10_secs + offset;
TOL = 0.1;  % 100ms match tolerance

% Find matched pairs: (s10_idx, stim_idx)
matched_s10  = [];
matched_stim = [];
for r = 1:length(stim_secs)
    [min_err, bi] = min(abs(s10_in_goni - stim_secs(r)));
    if min_err < TOL
        matched_s10(end+1)  = bi;
        matched_stim(end+1) = r;
    end
end

if length(matched_s10) < 2, return; end

% For consecutive matched pairs, compare inter-pair gaps
eeg_gaps  = diff(s10_secs(matched_s10));   % gap between matched S10s in EEG time
goni_gaps = diff(stim_secs(matched_stim)); % gap between matched stims in Goni time
diff_ms   = abs(eeg_gaps - goni_gaps) * 1000;

bad = find(diff_ms > IEI_WARN_MS);
if isempty(bad)
    fprintf('  IEI post-align: OK (max_diff=%.0fms across %d matched pairs)\n', max(diff_ms), length(matched_s10));
else
    for k = 1:length(bad)
        i = bad(k);
        fprintf('  IEI post-align MISMATCH pair %d->%d: EEG_gap=%.2fs Goni_gap=%.2fs diff=%.0fms\n', ...
            i, i+1, eeg_gaps(i), goni_gaps(i), diff_ms(i));
    end
    if max(diff_ms) > IEI_ERR_MS
        warning('align_eeg_goni [%s]: post-alignment IEI max diff=%.1fs. Alignment may be wrong.', ...
            label, max(diff_ms)/1000);
    end
end
end

function write_trigger_table(s10_secs, stim_secs, offset, label, qc_dir)
n_s10  = length(s10_secs);
n_stim = length(stim_secs);
mismatch = (n_s10 ~= n_stim);

if mismatch
    fprintf('  [MISMATCH] EEG S10=%d, Goni stim=%d\n', n_s10, n_stim);
end

s10_in_goni = s10_secs + offset;
lines = {};
lines{end+1} = sprintf('Trigger correspondence: %s', label);
lines{end+1} = sprintf('EEG S10=%d  Goni stim=%d  offset=%.3fs  %s', ...
    n_s10, n_stim, offset, ternary(mismatch, '[MISMATCH]', '[OK]'));
lines{end+1} = sprintf('%5s  %10s  %10s  %8s  %s', ...
    'stim#', 'stim_t(s)', 'S10_t(s)', 'err(ms)', 'matched');
lines{end+1} = repmat('-', 1, 50);

for r = 1:n_stim
    t = stim_secs(r);
    [min_err, best_idx] = min(abs(s10_in_goni - t));
    err_ms = (t - s10_in_goni(best_idx)) * 1000;
    is_match = min_err < 0.1;
    if is_match
        s10_str = sprintf('%.3f', s10_secs(best_idx));
    else
        s10_str = 'NO_MATCH';
    end
    lines{end+1} = sprintf('%5d  %10.3f  %10s  %8.1f  %s', ...
        r, t, s10_str, err_ms, mat2str(is_match));
end

for i = 1:length(lines)
    fprintf('  %s\n', lines{i});
end

if ~isempty(qc_dir)
    if ~exist(qc_dir, 'dir'), mkdir(qc_dir); end
    fname = fullfile(qc_dir, sprintf('trigger_table_%s.txt', label));
    fid = fopen(fname, 'w');
    for i = 1:length(lines)
        fprintf(fid, '%s\n', lines{i});
    end
    fclose(fid);
    fprintf('  -> Saved: %s\n', fname);
end
end

function s = ternary(cond, a, b)
if cond, s = a; else, s = b; end
end

function [n_match, errors_ms] = count_matches(s10_secs, stim_secs, offset)
s10_in_goni = s10_secs + offset;
errors_ms = [];
n_match = 0;
for r = 1:length(stim_secs)
    [min_err, ~] = min(abs(s10_in_goni - stim_secs(r)));
    if min_err < 0.1  % 100ms tolerance
        n_match = n_match + 1;
        best_idx = find(abs(s10_in_goni - stim_secs(r)) == min_err, 1);
        errors_ms(end+1) = (stim_secs(r) - s10_in_goni(best_idx)) * 1000;
    end
end
end
