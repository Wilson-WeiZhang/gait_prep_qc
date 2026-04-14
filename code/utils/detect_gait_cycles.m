function [cycle_starts, f_gait] = detect_gait_cycles(goni_signal, srate)
%% detect_gait_cycles — Find gait cycle boundaries from knee angle
%
% Detects gait cycles using peak detection on knee flexion angle.
% Also estimates dominant gait frequency from PSD.
%
% Input:
%   goni_signal — [1 x T] knee angle signal (e.g., LKneW X)
%   srate       — sample rate (Hz)
%
% Output:
%   cycle_starts — sample indices of gait cycle onsets (flexion peaks)
%   f_gait       — dominant gait frequency (Hz)

goni_signal = goni_signal(:)';
T = length(goni_signal);

%% Estimate gait frequency from PSD
nfft = min(2^nextpow2(T), 2048);
[pxx, f] = pwelch(goni_signal, hanning(nfft), round(nfft/2), nfft, srate);

% Find peak in gait range (0.5-2.5 Hz)
gait_range = f >= 0.5 & f <= 2.5;
f_gait_range = f(gait_range);
pxx_range    = pxx(gait_range);
[~, pk_idx]  = max(pxx_range);
f_gait = f_gait_range(pk_idx);

%% Find cycle boundaries via peak detection
min_dist = round(0.6 / f_gait * srate);  % minimum 60% of expected period
[~, cycle_starts] = findpeaks(goni_signal, 'MinPeakDistance', min_dist);

% If signal is inverted (troughs = cycle starts), try negative
if length(cycle_starts) < 2
    [~, cycle_starts] = findpeaks(-goni_signal, 'MinPeakDistance', min_dist);
end

end
