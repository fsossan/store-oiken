"""lvgrid: stage-1 screening of the OIKEN LV network portfolio.

Modules
-------
config      settings file + paths
data        the exported grid portfolio (CSV)
network     one network -> admittance matrix, nodal ratings, topology checks
loadflow    fixed-point AC load flow, vectorised over time steps
scenario    scenario configuration -> generated injections (CSV) -> consumed by the screening
profiles    demand (GMM), PV (yearly profile, representative day) and EV shapes
injections  per-node power time series container and their CSV form
screening   one-shot sanity check and temporal screening over the portfolio
dashboard   HTML dashboard (plotly) from a results folder
geo         node <-> coordinates
mv          HV/MV substation feeding each network; aggregation per substation
clearsky    clear-sky PV profile generator (pvlib)
"""
__version__ = "0.1.0"
