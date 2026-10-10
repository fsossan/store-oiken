"""Clear-sky PV profile for a location (pvlib).

Writes a yearly profile in the layout of data/pv/pv_profiles_year.csv:
`pv_norm_clearsky` is the DC output per unit of installed peak power of a
fixed-tilt system under an ideal clear sky (Ineichen clear-sky model, Hay-Davies
transposition, Faiman cell temperature, PVWatts DC with the given temperature
coefficient). Only the clear-sky series is produced; the `measured` series of
the reference file comes from a PVGIS typical meteorological year.

    python -m lvgrid clearsky                          # Sion/Sierre defaults, 2019
    python -m lvgrid clearsky --lat 46.29 --lon 7.53 --tilt 30 --azimuth 180 --year 2025 -o data/pv/my_site.csv
    python -m lvgrid clearsky --day 2019-06-21         # also print that day's profile
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

DEFAULTS = dict(site="sion_sierre", latitude=46.2625, longitude=7.4477, altitude=510.0, timezone="Etc/GMT-1",
                year=2019, step_min=15, tilt=35.0, azimuth=180.0, albedo=0.2, gamma_pdc=-0.004,
                temp_air=20.0, wind_speed=1.0)


def clearsky_profile(latitude: float, longitude: float, altitude: float, timezone: str, year: int, step_min: int,
                     tilt: float, azimuth: float, albedo: float = 0.2, gamma_pdc: float = -0.004,
                     temp_air: float = 20.0, wind_speed: float = 1.0) -> pd.DataFrame:
    import pvlib

    times = pd.date_range(f"{year}-01-01", f"{year + 1}-01-01", freq=f"{step_min}min", tz=timezone, inclusive="left")
    loc = pvlib.location.Location(latitude, longitude, timezone, altitude)
    pos = loc.get_solarposition(times)
    cs = loc.get_clearsky(times, model="ineichen", solar_position=pos)
    dni_extra = pvlib.irradiance.get_extra_radiation(times)
    poa = pvlib.irradiance.get_total_irradiance(tilt, azimuth, pos["apparent_zenith"], pos["azimuth"],
                                                cs["dni"], cs["ghi"], cs["dhi"], dni_extra=dni_extra,
                                                albedo=albedo, model="haydavies")
    g = poa["poa_global"].fillna(0.0).clip(lower=0.0)
    t_cell = pvlib.temperature.faiman(g, temp_air, wind_speed)
    pdc = pvlib.pvsystem.pvwatts_dc(g, t_cell, pdc0=1.0, gamma_pdc=gamma_pdc)   # per unit of peak DC power
    return pd.DataFrame({
        "time": times.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "pv_norm_clearsky": np.clip(pdc.to_numpy(), 0, 1),
        "poa_norm_clearsky": g.to_numpy() / 1000.0,
        "ghi_norm_clearsky": cs["ghi"].fillna(0.0).to_numpy() / 1000.0,
        "temp_air": float(temp_air),
        "solar_zenith": pos["apparent_zenith"].to_numpy(),
    })


def write_profile(df: pd.DataFrame, meta: dict, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w") as f:
        f.write("# " + json.dumps(meta) + "\n")
        df.to_csv(f, index=False, float_format="%.6g")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="python -m lvgrid clearsky", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lat", type=float, default=DEFAULTS["latitude"])
    ap.add_argument("--lon", type=float, default=DEFAULTS["longitude"])
    ap.add_argument("--alt", type=float, default=DEFAULTS["altitude"], help="altitude [m]")
    ap.add_argument("--tz", default=DEFAULTS["timezone"], help="fixed-offset zone, e.g. Etc/GMT-1 for CET without DST")
    ap.add_argument("--year", type=int, default=DEFAULTS["year"])
    ap.add_argument("--step-min", type=int, default=DEFAULTS["step_min"])
    ap.add_argument("--tilt", type=float, default=DEFAULTS["tilt"])
    ap.add_argument("--azimuth", type=float, default=DEFAULTS["azimuth"], help="180 = south")
    ap.add_argument("--albedo", type=float, default=DEFAULTS["albedo"])
    ap.add_argument("--gamma-pdc", type=float, default=DEFAULTS["gamma_pdc"], help="power temperature coefficient [1/K]")
    ap.add_argument("--temp-air", type=float, default=DEFAULTS["temp_air"], help="constant air temperature [degC]")
    ap.add_argument("--site", default=DEFAULTS["site"])
    ap.add_argument("-o", "--out", type=Path, default=None, help="default data/pv/clearsky_<site>_<year>.csv")
    ap.add_argument("--day", help="YYYY-MM-DD: also print that day's profile")
    a = ap.parse_args(argv)
    from .config import DATA_DIR
    out = a.out or DATA_DIR / "pv" / f"clearsky_{a.site}_{a.year}.csv"
    df = clearsky_profile(a.lat, a.lon, a.alt, a.tz, a.year, a.step_min, a.tilt, a.azimuth, a.albedo,
                          a.gamma_pdc, a.temp_air)
    meta = dict(site=a.site, latitude=a.lat, longitude=a.lon, altitude=a.alt, timezone=a.tz, reference_year=a.year,
                timestep_minutes=a.step_min, surface_tilt=a.tilt, surface_azimuth=a.azimuth, albedo=a.albedo,
                clearsky_model="ineichen", transposition_model="haydavies", celltemp_model="faiman",
                gamma_pdc=a.gamma_pdc, temp_air=a.temp_air, normalization="per-unit of installed peak DC power",
                n_steps=len(df))
    write_profile(df, meta, out)
    spd = 24 * 60 // a.step_min
    daily = df["pv_norm_clearsky"].to_numpy().reshape(-1, spd).sum(axis=1) * a.step_min / 60
    print(f"{len(df)} steps -> {out}")
    print(f"yearly yield {daily.sum():.0f} kWh/kWp, daily min {daily.min():.2f} max {daily.max():.2f} kWh/kWp, "
          f"peak {df['pv_norm_clearsky'].max():.3f} pu")
    if a.day:
        sel = df[df["time"].str.startswith(a.day)]
        print(sel[["time", "pv_norm_clearsky"]].to_string(index=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
