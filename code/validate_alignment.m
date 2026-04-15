function [n_match, match_frac, errors_ms, matched] = validate_alignment(eeg_times, goni_times, offset, label, qc_dir)
%% validate_alignment — Post-alignment validation + QC report
%
% Checks every EEG marker maps to a goni onset within tolerance.
% Also checks consecutive IOI consistency.
%
% Input:
%   eeg_times  - [1 x N] EEG marker times (seconds)
%   goni_times - [1 x M] goni stim times (seconds)
%   offset     - scalar, EEG→Goni time offset
%   label      - string, for logging/filenames
%   qc_dir     - string, directory for QC report ('' to skip file output)
%
% Output:
%   n_match    - number of matched events
%   match_frac - fraction matched
%   errors_ms  - [1 x N] alignment error in ms (NaN if unmatched)
%   matched    - [1 x N] logical, true if matched

eeg_in_goni = eeg_times(:)' + offset;
goni_times_row = goni_times(:)';
TOL = 0.25;  % 250ms (handles clock drift up to ~225ms, e.g. SUB_07_sess02)

n_eeg = length(eeg_times);
matched   = false(1, n_eeg);
errors_ms = nan(1, n_eeg);

for i = 1:n_eeg
    min_err = min(abs(goni_times_row - eeg_in_goni(i)));
    if min_err < TOL
        matched(i) = true;
        errors_ms(i) = min_err * 1000;
    end
end

n_match = sum(matched);
match_frac = n_match / n_eeg;
fprintf('  Validation: %d/%d matched (%.1f%%)\n', n_match, n_eeg, match_frac*100);
if n_match > 0
    fprintf('  Error: mean=%.1fms, max=%.1fms\n', ...
        mean(errors_ms(matched)), max(errors_ms(matched)));
end

% IOI consistency check
if n_match >= 2
    matched_idx = find(matched);
    eeg_gaps = diff(eeg_times(matched_idx));
    goni_match_t = nan(size(matched_idx));
    for k = 1:length(matched_idx)
        [~, bi] = min(abs(goni_times_row - eeg_in_goni(matched_idx(k))));
        goni_match_t(k) = goni_times_row(bi);
    end
    goni_gaps = diff(goni_match_t);
    gap_diff_ms = abs(eeg_gaps - goni_gaps) * 1000;
    bad_gaps = find(gap_diff_ms > 50);

    if isempty(bad_gaps)
        fprintf('  IOI consistency: OK (max gap diff=%.1fms)\n', max(gap_diff_ms));
    else
        fprintf('  IOI consistency: %d problematic gaps (>50ms)\n', length(bad_gaps));
    end
end

% Save QC report
if ~isempty(qc_dir) && exist(qc_dir, 'dir')
    fname = fullfile(qc_dir, sprintf('align_qc_%s.txt', label));
    fid = fopen(fname, 'w');
    fprintf(fid, 'Alignment QC: %s\n', label);
    fprintf(fid, 'Offset: %.6f sec\n', offset);
    fprintf(fid, 'EEG: %d, Goni: %d, Matched: %d/%d (%.1f%%)\n', ...
        n_eeg, length(goni_times), n_match, n_eeg, match_frac*100);
    if n_match > 0
        fprintf(fid, 'Error mean=%.3fms, max=%.3fms\n', ...
            mean(errors_ms(matched)), max(errors_ms(matched)));
    end
    fprintf(fid, '\n%5s %12s %10s %7s\n', 'idx', 'eeg_t(s)', 'err(ms)', 'match');
    for i = 1:n_eeg
        if matched(i)
            fprintf(fid, '%5d %12.3f %10.1f %7s\n', i, eeg_times(i), errors_ms(i), 'YES');
        else
            fprintf(fid, '%5d %12.3f %10s %7s\n', i, eeg_times(i), '-', 'NO');
        end
    end
    fclose(fid);
end

if match_frac < 0.9
    warning('validate_alignment:lowMatch', '%s: only %.0f%% matched', label, match_frac*100);
end
end
