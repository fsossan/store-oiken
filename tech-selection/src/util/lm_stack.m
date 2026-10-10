function A = lm_stack(x)
%LM_STACK  Normalise a gm.lm.* 0-order field to a [rows x T] numeric array.
%
%   A = lm_stack(x)
%
%   Accepts either:
%     - the current array format ([rows x T]) -> returned unchanged, or
%     - the legacy {1 x T} cell-of-column-vectors format (results saved
%       before the gm.lm restructure) -> concatenated with [x{:}].
%
%   Use at every gm.lm.* read site that must also open pre-restructure
%   result .mat files (the analyze_* / plot_* functions).

if iscell(x)
    A = [x{:}];
else
    A = x;
end
end
