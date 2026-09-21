#!/usr/bin/env python3
"""P1 classification by *provable* cause of missing content.

OV's chunk URIs keep the source path up to the file's stem:
   corpus/<dir>/<stem>/<H1-slug>/<section>.md
so failed-embedding URIs (from the server log) and embedded record URIs can both be
attributed to a source file without guessing.

Usage: p1_class.py LOGFILE
"""
import json
import os
import re
import sys

log = sys.argv[1] if len(sys.argv) > 1 else "server2.log"
recs = json.load(open("ovvB/_records.json", encoding="utf-8"))
recs = recs["records"] if isinstance(recs, dict) else recs
embedded = {r["uri"] for r in recs if r.get("uri")}
failed = set(re.findall(r"uri=(viking://[^\s)]+)", open(log, encoding="utf-8", errors="replace").read()))

rep = json.load(open("p1report.json", encoding="utf-8"))
rows = {r["file"]: r for r in rep["rows"]}
cov = {r["file"]: r["coverage"] for r in rep["rows"]}

classes = {"A_all_chunks_failed": [], "B_partial": [], "C_no_failure_but_loss": [],
           "C2_no_failure_full_coverage": [], "D_never_chunked": []}
detail = []
for s in sorted(rows):
    d = os.path.dirname(s)
    stem = os.path.basename(s)
    stem = re.sub(r"\.(md|yml|yaml|j2|py|sh)$", "", stem, flags=re.I)
    pre = "viking://resources/ov51b/corpus/" + (f"{d}/" if d != "." else "") + stem + "/"
    e = sum(1 for u in embedded if u.startswith(pre))
    f = sum(1 for u in failed if u.startswith(pre))
    c = cov[s]
    if e == 0 and f > 0:
        k = "A_all_chunks_failed"
    elif e > 0 and f > 0:
        k = "B_partial"
    elif e == 0 and f == 0:
        k = "D_never_chunked"
    elif c >= 0.95:
        k = "C2_no_failure_full_coverage"
    else:
        k = "C_no_failure_but_loss"
    classes[k].append((s, e, f, c))
    detail.append((k, s, e, f, c))

for k in classes:
    print(f"\n{k}: {len(classes[k])}")
    for s, e, f, c in classes[k]:
        print(f"    embedded={e:3d} failed={f:3d} coverage={c:.2f}  {s}")

tot_e = sum(1 for u in embedded)
print(f"\ntotals: embedded_uris={tot_e} failed_uris={len(failed)} sources={len(rows)}")
