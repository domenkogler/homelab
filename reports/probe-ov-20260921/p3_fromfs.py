#!/usr/bin/env python3
"""Build per-doc L0/L1 summaries from an fs-walk manifest (.abstract.md/.overview.md).

Usage: p3_fromfs.py FS_MANIFEST_JSON P1REPORT_JSON DOCS_TXT OUT_DIR
Maps each injected tier file to a source document by node-prefix using the content-derived
URI map (OV URI names are title slugs, so prefix matching against known chunk URIs is the
only reliable link back to the source file).
"""
import json
import os
import sys
from collections import defaultdict

man_p, rep_p, docs_p, outdir = sys.argv[1:5]
os.makedirs(outdir, exist_ok=True)
man = json.load(open(man_p, encoding="utf-8"))
rep = json.load(open(rep_p, encoding="utf-8"))
docs = [d.strip() for d in open(docs_p, encoding="utf-8") if d.strip()]

by_src = defaultdict(set)
for u, s in rep["uri2src"].items():
    by_src[s].add(u)

tiers = defaultdict(dict)
for uri, info in man.items():
    name = uri.rsplit("/", 1)[-1]
    if name not in (".abstract.md", ".overview.md"):
        continue
    node = uri.rsplit("/", 1)[0]
    best, bl = None, -1
    for s, us in by_src.items():
        for u in us:
            if u.startswith(node + "/") or node.startswith(u.rsplit("/", 1)[0]):
                n = node.count("/")
                if n > bl:
                    best, bl = s, n
    if best:
        try:
            tiers[best][name] = open(info["local"], encoding="utf-8", errors="replace").read()
        except Exception:  # noqa: BLE001
            pass

n = 0
for d in docs:
    t = tiers.get(d)
    if not t:
        continue
    body = (t.get(".abstract.md", "") or "") + "\n\n" + (t.get(".overview.md", "") or "")
    open(os.path.join(outdir, d.replace("/", "__") + ".md"), "w", encoding="utf-8").write(body)
    n += 1
    print(f"{d:46s} L0={len(t.get('.abstract.md','') or ''):5d} L1={len(t.get('.overview.md','') or ''):5d}")
print(f"docs_with_tiers={n}/{len(docs)}")
