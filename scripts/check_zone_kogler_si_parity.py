#!/usr/bin/env python3
"""HD-436 parity gate — the derived ``zone_kogler_si`` must answer EXACTLY what the
hand-authored sources answered (docs/network-dns.md §The answer-plane model).

``scripts/zone_kogler_si_render.py`` renders the THREE REAL consumers (the Technitium
seed task, the headscale ``config.yaml.j2``, the ``cloudflare_dns`` role task) into one
normalized shape; ``scripts/testdata/zone_kogler_si_golden.json`` is that shape captured
from the sources BEFORE the derivation (and the capture script refuses to regenerate it
once ``zone_kogler_si`` exists, so the fixture cannot be made self-fulfilling).

This script is the gate over the two: any dropped name, re-pointed address, or name moved
between the plain and the ``.ts`` namespace is RED here rather than an NXDOMAIN at 3am.
A deliberate change is allowed, but only out loud: read the diff it prints and land the
new fixture in the SAME commit, or the gate stays red.

Fail-loud by construction (HD-65 — a gate that passes vacuously is not a gate):
  * an empty answer plane, a missing consumer, or a zero-count consumer is an ERROR;
  * a golden field the projection drops must be listed in ``DROPPED_KEYS`` AND be empty
    in the fixture — a live value may never be projected away to make a diff go green.

Run ``--self-test`` to see it refuse the shapes it exists to refuse.

Wired into ``scripts/validate-all.sh``. Nothing here contacts a host or reads the vault.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import zone_kogler_si_render as zr  # noqa: E402

GOLDEN_PATH = zr.GOLDEN_PATH
# Golden fields the normalized shape does not carry, with the reason each is not a live
# answer-plane field. A golden value that is NOT empty under a dropped key is a hard error.
DROPPED_KEYS = {
    # The fixture captured the pre-change *loop item*, which carried an empty `state`.
    # The consumer is the task, and render_cloudflare() asserts the task pins
    # `state: present`, so an empty item-level state describes nothing live.
    "state": "task pins state: present (asserted in render_cloudflare)",
}
MAX_PRINTED = 12


class ParityError(RuntimeError):
    pass


def _project(row: dict, where: str) -> dict:
    out = {}
    for key, value in row.items():
        if key in DROPPED_KEYS:
            if str(value).strip():
                raise ParityError(
                    f"{where}: golden carries a NON-empty {key}={value!r} that the "
                    f"projection would drop ({DROPPED_KEYS[key]}) — project it or don't"
                )
            continue
        out[key] = value
    return out


def _rows(payload, path: str) -> list[dict]:
    if not isinstance(payload, list):
        raise ParityError(f"{path}: expected a list, got {type(payload).__name__}")
    if not payload:
        raise ParityError(f"{path}: ZERO records — an empty answer plane is never a pass")
    return [_project(r, path) for r in payload]


def _sets(payload, path: str) -> set[str]:
    return {json.dumps(r, sort_keys=True) for r in _rows(payload, path)}


def _surfaces(golden: dict, current: dict) -> list[tuple[str, set[str], set[str]]]:
    """(label, golden set, current set) for every consumer the fixture covers."""
    out: list[tuple[str, set[str], set[str]]] = []
    for inst in zr.INSTANCES:
        try:
            out.append((f"technitium.{inst}",
                        _sets(golden["technitium"][inst], f"golden.technitium.{inst}"),
                        _sets(current["technitium"][inst], f"current.technitium.{inst}")))
        except KeyError as exc:
            raise ParityError(f"fixture or render is missing technitium instance {inst} ({exc})") from exc
    for key in ("plain", "ts_only"):
        try:
            out.append((f"headscale:{key}",
                        _sets(golden["headscale"][key], f"golden.headscale.{key}"),
                        _sets(current["headscale"][key], f"current.headscale.{key}")))
        except KeyError as exc:
            raise ParityError(f"fixture or render is missing headscale.{key} ({exc})") from exc
    out.append(("cloudflare",
                _sets(golden["cloudflare"], "golden.cloudflare"),
                _sets(current["cloudflare"], "current.cloudflare")))
    return out


def compare(golden: dict, current: dict) -> list[str]:
    findings = []
    for label, g, c in _surfaces(golden, current):
        lost, gained = g - c, c - g
        if not lost and not gained:
            continue
        findings.append(f"{label}: golden {len(g)} vs derived {len(c)}")
        for row in sorted(lost)[:MAX_PRINTED]:
            findings.append(f"    LOST   {row}")
        for row in sorted(gained)[:MAX_PRINTED]:
            findings.append(f"    ADDED  {row}")
        if len(lost) > MAX_PRINTED:
            findings.append(f"    … and {len(lost) - MAX_PRINTED} more LOST")
        if len(gained) > MAX_PRINTED:
            findings.append(f"    … and {len(gained) - MAX_PRINTED} more ADDED")
    return findings


def main() -> int:
    try:
        golden = json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: cannot read the fixture {GOLDEN_PATH}: {exc}", file=sys.stderr)
        return 1
    try:
        current = zr.render_all()
    except zr.RenderError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    counts = {f"technitium:{i}": len(current["technitium"][i]) for i in zr.INSTANCES}
    counts.update({f"headscale:{k}": len(v) for k, v in current["headscale"].items()})
    counts["cloudflare"] = len(current["cloudflare"])
    golden_counts = golden.get("counts", {})
    drift_counts = {k: n for k, n in counts.items() if golden_counts.get(k) != n}

    findings = compare(golden, current)
    if findings or drift_counts:
        print("FAIL: the derived zone does not answer what the hand-authored sources answered",
              file=sys.stderr)
        if drift_counts:
            print("  count drift (golden vs derived): "
                  + ", ".join(f"{k}: {golden_counts.get(k)}→{n}" for k, n in sorted(drift_counts.items())),
                  file=sys.stderr)
        for line in findings:
            print(line, file=sys.stderr)
        print("\nEither fix zone_kogler_si, or make the change deliberately: review this "
              "diff, then re-derive the fixture in the SAME commit — and say why in the "
              "commit message.", file=sys.stderr)
        return 1

    print("OK: zone_kogler_si answers identically to the hand-authored sources — "
          + ", ".join(f"{k}={counts[k]}" for k in sorted(counts)))
    return 0


def self_test() -> int:
    """The gate must refuse the shapes it was written for. A gate that cannot fail is not evidence."""
    golden = json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))
    current = zr.render_all()
    cases = []

    # 1. clean render == fixture
    cases.append(("baseline green", not compare(golden, json.loads(json.dumps(current)))))

    # 2. a dropped name (the exact class: a name in one consumer and not another)
    mutated = json.loads(json.dumps(current))
    for inst in zr.INSTANCES:
        mutated["technitium"][inst] = [r for r in mutated["technitium"][inst]
                                       if r["name"] != "ha.kogler.si"]
    cases.append(("dropping ha.kogler.si is RED", bool(compare(golden, mutated))))

    # 3. a re-pointed address answers a different IP — same names, still RED
    mutated = json.loads(json.dumps(current))
    for inst in zr.INSTANCES:
        for row in mutated["technitium"][inst]:
            if row["name"] == "sso.kogler.si":
                row["ip"] = "10.10.10.10"
    cases.append(("re-pointing sso to a LAN IP is RED", bool(compare(golden, mutated))))

    # 4. moving a .ts-only name into the plain namespace (the HD-382/389 trap)
    mutated = json.loads(json.dumps(current))
    moved = [r for r in mutated["headscale"]["ts_only"] if r["name"].startswith("spark.")]
    if not moved:
        raise ParityError("self-test found no spark .ts record to move — the fixture changed shape")
    mutated["headscale"]["ts_only"] = [r for r in mutated["headscale"]["ts_only"] if r not in moved]
    mutated["headscale"]["plain"].append({**moved[0], "name": moved[0]["name"].replace(".ts.", ".")})
    cases.append(("a .ts-only name published plainly is RED", bool(compare(golden, mutated))))

    # 5. an empty plane must be an error, never a pass
    try:
        _sets({"technitium": []}, "x")
        cases.append(("an empty plane raises", False))
    except ParityError:
        cases.append(("an empty plane raises", True))

    # 6. a live value may not be projected away to silence a diff
    try:
        _project({"record": "x", "state": "proxied"}, "fixture")
        cases.append(("a non-empty dropped key raises", False))
    except ParityError:
        cases.append(("a non-empty dropped key raises", True))

    failed = [name for name, ok in cases if not ok]
    for name, ok in cases:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    if failed:
        print(f"SELF-TEST FAILED: {', '.join(failed)}", file=sys.stderr)
        return 1
    print(f"self-test OK ({len(cases)} cases)")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv[1:]:
        sys.exit(self_test())
    sys.exit(main())
