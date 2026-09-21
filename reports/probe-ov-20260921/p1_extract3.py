#!/usr/bin/env python3
"""P1 extract v3 — the real stored text.

Chunks are vector-store records addressed by viking:// URIs; they are NOT visible in
/api/v1/fs/ls. So: scroll the store for every record URI, then read each URI's stored
text with /api/v1/content/read?raw=true, and write a manifest compatible with p1_diff.py.

Usage: p1_extract3.py OUT_DIR ROOT_URI
"""
import json
import os
import sys
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:1933"
HDRS = {"X-OpenViking-Account": "default", "X-OpenViking-User": "probe"}


def get(path, params=None, raw_text=False):
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=HDRS)
    with urllib.request.urlopen(req, timeout=300) as r:
        body = r.read().decode("utf-8", errors="replace")
    d = json.loads(body)
    return d.get("result") if raw_text else d


def scroll(root):
    out, cursor = [], None
    filt = {} if root in ("", "-") else {"uri": root}
    while True:
        d = get("/api/v1/debug/vector/scroll",
                {"limit": 100, **filt, **({"cursor": cursor} if cursor else {})})
        res = d.get("result") or {}
        recs = res.get("records", []) if isinstance(res, dict) else []
        out.extend({"uri": r.get("uri"), "level": r.get("level"),
                    "sparse": r.get("sparse_vector") is not None,
                    "has_content": bool(r.get("content"))} for r in recs)
        cursor = res.get("next_cursor") or res.get("cursor")
        if not recs or not cursor:
            break
    return out


def main():
    outdir, root = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    recs = scroll(root)
    uris = sorted({r["uri"] for r in recs if r["uri"]})
    if root not in ("", "-"):
        uris = [u for u in uris if u.startswith(root + "/")]
        recs = [r for r in recs if r["uri"].startswith(root + "/")]
    sparse_any = any(r["sparse"] for r in recs)
    print(f"records={len(recs)} unique_uris={len(uris)} any_sparse={sparse_any} "
          f"content_inline_in_scroll={sum(1 for r in recs if r['has_content'])}")
    man, fail = {}, []
    for u in uris:
        try:
            txt = get("/api/v1/content/read", {"uri": u, "raw": "true"}, raw_text=True)
            if not isinstance(txt, str):
                txt = json.dumps(txt, ensure_ascii=False)
        except Exception as e:  # noqa: BLE001
            fail.append((u, f"{type(e).__name__}: {str(e)[:90]}"))
            continue
        dst = os.path.join(outdir, u.replace(root + "/", "").replace("/", "__"))
        with open(dst, "w", encoding="utf-8") as f:
            f.write(txt)
        man[u] = {"local": dst, "size": len(txt.encode()), "reported": len(txt.encode()),
                  "injected": u.rsplit("/", 1)[-1] in (".abstract.md", ".overview.md")}
    json.dump(man, open(os.path.join(outdir, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    json.dump(recs, open(os.path.join(outdir, "_records.json"), "w", encoding="utf-8"))
    print(f"read_ok={len(man)} read_failed={len(fail)}")
    for u, e in fail[:5]:
        print("FAIL", u, e)


if __name__ == "__main__":
    main()
