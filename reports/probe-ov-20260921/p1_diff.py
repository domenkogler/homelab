#!/usr/bin/env python3
"""P1 diff: compare the git-blob baseline against what OpenViking actually stored.

Usage: p1_diff.py BASELINE_JSON OUT_DIR REPORT_JSON

Eight checks of prompt-OV.md §7.3. Matching is content-based (OV drops file names),
so every assignment carries its confidence.
"""
import hashlib
import json
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p1_metrics import ATX_RE, FENCE_RE, in_fence_state, norm_ws  # noqa: E402


def content_lines(text):
    out = []
    for ln in text.splitlines():
        s = ln.strip()
        if s:
            out.append(s)
    return out


def headers_of(text):
    return [
        (len(m.group(1)), m.group(2).strip())
        for ln, inside in in_fence_state(text.splitlines(keepends=True))
        if not inside
        for m in [ATX_RE.match(ln.rstrip("\r\n"))]
        if m
    ]


def pipes_of(text):
    return [
        len(re.findall(r"(?<!\\)\|", ln.rstrip("\r\n")))
        for ln, inside in in_fence_state(text.splitlines(keepends=True))
        if not inside and "|" in ln.rstrip("\r\n")
    ]


def fences_of(text):
    return sum(1 for ln, _ in in_fence_state(text.splitlines(keepends=True)) if FENCE_RE.match(ln))


def main():
    baseline_p, outdir, report_p = sys.argv[1], sys.argv[2], sys.argv[3]
    base = json.load(open(baseline_p, encoding="utf-8"))
    man = json.load(open(os.path.join(outdir, "_manifest.json"), encoding="utf-8"))

    src_text, src_key = {}, {}
    for rel in base:
        p = os.path.join("/home/domen/ovprobe/corpus", rel)
        src_text[rel] = open(p, encoding="utf-8", errors="replace").read()
        src_key[rel] = set(content_lines(src_text[rel]))

    leaves = {}
    for uri, info in man.items():
        if uri.endswith("_manifest.json"):
            continue
        t = open(info["local"], encoding="utf-8", errors="replace").read()
        leaves[uri] = t

    # --- assign leaves to sources by line containment (injected files excluded) ---
    assign = {}
    injected = {}
    unmatched = {}
    for uri, t in leaves.items():
        name = uri.rsplit("/", 1)[-1]
        lines = set(content_lines(t))
        if not lines:
            unmatched[uri] = 0.0
            continue
        best, bestscore = None, 0.0
        for rel in src_key:
            if not src_key[rel]:
                continue
            sc = len(lines & src_key[rel]) / len(lines)
            if sc > bestscore:
                best, bestscore = rel, sc
        if name in (".abstract.md", ".overview.md"):
            injected[uri] = (best, round(bestscore, 3))
        elif bestscore >= 0.6:
            assign.setdefault(best, []).append((uri, t, round(bestscore, 3)))
        else:
            unmatched[uri] = round(bestscore, 3)

    rows = []
    for rel in sorted(base):
        b = base[rel]
        orig = src_text[rel]
        frags = assign.get(rel, [])
        joined = "\n".join(t for _u, t, _s in frags)
        # check 1/2: is ANY single leaf the whole file?
        exact = any(t == orig for _u, t, _s in frags)
        exact_bytes = any(
            hashlib.sha256(open(info["local"], "rb").read()).hexdigest() == b["sha256"]
            for uri, info in man.items()
            if uri.rsplit("/", 1)[-1] in [u.rsplit("/", 1)[-1] for u, _t, _s in frags]
        )
        ws = any(norm_ws(t) == norm_ws(orig) for _u, t, _s in frags)
        # line coverage of the original across all its fragments
        ol = set(content_lines(orig))
        fl = set(content_lines(joined)) if joined else set()
        cov = len(ol & fl) / len(ol) if ol else 1.0
        # front matter
        fm_ok = None
        if b["front_matter"]:
            fm_ok = all((k + ":") in joined for k in b["front_matter_keys"])
        # headers (multiset, order-insensitive)
        oh, fh = Counter(headers_of(orig)), Counter(headers_of(joined))
        hdr_missing = oh - fh
        hdr_added = fh - oh
        # pipes
        op, fp = Counter(p for p in pipes_of(orig) if p), Counter(p for p in pipes_of(joined) if p)
        # fences / block scalars / diacritics
        of, ff = fences_of(orig), fences_of(joined)
        bs_orig = b["yaml_block_scalars"]
        bs_new = len(re.findall(r"^\s*[A-Za-z_][\w.-]*:[ \t]*[|>&][-+0-9]*[ \t]*(#.*)?$", joined, re.M))
        dia_orig = b["diacritics_total"]
        dia_new = sum(joined.count(c) for c in "čćšžČĆŠŽđĐ")
        rows.append({
            "file": rel,
            "frags": len(frags),
            "best_conf": min([s for _u, _t, s in frags], default=None),
            "c1_bytes_identical": exact or exact_bytes,
            "c2_ws_identical": exact or exact_bytes or ws,
            "coverage": round(cov, 3),
            "c3_frontmatter": fm_ok,
            "c4_headers_missing": [[k[0], k[1], v] for k, v in hdr_missing.items()],
            "c4_headers_added": [[k[0], k[1], v] for k, v in hdr_added.items()],
            "c5_pipes_missing": {str(k): v for k, v in (op - fp).items()},
            "c6_fences": [of, ff],
            "c6_block_scalars": [bs_orig, bs_new],
            "c7_diacritics": [dia_orig, dia_new],
        })

    uri2src = {u: rel for rel, lst in assign.items() for u, _t, _s in lst}
    json.dump({"rows": rows, "injected": injected, "unmatched": unmatched,
               "uri2src": uri2src,
               "assigned_frags": sum(len(v) for v in assign.values()),
               "n_leaves": len(leaves)}, open(report_p, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    n = len(rows)
    def cnt(k):
        return sum(1 for r in rows if r[k] is True)
    print(f"sources={n} leaves={len(leaves)} assigned={sum(len(v) for v in assign.values())} "
          f"injected={len(injected)} unmatched={len(unmatched)}")
    print(f"C1 byte-identical: {cnt('c1_bytes_identical')}/{n}")
    print(f"C2 ws-identical  : {cnt('c2_ws_identical')}/{n}")
    fm = [r for r in rows if r["c3_frontmatter"] is not None]
    print(f"C3 front-matter  : {sum(1 for r in fm if r['c3_frontmatter'])}/{len(fm)} intact")
    print(f"C4 headers clean : {sum(1 for r in rows if not r['c4_headers_missing'])}/{n}")
    print(f"C5 pipes clean   : {sum(1 for r in rows if not r['c5_pipes_missing'])}/{n}")
    print(f"C6 fences equal  : {sum(1 for r in rows if r['c6_fences'][0] == r['c6_fences'][1])}/{n}")
    print(f"C7 diacritics eq : {sum(1 for r in rows if r['c7_diacritics'][0] == r['c7_diacritics'][1])}/{n}")
    print(f"full-coverage(1.0): {sum(1 for r in rows if r['coverage'] >= 0.999)}/{n}")
    print(f"coverage<0.5     : {sum(1 for r in rows if r['coverage'] < 0.5)}/{n}")
    print("--- worst 8 by coverage:")
    for r in sorted(rows, key=lambda x: x["coverage"])[:8]:
        print(f"  {r['coverage']:.3f} frags={r['frags']:3d} {r['file']}")


if __name__ == "__main__":
    main()
