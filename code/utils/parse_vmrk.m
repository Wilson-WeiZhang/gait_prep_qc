function [times, nums, srate] = parse_vmrk(vhdr_file)
%PARSE_VMRK Fast EEG marker extraction from BrainVision .vhdr/.vmrk
%   No EEGLAB needed. Reads sample rate from .vhdr, markers from .vmrk.
%
%   [times, nums, srate] = parse_vmrk('path/to/file.vhdr')
%   times - [1×N] marker times in seconds
%   nums  - [1×N] marker numbers (S1→1, S10→10, etc.)
%   srate - sampling rate in Hz

[fdir, fname, ~] = fileparts(vhdr_file);

% Parse sample rate from .vhdr
vhdr_txt = fileread(vhdr_file);
srate_tok = regexp(vhdr_txt, 'SamplingInterval=(\d+)', 'tokens');
if ~isempty(srate_tok)
    srate = 1e6 / str2double(srate_tok{1}{1});
else
    srate = 1000;
    warning('parse_vmrk:noSrate', 'No SamplingInterval in %s, using 1000 Hz', vhdr_file);
end

% Parse markers from .vmrk
vmrk_file = fullfile(fdir, [fname '.vmrk']);
if ~exist(vmrk_file, 'file')
    error('parse_vmrk:noVmrk', 'Marker file not found: %s', vmrk_file);
end
vmrk_txt = fileread(vmrk_file);
toks = regexp(vmrk_txt, 'Mk\d+=Stimulus,(S\s*\d+),(\d+),', 'tokens');

times = zeros(1, length(toks));
nums = zeros(1, length(toks));
n = 0;
for i = 1:length(toks)
    num = str2double(regexprep(toks{i}{1}, '\D', ''));
    sample = str2double(toks{i}{2});
    if ~isnan(num)
        n = n + 1;
        times(n) = sample / srate;
        nums(n) = num;
    end
end
times = times(1:n);
nums = nums(1:n);
end
