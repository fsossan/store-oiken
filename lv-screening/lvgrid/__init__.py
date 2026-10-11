"""lvgrid: stage-1 screening of the OIKEN LV network portfolio.

Modules
-------
config      settings file + paths
data        the exported grid portfolio (CSV)
network     one network -> admittance matrix, nodal ratings, topology checks
loadflow    fixed-point AC load flow, vectorised over time steps
scenario    SFOE scenario -> frozen scenario folder (PV kWp and EV counts per node, PV day, profile settings)
profiles    demand (GMM), PV (representative day) and EV shapes
injections  per-node power time series for a scenario
screening   one-shot sanity check and temporal screening over the portfolio
dashboard   HTML dashboard (plotly) from a results folder
geo         node <-> coordinates
mv          HV/MV substation feeding each network; aggregation per substation
clearsky    clear-sky PV profile generator (pvlib)
"""
__version__ = "0.1.0"
