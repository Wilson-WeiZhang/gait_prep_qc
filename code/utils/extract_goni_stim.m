function stim_times = extract_goni_stim(goni)
%EXTRACT_GONI_STIM Extract filtered stim onset times from goni struct
%   stim_times = extract_goni_stim(goni)
%   Detects rising edges in stim channel, filters spurious (IOI < 50ms).

if isempty(goni.stim)
    stim_times = [];
    return;
end

stim = goni.stim;
stim(stim < 5) = 0;
edges = find(diff([0; stim(:)]) > 0);

% Filter spurious onsets (IOI < 50ms = 50 samples at 1000Hz)
if length(edges) > 1
    keep = [true; diff(edges) >= 50];
    edges = edges(keep);
end

stim_times = (edges(:)' - 1) / goni.srate;
end
