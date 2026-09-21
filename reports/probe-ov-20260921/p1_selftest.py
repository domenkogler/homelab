#!/usr/bin/env python3
"""P1 self-test: prove each fidelity check CAN fail (prompt-OV.md §7.9:
"a test that cannot fail is not evidence").

Usage: p1_selftest.py SRC_FILE OUT_DIR
Writes mutated copies of SRC_FILE and asserts the metric each check protects moves
(and, for check 2, that whitespace-only reflow does NOT move it).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p1_metrics import ATX_RE, FENCE_RE, metrics_for  # noqa: E402


def load(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def main():
    src, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    text = load(src)
    base = metrics_for(src)
    results = []

    def variant(name, newtext, check, expect_change):
        p = os.path.join(outdir, name)
        with open(p, "w", encoding="utf-8") as f:
            f.write(newtext)
        m = metrics_for(p)
        if check == "sha256":
            changed = m["sha256"] != base["sha256"]
        elif check == "sha256_ws":
            changed = m["sha256_ws"] != base["sha256_ws"]
        elif check == "front_matter_keys":
            changed = m["front_matter_keys"] != base["front_matter_keys"]
        elif check == "headers":
            changed = m["headers"] != base["headers"]
        elif check == "pipe_counts":
            changed = m["pipe_counts"] != base["pipe_counts"]
        elif check == "fence_markers":
            changed = m["fence_markers"] != base["fence_markers"]
        elif check == "yaml_block_scalars":
            changed = m["yaml_block_scalars"] != base["yaml_block_scalars"]
        elif check == "diacritics":
            changed = m["diacritics"] != base["diacritics"]
        else:
            raise SystemExit(f"unknown check {check}")
        ok = changed is expect_change
        results.append((name, check, "PASS" if ok else "FAIL", f"changed={changed} expected={expect_change}"))

    # 1 byte-identical
    variant("c1_byte.py", text + "\n# x\n", "sha256", True)
    # 2 whitespace reflow must NOT trip the normalised check:
    #    trailing whitespace on every line + widening one internal space run
    _lines = text.split("\n")
    _reflow = [ln + "  " for ln in _lines]
    for _i, _ln in enumerate(_reflow):
        if re.search(r"\S {2,}\S", _ln):
            _reflow[_i] = re.sub(r" {2,}", "    ", _ln, count=1)
            break
    variant("c2_reflow.py", "\n".join(_reflow), "sha256_ws", False)
    # ... but a blank-line insertion (a real markdown block-structure change) must
    variant("c2_blank.py", re.sub(r"\n", "\n\n", text, count=1), "sha256_ws", True)
    # ... and a word change must
    _m = re.search(r"[A-Za-z]{6,}", text)
    variant("c2_word.py", text.replace(_m.group(0), _m.group(0)[::-1], 1) if _m else text + "x", "sha256_ws", True)
    # 3 front-matter key removal (needs a file with front-matter)
    if base["front_matter"]:
        v = re.sub(r"^[a-z_]+:.*\n", "", text.split("---\n", 2)[1], count=1, flags=re.M)
        variant("c3_fm.md", "---\n" + v + "---\n" + text.split("---\n", 2)[2], "front_matter_keys", True)
    # 4 header level change (drop the first real header line)
    if base["header_count"]:
        lines = text.splitlines(keepends=True)
        hi = next(i for i, ln in enumerate(lines) if ATX_RE.match(ln.rstrip("\r\n")))
        variant("c4_hdr.md", "".join(lines[:hi] + lines[hi + 1:]), "headers", True)
        # and a level change on the first level>=2 header
        hi2 = [i for i, ln in enumerate(lines) if re.match(r"^#{2,6} ", ln)]
        if hi2:
            i = hi2[0]
            variant("c4b_level.md", "".join(lines[:i] + [re.sub(r"^#{2,6} ", "# ", lines[i])] + lines[i + 1:]), "headers", True)
    # 5 pipe removal inside a table row
    if base["pipe_total"]:
        idx = next(i for i, ln in enumerate(text.splitlines()) if ln.count("|") >= 2)
        lines = text.splitlines(keepends=True)
        lines[idx] = lines[idx].replace("|", "", 1)
        variant("c5_pipe.md", "".join(lines), "pipe_counts", True)
    # 6 fence marker removal / block scalar removal
    if base["fence_markers"]:
        lines = text.splitlines(keepends=True)
        fi = next(i for i, ln in enumerate(lines) if FENCE_RE.match(ln))
        variant("c6_fence.md", "".join(lines[:fi] + lines[fi + 1:]), "fence_markers", True)
    if base["yaml_block_scalars"]:
        variant("c6_block.yml", re.sub(r"^(\s*\w+):[ \t]*\|", r"\1: scalar", text, count=1, flags=re.M), "yaml_block_scalars", True)
    # 7 diacritics strip (all characters actually present)
    if base["diacritics_total"]:
        v = text
        for ch in base["diacritics"]:
            v = v.replace(ch, "a")
        variant("c7_diac.md", v, "diacritics", True)

    for name, check, verdict, note in results:
        print(f"{verdict}  {check:20s} {name:16s} {note}")
    bad = [r for r in results if r[2] == "FAIL"]
    print(f"total={len(results)} fail={len(bad)}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
