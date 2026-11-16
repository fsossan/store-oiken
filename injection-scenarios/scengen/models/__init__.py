"""The injection models, one stream each. Every module has the same interface:

    NAME      config block of the scenario and name of the stream (CSV columns <node>:<NAME>_kw, optionally _kvar);
              not import / export / plmax / pg, whose _kw columns the screening already uses
    SIGN      'load' (consumption positive) or 'generation' (production positive)
    REQUIRED, OPTIONAL   the keys of the model's config block (anything else is rejected as a typo)
    NATIONAL  the national figures (keys of the scenario's `sfoe` block) the model scales to the region
    allocate(connections, cfg, national) -> dict
              adds the model's column to the allocation in place, one value per connection (nominal_demand_kw,
              pv_kwp, ev_count), and returns its totals for scenario.json; `national.to_region(key)` is a national
              figure scaled to the region by `sfoe.to_region`; `common.split` splits a total over the connections
              by the model's `split`
    prepare(cfg, step_min) -> state
              once per run: read data, check settings; the state is a small dataclass of the module
    series(state, connections, days, net_num) -> {column: array}
              one network's series per connection, [connections x len(days) x steps per day] per column (e.g.
              "ev_kw"), 3-phase kW / kvar in the model's sign; `connections` are the network's rows of the
              allocation, `days` day-of-year indices of the calendar, `net_num` (with the model's seed_offset)
              seeds any random draw
    expected(state, rows, days, samples) -> {column: array}
              level nl4: what `series` summed over many connections converges to, [rows x len(days) x steps per
              day]; each row is a sum of connections (the allocation summed per HV/MV substation, same columns);
              `samples` is the Monte Carlo size of any expectation that has no closed form

A scenario uses the models whose block is in its config.json, in the order of
MODELS (demand and pv are required: the PV profile file gives the year and the
day of the daily product). Adding one (e.g. heat): write models/heat.py with this
interface, append it to MODELS and add its block to scenario_defaults in
config.json; the screening reads the stream and its sign from scenario.json.
"""
from . import demand, ev, pv

MODELS = (demand, pv, ev)
