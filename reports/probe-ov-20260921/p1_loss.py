#!/usr/bin/env python3
"""P1 worked example: where did the source lines go for one doc?

Usage: p1_loss.py SRC_REL CHUNKDIR [N]
"""
import json
import os
import sys

sys.path.insert(0, "/home/domen/ovprobe")

src_rel, chunkdir = sys.argv[1], sys.argv[2]
n = int(sys.argv[3]) if len(sys.argv) > 3 else 18
orig = open(os.path.join("/home/domen/ovprobe/corpus", src_rel), encoding="utf-8", errors="replace").read()

rep = json.load(open("/home/domen/ovprobe/p1report.json", encoding="utf-8"))
uris = [u for u, s in rep["uri2src"].items() if s == src_rel]
man = json.load(open(os.path.join(chunkdir, "_manifest.json"), encoding="utf-8"))
blob = ""
for u in uris:
    p = man[u]["local"]
    blob += open(p, encoding="utf-8", errors="replace").read() + "\n"

norm = lambda t: [ln.strip() for ln in t.splitlines() if ln.strip()]  # noqa: E731
ol, bl = norm(orig), set(norm(blob))
missing = [ln for ln in ol if ln not in bl]
print(f"doc={src_rel} chunks={len(uris)} orig_lines={len(ol)} stored_lines_present={len(ol)-len(missing)} missing={len(missing)}")
print("--- chunk URIs (tail):")
for u in uris[:6]:
    print("   ", u.split("corpus/")[-1][:100])
print(f"--- first {n} missing source lines:")
for ln in missing[:n]:
    print("   -", ln[:110])
