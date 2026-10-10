function X_pu = slice_day_contiguous_pu(X_NxSxD, horizon, basepower)
%SLICE_DAY_CONTIGUOUS_PU  Slice a native-resolution [N x S x D] profile down
%                          to `horizon` and stack day-contiguous, in pu.
%
%   X_pu = slice_day_contiguous_pu(X_NxSxD, horizon, basepower)
%
%   X_NxSxD   : [N x S x D]  native-resolution profile (node x step x day)
%   horizon   : vector       timestep indices into the native day to keep
%   basepower : scalar       grid.basepower (VA); pu = kW / (basepower/1000)
%
%   X_pu      : [numel(horizon)*D x N], DAY-CONTIGUOUS: row t runs
%               day1[h1..hH], day2[h1..hH], ... (t = h + H*(d-1)).
%
%   Shared by generate_load_profile / load_pv_profile / generate_ev_profile
%   outputs inside build_temporal_profiles, so the day-contiguous ordering
%   fix (see build_temporal_profiles header) is applied identically to all
%   three streams from one place instead of three separate implementations.

N = size(X_NxSxD, 1);
D = size(X_NxSxD, 3);
X = X_NxSxD(:, horizon, :);                    % [N x H x D]
X = reshape(X, N, numel(horizon)*D).';         % day-contiguous, see header
X_pu = X / (basepower/1000);
end
