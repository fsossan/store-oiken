"""The injections: a scenario applied to a grid, in memory.

    grid       = load_grid()                  # grid.py: connections, networks, population
    scenario   = load_scenario("sc1_2040")    # scenario.py: national figures, time, model settings
    injections = prepare(grid, scenario)      # here: who gets what, when; nothing is written
    write(injections)                         # output.py: output/<name>/<level>/

`prepare` does three things. The allocation: each model (models/, one stream each) adds its column per connection
(nominal demand, PV kWp, EVs): national figures scaled to the region by `sfoe.to_region`, then split over the
connections by the model's `split`. The calendar: the year and the day(s) of the daily product. The model states:
data read and settings checked once. Any network's series are then computed on request (`series`, `network_sums`;
the whole portfolio's daily product in under a second), which is what scenario.ipynb previews and what `write`
writes. The daily product is the yearly series on the representative PV day, so the two products are consistent and
a day does not change with the horizon; seeds are per (network, day).
"""
from __future__ import annotations

import copy
from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from .grid import Grid, network_number
from .models.common import National
from .models.pv import PVYear
from .scenario import active_models, check_scenario


# -------------------------------------------------------------- calendar --
@dataclass(frozen=True)
class Calendar:
    """The time axis. The PV profile file gives the year (its timestamps, cut in days by position) and the
    representative day; days are day-of-year indices into it."""
    step_min: int
    time: pd.Series                     # timestamp of every step of the year
    days: list[int]                     # the daily product: the representative PV day, then the days after it
    date: str                           # date of the representative day
    yearly_step_min: int | None         # step of the yearly files; None: no yearly files

    def __post_init__(self):
        y = self.yearly_step_min
        if y is not None and (y < self.step_min or y % self.step_min or self.steps % (y // self.step_min)):
            raise ValueError("yearly.step_min must be a multiple of time.step_min that divides the day")

    @property
    def steps(self) -> int:
        """Steps per day."""
        return 24 * 60 // self.step_min

    @property
    def year(self) -> list[int]:
        """Every day of the year."""
        return list(range(len(self.time) // self.steps))

    @property
    def hours(self) -> np.ndarray:
        """Hour of each step of the daily product."""
        return np.arange(len(self.days) * self.steps) * self.step_min / 60.0

    @property
    def yearly_factor(self) -> int:
        """Steps averaged into one step of the yearly files."""
        return self.yearly_step_min // self.step_min

    @property
    def yearly_time(self) -> np.ndarray:
        """Timestamp of each step of the yearly files."""
        return self.time.to_numpy()[::self.yearly_factor]


def make_calendar(time: dict, pv: PVYear, step_min: int) -> Calendar:
    """From the `time` block of the scenario and the year of the PV profile file."""
    n_days = len(pv.profile)
    days = [(pv.day_index + i) % n_days for i in range(int(time.get("days", 1)))]
    yearly = time.get("yearly", {})
    return Calendar(step_min, pv.time, days, pv.date, int(yearly.get("step_min", step_min)) if yearly.get("enabled") else None)


# ------------------------------------------------------------ allocation --
TO_REGION = ("population",)        # values of sfoe.to_region


def region_share(grid: Grid, sfoe: dict) -> float:
    """The region's share of the national figures, by `sfoe.to_region`. 'population': the region's residents in the
    scenario year / the national population."""
    if sfoe["to_region"] == "population":
        return grid.population_share(sfoe["year"], sfoe["population_national"])
    raise ValueError(f"sfoe.to_region: unknown '{sfoe['to_region']}'; known: {', '.join(TO_REGION)}")


def allocate(grid: Grid, scenario: dict) -> tuple[pd.DataFrame, dict]:
    """Per connection of the grid, the column of each active model (nominal_demand_kw, pv_kwp, ev_count, ...), and the
    regional totals. National figures are scaled to the region by `sfoe.to_region` (region_share), then each model
    splits its regional total over the connections by its own `split` (models/common.SPLITS)."""
    sfoe = scenario["sfoe"]
    national = National(sfoe, region_share(grid, sfoe))
    connections = grid.connections.copy()
    totals = {"to_region": sfoe["to_region"], "region_share": national.share,
              "population_ratio": grid.population_share(sfoe["year"], sfoe["population_national"])}
    for m in active_models(scenario):
        totals.update(m.allocate(connections, scenario[m.NAME], national))
    return connections, totals


# ------------------------------------------------------------ injections --
@dataclass
class Injections:
    """A scenario applied to a grid: the allocation, the calendar and the model states. Nothing is written."""
    grid: Grid
    scenario: dict                      # a copy: later edits of the caller's dict do not reach it
    calendar: Calendar
    models: list                        # the active models, in MODELS order
    allocation: pd.DataFrame            # per connection: network_id, node (where it connects), plmax_kw, qlmax_kvar
                                        # + the models' columns
    totals: dict                        # regional totals of the allocation (region_share, pv_split, pv_region_kwp, ...)
    state: dict                         # model name -> what its prepare() returned (DemandState, PVYear, EVState)
    _by_network: dict[str, pd.DataFrame] = field(init=False, repr=False)

    def __post_init__(self):
        self._by_network = dict(tuple(self.allocation.groupby("network_id", sort=False)))

    @property
    def name(self) -> str:
        return self.scenario["name"]

    @property
    def ids(self) -> list[str]:
        """The networks, in grid order."""
        return list(self._by_network)

    def network(self, nid: str) -> pd.DataFrame:
        """The connections of one network: its rows of `allocation`."""
        if nid not in self._by_network:
            raise KeyError(f"{nid}: unknown network, or one without a fuse-rated connection")
        return self._by_network[nid]

    @property
    def streams(self) -> dict[str, str]:
        """Stream -> 'load' (consumption positive) | 'generation' (production positive), in model order."""
        return {m.NAME: m.SIGN for m in self.models}

    def series(self, nid: str, days: list[int] | None = None) -> dict[str, np.ndarray]:
        """One network's per-connection series, column (`<stream>_kw` / `_kvar`) -> [connections x days x steps], rows
        as in `network(nid)`; `days` are day-of-year indices (default: the daily product)."""
        connections = self.network(nid)
        days = self.calendar.days if days is None else [int(d) for d in days]
        out = {}
        for m in self.models:
            out.update(m.series(self.state[m.NAME], connections, days, network_number(nid)))
        return out

    def network_sums(self, ids: list[str] | None = None, days: list[int] | None = None) -> dict[str, np.ndarray]:
        """Each network's series summed over its connections, column -> [networks x days x steps], in the order of
        `ids` (default: every network, as in `self.ids`)."""
        ids = self.ids if ids is None else ids
        days = self.calendar.days if days is None else [int(d) for d in days]
        out: dict[str, np.ndarray] = {}
        for i, nid in enumerate(ids):
            for c, a in self.series(nid, days).items():
                out.setdefault(c, np.zeros((len(ids), len(days), self.calendar.steps)))[i] = a.sum(axis=0)
        return out

    def net_load(self, series: dict[str, np.ndarray]) -> tuple[np.ndarray, np.ndarray]:
        """(P [kW], Q [kvar]) of the arrays of `series` or `network_sums`: loads minus generation, so negative P is
        reverse flow; streams without a _kvar column have Q = 0."""
        sign = {name: 1 if kind == "load" else -1 for name, kind in self.streams.items()}
        p = sum(sign[c[:-3]] * a for c, a in series.items() if c.endswith("_kw"))
        q = sum((sign[c[:-5]] * a for c, a in series.items() if c.endswith("_kvar")), np.zeros_like(p))
        return p, q


def prepare(grid: Grid, scenario: dict) -> Injections:
    """Allocation, calendar and model states of a scenario (a dict; it need not be on disk) on a grid."""
    check_scenario(scenario)
    scenario = copy.deepcopy(scenario)
    models = active_models(scenario)
    step_min = int(scenario["time"]["step_min"])
    allocation, totals = allocate(grid, scenario)
    state = {m.NAME: m.prepare(scenario[m.NAME], step_min) for m in models}
    calendar = make_calendar(scenario["time"], state["pv"], step_min)
    return Injections(grid, scenario, calendar, models, allocation, totals, state)
