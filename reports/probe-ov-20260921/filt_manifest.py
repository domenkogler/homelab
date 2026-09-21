#!/usr/bin/env python3
"""Filter a manifest JSON in place to keys with a given URI prefix.

Usage: filt_manifest.py MANIFEST_JSON PREFIX
"""
import json
import sys

p, pre = sys.argv[1], sys.argv[2]
m = json.load(open(p, encoding="utf-8"))
k = {a: b for a, b in m.items() if a.startswith(pre)}
json.dump(k, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"kept={len(k)} of={len(m)}")
