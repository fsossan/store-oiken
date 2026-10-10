function profiles = build_temporal_profiles(varargin)
%BUILD_TEMPORAL_PROFILES  Former name of build_nodal_injections; kept so older
%                         scripts keep working. New code should call
%                         build_nodal_injections directly.
profiles = build_nodal_injections(varargin{:});
end
