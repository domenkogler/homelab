#!/usr/bin/env python3
"""Capture the ``kogler.si`` golden set (HD-436 step 1) — BEFORE the derivation lands.

Writes ``scripts/testdata/zone_kogler_si_golden.json``: the record set the THREE
hand-authored sources render today (Technitium per instance, headscale plain list,
headscale ``.ts``-only list, the public Cloudflare set). The parity checker
(``check_zone_kogler_si_parity.py``) compares the DERIVED output against this file, so
the derivation's promise — "one derived list, no name added, dropped or re-pointed" —
is checked against a snapshot taken while the old sources were still the truth.

Run it exactly once, while the hand-authored lists are still in place:

    python3 scripts/capture_zone_kogler_si_golden.py

A second run REFUSES: after the derivation, re-capturing would compare the derived list
against itself and the parity gate would be self-fulfilling.

No host is contacted, no vault is read. Exit 0 = fixture written, 1 = refused/failed.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from zone_kogler_si_render import (  # noqa: E402
    INSTANCES,
    GOLDEN_PATH,
    RenderError,
    is_derived,
    render_all,
)


def main() -> int:
    if is_derived():
        print(
            f"REFUSED: {GOLDEN_PATH.name} can only be captured while the zone is hand-authored "
            "(the seed's inline loop + tailnet_subdomains + tailnet_ts_only_subdomains + "
            "cloudflare_dns_records). 'zone_kogler_si' is already present in "
            "IaC/ansible/group_vars/all/main.yml, so a capture now would compare the derived "
            "list against itself. The committed fixture is the snapshot — do not regenerate it.",
            file=sys.stderr,
        )
        return 1

    try:
        data = render_all()
    except RenderError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    counts = {
        **{f"technitium:{inst}": len(rows) for inst, rows in data["technitium"].items()},
        "headscale:plain": len(data["headscale"]["plain"]),
        "headscale:ts_only": len(data["headscale"]["ts_only"]),
        "cloudflare": len(data["cloudflare"]),
    }
    # A zero anywhere here would make the fixture a silently useless baseline.
    empty = [k for k, n in counts.items() if n == 0]
    if empty:
        print(f"FAIL: rendered zero records for: {', '.join(sorted(empty))}", file=sys.stderr)
        return 1

    payload = {
        "_comment": (
            "Golden answer-plane set for the kogler.si zone, captured from the HAND-AUTHORED "
            "sources before HD-436 step 1 (one derived list) replaced them. Regenerating this "
            "from the derived list is self-fulfilling and is refused by "
            "capture_zone_kogler_si_golden.py. Every zone change must re-derive it on purpose: "
            "review the diff, then land the new fixture and the change in ONE commit."
        ),
        "counts": counts,
        **data,
    }
    GOLDEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"WROTE: {GOLDEN_PATH.relative_to(GOLDEN_PATH.parents[2])}")
    for key in sorted(counts):
        print(f"  {key}: {counts[key]}")
    print(f"instances: {', '.join(INSTANCES)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
