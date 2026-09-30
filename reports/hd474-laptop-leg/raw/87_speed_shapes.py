"""Build the three prompt shapes probe-speed measures (HD-474, 2026-09-30).

WHY a generator instead of `"xxxx" * n` or `"word " * n`: the engine's own tokenizer makes a lie of
character arithmetic - a run of `xxxx` lands near 2:1 chars/token and `word word word` near
3 tokens/word, while real prose is ~4.5:1. Two probes on this box measured HALF and THREE TIMES the
window they claimed because of exactly that (prompt-lmstudio.md §Traps). A degenerate repeat also
prefix-caches into nothing, so the number stops meaning anything.

So: real repository prose, chunked round-robin out of docs/*.md so no paragraph repeats inside one
shape, cut to a target token count using the tokens-per-character ratio MEASURED on this engine
(pass it as argv[2] after measuring; the default is the ratio the recall probe produced).

    python -X utf8 87_speed_shapes.py [target_tokens...] [--chars-per-token 4.5]

Writes 87-shape-<tokens>.txt next to this file and prints what it wrote. The prompt_tokens the
server reports for each file is the ONLY token number that goes in the record.
"""
import glob
import os
import re
import sys

RAW = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(RAW, "..", "..", ".."))
DEFAULT_TARGETS = (1800, 8000, 24000)


def prose_chunks():
    """Paragraphs from the repo's own docs, de-duplicated, in a stable order."""
    seen, out = set(), []
    for path in sorted(glob.glob(os.path.join(REPO, "docs", "*.md"))):
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for para in re.split(r"\n\s*\n", text):
            para = para.strip()
            if len(para) < 120 or para.startswith("<!--"):
                continue
            key = para[:80]
            if key in seen:
                continue
            seen.add(key)
            out.append(para)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    cpo = 4.5
    for a in sys.argv[1:]:
        if a.startswith("--chars-per-token"):
            cpo = float(a.split("=", 1)[1]) if "=" in a else 4.5
    targets = [int(a) for a in args] or list(DEFAULT_TARGETS)
    chunks = prose_chunks()
    print(f"{len(chunks)} distinct paragraphs available from docs/*.md; "
          f"chars/token assumed {cpo}")
    for t in targets:
        need = int(t * cpo)
        body, i = [], 0
        total = 0
        while total < need and i < len(chunks) * 3:
            p = chunks[i % len(chunks)]
            body.append(p)
            total += len(p) + 2
            i += 1
        text = "\n\n".join(body)[:need]
        out = os.path.join(RAW, "87-shape-%d.txt" % t)
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("wrote %-22s %7d chars (%d paragraphs) - label %dk, server's prompt_tokens is the truth"
              % (os.path.basename(out), len(text), len(body), t // 1000))
    print("\nNext: python scripts/laptop-llm.py probe-speed --model <id> --ttft --label cold-<k> "
          "--prompt-file reports/hd474-laptop-leg/raw/87-shape-<tokens>.txt")


main()
