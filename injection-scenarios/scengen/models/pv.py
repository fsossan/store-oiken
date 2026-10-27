"""PV (stream `pv`, generation): SFOE capacity split over the nodes by fuse-rated power, times the normalised
yearly profile (../data/pv/, pvlib, Sion, 35 deg south; per unit of installed DC peak).

The PV profile file also defines the calendar of the yearly series and the
representative day of the daily product (the real day closest to the season's
mean shape)."""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from ..config import resolve
from .common import population_ratio, season_mask, split_by_fuse

NAME, SIGN = "pv", "generation"


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
    months = pv_year["time"].dt.month.to_numpy()[::S]
    cand = np.flatnonzero(season_mask(months, season))
    mean_day = days[cand].mean(axis=0)
    k = cand[np.argmin(np.sqrt(((days[cand] - mean_day) ** 2).mean(axis=1)))]
    date = str(pv_year["time"].iloc[k * S].date())
    return days[k], date, int(k)


# ------------------------------------------------------------- interface ----
def allocate(nodes: pd.DataFrame, sfoe: dict, cfg: dict) -> dict:
    total = sfoe["PV_national_MW"] * 1e3 * population_ratio(sfoe)
    nodes["pv_kwp"] = split_by_fuse(nodes, total)
    return {"pv_region_kwp": total, "pv_allocated_kwp": float(nodes.loc[nodes["plmax_kw"] > 0, "pv_kwp"].sum())}


def prepare(cfg: dict, step_min: int) -> dict:
    """The yearly series, its calendar and the representative day (all scaled by `scale`)."""
    df = load_pv_year(resolve(cfg["file"]))
    year = pv_year_series(df, cfg["series"], step_min) * cfg.get("scale", 1.0)                 # [n_days x S]
    day, date, k = pv_representative_day(df, cfg["series"], cfg["season"], step_min)
    # TODO: change distribution here.
    return {"year": year, "time": df["time"], "day": day * cfg.get("scale", 1.0), "date": date, "day_index": k}


def series(state: dict, rows: pd.DataFrame, days: list[int], net_num: int) -> dict[str, np.ndarray]:
    return {"pv_kw": state["year"][days][None, :, :] * rows["pv_kwp"].to_numpy()[:, None, None]}
