"""The injection models, one stream each. Every module has the same interface:

    NAME     config block of the scenario and name of the stream (CSV columns <node>:<NAME>_kw, optionally _kvar);
             not import / export / plmax / pg, whose _kw columns the screening already uses
    SIGN     'load' (consumption positive) or 'generation' (production positive)
    allocate(nodes, sfoe, cfg) -> dict
             adds the model's per-node columns to the allocation in place (nodes without a fuse rating are
             dropped afterwards) and returns its regional totals for scenario.json
    prepare(cfg, step_min) -> state
             once per run: read data, check settings
    series(state, rows, days, net_num) -> {column: array}
             the network's per-node series, [nodes x len(days) x steps per day] per column (e.g. "ev_kw"),
             3-phase kW / kvar in the model's sign; `days` are day-of-year indices of the PV calendar,
             `net_num` (with the model's seed_offset) seeds any random draw

A scenario uses the models whose block is in its config.json, in the order of
MODELS (demand and pv are required: pv defines the calendar and the day of the
daily product). Adding one (e.g. heat): write models/heat.py with this
interface, append it to MODELS and add its block to scenario_defaults in
config.json; the screening reads the stream and its sign from scenario.json.
"""
from . import demand, ev, pv

MODELS = (demand, pv, ev)
