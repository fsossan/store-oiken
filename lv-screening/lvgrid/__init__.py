"""lvgrid: load-flow screening of the OIKEN LV network portfolio.

Modules
-------
config      settings file + paths
data        the exported grid portfolio (CSV)
network     one network -> admittance matrix, nodal ratings, topology checks
loadflow    fixed-point AC load flow, vectorised over time steps
scenario    a generated scenario (../scenario-generation/output/<name>) as the screening sees it
injections  per-node power time series read from the scenario's daily CSV files
screening   one-shot sanity check and temporal screening over the portfolio
dashboard   HTML dashboard (plotly) from a results folder
geo         node <-> coordinates
mv          HV/MV substation feeding each network; aggregation per substation
"""
__version__ = "0.1.0"
