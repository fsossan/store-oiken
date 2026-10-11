# oiken

Working repository of the OIKEN low-voltage grid study (Sion and Sierre,
Valais): 1116 LV networks, SFOE 2030/2040 energy-transition scenarios,
screening of grid constraints and siting/sizing of battery storage.

| folder | what it is | language |
|---|---|---|
| [`lv-screening/`](lv-screening/README.md) | **Stage 1, current toolchain.** Data sanity check, scenario injections (demand, PV, EV), daily load-flow screening of the whole portfolio, HTML dashboard, node coordinates, clear-sky PV utility. | Python |
| [`tech-selection/`](tech-selection/README.md) | **Stage 3.** Siting, sizing and technology selection of battery storage per network (MILP, CVX + Gurobi). Also holds the authoritative input data: `data/raw/lv_grids.mat` (grid portfolio), `data/raw/pv_profiles_year.mat`, `data/external/` (demand training set, not in git). | MATLAB |
| [`oiken-db-extraction/`](oiken-db-extraction/README.md) | Extraction of the LV networks from the DSO's SQL Server database. The 3.9 GB backup `tndb_esr_test_03102024 (1).bak` lives here and is not in git. | Python / SQL |
| [`obsolete/`](obsolete/README.md) | Superseded material: the first MATLAB stage 1 (`sanity_check`, whose Excel-reading and parameter-patching stages are still the source of `lv_grids.mat`), archived MATLAB code and outputs of tech-selection, the exploratory DB script, the original `.git` folders. | – |

Data flow:

```
DSO SQL backup ──(oiken-db-extraction)──► Excel exports ──(obsolete/sanity_check stages 1–3)──► lv_grids.mat
                                                                                         │
     lv-screening/tools/export_lv_grids.m (MATLAB, once) ◄───────────────────────────────┘
                 │
                 ▼
     lv-screening/data/lv_grids/*.csv ──► python -m lvgrid oneshot | screen | dashboard
                                                       │
     violation list per scenario (to do) ──────────────┴──► tech-selection (MILP per flagged network)

DSO SQL backup ──(lv-screening/tools/extract_nodes_from_bak.py)──► node coordinates ──► dashboard maps
```

## History

`tech-selection`, `sanity_check` and `oiken-db-extraction` were separate git
repositories (author DaFozi) until 2026-10-10; their original `.git` folders
are kept in `obsolete/nested-git/` (ignored by this repository) and can be
moved back to restore them. The first commit of this repository is the state
of the three folders at that date; everything after it is the Python
toolchain, documentation and the move of superseded material to `obsolete/`.
