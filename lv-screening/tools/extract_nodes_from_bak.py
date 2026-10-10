#!/usr/bin/env python3
"""Pull the node table (noeud_NOD) out of a SQL Server backup without SQL Server.

The .bak stores the database pages uncompressed, so the rows of one table can
be read by scanning for its 8 KB data pages and decoding the row format
(fixed-length columns, NULL bitmap, variable-length column offsets). This is a
one-off tool: it only knows the columns we need from noeud_NOD and finds the
table through the allocation-unit id printed in each page header.

    python tools/extract_nodes_from_bak.py <backup.bak> [-o data/geo/nodes_db.csv]
    python tools/extract_nodes_from_bak.py <backup.bak> --discover CTMT1078   # print page ids holding a code

Output columns: id_nod, code, name, node_class (1 = LV substation),
x_db, y_db (as stored: X = north, Y = east, LV03 or LV95),
E_lv95, N_lv95, record_type (0 primary, 1 forwarded).

Layout constants below were read off the backup of 2024-10-03 (see
lv-screening/README.md, "Node coordinates"); re-run --discover to re-derive
them for another backup.
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

import numpy as np
import pandas as pd

PAGE = 8192
STRIDE = 512                      # pages are 512-byte aligned inside the MTF stream
CHUNK = 256 << 20

# noeud_NOD in tndb_esr_test_03102024.bak
OBJ_ID = 237
INDEX_ID = 256
OFF_ID, OFF_CLASS, OFF_X, OFF_Y = 4, 8, 45, 53      # byte offsets inside the record
COL_X, COL_Y = 29, 30                               # 1-based column numbers (for the NULL bitmap)
VAR_CODE, VAR_NAME = 0, 1                           # variable-length column slots


def iter_pages(path: Path, obj_id: int, index_id: int):
    """Yield (file_offset, page_bytes) for every data page of the allocation unit."""
    ob = obj_id.to_bytes(4, "little")
    ib = index_id.to_bytes(2, "little")
    seen = set()
    with open(path, "rb") as f:
        prev = b""
        base = 0
        while True:
            buf = f.read(CHUNK)
            if not buf:
                break
            data = prev + buf
            start = base - len(prev)
            arr = np.frombuffer(data, np.uint8)
            if len(arr) >= PAGE:
                pos = np.arange(0, len(arr) - PAGE + 1, STRIDE)
                m = (arr[pos] == 1) & (arr[pos + 1] == 1)
                for k, b in enumerate(ob):
                    m &= arr[pos + 24 + k] == b
                for k, b in enumerate(ib):
                    m &= arr[pos + 6 + k] == b
                for p in pos[m]:
                    off = start + int(p)
                    if off in seen:
                        continue
                    seen.add(off)
                    yield off, data[p:p + PAGE]
            prev = data[-(PAGE - STRIDE):]
            base += len(buf)


def parse_page(page: bytes):
    """Rows (dicts) of one data page; forwarding stubs, ghosts and index rows are skipped."""
    slot_cnt = struct.unpack_from("<H", page, 22)[0]
    rows = []
    for i in range(slot_cnt):
        s = struct.unpack_from("<H", page, PAGE - 2 * (i + 1))[0]
        if s < 96 or s + 4 > PAGE:
            continue
        status = page[s]
        rtype = (status >> 1) & 7
        if rtype not in (0, 1):
            continue
        fixlen = struct.unpack_from("<H", page, s + 2)[0]
        if fixlen < OFF_Y + 8 or s + fixlen + 2 > PAGE:
            continue
        ncol = struct.unpack_from("<H", page, s + fixlen)[0]
        nb = (ncol + 7) // 8
        p = s + fixlen + 2 + nb
        if ncol < COL_Y or p + 2 > PAGE:
            continue
        nullbits = int.from_bytes(page[s + fixlen + 2:s + fixlen + 2 + nb], "little")
        has_var = bool(status & 0x20)
        code = name = ""
        if has_var:
            nvar = struct.unpack_from("<H", page, p)[0]
            if p + 2 + 2 * nvar > PAGE or nvar <= VAR_NAME:
                continue
            ends = [struct.unpack_from("<H", page, p + 2 + 2 * j)[0] & 0x7FFF for j in range(nvar)]
            vstart = p + 2 + 2 * nvar
            bounds = [vstart] + [s + e for e in ends]
            if any(b > PAGE for b in bounds) or any(bounds[j] > bounds[j + 1] for j in range(len(ends))):
                continue
            code = page[bounds[VAR_CODE]:bounds[VAR_CODE + 1]].decode("utf-16-le", "replace")
            name = page[bounds[VAR_NAME]:bounds[VAR_NAME + 1]].decode("utf-16-le", "replace")
        nid = struct.unpack_from("<i", page, s + OFF_ID)[0]
        ncl = struct.unpack_from("<i", page, s + OFF_CLASS)[0]
        x = struct.unpack_from("<d", page, s + OFF_X)[0]
        y = struct.unpack_from("<d", page, s + OFF_Y)[0]
        if (nullbits >> (COL_X - 1)) & 1:
            x = np.nan
        if (nullbits >> (COL_Y - 1)) & 1:
            y = np.nan
        rows.append(dict(id_nod=nid, code=code.strip(), name=name.strip(), node_class=ncl,
                         x_db=x, y_db=y, record_type=rtype))
    return rows


def to_lv95(x_db: np.ndarray, y_db: np.ndarray):
    """DB stores X = north, Y = east in LV03 (6 digits) or LV95 (7 digits); 0 = missing."""
    x = np.asarray(x_db, float).copy()
    y = np.asarray(y_db, float).copy()
    missing = ~np.isfinite(x) | ~np.isfinite(y) | (x < 1e4) | (y < 1e4)
    N = np.where(x < 1e6, x + 1e6, x)
    E = np.where(y < 2e6, y + 2e6, y)
    N[missing] = np.nan
    E[missing] = np.nan
    return E, N


def discover(path: Path, code: str):
    needle = code.encode("utf-16-le")
    with open(path, "rb") as f:
        prev = b""
        base = 0
        while True:
            buf = f.read(CHUNK)
            if not buf:
                break
            data = prev + buf
            start = base - len(prev)
            i = data.find(needle)
            while i != -1:
                off = start + i
                for back in range(0, 2 * PAGE, STRIDE):
                    cand = (off // STRIDE) * STRIDE - back
                    if cand < start:
                        break
                    pg = data[cand - start:cand - start + PAGE]
                    if len(pg) == PAGE and pg[0] == 1 and pg[1] == 1:
                        slot_cnt = struct.unpack_from("<H", pg, 22)[0]
                        free_cnt, free_data = struct.unpack_from("<HH", pg, 28)
                        if free_cnt + free_data + 2 * slot_cnt == PAGE:
                            obj = struct.unpack_from("<I", pg, 24)[0]
                            idx = struct.unpack_from("<H", pg, 6)[0]
                            print(f"offset {off}: data page at {cand} obj_id={obj} index_id={idx} slots={slot_cnt}")
                            break
                i = data.find(needle, i + 1)
            prev = data[-(2 * PAGE):]
            base += len(buf)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("bak", type=Path)
    ap.add_argument("-o", "--out", type=Path, default=Path(__file__).resolve().parent.parent / "data" / "geo" / "nodes_db.csv")
    ap.add_argument("--obj-id", type=int, default=OBJ_ID)
    ap.add_argument("--index-id", type=int, default=INDEX_ID)
    ap.add_argument("--discover", metavar="CODE", help="print the pages holding this node code and exit")
    a = ap.parse_args(argv)
    if a.discover:
        discover(a.bak, a.discover)
        return 0
    rows = []
    n_pages = 0
    for _, page in iter_pages(a.bak, a.obj_id, a.index_id):
        n_pages += 1
        rows.extend(parse_page(page))
    if not rows:
        print("no rows found: check --obj-id / --index-id with --discover", file=sys.stderr)
        return 1
    df = pd.DataFrame(rows)
    dup = df.duplicated("id_nod", keep=False)
    if dup.any():
        conflict = df[dup].groupby("id_nod").agg(nx=("x_db", "nunique"), ny=("y_db", "nunique"))
        n_conf = int(((conflict.nx > 1) | (conflict.ny > 1)).sum())
        print(f"{int(dup.sum())} duplicate row images for {dup.sum() and df[dup].id_nod.nunique()} ids "
              f"({n_conf} with differing coordinates); keeping the last image", file=sys.stderr)
    df = df.drop_duplicates("id_nod", keep="last").sort_values("id_nod").reset_index(drop=True)
    df["E_lv95"], df["N_lv95"] = to_lv95(df.x_db, df.y_db)
    a.out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(a.out, index=False)
    n_coord = int(df.E_lv95.notna().sum())
    print(f"{n_pages} pages, {len(df)} nodes ({(df.node_class == 1).sum()} LV substations), "
          f"{n_coord} with coordinates -> {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
