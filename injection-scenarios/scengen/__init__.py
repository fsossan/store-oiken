"""scengen: scenario generation for the OIKEN LV portfolio.

National scenario figures are scaled to the region, allocated to the connections of the grid and turned into
injection time series, in four steps with one module each:

    grid       = load_grid()                  # grid.py        the LV portfolio and the region's population (../data)
    scenario   = load_scenario("sc1_2040")    # scenario.py    what is assumed (scenarios/<name>/config.json)
    injections = prepare(grid, scenario)      # injections.py  allocation, calendar and any network's series, in memory
    write(injections)                         # output.py      the files (output/<name>/<level>/)

models     one module per stream (demand, pv, ev) with a common interface: allocation, preparation, series
demand_check  the rule and the sanity check behind demand_factor, for prepared injections
config     paths and the global settings (scenario defaults, SFOE table, demand-model fit, the basis of demand_factor)
dashboard  scenario browser (Dash): every stream of the generated scenarios, per region and network, and two scenarios compared
clearsky   clear-sky PV profile generator (pvlib)
"""
__version__ = "0.5.0"
