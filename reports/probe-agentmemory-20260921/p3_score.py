#!/usr/bin/env python3
"""P3 scorer: objective rubric for L1-quality, applied to any arm.

Usage: p3_score.py DOCS_TXT SUMMARY_SPEC OUT_JSON

SUMMARY_SPEC is either
  dir:PATH      -- arm (c): PATH/<slug of doc path>.md produced by p3_armc.py
  ovmode:NAME   -- arms (a)/(b): read OV's .overview.md for each doc via
                   ovout/_manifest.json + p1report uri2src

Rubric (prompt-OV.md §7.6, five yes/no-ish criteria, all machine-checkable):
  R1 subsystem named  : >=1 of the doc's rare terms present
  R2 right host       : no host mentioned that the source never mentions
  R3 numbers verbatim : count of numeric tokens in the summary absent from source
  R4 invents nothing  : invented hosts + invented HD ids + invented numbers
  R5 retrieval key    : H1 present AND >=3 rare source terms present
"""
import json
import os
import re
import sys

HOST_RE = re.compile(r"\b(oldsrv|spark|nas|vps|router|switch|pi99|pi|grafana|traefik|authentik|immich|ollama|litellm|qdrant|docling|openclaw|hermes|tailscale|kopia)\b", re.I)
NUM_RE = re.compile(r"(?<![\w.])\d[\d.,_ ]{0,9}(?![\w])")
HD_RE = re.compile(r"HD-\d+[a-z]?")


def terms(text):
    ws = re.findall(r"[A-Za-zčšžćđ]{6,}", text)
    stop = set("the and for with that this from which have will been could should would because these those there about what when where how".split())
    return [w.lower() for w in ws if w.lower() not in stop]


def rare_terms(src_texts, all_texts):
    """terms appearing in few documents of the set (document frequency <= 3)."""
    df = {}
    for t in all_texts:
        for w in set(terms(t)):
            df[w] = df.get(w, 0) + 1
    return {w for w, c in df.items() if c <= 3}


def score(doc_text, summary):
    src_terms = set(terms(doc_text))
    sum_terms = set(terms(summary))
    hosts_src = {h.lower() for h in HOST_RE.findall(doc_text)}
    hosts_sum = {h.lower() for h in HOST_RE.findall(summary)}
    inv_hosts = sorted(hosts_sum - hosts_src)
    nums_src = {n.strip(" .,") for n in NUM_RE.findall(doc_text)}
    nums_sum = [n.strip(" .,") for n in NUM_RE.findall(summary)]
    inv_nums = sorted({n for n in nums_sum if n and n not in nums_src and not any(n in s or s in n for s in nums_src)})
    hd_src = set(HD_RE.findall(doc_text))
    hd_sum = set(HD_RE.findall(summary))
    inv_hd = sorted(hd_sum - hd_src)
    h1 = ""
    for ln in doc_text.splitlines():
        if ln.startswith("# "):
            h1 = ln[2:].strip()
            break
    rare_present = len(sum_terms & src_terms)
    return {
        "chars": len(summary),
        "tokens_est": round(len(summary) / 4),
        "R1_subsystem": rare_present >= 3,
        "R2_hosts_clean": not inv_hosts,
        "R3_invented_numbers": len(inv_nums),
        "invented_number_examples": inv_nums[:5],
        "R4_invents_nothing": (not inv_hosts) and (not inv_hd) and (not inv_nums),
        "invented_hd": inv_hd,
        "R5_retrieval_key": bool(h1) and (h1.lower() in summary.lower()) and rare_present >= 3,
        "src_terms_shared": rare_present,
    }


def main():
    docs_p, spec, out = sys.argv[1], sys.argv[2], sys.argv[3]
    docs = [l.strip() for l in open(docs_p, encoding="utf-8") if l.strip()]
    corpus = "/home/domen/ovprobe/corpus"
    srcs = {d: open(os.path.join(corpus, d), encoding="utf-8", errors="replace").read() for d in docs}

    summaries = {}
    kind, arg = spec.split(":", 1)
    if kind == "dir":
        for d in docs:
            p = os.path.join(arg, d.replace("/", "__") + ".md")
            if os.path.exists(p):
                summaries[d] = open(p, encoding="utf-8").read()
    else:  # ovmode
        man = json.load(open("/home/domen/ovprobe/ovout/_manifest.json", encoding="utf-8"))
        rep = json.load(open("/home/domen/ovprobe/p1report.json", encoding="utf-8"))
        uri2src = rep["uri2src"]
        by_src = {}
        for uri, s in uri2src.items():
            by_src.setdefault(s, []).append(uri)
        for d in docs:
            uris = by_src.get(d, [])
            if not uris:
                continue
            # deepest shared ancestor of the doc's leaves
            parts = [u.split("/") for u in uris]
            common = []
            for seg in zip(*parts):
                if len(set(seg)) == 1:
                    common.append(seg[0])
                else:
                    break
            node = "/".join(common)
            for want in ("overview", "abstract"):
                for uri, info in man.items():
                    if uri.startswith(node + "/") and uri.endswith("/." + want + ".md"):
                        summaries.setdefault(d, open(info["local"], encoding="utf-8").read())
                        break
                if d in summaries:
                    break

    rows = {}
    for d in docs:
        if d not in summaries:
            rows[d] = {"missing": True}
            continue
        rows[d] = score(srcs[d], summaries[d])
    json.dump(rows, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    ok = [r for r in rows.values() if not r.get("missing")]
    n = len(ok)
    print(f"scored={n}/{len(docs)}")
    if n:
        print(f"R1 subsystem named  : {sum(1 for r in ok if r['R1_subsystem'])}/{n}")
        print(f"R2 hosts clean      : {sum(1 for r in ok if r['R2_hosts_clean'])}/{n}")
        print(f"R4 invents nothing  : {sum(1 for r in ok if r['R4_invents_nothing'])}/{n}")
        print(f"R5 retrieval key    : {sum(1 for r in ok if r['R5_retrieval_key'])}/{n}")
        print(f"invented numbers tot: {sum(r['R3_invented_numbers'] for r in ok)}")
        print(f"mean L1 chars       : {round(sum(r['chars'] for r in ok)/n)}  tokens_est {round(sum(r['tokens_est'] for r in ok)/n)}")


if __name__ == "__main__":
    main()
