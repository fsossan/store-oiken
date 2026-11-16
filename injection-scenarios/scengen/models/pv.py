"""PV (stream `pv`, generation): SFOE capacity scaled to the region (sfoe.to_region) and split over the connections
(pv.split, models/common.SPLITS: by fuse-rated power or equally), times the normalised yearly profile (../data/pv/,
pvlib, Sion, 35 deg south; per unit of installed DC peak).

The PV profile file also defines the year and the representative day of the
daily product (the real day closest to the season's mean shape): `prepare`
returns them as a PVYear, from which injections.make_calendar builds the calendar."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd

from ..config import resolve
from .common import National, season_mask, split

NAME, SIGN = "pv", "generation"
REQUIRED, OPTIONAL, NATIONAL = ("split", "file", "series", "season"), ("scale",), ("PV_national_MW",)


def load_pv_year(path: Path) -> pd.DataFrame:
    """The yearly PV profile CSV (a '#' JSON header line is skipped)."""
    df = pd.read_csv(path, comment="#")
    offsets = df["time"].str[-5:].unique()
    if len(offsets) != 1:
        raise ValueError(f"{path}: timestamps must share one fixed UTC offset (found {list(offsets)}); "
                         "days are cut by position, daylight-saving shifts would misalign them")
    df["time"] = pd.to_datetime(df["time"], utc=True).dt.tz_convert("Etc/GMT-1")
    return df


def pv_year_series(pv_year: pd.DataFrame, series: str, step_min: int) -> np.ndarray:
    """The normalised yearly PV series [n_days x S]."""
    S = 24 * 60 // step_min
    col = f"pv_norm_{series}"
    if col not in pv_year:
        raise KeyError(f"no column {col} in the PV profile file")
    y = pv_year[col].to_numpy(float)
    if len(y) % S:
        raise ValueError(f"PV profile has {len(y)} samples, not a whole number of {S}-step days")
    return y.reshape(-1, S)


def pv_representative_day(pv_year: pd.DataFrame, series: str, season: str, step_min: int):
    """Normalised PV of the real day closest (RMSE) to the mean shape of the season.

    Returns (profile [S], date string, day index)."""
    S = 24 * 60 // step_min
    days = pv_year_series(pv_year, series, step_min)
    k = closest_day(days, pv_year["time"].dt.month.to_numpy()[::S], season)
    date = str(pv_year["time"].iloc[k * S].date())
    return days[k], date, k


def closest_day(days: np.ndarray, months: np.ndarray, season: str) -> int:
    """Index of the day of `days` [n_days x S] closest (RMSE) to the mean shape of the season's days; `months` is the
    month of each day."""
    cand = np.flatnonzero(season_mask(months, season))
    mean_day = days[cand].mean(axis=0)
    return int(cand[np.argmin(np.sqrt(((days[cand] - mean_day) ** 2).mean(axis=1)))])


# ------------------------------------------------------------- interface ----
@dataclass(frozen=True)
class PVYear:
    """The year of the profile file and its representative day."""
    profile: np.ndarray                 # [days x steps per day], per unit of installed kWp (times `scale`)
    time: pd.Series                     # timestamp of every step of the year
    day_index: int                      # the representative day
    date: str                           # its date

    @property
    def day(self) -> np.ndarray:
        """The profile of the representative day."""
        return self.profile[self.day_index]

    @property
    def months(self) -> np.ndarray:
        """The month of each day."""
        return self.time.dt.month.to_numpy()[::self.profile.shape[1]]

    def season_day(self, season: str) -> int:
        """The representative day of another season (winter | spring | summer | autumn | all), chosen as for `day`."""
        return closest_day(self.profile, self.months, season)


def allocate(connections: pd.DataFrame, cfg: dict, national: National) -> dict:
    """pv_kwp: the national capacity scaled to the region, split over the connections by `split`."""
    total = national.to_region("PV_national_MW", 1e3)                    # kWp in the region
    connections["pv_kwp"] = split(connections, total, cfg["split"], where="pv.split")
    return {"pv_split": cfg["split"], "pv_region_kwp": total, "pv_allocated_kwp": float(connections["pv_kwp"].sum())}


def prepare(cfg: dict, step_min: int) -> PVYear:
    df = load_pv_year(resolve(cfg["file"]))
    profile = pv_year_series(df, cfg["series"], step_min) * cfg.get("scale", 1.0)
    _, date, k = pv_representative_day(df, cfg["series"], cfg["season"], step_min)
    return PVYear(profile, df["time"], k, date)


def series(state: PVYear, connections: pd.DataFrame, days: list[int], net_num: int) -> dict[str, np.ndarray]:
    return {"pv_kw": state.profile[days][None, :, :] * connections["pv_kwp"].to_numpy()[:, None, None]}


def expected(state: PVYear, rows: pd.DataFrame, days: list[int], samples: int) -> dict[str, np.ndarray]:
    """Level nl4: PV is linear in kWp with one profile for every connection, so a row's series (its summed kWp) is
    exactly the sum of its connections' series. Nothing is drawn: `samples` is not used."""
    return series(state, rows, days, 0)
