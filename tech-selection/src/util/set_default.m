function s = set_default(s, field, value)
%SET_DEFAULT  s.(field) = value, but only if s doesn't already have a
%             non-empty value there. Used to merge a partial params struct
%             (e.g. from JSON config) with a function's built-in defaults
%             without the caller having to specify every field.
%
%   s = set_default(s, field, value)

if ~isfield(s, field) || isempty(s.(field))
    s.(field) = value;
end
end
