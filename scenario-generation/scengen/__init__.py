"""scengen: scenario generation for the OIKEN LV portfolio.

A scenario configuration (scenarios/<name>/config.json) plus the grid tables
(../data/lv_grids) become per-node injection time series (output/<name>/).

config     paths and the global settings (scenario defaults, SFOE table, demand-model fit)
data       the grid portfolio tables and node ratings
profiles   demand model (GMM fit and sampling), yearly PV profile, EV charging
generate   allocation of PV/EV per node and the daily / yearly injection files
clearsky   clear-sky PV profile generator (pvlib)
"""
__version__ = "0.2.0"
