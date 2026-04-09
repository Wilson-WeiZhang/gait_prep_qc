function data_rand = phase_randomize_surrogate(data)
%% phase_randomize_surrogate — Phase randomization surrogate
%
% FFT -> random phase (same shift across channels to preserve spatial
% structure) -> IFFT. Preserves power spectrum, destroys phase relationships.
%
% Input:
%   data      — [n_ch x T] single trial
%
% Output:
%   data_rand — [n_ch x T] phase-randomized

[n_ch, T] = size(data);

% FFT along time dimension
X = fft(data, [], 2);

% Determine independent frequency bins
if mod(T, 2) == 0
    % Even: bins 2 to T/2 are independent complex, bin T/2+1 is Nyquist (real)
    pos_bins = 2 : T/2;
    neg_bins = T : -1 : T/2 + 2;
else
    % Odd: bins 2 to (T+1)/2 are independent complex
    pos_bins = 2 : (T+1)/2;
    neg_bins = T : -1 : (T+1)/2 + 1;
end

% Random phase (same for all channels)
n_indep = length(pos_bins);
rand_phase = exp(1i * 2 * pi * rand(1, n_indep));

% Apply to positive frequencies
X(:, pos_bins) = X(:, pos_bins) .* repmat(rand_phase, n_ch, 1);

% Mirror to negative frequencies (conjugate symmetry)
X(:, neg_bins) = conj(X(:, pos_bins));

% IFFT
data_rand = real(ifft(X, [], 2));
end
