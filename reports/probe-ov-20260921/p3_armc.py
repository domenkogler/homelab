#!/usr/bin/env python3
"""P3 arm (c): the no-LLM stand-in for OV's L1 overview.

Usage: p3_armc.py SRC_FILE OUT_FILE

First N non-empty lines (code-fence-safe) + the header outline, capped by characters.
This is the "cheap extract" arm: if it scores like the LLM arm, OV's L0/L1 layer buys
nothing on this corpus and the token cost is avoidable.
"""
import re
import sys

sys.path.insert(0, "/home/domen/ovprobe")
from p1_metrics import ATX_RE, in_fence_state  # noqa: E402

MAX_CHARS = 900
HEAD_LINES = 10


def main():
    src, out = sys.argv[1], sys.argv[2]
    text = open(src, encoding="utf-8", errors="replace").read()
    lines = text.splitlines(keepends=True)
    heads, first = [], []
    in_code = False
    for ln, inside in in_fence_state(lines):
        if inside:
            continue
        m = ATX_RE.match(ln.rstrip("\r\n"))
        if m:
            heads.append(f"{'#' * len(m.group(1))} {m.group(2).strip()}")
        elif len(first) < HEAD_LINES and ln.strip():
            first.append(ln.rstrip())
    body = "\n".join(first)
    outline = "\n".join(heads[:20])
    l1 = (body + "\n\n" + outline)[:MAX_CHARS]
    open(out, "w", encoding="utf-8").write(l1)
    print(f"{len(l1)} chars, heads={len(heads)}")


if __name__ == "__main__":
    main()
