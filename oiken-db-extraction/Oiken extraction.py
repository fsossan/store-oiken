import pyodbc
import pandas as pd
import math
import os

# ── Connection ────────────────────────────────────────────────────────────────
cnxn = pyodbc.connect(
    'DRIVER={ODBC Driver 17 for SQL Server};'
    'SERVER=localhost,1433;'
    'DATABASE=tndb_esr;'
    'UID=sa;PWD=Oiken@2026!;'
    'TrustServerCertificate=yes;'
)

print("Connected to database.")

# ── Load core tables ──────────────────────────────────────────────────────────
print("Loading data...")

# Node-branch relationship (full network)
query_NodCnx = """
SELECT id_NOD, cop.id_COP, code_NOD, idNDE_COP, id_BRA,
       longueur_BRA, idBCL_BRA, idNCL_NOD, etatFlux_COP,
       coordNationalX_NOD, coordNationalY_NOD, cop.idNIV_COP
FROM noeud_NOD nod
INNER JOIN composant_COP cop ON cop.idNOD_COP = nod.id_NOD
INNER JOIN connecteurComplexe_CNX cnx1 ON cop.id_COP = cnx1.idCOP_CNX
INNER JOIN connecteurComplexe_CNX cnx2 ON cnx1.idCNX_CNX = cnx2.id_CNX
INNER JOIN branche_BRA bra ON bra.id_BRA = cnx2.idBRA_CNX
"""
df_NodCnx = pd.read_sql_query(query_NodCnx, cnxn)
print(f"  NodCnx: {len(df_NodCnx)} rows")

# Cable parameters
query_Cable = """
SELECT b.id_BRA, cat.resLineique_CAT, cat.indLineique_CAT,
       cat.courantAdmissible_CAT, cat.section_CAT, cat.materiel_CAT
FROM branche_BRA b
INNER JOIN cable_CAB cab ON cab.idBRA_CAB = b.id_BRA
INNER JOIN nCableType_CAT cat ON cat.id_CAT = cab.idCAT_CAB
"""
df_Cable = pd.read_sql_query(query_Cable, cnxn)

# OHL parameters
query_OHL = """
SELECT b.id_BRA, lty.resLineique_LTY, lty.indLineique_LTY,
       lty.courantAdmissible_LTY, lty.section_LTY, lty.materiel_LTY
FROM branche_BRA b
INNER JOIN ligne_LIG lig ON lig.idBRA_LIG = b.id_BRA
INNER JOIN nLigneType_LTY lty ON lty.id_LTY = lig.idLTY_LIG
"""
df_OHL = pd.read_sql_query(query_OHL, cnxn)

# Loads
query_Load = """
SELECT idNOD_COF, clientConsommationAnnuelCompteur_COF,
       courantConsigne_COF, courantFinance_COF
FROM coffretIntroduction_COF
WHERE clientConsommationAnnuelCompteur_COF <> 0
AND clientConsommationAnnuelCompteur_COF IS NOT NULL
"""
df_Load = pd.read_sql_query(query_Load, cnxn)

# Generators
query_Gen = """
SELECT cof.idNOD_COF, epr.puissanceMax_EPR
FROM coffretIntroduction_COF cof
INNER JOIN composant_COP cop ON cop.idNOD_COP = cof.idNOD_COF
INNER JOIN elementProduction_EPR epr ON epr.idCOP_EPR = cop.id_COP
"""
df_Gen = pd.read_sql_query(query_Gen, cnxn)

# LV substation nodes
query_LV_nodes = "SELECT id_NOD FROM noeud_NOD WHERE idNCL_NOD = 1"
df_LV_nodes = pd.read_sql_query(query_LV_nodes, cnxn)
LV_node_ids = list(df_LV_nodes['id_NOD'].values)

print(f"  Found {len(LV_node_ids)} LV substation nodes.")

cnxn.close()

# ── Merge line parameters into NodCnx ────────────────────────────────────────
df_Cable.columns   = ['id_BRA', 'R', 'X', 'Ampacity', 'Section', 'Material']
df_OHL.columns     = ['id_BRA', 'R', 'X', 'Ampacity', 'Section', 'Material']
df_Cable['LineType'] = 'Cable'
df_OHL['LineType']   = 'Line'
df_LineParams = pd.concat([df_Cable, df_OHL], ignore_index=True)
df_LineParams = df_LineParams.drop_duplicates(subset='id_BRA')

df_NodCnx = df_NodCnx.merge(df_LineParams, on='id_BRA', how='left')
df_NodCnx['R']        = df_NodCnx['R'].fillna(0)
df_NodCnx['X']        = df_NodCnx['X'].fillna(0)
df_NodCnx['Ampacity'] = df_NodCnx['Ampacity'].fillna(0)
df_NodCnx['Section']  = df_NodCnx['Section'].fillna(0)
df_NodCnx['Material'] = df_NodCnx['Material'].fillna('Unknown')
df_NodCnx['LineType'] = df_NodCnx['LineType'].fillna('Unknown')

# Load lookup by node id
load_lookup = {}
for _, row in df_Load.iterrows():
    nid = row['idNOD_COF']
    courantFinance  = row['courantFinance_COF']
    courantConsigne = row['courantConsigne_COF']
    fuse = courantConsigne if (pd.isna(courantFinance) or courantFinance == 0) else courantFinance
    if not pd.isna(fuse) and fuse > 0:
        coslini = 0.9
        plini = math.sqrt(3) * 0.4 * fuse * coslini
        qlini = plini * math.tan(math.acos(coslini))
        load_lookup[nid] = (plini, qlini)

# Gen lookup by node id
gen_lookup = {}
for _, row in df_Gen.iterrows():
    nid = row['idNOD_COF']
    pwr = row['puissanceMax_EPR']
    gen_lookup[nid] = gen_lookup.get(nid, 0) + (pwr if not pd.isna(pwr) else 0)

# Node coordinate lookup
coord_lookup = df_NodCnx[['id_NOD','coordNationalX_NOD','coordNationalY_NOD']]\
    .drop_duplicates(subset='id_NOD').set_index('id_NOD')

def get_wkt(node_id):
    if node_id in coord_lookup.index:
        x = coord_lookup.at[node_id, 'coordNationalX_NOD']
        y = coord_lookup.at[node_id, 'coordNationalY_NOD']
        if pd.notna(x) and pd.notna(y):
            return f'POINT ({x} {y})'
    return 'POINT (0 0)'

# ── Border-node pre-computation ───────────────────────────────────────────────
# Nodes that are directly connected (via an LV-level branch) to at least one
# LV substation are "border-adjacent." During flood-fill we include the branch
# to such a node but stop expanding through it, so we don't drift into the
# territory of neighbouring substations. We build a dict:
#   node_adj_subs[nid] = set of LV substation IDs directly adjacent to nid
# At flood-fill time we allow expansion only when
#   node_adj_subs.get(nid, set()) <= {substation_id}
# i.e. the only adjacent substation is our own (or none).
print("Pre-computing border-node adjacency map...")

_sub_branches = df_NodCnx[
    (df_NodCnx['idNCL_NOD'] == 1) & (df_NodCnx['idNIV_COP'] == 1)
]['id_BRA'].unique()

_sub_side = (df_NodCnx[
    (df_NodCnx['id_BRA'].isin(_sub_branches)) &
    (df_NodCnx['idNCL_NOD'] == 1)
][['id_BRA', 'id_NOD']]
 .rename(columns={'id_NOD': 'sub_id'})
 .drop_duplicates())

_reg_side = (df_NodCnx[
    (df_NodCnx['id_BRA'].isin(_sub_branches)) &
    (df_NodCnx['idNCL_NOD'] != 1)
][['id_BRA', 'id_NOD']]
 .drop_duplicates())

_border_pairs = _reg_side.merge(_sub_side, on='id_BRA')[['id_NOD', 'sub_id']]
node_adj_subs = _border_pairs.groupby('id_NOD')['sub_id'].apply(set).to_dict()
print(f"  {len(node_adj_subs)} regular nodes adjacent to at least one LV substation.")

# ── Network extraction ────────────────────────────────────────────────────────
def extract_network(substation_id):
    """
    Flood-fill from substation_id to find all LV-level branches.

    Three boundary rules applied together:

    1. idNIV_COP == 1  — only follow LV-level connections (excludes MV
       interstation cables such as LRMT branches).

    2. etatFlux_COP == 1 at the FRONTIER node — don't traverse a branch whose
       component at the current node is "open" (normally-open tie switch).
       This stops the fill from crossing N.O. tie lines to other feeders.

    3. Far-end node must either have etatFlux_COP == 1, OR be a border-adjacent
       node (directly connected to another LV substation).  If the far end has
       etatFlux=0 and is a regular interior node, the branch is a dead-end N.O.
       stub from the far side and should not be included.  If the far end is a
       border node we still record the branch (energised stub to the tie point)
       but do not expand beyond it.
    """
    # Pre-compute the set of nodes adjacent to OTHER LV substations
    other_adj = frozenset(
        nid for nid, subs in node_adj_subs.items()
        if subs - {substation_id}
    )

    visited_nodes    = {substation_id}
    visited_branches = set()
    frontier         = {substation_id}

    while frontier:
        # LV-level branches from frontier nodes where the local component is active
        branch_candidates = set(df_NodCnx[
            (df_NodCnx['id_NOD'].isin(frontier)) &
            (df_NodCnx['idNIV_COP'] == 1) &
            (df_NodCnx['etatFlux_COP'] == 1) &   # rule 2: local switch must be closed
            (~df_NodCnx['id_BRA'].isin(visited_branches))
        ]['id_BRA'].values)

        if not branch_candidates:
            break

        # Get far-end node info for each candidate branch
        far_df = df_NodCnx[
            (df_NodCnx['id_BRA'].isin(branch_candidates)) &
            (~df_NodCnx['id_NOD'].isin(visited_nodes)) &
            (df_NodCnx['idNCL_NOD'] != 1)          # exclude LV substations
        ][['id_BRA', 'id_NOD', 'etatFlux_COP']].drop_duplicates()

        # Rule 3: a branch is valid only if every far-end node is either
        # (a) etatFlux=1 (active), or (b) a border node (adjacent to another substation).
        # Border nodes are acceptable — we record the branch as an energised stub but
        # never expand through them.
        far_df = far_df.copy()
        far_df['is_border'] = far_df['id_NOD'].isin(other_adj)
        far_df['ok']        = (far_df['etatFlux_COP'] == 1) | far_df['is_border']

        # Drop branches that have at least one "not-ok" far-end node
        bad_branches  = set(far_df.loc[~far_df['ok'], 'id_BRA'])
        valid_branches = branch_candidates - bad_branches

        visited_branches.update(valid_branches)

        # Expand frontier: far-end nodes of valid branches that are active (etatFlux=1)
        # and not adjacent to another LV substation
        good_far = far_df[
            far_df['id_BRA'].isin(valid_branches) &
            (far_df['etatFlux_COP'] == 1) &
            ~far_df['is_border']
        ]
        frontier = set(good_far['id_NOD'].unique())
        visited_nodes.update(frontier)

    return visited_branches, visited_nodes


def build_branch_table(substation_id):
    visited_branches, visited_nodes = extract_network(substation_id)

    if not visited_branches:
        return None

    rows = []
    for bra_id in visited_branches:
        bra_nodes = df_NodCnx[df_NodCnx['id_BRA'] == bra_id][['id_NOD','code_NOD']]\
            .drop_duplicates()

        if len(bra_nodes) < 2:
            continue  # skip degenerate branches

        node_ids = list(bra_nodes['id_NOD'].values)
        node_codes = list(bra_nodes['code_NOD'].values)

        from_id, to_id     = node_ids[0],  node_ids[1]
        from_code, to_code = node_codes[0], node_codes[1]

        params = df_NodCnx[df_NodCnx['id_BRA'] == bra_id].iloc[0]
        length   = params['longueur_BRA']
        R        = params['R']
        X        = params['X']
        ampacity = params['Ampacity']
        section  = params['Section']
        material = params['Material']
        linetype = params['LineType']

        plini, qlini = load_lookup.get(to_id, (0, 0))
        sgn = gen_lookup.get(to_id, 0)

        from_wkt = get_wkt(from_id)
        to_wkt   = get_wkt(to_id)

        rows.append({
            'From':         from_code,
            'To':           to_code,
            'Line':         bra_id,
            'Length(m)':    length,
            'R(Ohm/km)':    R,
            'X(Ohm/km)':    X,
            'Ampacity (A)': ampacity,
            'PLmax(kW)':    round(plini, 6),
            'QLmax(kVar)':  round(qlini, 6),
            'Pg(kW)':       sgn,
            'Section(mm2)': section,
            'Cu/Al':        material,
            'Cable/Line':   linetype,
            'From_XY':      from_wkt,
            'To_XY':        to_wkt,
        })

    if not rows:
        return None

    return pd.DataFrame(rows).sort_values('Line').reset_index(drop=True)


# ── Test on network 1 ─────────────────────────────────────────────────────────
print("\nTesting on substation id_NOD = 1 (CTMT1078) ...")
df_test = build_branch_table(1)

if df_test is not None:
    print(f"  Extracted {len(df_test)} branches.")
    print(df_test[['From','To','Line','Length(m)','R(Ohm/km)','X(Ohm/km)']].to_string())
    df_test.to_excel('network_1_test.xlsx', index=False)
    print("  Saved to network_1_test.xlsx")
else:
    print("  No branches found.")

# ── Full extraction — all LV substations ──────────────────────────────────────
RUN_FULL = False   # set to True to extract all ~1300 networks

if RUN_FULL:
    import time

    out_dir = 'networks'
    os.makedirs(out_dir, exist_ok=True)

    # Build a lookup: id_NOD → code_NOD for substations
    sub_code = (df_NodCnx[df_NodCnx['idNCL_NOD'] == 1][['id_NOD','code_NOD']]
                .drop_duplicates('id_NOD')
                .set_index('id_NOD')['code_NOD']
                .to_dict())

    t0      = time.time()
    n_ok    = 0
    n_empty = 0

    for i, sub_id in enumerate(LV_node_ids):
        code = sub_code.get(sub_id, str(sub_id))
        safe = code.replace('/', '_').replace('\\', '_')
        out_path = os.path.join(out_dir, f'{safe}.xlsx')

        df_net = build_branch_table(sub_id)
        if df_net is not None:
            df_net.to_excel(out_path, index=False)
            n_ok += 1
        else:
            n_empty += 1

        if (i + 1) % 50 == 0 or (i + 1) == len(LV_node_ids):
            elapsed = time.time() - t0
            rate    = (i + 1) / elapsed
            eta     = (len(LV_node_ids) - i - 1) / rate if rate > 0 else 0
            print(f"  [{i+1}/{len(LV_node_ids)}]  ok={n_ok}  empty={n_empty}"
                  f"  elapsed={elapsed:.0f}s  ETA={eta:.0f}s")

    print(f"\nDone. {n_ok} networks saved to '{out_dir}/', {n_empty} empty.")
    print(f"Total time: {time.time() - t0:.1f}s")