#!/usr/bin/env python3
"""Join embedding-failure URIs (server log) with the per-source P1 table.

Usage: p1_failjoin.py LOGFILE OUTDIR
"""
import json
import os
import re
import sys
from collections import defaultdict

log, d = sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "ovv3"
txt = open(log, encoding="utf-8", errors="replace").read()
uris = sorted(set(re.findall(r"uri=(viking://[^\s)]+)", txt)))
too_big = re.findall(r"input \((\d+) tokens\) is too large", txt)
print(f"failed_uris={len(uris)} too_large_events={len(too_big)} "
      f"tokens_seen={sorted(set(int(t) for t in too_big))[:8]}...{sorted(set(int(t) for t in too_big))[-3:]}")

rep = json.load(open("p1report.json", encoding="utf-8"))
rows = {r["file"]: r for r in rep["rows"]}
uri2src = rep["uri2src"]

# a failed URI is a section of some doc: match by the doc's node prefix (dir of its chunks)
by_src = defaultdict(set)
for u, s in uri2src.items():
    by_src[s].add(u)


def src_of_fail(fu):
    best, bl = None, -1
    for s, us in by_src.items():
        for u in us:
            # longest common path prefix
            a, b = fu.split("/"), u.split("/")
            i = 0
            while i < min(len(a), len(b)) and a[i] == b[i]:
                i += 1
            if i > bl:
                best, bl = s, i
    return best, bl


fail_src = defaultdict(list)
for fu in uris:
    s, ln = src_of_fail(fu)
    if ln >= 5:
        fail_src[s].append(fu)

clean, dirty = [], []
for s, r in sorted(rows.items()):
    nf = len(fail_src.get(s, ()))
    line = f"{s:56s} chunks={len(by_src.get(s, ())):3d} cov={r['coverage']:.2f} failed_chunks={nf}"
    (dirty if nf else clean).append(line)
    print(line)

print("\n--- docs with NO failed chunks (fidelity attributable to OV sectioning alone):")
for l in clean:
    print("  ", l)
