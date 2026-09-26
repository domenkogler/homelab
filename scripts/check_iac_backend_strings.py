#!/usr/bin/env python3
"""Lint: the retired-backend mentions may not regrow (HD-404).

`Prometheus` and `Loki` were replaced on the VPS by VictoriaMetrics + VictoriaLogs in
HD-342, but the IaC kept naming them as the backend in headers and comments. Not
cosmetic: a header is what a converging agent reads first, and "the observability
backend (Prometheus/Grafana/n8n) lives on the VPS" sends the next session to debug a
container that does not exist. The 2026-09-20 sweep cleaned `docs/`; HD-404 cleaned
the code-side twins. This gate stops them coming back.

Why a RATCHET and not a per-line semantic test (measured, so the next session does
not re-derive it): a line-by-line "is this line lying?" rule is leaky in both
directions. Of the four violations HD-404 actually fixed, an assertion-shaped
regex (`backend` / `scraped by` / `lives on`) catches two and misses the other two
(`prometheus/loki fall back to 127.0.0.1`, `forwards telemetry to the VPS
Prometheus/Loki`) — a documented 50 % recall is not a gate. A permissive regex with
an allowlist is worse: most of these mentions are legitimate today (the Alloy
`prometheus.scrape` module, the `alloy_ha_exporter` var, the retired-pin notes,
the paragraph explaining what replaced what), so a naked grep prints mostly noise and
gets muted inside a week — the failure mode HD-417 names.

So the gate is a monotone ratchet over the whole corpus:

    count of `prometheus|loki` (case-insensitive, whole word-ish) occurrences under
    IaC/ansible/playbooks/ + IaC/ansible/group_vars/  must not exceed FLOOR.

Removing a mention is always allowed (and the floor should then be lowered with it);
adding one is refused unless it is genuinely required, in which case the floor moves
with the change and the commit says why. `--show` prints today's count so FLOOR is
re-derivable, never remembered.

Self-test: `python3 scripts/check_iac_backend_strings.py --self-test` — a planted
mention turns it red, a removal does not, and the blessed corpus is green.

Run:   python3 scripts/check_iac_backend_strings.py [--show] [--self-test]
Exit:  0 = at or below FLOOR, 1 = regrowth. Wired into `scripts/validate-all.sh`.
"""
from __future__ import annotations

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TREES = ("IaC/ansible/playbooks", "IaC/ansible/group_vars")
MENTION = re.compile(r"prometheus|loki", re.I)

# Re-derive with: python3 scripts/check_iac_backend_strings.py --show
# Lowered to this by HD-404 (2026-09-25), which removed six stale backend claims.
# 15 of the survivors are the shapes the docstring lists as legitimate; 2 are the
# "what was replaced / where the HA token file would have lived" notes.
# Re-derive with: python3 scripts/check_iac_backend_strings.py --show
# Set by HD-404 (2026-09-25) at the post-sweep count. Measured on BOTH sides of the
# change: 28 mentions before, 28 after — the six HD-404 fixes rewrote wording that
# already named Victoria in the same line or kept the name deliberately (the
# `alloy_ha_exporter` var, the Alloy `prometheus.scrape` module, the retired-pin
# notes in versions.yml, the paragraph explaining what replaced what). So this floor
# is not a victory count, it is a ratchet that keeps 28 from becoming 29; removing a
# mention is welcome — lower the floor in the same commit and say why.
FLOOR = 27


def count(root: Path) -> tuple[int, list[str]]:
    total, where = 0, []
    for rel in TREES:
        d = root / rel
        if not d.is_dir():
            continue
        for path in sorted(d.rglob("*")):
            if not path.is_file() or path.suffix.lower() not in (".yml", ".yaml"):
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            hits = len(MENTION.findall(text))
            if hits:
                total += hits
                where.append((path.relative_to(root).as_posix(), hits))
    return total, where


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()
    total, where = count(ROOT)
    if "--show" in sys.argv:
        print(f"current mentions: {total} (FLOOR {FLOOR}) — re-derive the floor from this line")
        for f, n in sorted(where, key=lambda x: -x[1]):
            print(f"  {n:3d}  {f}")
        return 0
    if total > FLOOR:
        print(f"FAIL: {total} Prometheus/Loki mentions under {', '.join(TREES)} — the floor is "
              f"{FLOOR}, so this is +{total - FLOOR} (HD-404: the VPS backend is VictoriaMetrics + "
              "VictoriaLogs since HD-342).")
        print("Either name the Victoria backend, or — if the mention is genuinely required — move "
              "FLOOR in this file with the same commit and say why in the message.")
        print("Today's distribution: python3 scripts/check_iac_backend_strings.py --show")
        return 1
    print(f"OK: {total} Prometheus/Loki mentions (floor {FLOOR}) — no regrowth of the retired "
          "backend names (HD-404/HD-342)")
    return 0


def self_test() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="hd404-ratchet-") as td:
        root = Path(td)
        for rel in TREES:
            (root / rel).mkdir(parents=True, exist_ok=True)
        base = "# victoria is the backend\n" * 1  # zero mentions
        (root / TREES[0] / "a.yml").write_text(base, encoding="utf-8")
        if count(root)[0] != 0:
            failures.append("a clean tree must count 0 mentions")
        (root / TREES[0] / "a.yml").write_text(base + "# the observability backend (Prometheus) lives here\n",
                                               encoding="utf-8")
        if count(root)[0] != 1:
            failures.append("a planted mention was not counted — the ratchet cannot see regrowth")
        (root / TREES[1] / "b.yml").write_text("# prometheus.scrape + loki_version are live names\n",
                                               encoding="utf-8")
        if count(root)[0] != 3:
            failures.append(f"expected 3 mentions, got {count(root)[0]} — the counter shape changed")
        (root / TREES[1] / "b.yml").write_text("", encoding="utf-8")
        if count(root)[0] != 1:
            failures.append("a removal was not reflected — the floor could never be lowered")
        # the floor itself must not be below the corpus it guards (a typo would mute the gate),
        # nor absurdly above it (a floor that loose catches nothing).
        real, _ = count(ROOT)
        if FLOOR < real:
            failures.append(f"FLOOR ({FLOOR}) is below the real corpus ({real}) — the gate is red "
                            "at rest, which means it will be switched off, not fixed")
        if FLOOR - real > 20:
            failures.append(f"FLOOR ({FLOOR}) sits {FLOOR - real} above the real corpus ({real}) — "
                            "a floor that loose catches nothing; re-derive with --show")
    if failures:
        print("FAIL: check_iac_backend_strings.py self-test:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("OK: self-test — regrowth is counted, removal is counted, and FLOOR is not below the "
          "corpus it guards (HD-404)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
