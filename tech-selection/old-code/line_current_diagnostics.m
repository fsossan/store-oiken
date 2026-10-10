% run_line_current_diagnostics.m
% Assumes in workspace: Imag0, CABLE_AMP, T, L, net_id

% --- Reshape Imag0 from (L*T) to (L x T) ---
Imag0_mat = reshape(abs(Imag0), L, T);

% --- Normalise by rating ---
util_mat = Imag0_mat ./ repmat(CABLE_AMP, 1, T);  % L x T, in pu of rating

% --- Per-line stats ---
util_max  = max(util_mat, [], 2);   % L x 1
util_mean = mean(util_mat, 2);

% --- Summary ---
n_vio = sum(util_max > 1);
fprintf('\n===== Line Current Diagnostics: %s =====\n', net_id);
fprintf('Lines                  : %d\n', L);
fprintf('Timesteps              : %d\n', T);
fprintf('Lines violating (>1pu) : %d / %d (%.1f%%)\n', n_vio, L, 100*n_vio/L);
fprintf('Max utilisation        : %.4f pu\n', max(util_max));
fprintf('Mean utilisation       : %.4f pu\n', mean(util_mean));
fprintf('\nCABLE_AMP  min=%.4f  max=%.4f  median=%.4f pu\n', ...
    min(CABLE_AMP), max(CABLE_AMP), median(CABLE_AMP));
fprintf('Imag0(abs) min=%.4f  max=%.4f  median=%.4f pu\n', ...
    min(Imag0_mat(:)), max(Imag0_mat(:)), median(Imag0_mat(:)));

% --- Lines already violated at operating point ---
vio_lines = find(util_max > 1);
if ~isempty(vio_lines)
    fprintf('\nViolating lines (index, CABLE_AMP pu, max_util):\n');
    for k = 1:numel(vio_lines)
        fprintf('  Line %3d  rating=%.4f pu  max_util=%.4f pu\n', ...
            vio_lines(k), CABLE_AMP(vio_lines(k)), util_max(vio_lines(k)));
    end
end

% --- Figure 1: utilisation heatmap ---
figure;
imagesc(util_mat);
colorbar;
clim([0 max(1.1, max(util_mat(:)))]);
xlabel('Timestep'); ylabel('Line index');
title(sprintf('Line utilisation (pu of rating) — %s', net_id), 'Interpreter', 'none');
yline(0.5, 'w--');  % placeholder
hold on;
% Mark violating lines
for k = 1:numel(vio_lines)
    yline(vio_lines(k), 'r-', 'LineWidth', 1);
end
hold off;

% --- Figure 2: max utilisation per line ---
figure;
bar(util_max);
yline(1.0, 'r--', 'LineWidth', 1.5);
xlabel('Line index'); ylabel('Max utilisation (pu of rating)');
title(sprintf('Per-line max utilisation — %s', net_id), 'Interpreter', 'none');
grid on;

% --- Figure 3: CABLE_AMP distribution ---
figure;
histogram(CABLE_AMP, 20, 'FaceColor', [0.4 0.6 0.9]);
xlabel('Ampacity (pu)'); ylabel('Count');
title('CABLE\_AMP distribution', 'Interpreter', 'none');
grid on;
xline(median(CABLE_AMP), 'r--', 'LineWidth', 1.5);