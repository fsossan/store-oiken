function viol = report_violations(Vmag, Imag_pu, grid, cfg, label, log_fid)
% REPORT_VIOLATIONS  Print nodal voltage and line current violations,
%                    labelled with topology node ids.
%
%   viol = report_violations(Vmag, Imag_pu, grid, cfg, label, log_fid)
%
%   Inputs
%   ------
%   Vmag    : [N x T]  nodal voltage magnitudes, pu (complex is abs'd).
%             N-space, i.e. slack excluded: row k is topology node k+1.
%   Imag_pu : [L x T]  branch currents, pu (complex phasors are abs'd).
%             Row l is line l of grid.N1N2Y.
%   grid    : struct   gm.grid (N1N2Y, ampacities [A], basecurrent [A],
%                      graph_data.node_names / tr_branch_idx)
%   cfg     : struct   uses cfg.solver.V_MIN / V_MAX (default 0.9 / 1.1)
%   label   : string   header text, e.g. "Base operating point: LV_Grid_101"
%   log_fid : file id  optional; [] or omitted prints to console only
%
%   Output
%   ------
%   viol : struct
%       .V_MIN .V_MAX .T
%       .node(k) .topo_id .name .dir ('OVER'|'UNDER') .extreme .t_extreme .steps
%       .line(k) .idx .from .to .is_trafo .I_max_A .ampacity_A .ratio .t_max .steps
%
%   A node that is OVER at some steps and UNDER at others gets one entry per
%   direction. Entries are sorted most severe first. Same inputs work for
%   the solved load flow (out.grid.V_lf / I_lf), reshaped to [N x T] / [L x T].

if nargin < 5 || isempty(label),   label = "";  end
if nargin < 6,                     log_fid = []; end

V_MIN = 0.9;  if isfield(cfg.solver, 'V_MIN'), V_MIN = cfg.solver.V_MIN; end
V_MAX = 1.1;  if isfield(cfg.solver, 'V_MAX'), V_MAX = cfg.solver.V_MAX; end

Vmag    = abs(Vmag);
I_A     = abs(Imag_pu) * grid.basecurrent;     % [L x T] amperes
amp_A   = grid.ampacities(:);                  % [L x 1] amperes
[N, T]  = size(Vmag);

have_names = isfield(grid, 'graph_data') && isfield(grid.graph_data, 'node_names');
tr_idx = [];
if isfield(grid, 'graph_data') && isfield(grid.graph_data, 'tr_branch_idx')
    tr_idx = grid.graph_data.tr_branch_idx(:);
end

viol.V_MIN = V_MIN;
viol.V_MAX = V_MAX;
viol.T     = T;

% --- nodal voltage violations ---
node = struct('topo_id', {}, 'name', {}, 'dir', {}, 'extreme', {}, ...
              't_extreme', {}, 'steps', {}, 'severity', {});
for k = 1:N
    topo_id = k + 1;    % N-space excludes the slack bus (topology node 1)
    name = "";
    if have_names, name = string(grid.graph_data.node_names(topo_id)); end

    over = find(Vmag(k,:) > V_MAX);
    if ~isempty(over)
        [vx, i] = max(Vmag(k, over));
        node(end+1) = struct('topo_id', topo_id, 'name', name, 'dir', 'OVER', ...
            'extreme', vx, 't_extreme', over(i), 'steps', over, 'severity', vx - V_MAX); %#ok<AGROW>
    end
    under = find(Vmag(k,:) < V_MIN);
    if ~isempty(under)
        [vn, i] = min(Vmag(k, under));
        node(end+1) = struct('topo_id', topo_id, 'name', name, 'dir', 'UNDER', ...
            'extreme', vn, 't_extreme', under(i), 'steps', under, 'severity', V_MIN - vn); %#ok<AGROW>
    end
end
if ~isempty(node)
    [~, ord] = sort([node.severity], 'descend');
    node = node(ord);
end
viol.node = rmfield(node, 'severity');

% --- line current violations ---
line = struct('idx', {}, 'from', {}, 'to', {}, 'is_trafo', {}, 'I_max_A', {}, ...
              'ampacity_A', {}, 'ratio', {}, 't_max', {}, 'steps', {});
for l = 1:size(I_A, 1)
    steps = find(I_A(l,:) > amp_A(l));
    if isempty(steps), continue; end
    [imax, i] = max(I_A(l, steps));
    line(end+1) = struct('idx', l, 'from', grid.N1N2Y(l,1), 'to', grid.N1N2Y(l,2), ...
        'is_trafo', ismember(l, tr_idx), 'I_max_A', imax, 'ampacity_A', amp_A(l), ...
        'ratio', imax / amp_A(l), 't_max', steps(i), 'steps', steps); %#ok<AGROW>
end
if ~isempty(line)
    [~, ord] = sort([line.ratio], 'descend');
    line = line(ord);
end
viol.line = line;

% --- print ---
out = @(varargin) print_both(log_fid, varargin{:});
out('\n=== Violations: %s (T=%d) ===\n', label, T);

if isempty(node)
    out('  Voltage: none outside [%.2f, %.2f] pu\n', V_MIN, V_MAX);
else
    out('  Voltage: %d violation(s) at %d node(s) outside [%.2f, %.2f] pu\n', ...
        numel(node), numel(unique([node.topo_id])), V_MIN, V_MAX);
    for k = 1:numel(node)
        nm = "";
        if strlength(node(k).name) > 0, nm = " (" + node(k).name + ")"; end
        if strcmp(node(k).dir, 'OVER'), what = 'max'; else, what = 'min'; end
        out('    node %4d%s : %-5s %s %.4f pu at t=%d   steps %s (%d/%d)\n', ...
            node(k).topo_id, nm, node(k).dir, what, node(k).extreme, node(k).t_extreme, ...
            fmt_ranges(node(k).steps), numel(node(k).steps), T);
    end
end

if isempty(line)
    out('  Current: no line over ampacity\n');
else
    out('  Current: %d line(s) over ampacity\n', numel(line));
    for k = 1:numel(line)
        tr = '';
        if line(k).is_trafo, tr = ' [transformer]'; end
        out('    line %4d : node %d -> node %d%s   I_max %.1f A / ampacity %.1f A (%.2fx) at t=%d   steps %s (%d/%d)\n', ...
            line(k).idx, line(k).from, line(k).to, tr, line(k).I_max_A, line(k).ampacity_A, ...
            line(k).ratio, line(k).t_max, fmt_ranges(line(k).steps), numel(line(k).steps), T);
    end
end

end

% -------------------------------------------------------------------------
function print_both(fid, varargin)
fprintf(varargin{:});
if ~isempty(fid) && fid > 0
    fprintf(fid, varargin{:});
end
end

function s = fmt_ranges(idx)
% Compress sorted step indices into "11-15, 19" form; capped so a full-year
% run doesn't print thousands of ranges.
MAX_RANGES = 6;
brk    = [0, find(diff(idx) > 1), numel(idx)];
n_rng  = numel(brk) - 1;
parts  = strings(1, min(n_rng, MAX_RANGES));
for r = 1:numel(parts)
    a = idx(brk(r) + 1);  b = idx(brk(r + 1));
    if a == b, parts(r) = sprintf('%d', a); else, parts(r) = sprintf('%d-%d', a, b); end
end
s = strjoin(parts, ', ');
if n_rng > MAX_RANGES
    s = s + sprintf(', ... (+%d more ranges)', n_rng - MAX_RANGES);
end
s = char(s);
end
