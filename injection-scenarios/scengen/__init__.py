"""scengen: scenario generation for the OIKEN LV portfolio.

A scenario configuration (scenarios/<name>/config.json) plus the grid tables
(../data/lv_grids) become per-node injection time series (output/<name>/).

config     paths and the global settings (scenario defaults, SFOE table, demand-model fit)
data       the grid portfolio tables and node ratings
models     one module per stream (demand, pv, ev) with a common interface: allocation, preparation, series
generate   runs the models over the networks and writes the daily / yearly injection files
dashboard  Dash app on the demand of the generated scenarios
clearsky   clear-sky PV profile generator (pvlib)
"""
__version__ = "0.3.0"
