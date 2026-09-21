#!/usr/bin/env python3
"""Fetch OV's L0 abstract / L1 overview text per doc-node.

The load tiers are NOT fs leaves: they are level-0/1 vector-store records whose text must
be read via /api/v1/content/abstract and /api/v1/content/overview.

Usage: p3_tiers.py PARENT_ROOT OUT_JSON
Writes {doc_node_uri: {"abstract": str, "overview": str}}.
"""
import json
import sys
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:1933"
HDRS = {"X-OpenViking-Account": "default", "X-OpenViking-User": "probe"}


def get(path, uri):
    u = BASE + path + "?" + urllib.parse.urlencode({"uri": uri})
    try:
        d = json.loads(urllib.request.urlopen(urllib.request.Request(u, headers=HDRS), timeout=120).read().decode())
        r = d.get("result")
        return r if isinstance(r, str) else json.dumps(r, ensure_ascii=False)
    except Exception as e:  # noqa: BLE001
        return f"__ERR__ {type(e).__name__}: {str(e)[:60]}"


def main():
    root, out = sys.argv[1], sys.argv[2]
    recs = json.load(open("ovvA/_records.json", encoding="utf-8"))
    recs = recs["records"] if isinstance(recs, dict) else recs
    nodes = sorted({r["uri"] for r in recs if r.get("uri", "").startswith(root) and r.get("level") in (0, 1)})
    # a node appears once per level; keep unique dirs
    seen, res = set(), {}
    for u in nodes:
        key = u
        if key in seen:
            continue
        seen.add(key)
        res[key] = {"abstract": get("/api/v1/content/abstract", u),
                    "overview": get("/api/v1/content/overview", u)}
    json.dump(res, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    ok = sum(1 for v in res.values() if not v["overview"].startswith("__ERR__") and len(v["overview"]) > 20)
    print(f"tier_uris={len(res)} overview_ok={ok}")
    for k in list(res)[:3]:
        print(" e.g.", k.split("corpus20/")[-1][:60], "|", res[k]["overview"][:90].replace("\n", " "))


if __name__ == "__main__":
    main()
