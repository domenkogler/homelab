#!/usr/bin/env python3
"""P2 retrieval: run the same 10 questions through OV find and through a grep baseline.

Usage:
  p2_run.py ov       QUESTIONS_JSON OUT_JSON
  p2_run.py grep     QUESTIONS_JSON OUT_JSON
  p2_run.py score    OV_JSON GREP_JSON [P1REPORT_JSON]

Scoring is answer-substring based (§7.5 "answer correctness") and hit@5 against a known
source file. OV URIs are mapped back to source files by longest-prefix match against the
content-derived URI map built by p1_diff.py — because OV does not keep file names.
"""
import json
import os
import re
import subprocess
import sys
import time

BASE = "http://127.0.0.1:1933"
CORPUS = "/home/domen/ovprobe/corpus"
ROOT_URI = "viking://resources/ov51b/corpus"
HDRS = {"content-type": "application/json",
        "X-OpenViking-Account": "default", "X-OpenViking-User": "probe"}
STOP = set("""what which who where when how why is are does do did the a an of on in to for and or
at by with from we us our it its this that these those runs run used use uses tell me list give""".split())


def find(question, limit=5, read_content=True):
    import urllib.request
    body = {"query": question, "target_uri": ROOT_URI, "limit": limit,
            "node_limit": limit, "score_threshold": 0,
            "read_content": read_content, "telemetry": True}
    t0 = time.time()
    req = urllib.request.Request(BASE + "/api/v1/search/find",
                                 data=json.dumps(body).encode(), headers=HDRS, method="POST")
    with urllib.request.urlopen(req, timeout=600) as r:
        d = json.loads(r.read().decode())
    return round(time.time() - t0, 2), d


def flatten(d):
    """Return list of (uri, content, score, level) from a find response."""
    out = []
    res = d.get("result", d)
    buckets = res.get("resources", []) if isinstance(res, dict) else []
    if isinstance(res, list):
        buckets = res
    for b in buckets:
        out.append((b.get("uri"), b.get("content") or b.get("text") or "",
                    b.get("score"), b.get("level")))
    return out


def mode_ov(qs, out):
    rows = []
    for q in qs:
        try:
            lat, d = find(q["q"])
        except Exception as e:  # noqa: BLE001
            rows.append({"id": q["id"], "error": f"{type(e).__name__}: {str(e)[:160]}"})
            continue
        hits = flatten(d)
        content = "\n".join(h[1] for h in hits)
        rows.append({
            "id": q["id"], "latency_s": lat,
            "uris": [h[0] for h in hits],
            "scores": [h[2] for h in hits],
            "levels": [h[3] for h in hits],
            "answer_present": any(a in content for a in q["answers"]),
            "chars_retrieved": len(content),
            "tokens_est": round(len(content) / 4),
            "usage": (d.get("result") or {}).get("usage") if isinstance(d.get("result"), dict) else None,
            "expected_file": q["file"],
        })
        print(f"{q['id']} {lat:6.2f}s hits={len(hits)} answer={rows[-1]['answer_present']}", flush=True)
    json.dump(rows, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def keywords(text):
    toks = re.findall(r"[A-Za-zčšžćđČŠŽć]{4,}", text)
    return [t for t in toks if t.lower() not in STOP]


def mode_grep(qs, out):
    rows = []
    for q in qs:
        t0 = time.time()
        kws = keywords(q["q"])
        calls = 1
        hits = {}
        for kw in kws:
            r = subprocess.run(["grep", "-ril", "--fixed-strings", kw, CORPUS],
                               capture_output=True, text=True, timeout=120)
            for f in r.stdout.split():
                hits.setdefault(f, set()).add(kw.lower())
        ranked = sorted(hits.items(), key=lambda kv: (-len(kv[1]), kv[0]))
        top5 = [f for f, _ in ranked[:5]]
        read_bytes = 0
        content = ""
        for f in [f for f, _ in ranked[:3]]:
            calls += 1
            b = open(f, "rb").read()
            read_bytes += len(b)
            content += b.decode("utf-8", errors="replace")
        lat = round(time.time() - t0, 2)
        rows.append({
            "id": q["id"], "latency_s": lat, "grep_calls": calls,
            "keywords": kws, "files_matched": len(hits),
            "top5_rel": [os.path.relpath(f, CORPUS) for f in top5],
            "answer_present": any(a in content for a in q["answers"]),
            "read_bytes": read_bytes, "tokens_est": round(read_bytes / 4),
            "expected_file": q["file"],
        })
        print(f"{q['id']} {lat:6.2f}s matched={len(hits)} answer={rows[-1]['answer_present']}", flush=True)
    json.dump(rows, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def mode_score(ovj, grepj, p1j=None):
    ov = json.load(open(ovj, encoding="utf-8"))
    gp = json.load(open(grepj, encoding="utf-8"))
    uri2src = {}
    if p1j and os.path.exists(p1j):
        uri2src = json.load(open(p1j, encoding="utf-8")).get("uri2src", {})

    def uri_to_src(u):
        if u in uri2src:
            return uri2src[u]
        cands = [s for uu, s in uri2src.items() if uu.startswith(u.rstrip("/") + "/")]
        if len(set(cands)) == 1:
            return cands[0]
        return f"AMBIG:{len(set(cands))}" if cands else "UNMATCHED"

    print(f"{'id':4s} {'OV hit@5':9s} {'OV src':28s} {'OV ans':7s} {'OV tok':7s} "
          f"{'OV s':6s} | {'grep hit@5':10s} {'grep ans':8s} {'grep tok':8s} {'grep s':6s}")
    ovhit = ovt = 0
    ghit = gtt = 0
    for o, g in zip(ov, gp):
        srcs = [uri_to_src(u or "") for u in o.get("uris", [])]
        ohit = o.get("expected_file") in srcs
        ghit5 = o.get("expected_file") in g.get("top5_rel", [])
        ovhit += ohit
        ghit += ghit5
        ovt += o.get("tokens_est") or 0
        gtt += g.get("tokens_est") or 0
        uniq = sorted({s for s in srcs if not s.startswith(("AMBIG", "UNMATCHED"))})
        print(f"{o['id']:4s} {str(ohit):9s} {(uniq[0] if len(uniq)==1 else ','.join(uniq))[:28]:28s} "
              f"{str(o.get('answer_present')):7s} {str(o.get('tokens_est')):7s} {str(o.get('latency_s')):6s} | "
              f"{str(ghit5):10s} {str(g.get('answer_present')):8s} {str(g.get('tokens_est')):8s} {str(g.get('latency_s')):6s}")
    print(f"TOTALS  OV hit@5={ovhit}/{len(ov)} tokens={ovt} | grep hit@5={ghit}/{len(gp)} tokens={gtt}")


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "ov":
        mode_ov(json.load(open(sys.argv[2], encoding="utf-8")), sys.argv[3])
    elif mode == "grep":
        mode_grep(json.load(open(sys.argv[2], encoding="utf-8")), sys.argv[3])
    else:
        mode_score(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
