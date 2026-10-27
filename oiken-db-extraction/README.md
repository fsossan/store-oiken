# oiken-db-extraction

Extracts low-voltage (LV) distribution networks from an Oiken / ESR SQL Server
network database and exports each network as a branch table (nodes, line
impedances, ampacities, loads, generation and national-grid coordinates) ready
for load-flow tooling.

The core problem this solves: the database stores one single connected graph for
the whole utility. This repo splits it into the ~1300 individual LV networks, one
per LV substation, by flood-filling outward from each substation and stopping at
the correct electrical boundaries.

---

## 1. Prerequisites

| Requirement | Notes |
|---|---|
| Python 3.10+ | |
| SQL Server 2019+ | Local instance or Docker; needed to host the restored database |
| ODBC Driver 17 for SQL Server | Must match the driver name in the connection string |
| Python packages | `pyodbc`, `pandas`, `openpyxl` |

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install pyodbc pandas openpyxl
```

macOS driver install:

```bash
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
brew install msodbcsql17
```

Check the driver is visible to Python:

```bash
python -c "import pyodbc; print(pyodbc.drivers())"
```

---

## 2. Get the database

**The database backup is not in this repository.** It is a ~3.6 GB `.bak` file,
far over GitHub's 100 MB file limit, and it contains real utility network data —
so it is excluded via the repository's root `.gitignore` and must be transferred out of band (shared
drive, SFTP, or physical media). Ask the repo owner for
`tndb_esr_test_<date>.bak`.

Place it in the repo root (it will be ignored by git) and restore it:

```sql
RESTORE DATABASE tndb_esr
FROM DISK = '/path/to/tndb_esr_test_03102024.bak'
WITH MOVE 'tndb_esr'     TO '/var/opt/mssql/data/tndb_esr.mdf',
     MOVE 'tndb_esr_log' TO '/var/opt/mssql/data/tndb_esr_log.ldf',
     REPLACE;
```

Use `RESTORE FILELISTONLY FROM DISK = '...'` first if the logical file names
differ from the above.

Running SQL Server in Docker is the quickest path on macOS/Linux:

```bash
docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=<your-password>" \
  -p 1433:1433 --name mssql -d mcr.microsoft.com/mssql/server:2022-latest
```

---

## 3. Configure the connection

The connection block is at the top of [Oiken extraction.py](Oiken%20extraction.py).
Edit the server, database and credentials to match your instance:

```python
cnxn = pyodbc.connect(
    'DRIVER={ODBC Driver 17 for SQL Server};'
    'SERVER=localhost,1433;'
    'DATABASE=tndb_esr;'
    'UID=sa;PWD=<your-password>;'
    'TrustServerCertificate=yes;'
)
```

> **Do not commit your password.** Prefer reading it from the environment
> (`os.environ["MSSQL_PASSWORD"]`) and exporting it in your shell, or use
> `Trusted_Connection=yes` on Windows with a domain account — as
> the original research script (`../obsolete/db-extraction-research/Research+2025-Main.py`) does.

---

## 4. Run

```bash
python "Oiken extraction.py"
```

By default this extracts the single test network and writes
`network_1_test.xlsx`. To extract all LV networks, set the flag near the bottom
of the script:

```python
RUN_FULL = True     # writes one .xlsx per substation into networks/
```

Full extraction writes ~1300 files into `networks/` and prints progress with an
ETA every 50 substations.

---

## 5. Repository layout

| Path | What it is |
|---|---|
| [Oiken extraction.py](Oiken%20extraction.py) | **Main script.** Cleaned-up extraction with the three boundary rules |
| `../obsolete/db-extraction-research/` | Original exploratory research script and its notebook version (moved out on 2026-10-11) |
| [query_network_data.sql](query_network_data.sql) | Pure-SQL equivalent of the branch table for one substation |
| [testing_network_query.sql](testing_network_query.sql) | Scratch queries used while validating joins |
| `*.csv` | Small sample table dumps kept for reference (`noeud_NOD`, `branche_BRA`, …) |
| `network_1_test.xlsx` | Expected output for the validation network (24 branches) |
| `LV_grid_1.xlsx`, `MV_LV_substation_1.xlsx` | Reference exports used for cross-checking |

---

## 6. How the extraction works

A flood-fill starts at an LV substation node (`idNCL_NOD = 1`) and walks the
node–branch graph. Three rules applied together define the network boundary:

1. **LV level only** — follow connections where `idNIV_COP = 1`. This excludes
   MV interstation cables (e.g. `LRMT` branches).
2. **Closed switch at the frontier** — don't traverse a branch whose component
   at the *current* node has `etatFlux_COP = 0` (a normally-open tie switch).
   This stops the fill from crossing N.O. tie lines into other feeders.
3. **Valid far end** — the far-end node must either have `etatFlux_COP = 1`, or
   be *border-adjacent* (directly connected to another LV substation). A far end
   with `etatFlux = 0` on a regular interior node is a dead-end N.O. stub owned
   by the other side and is dropped. Border nodes are recorded as energised
   stubs to the tie point, but the fill never expands through them.

Rule 3 is what keeps networks from bleeding into neighbouring substations'
territory. The border-adjacency map is precomputed once, before any extraction.

### Key database fields

| Field | Meaning |
|---|---|
| `idNCL_NOD` | Node class — `1` marks an LV substation node |
| `idNIV_COP` | Voltage level of a component — `1` is LV |
| `etatFlux_COP` | Switch state of a component — `1` closed/energised, `0` open |
| `idBCL_BRA` | Branch class — `1` cable, `2` overhead line |

### Derived quantities

Loads come from `coffretIntroduction_COF` and are sized from the fuse rating
(`courantFinance_COF`, falling back to `courantConsigne_COF`) at 400 V:

```
P = √3 · 0.4 · I_fuse · cosφ        (cosφ = 0.9)
Q = P · tan(arccos(cosφ))
```

Generation is the sum of `puissanceMax_EPR` per node. Coordinates are emitted as
WKT `POINT (x y)` in the Swiss national grid.

---

## 7. Output columns

`From`, `To`, `Line`, `Length(m)`, `R(Ohm/km)`, `X(Ohm/km)`, `Ampacity (A)`,
`PLmax(kW)`, `QLmax(kVar)`, `Pg(kW)`, `Section(mm2)`, `Cu/Al`, `Cable/Line`,
`From_XY`, `To_XY`

---

## 8. Validation

Substation `id_NOD = 1` (**CTMT1078**, "COLLEGE CANTONAL") is the reference case
and must yield **24 branches**. The script runs it on every invocation and
prints the branch table, so a regression is visible immediately. Compare against
the committed `network_1_test.xlsx`.

---

## 9. Data handling

The database contains real network and customer-consumption data. Keep the
`.bak`, any `networks/` output and customer-level exports off GitHub — the
root `.gitignore` already covers database backups, credentials and bulk outputs.
