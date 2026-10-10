function status = check_voltage_guard(gm, cfg)
% CHECK_VOLTAGE_GUARD  Reject degenerate networks with out-of-range
%                      linearisation-point voltages.
%
%   status = check_voltage_guard(gm, cfg)
%
%   Inputs
%   ------
%   gm  : struct   linear grid model
%   cfg : struct   sizing config  (uses cfg.solver.VMAG_LB / VMAG_UB)
%
%   Output
%   ------
%   status : struct
%       .passed    logical   true = network is safe to optimise
%       .Vmag0_min scalar
%       .Vmag0_max scalar

Vmag0_all = lm_stack(gm.lm.Vmag0);     % [N x T] array (or legacy {1xT} cells)
% abs() guard: Vmag0 should already be real magnitudes, but be safe
Vmag0_all = abs(Vmag0_all(:));

vmin = min(Vmag0_all(:));
vmax = max(Vmag0_all(:));

status.Vmag0_min = vmin;
status.Vmag0_max = vmax;
status.passed    = (vmin >= cfg.solver.VMAG_LB) && (vmax <= cfg.solver.VMAG_UB);

end
