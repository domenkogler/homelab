#!/usr/bin/env python3
"""HD-436 parity gate — the derived ``zone_kogler_si`` must answer EXACTLY what the
hand-authored sources answered (docs/network-dns.md §The answer-plane model).

``scripts/ansible/zone_kogler_si_render.py`` renders the THREE REAL consumers (the Technitium
seed task, the headscale ``config.yaml.j2``, the ``cloudflare_dns`` role task) into one
normalized shape; ``scripts/testdata/zone_kogler_si_golden.json`` is that shape captured
from the sources BEFORE the derivation (and the capture script refuses to regenerate it
once ``zone_kogler_si`` exists, so the fixture cannot be made self-fulfilling).

This script is the gate over the two: any dropped name, re-pointed address, or name moved
between the plain and the ``.ts`` namespace is RED here rather than an NXDOMAIN at 3am. Headscale
renders its MagicDNS records through ONE of two mutually exclusive keys -- the ``dns.extra_records``
block and the ``dns.extra_records_path`` file -- so BOTH shapes are rendered and compared against the
same fixture, and a config that emits both keys, or a path the compose bind does not provide, is a
hard error: either one is a control plane that exits at startup while ``docker`` calls it ``Running``.
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

# HD-1118 Stage 1: the renderer is found by NAME. These two files are headed for
# different folders in Stage 3 (checker → gate/, renderer → ansible/), and a
# same-directory import would then fail in whichever way the gate does not see.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import script_path as _hl_script_path  # noqa: E402
sys.path.insert(0, str(_hl_script_path("zone_kogler_si_render.py", __file__).parent))

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
        # The SAME golden rows must come out of the `dns.extra_records_path` shape: the swap moves
        # the file, never an answer, and the fixture is shape-independent by design. A surface that
        # no render feeds would pass vacuously, so `zone_kogler_si_render.render_all` renders it.
        try:
            out.append((f"headscale_file:{key}",
                        _sets(golden["headscale"][key], f"golden.headscale.{key}"),
                        _sets(current["headscale_file"][key], f"current.headscale_file.{key}")))
        except KeyError as exc:
            raise ParityError(f"render is missing headscale_file.{key} ({exc})") from exc
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
    # `headscale_file:*` is deliberately absent from the count table: it is the same records through
    # the other dns key, so a fixture number for it would be a second, hand-typed copy of a number
    # the fixture already carries. Its parity is the set diff in compare(), not a count.
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
          + ", ".join(f"{k}={counts[k]}" for k in sorted(counts))
          + f", headscale_file={sum(len(v) for v in current['headscale_file'].values())}"
            " (records-file shape)")
    return 0


def _raises(fn, *args) -> bool:
    """True iff `fn(*args)` raises the renderer's error — the shape every canary below asserts."""
    try:
        fn(*args)
    except zr.RenderError:
        return True
    return False


def _render_with_field(zone: list, name: str, field: str, value) -> dict:
    """Re-render EVERY consumer with one field of one `zone_kogler_si` entry changed.

    The flag flip must be tested at the SOURCE rather than in a mutated render: mutating a render
    proves the diff works, mutating the list proves the consumers still read the list.
    """
    original = zr._raw_vars

    def patched():
        raw = original()
        raw["zone_kogler_si"] = [dict(e, **{field: value}) if e.get("name") == name else e
                                 for e in raw["zone_kogler_si"]]
        return raw

    zr._raw_vars = patched
    try:
        return zr.render_all()
    finally:
        zr._raw_vars = original


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

    # 7. the `dns.extra_records_path` shape must be a REAL surface: mutate only the records-file
    #    render and the gate has to notice. A surface nothing feeds would sit green forever.
    mutated = json.loads(json.dumps(current))
    dropped = [r for r in mutated["headscale_file"]["ts_only"] if r["name"].startswith("pi-oldsrv.")]
    if not dropped:
        raise ParityError("self-test found no pi-oldsrv .ts record in the file shape — the render changed shape")
    mutated["headscale_file"]["ts_only"] = [r for r in mutated["headscale_file"]["ts_only"] if r not in dropped]
    cases.append(("the extra_records_path shape losing a name is RED",
                  bool(compare(golden, mutated))))

    # 8. the two shapes answer the same rows in the same order — canary: feed the probe a pair that
    #    differs only in ORDER, the one thing a set diff cannot see.
    cases.append(("a re-ordered records file is refused", _raises(
        zr.require_same_records, current["headscale"]["plain"][::-1], current["headscale"]["plain"], "fixture")))

    # 9. ⛔ the shape that kills the control plane: both record keys at once. `docker` reports such a
    #    container Running, so this probe is the only thing between the tree and a crash loop.
    cases.append(("both dns record keys at once is refused", _raises(
        zr._dns_record_key,
        {"extra_records": [{"name": "x.kogler.si"}], "extra_records_path": "/etc/headscale/extra_records.yaml"},
        "fixture")))

    # 10. `extra_records_path` must name the path the compose bind provides — a path that is not
    #     mounted is a fatal config that still reports Running.
    cases.append(("a records path the bind does not provide is refused", _raises(
        zr._headscale_rows, zr.build_context(extra={"headscale_extra_records_path": "/etc/headscale/nowhere.yaml"}),
        "default")))

    # 11. the flag flips themselves, at the SOURCE: one field of one `zone_kogler_si` entry changed,
    #     re-rendered through every consumer. This is what proves the swap did not stop the answer
    #     plane reading the list — a flipped flag must still turn the matching surface RED in BOTH
    #     record shapes. `edge → node` is used because it is a LEGAL zone state (`edge → none` would
    #     leave `ts_router: true` on a name with no router, which another validator exists to refuse).
    zone = zr._raw_vars()["zone_kogler_si"]
    edge = next((e["name"] for e in zone if e.get("tailnet") == "edge"), None)
    published = next((e["name"] for e in zone if e.get("public")), None)
    if not edge or not published:
        raise ParityError("self-test found no `tailnet: edge` / `public: true` entry to flip — the zone changed shape")
    findings = compare(golden, _render_with_field(zone, edge, "tailnet", "node"))
    cases.append((f"flipping {edge} tailnet edge→node reddens both headscale shapes",
                  all(any(f.startswith(f"{s}:") for f in findings)
                      for s in ("headscale:plain", "headscale_file:plain"))))
    findings = compare(golden, _render_with_field(zone, published, "public", False))
    cases.append((f"flipping {published} public→false reddens the public surface",
                  any(f.startswith("cloudflare:") for f in findings)))

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
