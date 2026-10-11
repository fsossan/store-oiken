# obsolete

Material kept for reference only. Nothing here is used by the current
toolchain (`lv-screening/`, `tech-selection/`, `oiken-db-extraction/`).

| folder | what it is | why it is here |
|---|---|---|
| `sanity_check/` | The first MATLAB implementation of stage 1 (one-shot and temporal load flows, MkDocs website) by DaFozi, state of 2026-10-10. | Re-implemented in `lv-screening/`. Its stages 1–3 (`main.m`: reading the OIKEN Excel files in `network_data/` and patching missing line and transformer parameters into `data_v2.mat`) are still the only implementation of that data preparation; rerun them from this folder if OIKEN delivers new data, then re-export with `lv-screening/tools/export_lv_grids.m`. |
| `tech-selection-old-code/` | `tech-selection/old-code/`: archived MATLAB functions (10k lines) that were never on the path. | Not reachable from `main.m`; kept because the development notes refer to it. |
| `tech-selection-legacy-output/` | `tech-selection/results/legacy_output/`: MILP outputs produced before the 2026-10-10 restructure (not in git, 862 MB). | Old demand realisations; reproducible only from here. |
| `db-extraction-research/` | `Research+2025-Main.py` / `.ipynb`: the exploratory database script that preceded `oiken-db-extraction/Oiken extraction.py`. | Superseded by the cleaned-up extraction script; its coordinate lookup is now done by `lv-screening/tools/extract_nodes_from_bak.py`. |
| `nested-git/` | The original `.git` folders of the three sub-projects (not in git, 2.3 GB). | Move one back (e.g. `mv obsolete/nested-git/tech-selection.git tech-selection/.git`) to restore that folder as its own repository with its GitHub remote. |
