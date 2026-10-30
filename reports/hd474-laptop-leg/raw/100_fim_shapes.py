#!/usr/bin/env python3
"""Build the FIM prompt shapes this run measures trigger latency at (HD-474 gate 5).

The shape is the instruction + [PREFIX]/[SUFFIX] code-fence form — the surface that this lane proved
infills correctly (`fim_surface: instruction-fenced`, raw/40-coder-probes.txt) and the one Continue's
tab provider sends. The TEMPLATE string is printed into the log so the exact bytes are reproducible;
the previous session's wording is not recorded anywhere in the repo, so this run states its own.

The code is real repository source (scripts/bench/laptop-llm.py), split at a real cursor position:
the PREFIX is the file up to the cursor, the SUFFIX is what follows. No filler, no repeated words.
Sizes are named for the prompt tokens they land on, which the SERVER reports — never chars/4.
"""
import pathlib
import sys

REPO = pathlib.Path(sys.argv[1]).resolve()
OUT = pathlib.Path(sys.argv[2]).resolve()
SRC = (REPO / "scripts/bench/laptop-llm.py").read_text(encoding="utf-8")

TEMPLATE = """Complete the code between [PREFIX] and [SUFFIX], and output only the completion.

[PREFIX]
```python
{prefix}
```
[SUFFIX]
```python
{suffix}
```
"""

TOY = dict(name="gap", prefix="x = a ", suffix=" + b")
# Code-shape ladder: the cursor sits at a real line boundary in a real file; ~3.5 chars/token on code,
# so the char counts below are aimed at ~1k / ~4k / ~7k prompt tokens (the server reports the real one).
CODE = [dict(cut=800, tail=1_200), dict(cut=1_900, tail=1_200), dict(cut=3_400, tail=1_200),
        dict(cut=13_500, tail=1_200), dict(cut=24_500, tail=1_200)]

manifest = []
toy = TEMPLATE.format(**{k: TOY[k] for k in ("prefix", "suffix")})
(OUT / f"100-fim-shape-{TOY['name']}.txt").write_text(toy, encoding="utf-8")
manifest.append((TOY["name"], len(toy)))
for c in CODE:
    if c["cut"] + c["tail"] > len(SRC):
        sys.exit(f"cursor {c['cut']}+{c['tail']} past end of source ({len(SRC)} chars)")
    body = TEMPLATE.format(prefix=SRC[:c["cut"]], suffix=SRC[c["cut"] + 1:c["cut"] + 1 + c["tail"]])
    (OUT / f"100-fim-shape-cut{c['cut']}.txt").write_text(body, encoding="utf-8")
    manifest.append((f"cut{c['cut']}", len(body)))

print("template:\n" + TEMPLATE.replace("{prefix}", "<prefix>").replace("{suffix}", "<suffix>"))
for n, size in manifest:
    print(f"  {n:<10} {size:>7} chars")
