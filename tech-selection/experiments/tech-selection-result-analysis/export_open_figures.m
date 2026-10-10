function export_open_figures(tag, figures_dir)
% EXPORT_OPEN_FIGURES  Export every currently-open figure as PNG and TikZ.
%
%   export_open_figures(tag, figures_dir)
%
%   Inputs
%   ------
%   tag         : string   prefix for filenames, e.g. "230_Finv_LiIon"
%   figures_dir : string   optional, default
%                          results/experiments/tech-selection-result-analysis/figures/
%                          (expects png/ and tikz/ subfolders under it)
%
%   Requires matlab2tikz (https://github.com/matlab2tikz/matlab2tikz) on the
%   MATLAB path for the .tikz export -- PNG export has no such dependency.

if nargin < 2 || isempty(figures_dir)
    proj        = project_paths();
    figures_dir = fullfile(proj.results, 'experiments', 'tech-selection-result-analysis', 'figures');
end
png_dir  = fullfile(figures_dir, 'png');
tikz_dir = fullfile(figures_dir, 'tikz');
if ~exist(png_dir, 'dir');  mkdir(png_dir);  end
if ~exist(tikz_dir, 'dir'); mkdir(tikz_dir); end

have_m2t = exist('matlab2tikz', 'file') == 2;
if ~have_m2t
    warning('export_open_figures:noMatlab2tikz', ...
        'matlab2tikz not found on path -- skipping .tikz export, PNG only. Add matlab2tikz-master/src to the MATLAB path to enable it.');
end

figs = findobj('Type', 'figure');
figs = sort(figs);  % stable, by figure number

for k = 1:numel(figs)
    fh   = figs(k);
    name = get(fh, 'Name');
    if isempty(name)
        name = sprintf('fig%d', fh.Number);
    else
        name = matlab.lang.makeValidName(name);
    end
    base = sprintf('%s_%s', tag, name);

    png_path = fullfile(png_dir, [char(base) '.png']);
    exportgraphics(fh, png_path, 'Resolution', 200);

    if have_m2t
        tikz_path = fullfile(tikz_dir, [char(base) '.tex']);
        try
            matlab2tikz('filename', tikz_path, 'figurehandle', fh, ...
                'showInfo', false, 'checkForUpdates', false);
        catch ME
            % Some matlab2tikz versions/forks don't handle every HG2 object
            % type (e.g. the ConstantLine object behind yline/xline, used
            % throughout the analyze_* figures) -- don't let one figure's
            % tikz export kill PNG export + tikz export for every figure
            % after it in this loop.
            warning('export_open_figures:tikzFailed', ...
                'matlab2tikz failed for %s: %s (skipping .tex, PNG already saved)', ...
                base, ME.message);
        end
    end
end

fprintf('Exported %d figure(s) to %s (png) %s\n', numel(figs), png_dir, ...
    ternary(have_m2t, sprintf('and %s (tikz)', tikz_dir), '(tikz skipped)'));

end

function v = ternary(cond, a, b)
if cond
    v = a;
else
    v = b;
end
end
