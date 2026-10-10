function results = test_load_profile_determinism(seed, D)
% TEST_LOAD_PROFILE_DETERMINISM  Does generate_nodal_scenarios_4 (via
%                                  generate_load_profile) reproduce the same
%                                  demand realization when called twice with
%                                  the identical seed, horizon, and params?
%
%   results = test_load_profile_determinism()
%   results = test_load_profile_determinism(seed, D)
%
%   This is a direct falsification test of the claim (docs/DEVELOPMENT_NOTES.md, and this
%   project's working assumption): "generate_nodal_scenarios_4 is NOT
%   reproducible run-to-run even under identical seeding." Four checks,
%   isolating each possible source of non-determinism separately:
%
%     A. End-to-end: generate_load_profile(..., seed) called twice, with the
%        ambient global rng reset (rng('default')) immediately before EACH
%        call. If the function were fully seed-controlled, this must match
%        exactly -- this is the "same seed, same horizon, same timestep"
%        scenario the user described.
%     B. Same as A, but WITHOUT resetting the ambient rng between calls (so
%        the two calls see different ambient rng states on entry). Exposes
%        whether the function's output depends on ambient rng state at all,
%        which it should NOT if "seed" is really controlling everything.
%     C. nodal_clusters only (the one quantity generate_nodal_scenarios_4
%        explicitly seeds deterministically via rng(network_id,'twister')
%        before randsample, see line ~111) -- expected to match under A's
%        protocol; isolates that this part of the pipeline IS seed-controlled.
%     D. fitgmdist repeatability in isolation: fit the same GMM twice on the
%        identical residual data with the ambient rng reset identically
%        before each fit. This targets the specific mechanism (EM
%        thread-level floating-point non-associativity) documented as the
%        source of non-determinism independent of any seed plumbing.
%
%   Prints PASS/FAIL per check plus max abs diff, and returns a results
%   struct with the raw comparison data for post-hoc inspection.

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);
addpath(repo_root);
proj = setup_paths();   % src/ on the path + project folder layout (proj.results, ...)

if nargin < 1 || isempty(seed); seed = 42; end
if nargin < 2 || isempty(D);    D    = 1;  end

node_power_kw = [5; 8; 12; 3; 20];   % small synthetic node set, fast + representative
params = struct();                    % all generate_load_profile defaults

fprintf('=== test_load_profile_determinism: seed=%d, D=%d ===\n\n', seed, D);

% -------------------------------------------------------------------
% A. End-to-end, ambient rng reset before each call
% -------------------------------------------------------------------
fprintf('--- A. generate_load_profile, same seed, rng(''default'') reset before each call ---\n');
rng('default');
[Xa1, ~, clustA1] = generate_load_profile(node_power_kw, D, params, seed);
rng('default');
[Xa2, ~, clustA2] = generate_load_profile(node_power_kw, D, params, seed);

diffA = max(abs(Xa1(:) - Xa2(:)));
passA = diffA == 0;
fprintf('  max|X1-X2| = %.6g  ->  %s\n\n', diffA, ternary(passA, 'PASS (identical)', 'FAIL (differs)'));

% -------------------------------------------------------------------
% B. End-to-end, ambient rng NOT reset between calls
% -------------------------------------------------------------------
fprintf('--- B. generate_load_profile, same seed, ambient rng left to drift between calls ---\n');
rng('default');
[Xb1, ~, ~] = generate_load_profile(node_power_kw, D, params, seed);
% no rng reset here -- ambient state now wherever call 1 left it
[Xb2, ~, ~] = generate_load_profile(node_power_kw, D, params, seed);

diffB = max(abs(Xb1(:) - Xb2(:)));
passB = diffB == 0;
fprintf('  max|X1-X2| = %.6g  ->  %s\n', diffB, ternary(passB, 'PASS (identical)', 'FAIL (differs)'));
fprintf('  (If A passes but B fails: the seed only controls PART of the\n');
fprintf('   pipeline, and the rest silently depends on ambient rng state.)\n\n');

% -------------------------------------------------------------------
% C. nodal_clusters only -- the explicitly seeded quantity
% -------------------------------------------------------------------
fprintf('--- C. nodal_clusters (explicitly seeded via rng(seed,''twister'')) ---\n');
passC = isequal(clustA1, clustA2);
fprintf('  nodal_clusters identical across A''s two calls -> %s\n\n', ternary(passC, 'PASS', 'FAIL'));

% -------------------------------------------------------------------
% D. fitgmdist repeatability in isolation
% -------------------------------------------------------------------
fprintf('--- D. fitgmdist repeatability on identical data, rng(''default'') reset before each fit ---\n');
rng('default');
sample_data = randn(2000, 1) * 0.3 + [zeros(1000,1); ones(1000,1)];   % 2-mode synthetic residuals
rng('default');
gm1 = fitgmdist(sample_data, 2, 'RegularizationValue', 1e-6);
rng('default');
gm2 = fitgmdist(sample_data, 2, 'RegularizationValue', 1e-6);

diffD = max(abs(sort(gm1.mu) - sort(gm2.mu)));
passD = diffD == 0;
fprintf('  max|sorted(mu1)-sorted(mu2)| = %.6g  ->  %s\n\n', diffD, ternary(passD, 'PASS (identical)', 'FAIL (differs)'));

% -------------------------------------------------------------------
% Summary
% -------------------------------------------------------------------
fprintf('=== SUMMARY ===\n');
fprintf('  A (end-to-end, seed+rng reset both controlled) : %s\n', ternary(passA, 'PASS', 'FAIL'));
fprintf('  B (end-to-end, seed controlled, ambient rng not): %s\n', ternary(passB, 'PASS', 'FAIL'));
fprintf('  C (nodal_clusters only)                         : %s\n', ternary(passC, 'PASS', 'FAIL'));
fprintf('  D (fitgmdist in isolation)                      : %s\n', ternary(passD, 'PASS', 'FAIL'));

results = struct('seed', seed, 'D', D, ...
    'diffA', diffA, 'passA', passA, ...
    'diffB', diffB, 'passB', passB, ...
    'passC', passC, ...
    'diffD', diffD, 'passD', passD);

end

function out = ternary(cond, a, b)
if cond; out = a; else; out = b; end
end
