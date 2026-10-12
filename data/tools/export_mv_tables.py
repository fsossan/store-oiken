#!/usr/bin/env python3
"""One-off: the MV-level sheets of the OIKEN Excel export -> data/mv/*.csv  (run: python data/tools/export_mv_tables.py)

    mv_lines.csv          2_MV Grid_*.xlsx   one row per MV line, column mv_grid = sheet id
    mv_stations.csv       4_MV Stations_*.xlsx  switches/busbars of MV switching stations, column station = sheet id
    hvmv_substations.csv  5_HV-MV Substations_*.xlsx  HV/MV transformers (65/16 kV) and their switchgear, column hvmv = sheet id

Node names follow the LV export (N_<id>, N_SWM_<id> MV switch, N_JbM_ MV busbar,
N_TrM_/N_TrH_ transformer MV/HV node, N_JbH_/N_SWH_ HV busbar/switch).
"""
import re
import sys
import warnings
from pathlib import Path

import pandas as pd

warnings.filterwarnings("ignore")
here = Path(__file__).resolve().parent
src = Path(sys.argv[1]) if len(sys.argv) > 1 else here.parent.parent / "obsolete" / "sanity_check" / "network_data" / "excel_data"
out = here.parent / "mv"
out.mkdir(parents=True, exist_ok=True)

LINE_COLS = {"From": "from", "To": "to", "Line": "line", "Length(m)": "length_m", "R(Ohm/km)": "r_ohm_km", "X(Ohm/km)": "x_ohm_km",
             "Ampacity (A)": "ampacity_a", "PLmax(kW)": "plmax_kw", "QLmax(kVar)": "qlmax_kvar", "Pg(kW)": "pg_kw",
             "Section(mm2)": "section_mm2", "Cu/Al": "material", "Cable/Line": "kind"}
SUB_COLS = {"From": "from", "To": "to", "Object": "object", "On\\Off state": "on_off", "R(p.u)": "r_pu", "X(p.u)": "x_pu",
            "Rated power (kVA)": "rated_kva", "From: voltage (kV)": "from_kv", "To: voltage (kV)": "to_kv"}


def read_book(pattern: str, key: str, cols: dict) -> pd.DataFrame:
    frames = []
    for city in ("Sion", "Sierre"):
        files = list((src / city).glob(pattern))
        if not files:
            raise FileNotFoundError(f"{pattern} not found in {src / city}")
        xl = pd.ExcelFile(files[0])
        for sheet in xl.sheet_names:
            df = xl.parse(sheet, dtype={"From": str, "To": str, "Object": str}).rename(columns=cols)
            df.insert(0, key, re.search(r"\d+", sheet).group())
            df.insert(1, "city", city)
            frames.append(df)
    return pd.concat(frames, ignore_index=True)


lines = read_book("2_MV Grid_*.xlsx", "mv_grid", LINE_COLS)
stations = read_book("4_MV Stations_*.xlsx", "station", SUB_COLS)
hvmv = read_book("5_HV-MV Substations_*.xlsx", "hvmv", SUB_COLS)
lines.to_csv(out / "mv_lines.csv", index=False)
stations.to_csv(out / "mv_stations.csv", index=False)
hvmv.to_csv(out / "hvmv_substations.csv", index=False)
print(f"{lines.mv_grid.nunique()} MV grids / {len(lines)} lines, {stations.station.nunique()} MV stations / {len(stations)} rows, "
      f"{hvmv.hvmv.nunique()} HV/MV substations / {len(hvmv)} rows -> {out}")
