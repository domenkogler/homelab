#!/usr/bin/env python3
"""P1 summary: classify what OpenViking kept, per source file."""
import json
import os
import sys
from collections import Counter, defaultdict

d = sys.argv[1] if len(sys.argv) > 1 else "ovv3"
rep = json.load(open("p1report.json", encoding="utf-8"))
_r = json.load(open(os.path.join(d, "_records.json"), encoding="utf-8"))
recs = _r["records"] if isinstance(_r, dict) else _r
man = json.load(open(os.path.join(d, "_manifest.json"), encoding="utf-8"))
uri2src = rep["uri2src"]

print("levels:", dict(Counter(r.get("level") for r in recs)))
print("context_types:", dict(Counter(r.get("context_type") for r in recs)))
print("records:", len(recs), "unique uris:", len({r["uri"] for r in recs}),
      "read ok:", len(man))

by_src = defaultdict(set)
for u, s in uri2src.items():
    by_src[s].add(u)
rows = {r["file"]: r for r in rep["rows"]}
sources = sorted(rows)
no_chunk = [s for s in sources if not by_src.get(s)]
print(f"\nsources={len(sources)} with_chunks={len(sources)-len(no_chunk)} without_chunks={len(no_chunk)}")
for s in no_chunk:
    print("   NO CHUNKS:", s, "orig_frags_expected")

print("\n--- per-source (chunks, coverage, c1 bytes, c3 fm, c4 hdrMissing, c5 pipesMiss, c6 fences, c7 diac) ---")
for s in sources:
    r = rows[s]
    n = len(by_src.get(s, ()))
    print(f"{n:4d} cov={r['coverage']:.2f} c1={str(r['c1_bytes_identical'])[0]} "
          f"c3={str(r['c3_frontmatter'])[0]} c4-={len(r['c4_headers_missing']):3d} c5-={len(r['c5_pipes_missing']):2d} "
          f"c6={r['c6_fences'][0]}/{r['c6_fences'][1]} c7={r['c7_diacritics'][0]}/{r['c7_diacritics'][1]} {s}")

un = rep["unmatched"]
print(f"\nunmatched_leaves={len(un)}")
for u, sc in list(un.items())[:8]:
    p = man.get(u, {}).get("local")
    head = ""
    if p and os.path.exists(p):
        head = open(p, encoding="utf-8", errors="replace").read()[:90].replace("\n", "\\n")
    print(f"  score={sc} {u.split('corpus/')[-1][:70]} :: {head}")
