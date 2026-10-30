#!/usr/bin/env python3
"""contain-leaked-values.py — lower the copy count of a value this fleet CANNOT rotate (HD-1218).

WHY THIS EXISTS, and the sentence it must never be confused with. Most leak debts close by rotating:
the value moves, every old copy becomes a dead byte, and the register line goes `CLOSED`. A few do not
have that option — `pppoe_login` is provisioned by an ISP, the Soulseek network account's reset mail
never arrives — and for those, "rotate and forget it" is not an answer, so the copies stay readable
forever. This tool is the act that is left: **exposure reduction, never closure**
(docs/deployment-secrets.md §Creation & Rotation Workflow; docs/deployment-rejected.md, where the owner
overrode the no-transcript-edit half of HD-1181 precisely so this act could exist). A debt line SURVIVES
a redaction, and `check_secret_leak.py` prints such a pair `CONTAINED` — never `STALE`, never `OK` —
because a redaction that reads as a rotation is the one thing that ledger's own header forbids.

MANUAL INVOCATION ONLY. This is not a `validate-all.sh` item and never an automatic sweep: a scrubber
that runs by itself is how a tool that rewrites a seat's transcripts becomes invisible. `--dry-run` is
the DEFAULT and changes nothing; `--apply` is the act.

THE SCOPE IS DERIVED, NEVER TYPED — from the register's `path: none` column
(`scripts/gate/secret_debt_register.txt`), the fleet's machine-readable statement of "no rotation path
exists at either end". Two rules follow from that, and both are enforced here:
  * ⛔ `NOT_AUTO_ROTATABLE` is NOT the scope. That set is the auto-rotation ORDERING guard — it asserts
    only that a vault-only `--rotate` would leave the FAR END on the old value — and most of its members
    ARE rotatable by a lane through that far end. Redacting something that could simply have been
    rotated would hide a live credential behind a scrub. The scope is the item-level ruling, which is
    the same ruling `NOT_ROTATABLE` states in `scripts/secrets/provision-secrets.py`; when the two
    disagree this tool REFUSES, because two copies of one decision is the twin every gate here catches
    (`check_secret_debt.py` holds them equal on every run — this is that arm, at the moment of the act).
  * Replace BY VALUE, never by shape. The shape that has walked past every filter in this fleet is
    `KEY: "value"`, and an item's key name is not evidence of anything.

WHAT IT REFUSES TO TOUCH, and why each refusal is itself a leak of another kind:
  * anything under `.git/` — rewriting an object store rewrites history, a different decision with a
    different owner (HD-1170: rotation, not `filter-repo`);
  * the repo tree, `IaC/**` and rendered live config (`/srv/docker/**`, `config.xml`, `config.yaml`,
    `docker-compose*`, `.env`) — those are the SSOT and its render views, and scrubbing one breaks a
    service to make a check quieter;
  * `$SESSION_DIR`, the invoking session's own capture — a tool editing the file the harness is
    appending to is the fourth leak;
  * its own receipt.

WHAT IT PRINTS: item ids, counts, paths and verdict words. Never a value, never a length, never a
captured line — the same disclosure budget as the leak eye, or the instrument becomes the leak
(CONVENTIONS §6). The proof that a mask landed is the scanner's BEFORE/AFTER hit count, which prints no
value; run `check_secret_leak.py` on both sides of the act.

USE:
    python3 scripts/secrets/contain-leaked-values.py                 # dry run: what WOULD change
    python3 scripts/secrets/contain-leaked-values.py --apply         # do it, then append the receipt
    python3 scripts/secrets/contain-leaked-values.py --self-test     # fixture arms, ZERO vault requests
Exit: 0 nothing to contain, or the act was performed (a dry run counts as performed);
      1 a refusal (the two statements of the ruling disagree, every target refused, a write failed);
      2 environment boundary: no vault route, an unreadable register. Never a green.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
import tempfile
import time
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gate"))
from repo_root import root as _hl_root  # noqa: E402
import check_secret_debt as debt  # noqa: E402  (register reader, seat arm, guard cross-check — not re-spelled)
import check_secret_leak as leak  # noqa: E402  (store walk and needles — imported, not re-spelled)

ROOT = _hl_root(__file__)
MARKER = "[contained:{id8}]"
# The receipt is per-SEAT state, not repo content: it names paths on one machine, so it lives in the
# user's state dir and never in git. `check_secret_leak.py` reads it to print CONTAINED, and
# `$HL_CONTAINMENT_RECEIPT` is the seam that lets a fixture arm aim it (the role `$HL_LEAK_LEDGER`
# plays in the eye). RESOLVED PER CALL, never at import: a self-test that moves `$HOME` after import
# must not find itself writing the real seat's receipt — that mistake is what this file's first
# self-test run did, on this seat, on 2026-10-30.
def receipt_path() -> Path:
    return Path(os.environ.get("HL_CONTAINMENT_RECEIPT")
                or Path.home() / ".local" / "state" / "homelab" / "containment-receipt.jsonl")
# The eye's own size ceiling, so a 4 GB transcript cannot OOM this tool into a partial sweep.
MAX_BYTES = 64 * 1024 * 1024


class Refused(Exception):
    """The act was not performed. A refusal prints and reddens the run; it is never a quiet skip."""


# --------------------------------------------------------------------------- the scope
def none_scope(register: Path) -> list[debt.Line]:
    """The register's `path: none` lines — the debts with no rotation path at either end."""
    lines, bad = debt.read_register(register)
    if bad:
        raise Refused("; ".join(bad) + " — a malformed register line means the containment scope cannot "
                      "be read, and guessing it would redact the wrong item")
    return [ln for ln in lines if ln.path == "none"]


def scoped_items(none_lines: list[debt.Line], titles: dict[str, str]) -> dict[str, str]:
    """Resolve the `path: none` lines to vault items: full id -> title.

    The register carries an 8-char id prefix and the vault answers full ids, so the join is a prefix
    match. A line the vault cannot answer is a REFUSAL, not a skip: a book the vault does not answer is
    a book that was not re-derived, and containing "nothing" would print as a clean sweep."""
    out: dict[str, str] = {}
    for ln in none_lines:
        named = {iid: title for iid, title in titles.items() if iid.startswith(ln.item)}
        if not named:
            raise Refused(f"register line {ln.item} ({ln.cls}/{ln.seat}, v{ln.version}) names no item "
                          "the vault answered — the book is not re-derived")
        out.update(named)
    return out


def guard_agreement(scoped: dict[str, str]) -> list[str]:
    """The derived ruling against the stated one. Anything but agreement is a refusal.

    `path: none` resolved to TITLES is the derived statement (titles are the key `NOT_ROTATABLE` is
    written in); `NOT_ROTATABLE` in the provisioner is the stated one. Redacting an item the guard
    believes is rotatable would hide a live credential behind a scrub; leaving standing an item the
    register calls unrotatable would be a quieter lie."""
    derived = {title: iid[:8] for iid, title in scoped.items()}
    stated = debt.provision_not_rotatable()
    out = [f"{iid} carries `path: none` in the register and is absent from NOT_ROTATABLE in "
           f"scripts/secrets/provision-secrets.py — {title!r} may be rotatable, and a rotatable item "
           f"is rotated, not scrubbed" for title, iid in sorted(derived.items()) if title not in stated]
    out += [f"NOT_ROTATABLE states no rotation path for {t!r} and no register line carries `path: none` "
            f"for it — the debt is not in the book, so this tool has no scope for it"
            for t in sorted(stated - set(derived))]
    return out


# --------------------------------------------------------------------------- the refusals
def own_capture_roots() -> tuple[list[tuple[Path, str]], str | None]:
    """(this process's own capture directories, the run id its own scratch dir is named with).

    A tool editing the file the harness is appending to is the fourth leak, and `--self-test` must
    never touch a real seat's store — the first run of this file's self-test learned that the hard way
    on 2026-10-30 by rewriting its own lane's live scratch capture.

    `$SESSION_DIR` is the harness's own statement of the idea; `$PI_SESSION_FILE` is what a pi lane
    actually gets. From the latter: the transcript directory, and the run id embedded in its path, so
    the live scratch copy of the SAME run under `…/async-subagent-runs/<run id>/` is refused too."""
    dirs: list[tuple[Path, str]] = []
    run_id: str | None = None
    sd = os.environ.get("SESSION_DIR")
    if sd:
        dirs.append((Path(sd), "the invoking session's own capture directory ($SESSION_DIR)"))
    sf = os.environ.get("PI_SESSION_FILE")
    if sf:
        dirs.append((Path(sf).parent, "this session's own transcript ($PI_SESSION_FILE)"))
        m = re.search(r"/([^/]+)/run-\d+/", "/" + sf.replace("\\", "/"))
        if m:
            run_id = m.group(1)
    return dirs, run_id


def refused_because(path: Path, extra: Path | None = None) -> str | None:
    """Why this path must not be rewritten, or None when it is a fair target."""
    try:
        resolved = path.resolve()
    except OSError:
        return "a path that would not resolve"
    if ".git" in resolved.parts:
        return "a git object store (rewriting history is a different decision, with a different owner)"
    try:
        rel = resolved.relative_to(ROOT)
    except ValueError:
        rel = None
    if rel is not None:
        if rel.parts and rel.parts[0] == "IaC":
            return "the repo's own IaC — the SSOT, never a scrub target"
        return "the repo tree (CONVENTIONS §2: values live in IaC; a scrubbed repo is a broken deploy)"
    low = str(resolved).lower()
    for needle, why in (("/srv/docker/", "rendered live config — a service reads this file"),
                        ("config.xml", "live app config"),
                        ("config.yaml", "live app config"),
                        ("docker-compose", "rendered compose — a live far end"),
                        ("/.env", "a live environment file")):
        if needle in low:
            return why
    dirs, run_id = own_capture_roots()
    if extra is not None:
        dirs.append((extra, "the capture directory the caller named"))
    for root, why in dirs:
        try:
            root = root.resolve()
        except OSError:
            continue
        if resolved == root or root in resolved.parents:
            return why
    if run_id and run_id in resolved.parts:
        return f"this run's own live capture (run id {run_id})"
    if resolved == receipt_path().resolve():
        return "the containment receipt itself"
    return None


# --------------------------------------------------------------------------- the act
def contain(files: list[str], needles: dict[bytes, list[str]], scoped: set[str], apply_: bool,
            session_dir: Path | None = None) -> tuple[dict[str, dict], list[str], dict[str, int], list[str]]:
    """Replace every scoped value with a marker. Returns (per-item tally, refused paths, skipped counts).

    `needles` is the leak eye's own map (value bytes -> item ids), so the match is by CURRENT VALUE and
    nothing else. Longest needle first, so a value that contains another cannot leave a fragment of the
    shorter one inside the marker.

    A refusal is reported ONLY for a file that actually holds a scoped value: the refusal a human has to
    act on is "a copy lives where this tool may not go", not a list of every capture on the seat.
    Files this tool could not open are COUNTED, and the count is printed, because a copy inside one of
    them was not checked."""
    # A needle is in scope only when EVERY item carrying it is in scope: redacting a value that an
    # unrotatable and a rotatable item happen to SHARE would contain the rotatable one by accident,
    # and an item that can be rotated is rotated. Those are reported, never rewritten.
    included, shared = [], []
    for needle, ids in needles.items():
        if all(i in scoped for i in ids):
            included.append((needle, ids))
        elif any(i in scoped for i in ids):
            shared.append((needle, ids))
    included.sort(key=lambda kv: -len(kv[0]))
    ordered = included
    tally: dict[str, dict] = {}
    refusals: list[str] = []
    skipped = {"too_big": 0, "unreadable": 0}
    for path_str in files:
        path = Path(path_str)
        try:
            if path.stat().st_size > MAX_BYTES:
                skipped["too_big"] += 1
                continue
            data = path.read_bytes()
        except OSError:
            skipped["unreadable"] += 1
            continue
        if b"\0" in data[:8192]:
            continue  # binary: the eye does not call it a finding either
        found = [(needle, ids) for needle, ids in ordered if needle in data]
        if not found:
            continue
        why = refused_because(path, session_dir)
        if why:
            refusals.append(f"{path} — {why} — {len(found)} scoped value(s) live here and were NOT "
                            "touched")
            continue
        hits = 0
        ids_here: set[str] = set()
        for needle, ids in found:
            count = data.count(needle)
            id8 = next(i for i in ids if i in scoped)[:8]
            entry = tally.setdefault(id8, {"occurrences": 0, "paths": set()})
            entry["occurrences"] += count
            hits += count
            ids_here.add(id8)
            data = data.replace(needle, MARKER.format(id8=id8).encode())
        if hits == 0:
            continue
        if apply_:
            mode = path.stat().st_mode
            with open(path, "wb") as fh:
                fh.write(data)
            os.chmod(path, mode)
        for id8 in ids_here:
            tally[id8]["paths"].add(str(path))
    for entry in tally.values():
        entry["paths"] = sorted(entry["paths"])
    notes = [f"a value shared with {sorted({i[:8] for i in ids if i not in scoped})} is NOT redacted — "
             "the same bytes are carried by an item this tool has no scope for"
             for _needle, ids in shared]
    return tally, sorted(set(refusals)), skipped, notes


def write_receipt(rows: list[dict]) -> Path:
    dest = receipt_path()
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(dest), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, "a", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, sort_keys=True) + "\n")
    return dest


def run(register: Path, apply_: bool, home: Path | None, session_dir: Path | None,
        files: list[str] | None = None) -> int:
    """The act. `files` is a TEST SEAM, not a user knob: a fixture supplies its own file set so a
    self-test can never rewrite a real seat's captures (the leak eye always also reads `/tmp`, so
    pointing `$HOME` and `$TMPDIR` at a temp tree is not enough to isolate a run)."""
    none_lines = none_scope(register)
    if not none_lines:
        print("nothing to contain: the register carries no `path: none` line, and this tool's scope is "
              "derived from that column alone")
        return 0
    needles, titles, _short, errs, _vkey = leak.load_values()
    if errs:
        print(f"REFUSED: the vault read was PARTIAL ({errs[0]}) — containing against an incomplete "
              "value set can redact the wrong copy")
        return 1
    scoped = scoped_items(none_lines, titles)
    disagree = guard_agreement(scoped)
    if disagree:
        print("REFUSED — the register and the provisioner do not state the same no-rotation-path ruling:")
        for line in disagree:
            print(f"  {line}")
        print("Nothing was rewritten. A membership change is ONE commit on both sides "
              "(docs/deployment-secrets.md §Creation & Rotation Workflow).")
        return 1
    versions, _vt, route, vnote = debt.versions_and_titles()
    if vnote:
        print(vnote)
    session_root = (Path(os.environ["SESSION_DIR"]) if os.environ.get("SESSION_DIR") else session_dir)
    if files is None:
        stores = leak.capture_stores(home)
        files = leak.capture_files(home)
        print(leak.stores_note(stores))
    else:
        print(f"stores: file set supplied by the caller ({len(files)} file(s)) — the seat's own stores "
              "were NOT walked, which is a fixture seam, never a fleet verdict")
    print(f"scope: {len(scoped)} item(s) with no rotation path (versions off the {route} read) — "
          + ", ".join(sorted(f"{title}({iid[:8]})" for iid, title in scoped.items())))
    print(f"mode: {'APPLY — files WILL be rewritten' if apply_ else 'DRY RUN — nothing is written (the default)'}")

    tally, refusals, skipped, notes = contain(files, needles, set(scoped), apply_, session_root)
    for note in notes:
        print(f"note: {note}")
    if skipped["too_big"] or skipped["unreadable"]:
        print(f"note: {skipped['too_big']} file(s) over the ceiling and {skipped['unreadable']} unreadable "
              "file(s) were NOT checked — a copy inside one of them survives this run")
    for why in refusals[:10]:
        print(f"REFUSED path: {why}")
    if len(refusals) > 10:
        print(f"  … {len(refusals) - 10} more refused path(s), same rules")
    before = sum(e["occurrences"] for e in tally.values())
    if before == 0:
        print("before/after: 0 occurrence(s) for the contained set in the stores this seat can read — "
              "nothing to do")
        return 0
    print(f"before/after: {before} occurrence(s) across "
          f"{len({p for e in tally.values() for p in e['paths']})} file(s)")
    by_prefix = {iid[:8]: iid for iid in scoped}
    for id8, entry in sorted(tally.items()):
        iid = by_prefix[id8]
        verb = "redacted" if apply_ else "WOULD redact"
        print(f"  {id8} {scoped[iid]}: {entry['occurrences']} occurrence(s) in {len(entry['paths'])} "
              f"file(s) — {verb}")
        for p in entry["paths"][:5]:
            print(f"      {p}")
        if len(entry["paths"]) > 5:
            print(f"      … {len(entry['paths']) - 5} more file(s)")
    if not apply_:
        print("DRY RUN: no file was written and no receipt appended. Re-run with --apply.")
        return 0
    seat = debt.this_seat()
    rows = [{"item": id8, "class": "run-capture", "seat": seat, "paths": entry["paths"],
             "occurrences": entry["occurrences"],
             "vault_version": versions.get(by_prefix[id8]),
             "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "tool": "contain-leaked-values.py"}
            for id8, entry in sorted(tally.items())]
    dest = write_receipt(rows)
    print(f"receipt appended: {len(rows)} row(s) -> {dest} (0600, append-only)")
    print("The debt STAYS OPEN. `check_secret_leak.py` now prints CONTAINED for these pairs — never "
          "STALE, never OK. Rotation remains the only close, and these items have no rotation path.")
    return 0


# --------------------------------------------------------------------------- self-test
def self_test() -> int:
    """Fixture arms at ZERO vault requests: a minted vault, a minted register, a minted store."""
    fails = 0

    def check(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        fails += not ok
        print(f"  arm {label}: {'ok' if ok else 'FAIL'}{(' — ' + detail) if (detail and not ok) else ''}")
    canary = "CANARYvalue0123456789abcdefXYZ"
    rotatable = "ROTATABLEvalue0123456789ab"
    other = "OTHERcanary0123456789abcdefg"
    third = "THIRDcanary0123456789abcdefgh"
    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        # A minted vault whose titles cover EVERY member of the real NOT_ROTATABLE, so the equality
        # arm runs against the provisioner's own source and not a stub of it.
        fx = tdp / "vault.json"
        fx.write_text(json.dumps({"items": {
            "aaaa11112222333344445555": {"title": "pppoe_login", "version": 2, "fields": [
                {"id": "password", "label": "password", "value": canary}]},
            "cccc33334444555566667777": {"title": "soulseek_login", "version": 1, "fields": [
                {"id": "password", "label": "password", "value": other}]},
            "dddd44445555666677778888": {"title": "slskd_login", "version": 1, "fields": [
                {"id": "password", "label": "password", "value": third}]},
            "bbbb11112222333344446666": {"title": "wat_api", "version": 1, "fields": [
                {"id": "credential", "label": "credential", "value": rotatable}]},
        }}), encoding="utf-8")
        reg = tdp / "register.txt"
        reg.write_text("# book\naaaa1111\trun-capture\twsl\t2\tnone\tdocs/network-rejected.md\n"
                       "cccc3333\trun-capture\twsl\t1\tnone\tdocs/services-media.md\n"
                       "dddd4444\trun-capture\twsl\t1\tnone\tdocs/services-media.md\n",
                       encoding="utf-8")
        home = tdp / "home"
        store = home / ".pi" / "agent" / "sessions" / "wsl"
        store.mkdir(parents=True)
        cap = store / "session.jsonl"
        cap.write_text(f'{{"line": "pppoe is {canary} and the other is {rotatable}"}}\n', encoding="utf-8")
        live = tdp / "srv" / "docker" / "x" / "docker-compose.yml"
        live.parent.mkdir(parents=True)
        live.write_text(f'PASS: "{canary}"\n', encoding="utf-8")
        receipt = tdp / "receipt.jsonl"
        keep = {k: os.environ.get(k) for k in ("HL_VAULT_READ_FIXTURE", "HL_DEBT_REGISTER",
                                               "HL_CONTAINMENT_RECEIPT", "HOME", "USERPROFILE",
                                               "SESSION_DIR", "XDG_STATE_HOME", "PI_SESSION_FILE")}
        os.environ.update(HL_VAULT_READ_FIXTURE=str(fx), HL_DEBT_REGISTER=str(reg),
                          HL_CONTAINMENT_RECEIPT=str(receipt), HOME=str(home), USERPROFILE=str(home),
                          XDG_STATE_HOME=str(tdp / "state"))
        os.environ.pop("SESSION_DIR", None)
        os.environ.pop("PI_SESSION_FILE", None)
        old_seat = debt.this_seat
        debt.this_seat = lambda: "wsl"

        def attempt(register: Path, apply_: bool) -> tuple[int, str]:
            """run() over the fixture's own file set, with output captured and a Refused caught as red.
            Supplying `files` is what keeps a self-test away from this seat's real captures."""
            buf = io.StringIO()
            try:
                with redirect_stdout(buf):
                    rc = run(register, apply_, home, None, files=[str(cap), str(live)])
            except Refused as exc:
                buf.write(f"REFUSED: {exc}\n")
                rc = 1
            return rc, buf.getvalue()

        try:
            # The guard parse itself, against the real provisioner source: no fixture can fake this.
            stated = debt.provision_not_rotatable()
            check("NOT_ROTATABLE is read from the provisioner's source, not restated here",
                  {"pppoe_login", "soulseek_login", "slskd_login"} <= stated, str(sorted(stated))[:120])

            rc, out = attempt(reg, False)
            check("a dry run changes nothing and names its own mode",
                  rc == 0 and "DRY RUN" in out and canary in cap.read_text(encoding="utf-8"), out[-200:])
            scope_line = next((l for l in out.splitlines() if l.startswith("scope:")), "")
            check("the scope is derived from the register's `path: none` column, so a rotatable item "
                  "is not in it",
                  "pppoe_login(aaaa1111)" in scope_line and "wat_api" not in scope_line, scope_line[:200])

            rc, out = attempt(reg, True)
            body = cap.read_text(encoding="utf-8")
            check("--apply replaces the no-path value BY VALUE and leaves the rotatable one standing",
                  rc == 0 and "[contained:aaaa1111]" in body and canary not in body
                  and rotatable in body, out[-260:])
            check("rendered live config is refused even though it holds the value",
                  "REFUSED path" in out and canary in live.read_text(encoding="utf-8"), out[-260:])
            text = receipt.read_text(encoding="utf-8") if receipt.is_file() else ""
            check("the receipt is 0600 and carries item, class, seat, paths, vault version and time "
                  "— never a value",
                  receipt.is_file() and (receipt.stat().st_mode & 0o777) == 0o600 and canary not in text
                  and all(k in text for k in ('"item"', '"class"', '"seat"', '"paths"',
                                              '"vault_version": 2', '"ts"')), text[:200] or "no receipt")

            rc, out = attempt(reg, True)
            check("a second run finds nothing left to contain (the before/after count is the proof)",
                  rc == 0 and "nothing to do" in out, out[-160:])

            cap.write_text(f'{{"x": "{canary}"}}\n', encoding="utf-8")
            disagree = tdp / "disagree.txt"
            disagree.write_text("aaaa1111\trun-capture\twsl\t2\tnone\tdocs/x.md\n"
                                "cccc3333\trun-capture\twsl\t1\tnone\tdocs/x.md\n"
                                "dddd4444\trun-capture\twsl\t1\tnone\tdocs/x.md\n"
                                "bbbb1111\trun-capture\twsl\t1\tnone\tdocs/x.md\n", encoding="utf-8")
            rc, out = attempt(disagree, True)
            check("an item the guard does NOT state as unrotatable stops the act, and nothing is rewritten",
                  rc == 1 and "REFUSED" in out and "wat_api" in out
                  and canary in cap.read_text(encoding="utf-8"), out[-200:])

            cap.write_text(f'{{"x": "{canary}"}}\n', encoding="utf-8")
            missing = tdp / "missing.txt"
            missing.write_text("ffff9999\trun-capture\twsl\t1\tnone\tdocs/x.md\n", encoding="utf-8")
            rc, out = attempt(missing, True)
            check("a register line the vault does not answer is a refusal, never a clean sweep",
                  rc == 1 and "not re-derived" in out
                  and canary in cap.read_text(encoding="utf-8"), out[-160:])

            gone = tdp / "gone.txt"
            gone.write_text("aaaa1111\trun-capture\twsl\t2\tnone\tdocs/x.md\n", encoding="utf-8")
            rc, out = attempt(gone, True)
            check("a register that leaves a stated-unrotatable item out of the book is a refusal too",
                  rc == 1 and "no register line carries" in out, out[-200:])

            blocked = [refused_because(ROOT / "CONVENTIONS.md", None),
                       refused_because(ROOT / "IaC" / "ansible" / "x.yml", None),
                       refused_because(ROOT / ".git" / "config", None)]
            check("the repo tree, its IaC, and a git object store are each named as untouchable",
                  blocked[0] is not None and "repo tree" in blocked[0]
                  and "SSOT" in (blocked[1] or "") and "object store" in (blocked[2] or ""),
                  str(blocked)[:180])

            # The shape the real fleet answered on 2026-10-30: ONE value carried by two items, only one
            # of them in scope. Redacting those bytes would contain an item nobody scoped, and an item
            # that can be rotated is rotated.
            shared = store / "shared.jsonl"
            shared.write_text(f'{{"x": "{canary}"}}\n', encoding="utf-8")
            tally, _refs, _sk, notes = contain([str(shared)],
                                               {canary.encode(): ["aaaa11112222333344445555",
                                                                 "bbbb11112222333344446666"]},
                                               {"aaaa11112222333344445555"}, True, None)
            check("a value an unscoped item also carries is left standing and NAMED, not redacted",
                  not tally and bool(notes) and "no scope" in notes[0]
                  and canary in shared.read_text(encoding="utf-8"), str(notes)[:160])

            sess = store / "self.jsonl"
            sess.write_text(f'{{"x": "{canary}"}}\n', encoding="utf-8")
            tally, refs, _skipped, _notes = contain([str(sess)], {canary.encode(): ["aaaa11112222333344445555"]},
                                            {"aaaa11112222333344445555"}, True, store)
            check("the invoking session's own capture directory is refused",
                  bool(refs) and "capture directory" in refs[0] and canary in sess.read_text(encoding="utf-8"),
                  str(refs)[:160])

            # The live scratch copy of THIS run, named by the run id inside $PI_SESSION_FILE.
            run_id = "11112222-3333-4444-5555-666677778888"
            live_run = tdp / "pi-subagents-uid-1000" / "async-subagent-runs" / run_id
            live_run.mkdir(parents=True)
            events = live_run / "events.jsonl"
            events.write_text(f'{{"x": "{canary}"}}\n', encoding="utf-8")
            os.environ["PI_SESSION_FILE"] = str(store / run_id / "run-0" / "session.jsonl")
            tally, refs, _skipped, _notes = contain([str(events)], {canary.encode(): ["aaaa11112222333344445555"]},
                                            {"aaaa11112222333344445555"}, True, None)
            check("the run's own live scratch capture is refused by run id, not by luck of the path",
                  bool(refs) and "own live capture" in refs[0]
                  and canary in events.read_text(encoding="utf-8"), str(refs)[:160])
            os.environ.pop("PI_SESSION_FILE", None)
        finally:
            for k, v in keep.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
            debt.this_seat = old_seat
    print(f"contain-leaked-values.py --self-test: {fails} failing arm(s)")
    return 1 if fails else 0



def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="actually rewrite the copies (the default is a dry run, deliberately)")
    ap.add_argument("--register", help="the register to derive the scope from (default: the committed book)")
    ap.add_argument("--self-test", action="store_true", help="fixture arms; ZERO vault requests")
    args = ap.parse_args()
    if args.self_test:
        print("contain-leaked-values.py --self-test")
        return self_test()
    try:
        return run(Path(args.register) if args.register else debt.register_path(), args.apply, None, None)
    except Refused as exc:
        print(f"REFUSED: {exc}")
        return 1
    except (leak.Boundary, debt.Boundary, OSError, ValueError) as exc:
        print(f"SKIP: {exc} — an unreadable vault or book is an environment boundary, never a green")
        return 2


if __name__ == "__main__":
    sys.exit(main())
