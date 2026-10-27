# data

Inputs shared by `../injection-scenarios` and `../lv-screening`, all in
Python-readable form. Everything here is derived from the raw sources listed
below and can be regenerated with the scripts in `tools/`.

| file | origin | regenerate with |
|---|---|---|
| `lv_grids/lines.csv`, `lv_grids/substations.csv` | `../tech-selection/data/raw/lv_grids.mat` (= the patched OIKEN export `../obsolete/sanity_check/data_v2.mat`; MATLAB tables, unreadable elsewhere) | `matlab -batch "run('data/tools/export_lv_grids.m')"` |
| `pv/pv_profiles_year.csv` | `../tech-selection/data/raw/pv_profiles_year.mat` (pvlib, 2019, Sion, 35° south; clear sky and PVGIS TMY) | `python3 injection-scenarios/tools/export_pv_profiles.py` |
| `pv/clearsky_sion_sierre_2019.csv` | `generate_scenario.py clearsky` (constant 20 °C air temperature: 5 % lower annual yield than the reference, same daily shape) | same |
| `demand_gmm.npz` | fitted from `../tech-selection/data/external/load_consumption_train_heapo.mat` (163 MB, not in git) | `python3 injection-scenarios/generate_scenario.py fit-demand` |
| `demand_train_days.csv` | calendar of the training days, for weekday/season filters of the fit | `injection-scenarios/tools/export_demand_train_days.m` |
| `geo/nodes_db.csv` | node table of the DSO database, read directly from the SQL Server backup in `../oiken-db-extraction/` (not in git) | `python3 data/tools/extract_nodes_from_bak.py <backup.bak>` |
| `geo/node_coordinates.csv`, `geo/substations.csv` | node and substation positions of the 1116 networks (LV95 and WGS84) | `python -m lvgrid geo` (in lv-screening) |
| `mv/mv_lines.csv`, `mv/mv_stations.csv`, `mv/hvmv_substations.csv` | MV sheets of the OIKEN Excel export (`../obsolete/sanity_check/network_data/excel_data/`) | `python3 data/tools/export_mv_tables.py` |
| `mv/lv_to_hvmv.csv`, `mv/hvmv.csv` | which HV/MV substation feeds each LV network | `python -m lvgrid mv-map` (in lv-screening) |

`lines.csv`: one row per LV line segment (`network_id, from, to, line,
length_m, r_ohm_km, x_ohm_km, ampacity_a, plmax_kw, qlmax_kvar, pg_kw,
section_mm2, material, kind`); `plmax`/`qlmax` are the fuse-rated peak of the
connection at the `to` node (3-phase), `pg_kw` its existing PV; parallel
branches into a node repeat its values. `substations.csv`: one row per MV/LV
substation element (`network_id, from, to, object, on_off, r_pu, x_pu,
rated_kva, from_kv, to_kv`; `T...` transformers, `SW...` switches).
