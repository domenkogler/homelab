#!/usr/bin/env python3
"""port_v33.py — the counted porter of the spark-profile-fast-v33 lineage.

WHY THIS EXISTS INSTEAD OF A RUN OF `sed -i` LINES
    A `sed -i` that matches nothing exits 0. A build made of those exits 0 too, and the image it
    produces boots normally while carrying none of the behaviour the patch set was supposed to buy.
    The v32 window learned the second half of that lesson the expensive way: upstream's MoE clone
    patcher asserts EXACTLY TWO `expert_data.copy_(loaded_weight)` sites, our live image carries five
    and the v32 image four — an assert widened to "at least one" would have patched two of five sites
    and called the build green.

WHAT IT DOES
    It reads a plan (`patch-plan.json`, rendered by the role from
    `spark_profile_fast_v33_patch_plan`), and for every entry: counts the anchor in the file AS IT IS
    IN THE BASE IMAGE, refuses if that count is not the number the plan declares, runs the entry's
    command, then counts the entry's MARKER in the file it just wrote. Nothing is applied on a
    mismatch, and a plan entry without a marker is refused as unsound rather than trusted.

    Before/after is measured against the BASE's own text. It never compares against a snapshot of a
    day-0 file dropped on top of the new one — that is the shape of a port that silently reverts a
    base fix (the v32 report's §7 finding, and the reason this file does not accept a `--from` tree).

MODES
    count   read-only: print the anchor table for the tree it is pointed at, and exit 0/1
    apply   perform the plan, refusing on the first mismatch
    verify  read-only: assert every marker is present (the mid-build self-check)

    --root <dir>      the python tree to work on (default $VLLM_ROOT, then
                      /usr/local/lib/python3.12/dist-packages/vllm)
    --plan <file>     the plan (default /port/patch-plan.json, then ./patch-plan.json)
    --force-counts    NOT provided, on purpose: an override that makes a mismatch pass would remove
                      the only thing this tool is for.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys

DEFAULT_ROOTS = [
    os.environ.get("VLLM_ROOT", ""),
    "/usr/local/lib/python3.12/dist-packages/vllm",
]


def die(msg: str) -> "None":
    sys.stderr.write("port_v33: %s\n" % msg)
    raise SystemExit(1)


def resolve_root(argv: list) -> str:
    if "--root" in argv:
        return argv[argv.index("--root") + 1]
    for cand in DEFAULT_ROOTS:
        if cand and os.path.isdir(cand):
            return cand
    die("no vLLM tree found: pass --root, or set VLLM_ROOT")
    return ""      # unreachable; die() exits


def resolve_plan(argv: list) -> dict:
    path = argv[argv.index("--plan") + 1] if "--plan" in argv else ""
    for cand in [path, "/port/patch-plan.json", "./patch-plan.json"]:
        if cand and os.path.isfile(cand):
            with open(cand, encoding="utf-8") as fh:
                return json.load(fh)
    die("no plan found. The plan is IaC data (spark_profile_fast_v33_patch_plan in "
        "roles/spark-profile-fast-v33/defaults/main.yml) rendered into patch-plan.json by the role; "
        "an empty plan must never reach a build at all.")
    return {}


def read(path: str) -> str:
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def count(text: str, needle: str) -> int:
    return text.count(needle)


def fingerprint(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:12]


def check_shape(plan: list) -> None:
    for ent in plan:
        for key in ("name", "path", "pattern", "marker", "cmd"):
            if key not in ent or ent[key] in (None, ""):
                die("plan entry %r is missing %r" % (ent.get("name", "?"), key))
        if not isinstance(ent["expect"], int):
            die("plan entry %r has expect=%r; it must be an integer read from the base at this "
                "digest, not a guess" % (ent["name"], ent["expect"]))


def table(plan: list, root: str, show_after: bool = False) -> int:
    bad = 0
    for ent in plan:
        path = os.path.join(root, ent["path"])
        if not os.path.isfile(path):
            print("MISSING  %-22s %s (file not in this tree)" % (ent["name"], ent["path"]))
            bad += 1
            continue
        text = read(path)
        got = count(text, ent["pattern"])
        mark = count(text, ent["marker"])
        line = ("  %-22s anchor %3d (plan %3d)  marker %3d  %s"
                % (ent["name"], got, ent["expect"], mark, os.path.basename(ent["path"])))
        if show_after:
            line += "  sha %s" % fingerprint(text)
        # show_after (the verify leg) grades the MARKER only: the anchor is the
        # pre-state, and a sed that did its job legitimately deletes it (the fla
        # lines). Re-asserting the anchor here would fail an edit that landed.
        ok = (mark >= 1) if show_after else (got == ent["expect"])
        print(("OK     " if ok else "BAD    ") + line)
        if not ok:
            bad += 1
    return bad


def main() -> int:
    argv = sys.argv[1:]
    mode = argv[0] if argv and not argv[0].startswith("--") else "count"
    if mode not in ("count", "apply", "verify"):
        die("unknown mode %r (count | apply | verify)" % mode)

    root = resolve_root(argv)
    plan = resolve_plan(argv).get("edits", [])
    if not plan:
        die("the rendered plan carries no edits")
    check_shape(plan)
    print("port_v33: mode=%s root=%s entries=%d" % (mode, root, len(plan)))

    if mode == "count":
        bad = table(plan, root)
        print("port_v33: %d/%d anchors match the plan" % (len(plan) - bad, len(plan)))
        if bad:
            print("port_v33: READ each site the count disagrees about and restate the plan. Do not "
                  "widen an upstream patcher's assert to make a count pass: a host-to-device expert "
                  "copy you did not patch is a silent behaviour change.")
        return 1 if bad else 0

    if mode == "verify":
        bad = table(plan, root, show_after=True)
        print("port_v33: %d/%d markers present" % (len(plan) - bad, len(plan)))
        return 1 if bad else 0

    # apply: refuse to touch a tree whose counts were not read first, then edit entry by entry.
    bad = table(plan, root)
    if bad:
        die("refusing to apply: %d anchor count(s) do not match the plan in THIS base. Re-take the "
            "census and restate the plan; the build has written nothing." % bad)

    for ent in plan:
        path = os.path.join(root, ent["path"])
        before = fingerprint(read(path))
        env = dict(os.environ, VLLM_FILE=path, VLLM_ROOT=root,
                   ANCHOR_PATTERN=ent["pattern"], MARKER=ent["marker"])
        proc = subprocess.run(["bash", "-ec", ent["cmd"]], env=env)
        if proc.returncode != 0:
            die("entry %r exited %d; nothing else applied" % (ent["name"], proc.returncode))
        text = read(path)
        if fingerprint(text) == before:
            die("entry %r changed no bytes in %s (the command matched nothing)" % (ent["name"], path))
        if count(text, ent["marker"]) < 1:
            die("entry %r changed %s but left no marker %r — the build could not later prove it ran"
                % (ent["name"], path, ent["marker"]))
        print("  applied %-22s %s -> %s" % (ent["name"], before, fingerprint(text)))

    bad = table(plan, root, show_after=True)
    if bad:
        die("%d marker(s) missing after apply" % bad)
    print("port_v33: applied %d entries, every marker present" % len(plan))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
