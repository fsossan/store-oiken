"""The rule and the sanity check behind `demand_factor`, computed for prepared injections.

The reasoning is in README.md ("Where demand_factor comes from") and demand_factor.ipynb; the parameters are the
`demand_factor_basis` block of config.json. Nothing here feeds the generator.

    rule          the networks of about the median size should peak, over the year, near the DSO planning value
                  (`planning_peak`, as a share of their fuse-rated power)
    sanity check  the yearly energy of all connections should lie between two bounds taken from Swiss consumption
                  prorated to the region by population: the households' share of it and the households' + services'
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .injections import Injections


def energy_bounds(basis: dict, population_share: float) -> tuple[float, float, float]:
    """(region, households, households + services) in GWh/yr: Swiss consumption prorated to the region by population,
    and the part of it taken by households (lower bound) and by households and services (upper bound)."""
    region = basis["ch_consumption_twh"] * 1e3 * population_share
    return region, region * basis["share_households"], region * (basis["share_households"] + basis["share_services"])


@dataclass(frozen=True)
class DemandCheck:
    demand_factor: float
    planning_peak: float                # the DSO planning value, share of the fuse-rated power
    median_size: int                    # connections of the median network
    n_networks: int                     # networks of about that size, used for the peak and the energy per kW
    peak: float                         # their yearly peak as a share of their fuse-rated power (median)
    energy_gwh: float                   # all connections, per year
    region_gwh: float                   # Swiss consumption prorated to the region, all sectors
    households_gwh: float               # lower bound
    households_services_gwh: float      # upper bound
    basis: dict
    population_share: float

    @property
    def plausible(self) -> bool:
        return self.households_gwh <= self.energy_gwh <= self.households_services_gwh

    def __str__(self) -> str:
        b = self.basis
        both = b["share_households"] + b["share_services"]
        return "\n".join([
            f"demand_factor {self.demand_factor}",
            f"rule          the {self.n_networks} networks of {self.median_size - 1} to {self.median_size + 1} connections peak at "
            f"{self.peak:.1%} of their fuse-rated power over the year (median); DSO planning value {self.planning_peak:.0%}",
            f"sanity check  all connections use {self.energy_gwh:,.0f} GWh/yr. Swiss consumption ({b['ch_consumption_twh']:g} TWh) x "
            f"the region's population share ({self.population_share:.2%}) = {self.region_gwh:,.0f} GWh/yr, of which",
            f"              households ({b['share_households']:.0%}) {self.households_gwh:,.0f} GWh  and  households + services "
            f"({both:.0%}) {self.households_services_gwh:,.0f} GWh: {self.energy_gwh:,.0f} GWh is "
            + ("between the two bounds" if self.plausible else "OUTSIDE the two bounds")])


def demand_check(inj: Injections, basis: dict) -> DemandCheck:
    """From a year of household demand of the networks within one connection of the median size (a few seconds)."""
    size = inj.grid.networks["connections"]
    median = int(size.median())
    typical = [nid for nid in inj.ids if abs(size[nid] - median) <= 1]
    peaks, kwh, nominal_kw = [], 0.0, 0.0
    for nid in typical:
        demand = inj.series(nid, inj.calendar.year)["demand_kw"]            # [connections x days of the year x steps]
        connections = inj.network(nid)
        peaks.append(demand.sum(axis=0).max() / connections["plmax_kw"].sum())
        kwh += demand.sum() * inj.calendar.step_min / 60
        nominal_kw += connections["nominal_demand_kw"].sum()
    energy = inj.allocation["nominal_demand_kw"].sum() * (kwh / nominal_kw) / 1e6    # energies add up: kW x hours at nominal demand
    share = inj.totals["population_ratio"]
    return DemandCheck(inj.scenario["demand"]["demand_factor"], basis["planning_peak"], median, len(typical), float(np.median(peaks)),
                       energy, *energy_bounds(basis, share), basis, share)
