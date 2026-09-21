#!/usr/bin/env python3
"""M1/M2 recall harness for the agentmemory probe.

Reuses the OV lane's scoring conventions (p2_run.py): hit@5 = the question's
expected_file appears among the top-5 returned sources; answer_present = one of the
question's answer strings appears in the retrieved text; tokens_est = chars/4.

Modes:
  ingest  CORPUS_JSON                       -> POST every observation, report capture rate
  search  QUESTIONS_JSON OUT_JSON [--full]  -> hit@5 + latency + tokens (token text via
                                               mem::context, OV-comparable injection)
  determ  QUESTIONS_JSON OUT_JSON N         -> same query N x , rank identity check
  synth   OUT_JSON                          -> the synthetic-session gates (exact-id,
                                               contradiction supersession, capture/session)

Scoring is deliberately dumb and identical for every arm, so BM25-only vs hybrid vs
Hermes-vs-Qdrant are the same rubric as the OV lane's hit@5.
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

BASE = os.environ.get("AM_URL", "http://127.0.0.1:3111")
SECRET_FILE = os.environ.get("AM_SECRET_FILE", "")


def hdr():
    h = {"content-type": "application/json"}
    if SECRET_FILE and os.path.exists(SECRET_FILE):
        h["authorization"] = "Bearer " + open(SECRET_FILE, encoding="utf-8").read().strip()
    return h


def post(path, body, timeout=120):
    t0 = time.time()
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(),
                                 headers=hdr(), method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return round(time.time() - t0, 3), json.loads(r.read().decode())


# ------------------------------------------------------------------ ingest
def mode_ingest(corpus_json):
    d = json.load(open(corpus_json, encoding="utf-8"))
    obs = d["replay"] + d["synthetic"]
    ok = err = 0
    per_session = {}
    t0 = time.time()
    for o in obs:
        try:
            _, r = post("/agentmemory/observe", o, timeout=60)
            if "observationId" in r:
                ok += 1
                per_session[o["sessionId"]] = per_session.get(o["sessionId"], 0) + 1
            else:
                err += 1
        except Exception as e:  # noqa: BLE001
            err += 1
            if err < 5:
                print("ERR", type(e).__name__, str(e)[:120], flush=True)
    dt = round(time.time() - t0, 1)
    print("obs_ok=%d obs_err=%d wall=%ss per_session_sessions=%d"
          % (ok, err, dt, len(per_session)), flush=True)
    json.dump({"obs_ok": ok, "obs_err": err, "wall_s": dt,
               "sessions_seen": len(per_session),
               "obs_per_session": per_session},
              open("/home/domen/amprobe/logs/ingest.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)


def sessions():
    req = urllib.request.Request(BASE + "/agentmemory/sessions", headers=hdr())
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode()).get("sessions", [])


# ------------------------------------------------------------------ search
def retrieve(query, limit=5):
    """Recall, in the shape a client can actually use.

    /search?format=full returns observation bodies (narrative text); smart-search
    returns identity-only rows (obsId/score/sessionId/title, no content, no project),
    and its expandIds path returned 0 results for live obsIds on 0.9.29. So scoring
    uses /search; smart-search is measured separately as the default client surface.
    """
    return post("/agentmemory/search", {"query": query, "limit": limit, "format": "full"})


def retrieve_compact(query, limit=5):
    return post("/agentmemory/smart-search", {"query": query, "limit": limit})


def sid2file():
    """session -> repo file for replay sessions; the analogue of OV's uri2src."""
    sess = sessions()
    m = {}
    for s in sess:
        sid = s.get("id", "")
        if sid.startswith("replay-"):
            m[sid] = sid[len("replay-"):].rsplit("_", 1)[0]
    return m


def norm_session_sid(sid, files):
    """replay-docs_services-ai_md -> docs/services-ai.md  (lossy: underscores)."""
    if not sid.startswith("replay-"):
        return sid
    slug = sid[len("replay-"):]
    cands = [f for f in files if f.replace("/", "_").replace(".", "_") == slug]
    return cands[0] if len(cands) == 1 else ("AMBIG:%d" % len(cands) if cands else "UNMATCHED")


def results_of(d):
    """Normalise /search full-mode rows to (session_id, text, score)."""
    out = []
    for r in (d.get("results") or []):
        o = r.get("observation") or {}
        txt = " ".join(str(o.get(k) or "") for k in ("title", "narrative"))
        for f in (o.get("facts") or []):
            txt += " " + str(f)
        for f in (o.get("concepts") or []):
            txt += " " + str(f)
        out.append((o.get("sessionId") or r.get("sessionId") or "", txt, r.get("score")))
    return out


def projects_of(d, limit=5, files=()):
    return [norm_session_sid(sid, files) for sid, _, _ in results_of(d)[:limit]]


def mode_search(questions_json, out_json, corpus_json=None):
    qs = json.load(open(questions_json, encoding="utf-8"))
    files = set()
    if corpus_json and os.path.exists(corpus_json):
        files = {o["project"] for o in json.load(open(corpus_json, encoding="utf-8"))["replay"]}
    rows = []
    for q in qs:
        try:
            lat, d = retrieve(q["q"], 5)
            clat, cd = retrieve_compact(q["q"], 5)
        except Exception as e:  # noqa: BLE001
            rows.append({"id": q["id"], "error": f"{type(e).__name__}: {str(e)[:160]}"})
            print(q["id"], "ERROR", str(e)[:100], flush=True)
            continue
        res = results_of(d)
        projs = [norm_session_sid(sid, files) for sid, _, _ in res[:5]]
        blob = "\n".join(t for _, t, _ in res)
        row = {
            "id": q["id"],
            "latency_s": lat,
            "smartsearch_latency_s": clat,
            "top5_src": projs,
            "scores": [sc for _, _, sc in res[:5]],
            "expected_file": q["file"],
            "hit_at5_expected": q["file"] in projs,
            "answer_present": any(a in blob for a in q["answers"]),
            "answer_in_smartsearch_compact": False,
            "n_results": len(res),
            "chars_retrieved": len(blob),
            "tokens_est": round(len(blob) / 4),
            "compact_tokens_est": round(len(json.dumps(cd, ensure_ascii=False)) / 4),
        }
        rows.append(row)
        print("%s %6.3fs hit=%s ans=%s tok=%d src=%s" % (
            q["id"], lat, row["hit_at5_expected"], row["answer_present"],
            row["tokens_est"], (projs[0] if projs else "-")[:34]), flush=True)
    json.dump(rows, open(out_json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    hits = sum(1 for r in rows if r.get("hit_at5_expected"))
    ans = sum(1 for r in rows if r.get("answer_present"))
    tok = sum(r.get("tokens_est") or 0 for r in rows)
    print("TOTALS hit@5=%d/%d answer=%d/%d tokens=%d (%d/query)"
          % (hits, len(rows), ans, len(rows), tok, tok // max(1, len(rows))), flush=True)


# ---------------------------------------------------------------- determinism
def mode_determ(questions_json, out_json, n=5):
    """Same query N times -> is the RANKING identical? Rank identity = ordered obsIds."""
    qs = json.load(open(questions_json, encoding="utf-8"))
    rows = []
    for q in qs:
        ranks, lats, scores = [], [], []
        for _ in range(n):
            try:
                lat, d = retrieve(q["q"], 5)
                res = results_of(d)
                ranks.append(tuple(json.loads(json.dumps([o for o in res], default=str))[i][0]
                                   for i in range(len(res))))
                lats.append(lat)
                scores.append([round(sc, 6) for _, _, sc in res])
            except Exception as e:  # noqa: BLE001
                ranks.append(("ERROR:" + str(e)[:60],))
        distinct = len(set(ranks))
        score_drift = len({json.dumps(s) for s in scores})
        rows.append({"id": q["id"], "runs": n, "identical": distinct == 1,
                     "distinct_rankings": distinct, "distinct_score_vectors": score_drift,
                     "rankings": ["|".join(r) for r in ranks], "latencies": lats,
                     "scores": scores})
        print("%s identical=%s distinct_ranks=%d distinct_scores=%d"
              % (q["id"], distinct == 1, distinct, score_drift), flush=True)
    json.dump(rows, open(out_json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("DETERMINISM: %d/%d questions identical across %d runs"
          % (sum(1 for r in rows if r["identical"]), len(rows), n), flush=True)


# ------------------------------------------------------------ synthetic gates
EXACT_IDS = ["9002", "3111", "6333", "515,786", "0.34", "512", "64", "HD-268",
             "HD-387", "#26", "#28", "Kopia", "RX 7600", "10.10.1.30:4000", "3114"]

SYNTH_QUERIES = [
    {"id": "E1", "q": "Which TCP port does the pinned embedding leg listen on?",
     "must": ["9002"], "session": "s01-embedding-leg"},
    {"id": "E2", "q": "What rerank latency was measured for twenty documents on the RX 7600?",
     "must": ["0.34", "RX 7600"], "session": "s02-rerank-latency"},
    {"id": "E3", "q": "How large is the vLLM KV cache pool on spark in tokens?",
     "must": ["515,786"], "session": "s03-kv-pool"},
    {"id": "E4", "q": "Which HD backlog row owns the corpus reader rag-mcp?",
     "must": ["HD-268"], "session": "s07-rag-owner"},
    {"id": "E5", "q": "Which HD row requires the spark/ prefix on every LLM path?",
     "must": ["HD-387"], "session": "s07b-hd387"},
    {"id": "E6", "q": "Which numbered decision keeps the harness pointed straight at the engine?",
     "must": ["#26"], "session": "s10-decision-26"},
    {"id": "E7", "q": "Which numbered decision says spark is text-only with no vision leg?",
     "must": ["#28"], "session": "s06-decision-28"},
    {"id": "E8", "q": "Kako obnovim izbrisane datoteke iz varnostne kopije?",
     "must": ["Kopia"], "session": "s08-restore-sl"},
    {"id": "E9", "q": "Which Qdrant REST port runs on oldsrv?",
     "must": ["6333"], "session": "s13-qdrant-port"},
    {"id": "E10", "q": "What direct address must be used for the gateway from oldsrv?",
     "must": ["10.10.1.30:4000"], "session": "s17-split-dns"},
    {"id": "E11", "q": "Kateri port ima vizualni pregledovalnik agentmemory v tej namestitvi?",
     "must": ["3114"], "session": "s12-correction", "supersedes": "3113"},
    {"id": "E12", "q": "Kakšna politika obdržanja velja za varnostne kopije?",
     "must": ["hourly 48"], "session": "s19-kopia-retention"},
]


def mode_synth(out_json):
    rows = []
    for q in SYNTH_QUERIES:
        try:
            lat, d = retrieve(q["q"], 5)
        except Exception as e:  # noqa: BLE001
            rows.append({"id": q["id"], "error": str(e)[:160]})
            continue
        res = results_of(d)
        blob = "\n".join(t for _, t, _ in res)
        present = [m for m in q["must"] if m in blob]
        row = {
            "id": q["id"], "q": q["q"], "latency_s": lat,
            "must": q["must"], "present": present,
            "exact_hit": len(present) == len(q["must"]),
            "sessions_returned": sorted({sid for sid, _, _ in res}),
            "top5": [{"s": sid, "score": sc, "text": t[:160]} for sid, t, sc in res[:5]],
            "tokens_est": round(len(blob) / 4),
        }
        if "supersedes" in q:
            row["superseded_token_present"] = q["supersedes"] in blob
            row["superseded_in_top5"] = any(q["supersedes"] in t for _, t, _ in res[:5])
            row["correct_rank"] = next((i + 1 for i, (sid, t, _) in enumerate(res)
                                        if "3114" in t), None)
            row["stale_rank"] = next((i + 1 for i, (_, t, _) in enumerate(res)
                                      if "3113" in t), None)
        rows.append(row)
        print("%s exact=%s lat=%5.3fs present=%s%s" % (
            q["id"], row["exact_hit"], lat, present,
            (" stale=%s" % row.get("superseded_token_present")) if "supersedes" in q else ""),
            flush=True)
    json.dump(rows, open(out_json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("EXACT-ID: %d/%d" % (sum(1 for r in rows if r.get("exact_hit")), len(rows)), flush=True)


if __name__ == "__main__":
    m = sys.argv[1]
    if m == "ingest":
        mode_ingest(sys.argv[2])
    elif m == "search":
        mode_search(sys.argv[2], sys.argv[3],
                    sys.argv[4] if len(sys.argv) > 4 else None)
    elif m == "determ":
        mode_determ(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 5)
    elif m == "synth":
        mode_synth(sys.argv[2])
    else:
        sys.exit("unknown mode " + m)
