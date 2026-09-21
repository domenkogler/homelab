#!/usr/bin/env python3
"""P1 extract v2 — full HTTP walk (the `ov` CLI clamps listings to 256 nodes).

Usage: p1_extract2.py OUT_DIR [ROOT_URI]
Walks with /api/v1/fs/ls?recursive=true (paged), downloads every leaf with
/api/v1/content/download, writes _manifest.json for p1_diff.py.
"""
import json
import os
import sys
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:1933"
HDRS = {"X-OpenViking-Account": "default", "X-OpenViking-User": "probe"}


def get(path, params=None, raw=False):
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=HDRS)
    with urllib.request.urlopen(req, timeout=300) as r:
        data = r.read()
    if raw:
        return data
    return json.loads(data.decode())


def ls_all(root):
    out, offset, page = [], 0, 500
    while True:
        d = get("/api/v1/fs/ls", {"uri": root, "recursive": "true", "show_all_hidden": "true",
                                  "node_limit": page, "offset": offset, "abs_limit": 0})
        res = d.get("result") or []
        items = res.get("result", res) if isinstance(res, dict) else res
        if not items:
            break
        out.extend(items)
        if len(items) < page:
            break
        offset += len(items)
    return out


def main():
    outdir = sys.argv[1]
    root = sys.argv[2] if len(sys.argv) > 2 else "viking://resources/homelab/corpus"
    os.makedirs(outdir, exist_ok=True)
    nodes = ls_all(root)
    json.dump(nodes, open(os.path.join(outdir, "_tree.json"), "w", encoding="utf-8"), ensure_ascii=False)
    leaves = [n for n in nodes if not n.get("isDir")]
    print(f"nodes={len(nodes)} leaves={len(leaves)}")
    man, fail = {}, []
    for n in leaves:
        uri = n["uri"]
        rel = uri.replace(root + "/", "").replace("/", "__")
        dst = os.path.join(outdir, rel)
        try:
            data = get("/api/v1/content/download", {"uri": uri}, raw=True)
            with open(dst, "wb") as f:
                f.write(data)
            man[uri] = {
                "local": dst,
                "size": len(data),
                "reported": n.get("size"),
                "injected": uri.rsplit("/", 1)[-1] in (".abstract.md", ".overview.md"),
            }
        except Exception as e:  # noqa: BLE001
            fail.append((uri, f"{type(e).__name__}: {str(e)[:100]}"))
    json.dump(man, open(os.path.join(outdir, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"downloaded={len(man)} failed={len(fail)}")
    for u, e in fail[:6]:
        print("FAIL", u, e)
    inj = sum(1 for v in man.values() if v["injected"])
    print(f"injected_leaves={inj}")


if __name__ == "__main__":
    main()
