#!/usr/bin/env python3
"""One-off: tech-selection/data/raw/pv_profiles_year.mat -> data/pv/pv_profiles_year.csv

Same content, Python-readable: 15-min timestamps of the reference year with the
normalised PV output (per unit of installed DC peak) for the ideal clear sky and
for the PVGIS typical meteorological year, plus the irradiance / temperature
reference columns. `lvgrid clearsky` writes files of the same layout.
"""
import json
import sys
from pathlib import Path

import pandas as pd
import scipy.io as sio

here = Path(__file__).resolve().parent
src = Path(sys.argv[1]) if len(sys.argv) > 1 else here.parent.parent / "tech-selection" / "data" / "raw" / "pv_profiles_year.mat"
dst = here.parent / "data" / "pv" / "pv_profiles_year.csv"
m = sio.loadmat(src, squeeze_me=True, struct_as_record=False)
cols = ["pv_norm_clearsky", "pv_norm_measured", "poa_norm_clearsky", "poa_norm_measured",
        "ghi_norm_clearsky", "ghi_norm_measured", "temp_air", "solar_zenith"]
df = pd.DataFrame({"time": m["time_iso"], **{c: m[c] for c in cols}})
meta = {k: (v.item() if hasattr(v, "item") else v) for k, v in vars(m["meta"]).items() if not k.startswith("_")}
dst.parent.mkdir(parents=True, exist_ok=True)
with open(dst, "w") as f:
    f.write("# " + json.dumps(meta, default=str) + "\n")
    df.to_csv(f, index=False, float_format="%.6g")
print(f"{len(df)} rows -> {dst}")
