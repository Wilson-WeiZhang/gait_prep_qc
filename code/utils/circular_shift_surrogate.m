function data_shifted = circular_shift_surrogate(data, srate, min_shift_sec)
%% circular_shift_surrogate — Circular time-shift surrogate
%
% Applies a random circular shift to each trial independently.
% Preserves autocorrelation structure, destroys phase alignment with goni.
%
% Input:
%   data           — [n_ch x T] or {1 x n_trials} cell of [n_ch x T]
%   srate          — sample rate (Hz)
%   min_shift_sec  — minimum shift in seconds (default: 0.5)
%
% Output:
%   data_shifted   — same format as input, circularly shifted

if nargin < 3, min_shift_sec = 0.5; end
min_shift = round(min_shift_sec * srate);

if iscell(data)
    data_shifted = cell(size(data));
    for t = 1:length(data)
        T = size(data{t}, 2);
        max_shift = T - min_shift;
        if max_shift <= min_shift
            shift = randi(T);
        else
            shift = randi([min_shift, max_shift]);
        end
        data_shifted{t} = circshift(data{t}, [0, shift]);
    end
else
    T = size(data, 2);
    max_shift = T - min_shift;
    if max_shift <= min_shift
        shift = randi(T);
    else
        shift = randi([min_shift, max_shift]);
    end
    data_shifted = circshift(data, [0, shift]);
end
end
