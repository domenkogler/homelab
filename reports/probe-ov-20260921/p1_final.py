#!/usr/bin/env python3
"""P1 final cut: split the failure classes, then score fidelity on what stored cleanly."""
import json
import sys

d = sys.argv[1] if len(sys.argv) > 1 else "ovv3"
rep = json.load(open("p1report.json", encoding="utf-8"))
rows = rep["rows"]
from collections import defaultdict
by = defaultdict(int)
for u, s in rep["uri2src"].items():
    by[s] += 1

zero = [r for r in rows if by.get(r["file"], 0) == 0]
full = [r for r in rows if r["coverage"] >= 0.95]
part = [r for r in rows if 0 < r["coverage"] < 0.95]
print(f"sources={len(rows)}  no_chunks={len(zero)}  cov>=0.95={len(full)}  partial={len(part)}")


def stat(name, group):
    if not group:
        print(f"  {name}: (none)")
        return
    n = len(group)
    print(f"  {name}: n={n}"
          f" | c1_bytes={sum(1 for r in group if r['c1_bytes_identical'])}"
          f" | c2_ws={sum(1 for r in group if r['c2_ws_identical'])}"
          f" | c3_fm_ok={sum(1 for r in group if r['c3_frontmatter'] is True)}/{sum(1 for r in group if r['c3_frontmatter'] is not None)}"
          f" | c4_hdr_ok={sum(1 for r in group if not r['c4_headers_missing'])}"
          f" | c5_pipe_ok={sum(1 for r in group if not r['c5_pipes_missing'])}"
          f" | c6_fence_ok={sum(1 for r in group if r['c6_fences'][0] == r['c6_fences'][1])}"
          f" | c7_diac_ok={sum(1 for r in group if r['c7_diacritics'][0] == r['c7_diacritics'][1])}")


print("\nfidelity by class:")
stat("cleanly stored (cov>=0.95)", full)
stat("partially stored (0<cov<0.95)", part)
print("\ndocs with NO embedded chunk (invisible to search):")
for r in zero:
    print(f"   {r['file']}  (orig fences={r['c6_fences'][0]}, headers={r['header_count']})")

print("\npartially stored, worst first:")
for r in sorted(part, key=lambda x: x["coverage"])[:12]:
    print(f"   cov={r['coverage']:.2f} chunks={by.get(r['file'],0):3d} {r['file']}")

print("\nfully-stored list:")
for r in sorted(full, key=lambda x: x["file"]):
    print(f"   cov={r['coverage']:.2f} chunks={by.get(r['file'],0):3d} c1={r['c1_bytes_identical']} {r['file']}")
