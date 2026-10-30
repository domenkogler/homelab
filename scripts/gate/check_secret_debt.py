#!/usr/bin/env python3
"""check_secret_debt.py — what an open leak debt still needs: who acts, on which seat, rotated yet.

`scripts/gate/secret_leak_ledger.txt` mutes the pairs it names and prints a pair `STALE` when its hit
is gone. Neither fact answers the three questions a debt actually poses — WHO can rotate this at all,
on WHICH seat the hit sits, and whether the value behind it MOVED since the debt was recorded — and
the ledger cannot answer them, because `--update-ledger` rewrites its body and a fourth column added
there dies at the next run (docs/deployment-rejected.md). So this checker reads the COMPANION book,
`scripts/gate/secret_debt_register.txt`, and holds it against two facts the ledger does not carry:

  * the vault's per-item `version` numbers, off ONE read through `scripts/lib/vault_read.py`. A
    names-only read costs a single request and reads no value at all; where the route's list rows
    carry no version numbers this fleet's print says so and the batched read answers instead — values
    in memory only, nothing printed, `requests=` counted like every other leg. `version` unmoved ⇒
    provably NOT ROTATED; `version` moved ⇒ CANDIDATE, and the content scan proves it.
    ⛔ Nothing here hashes a value: on credentials this short a hash is an offline guess-check, and a
    hash proves a HOLDER, never a HISTORY.
  * the ledger's pair set, read with the ledger's OWN row reader — `check_secret_leak.read_ledger`,
    imported rather than re-spelled, because two ideas of what a `(item, class)` pair is is the twin
    this family of gates exists to catch.

THE VERDICTS, and the pair of them that is the whole reason this file exists:

    pair in ledger, version unmoved     `NOT ROTATED` — the debt is open and nothing has moved
    pair in ledger, version moved       `CANDIDATE — prove with check_secret_leak.py`
    pair left ledger, version moved     `CLOSED — remove the line` — rotated AND proven absent
    pair left ledger, version unmoved   `REFUSED — the hit left the ledger and the value never
                                        rotated` (exit 1)
    the vault answers no such item      `GONE — re-derive, then remove the line`
    a foreign seat's line, or a store   `NOT JUDGED` — nothing known either way, and a line is
    this run could not read             closable only by the seat that recorded it

The `REFUSED` line is the defect the ledger alone cannot see: a redaction, a shredded store or a
hand-edited book makes a hit disappear, and in the ledger alone that looks EXACTLY like a rotation.
Only the version tells them apart, and `CONTAINED` is the honest word for the act that lowers the copy
count and closes nothing (`scripts/secrets/contain-leaked-values.py`, HD-1218).

THE SECOND FACT THIS FILE HOLDS: the register's `path: none` set is the fleet's machine-readable "no
rotation path exists", and `NOT_ROTATABLE` in `scripts/secrets/provision-secrets.py` states the same
ruling at the item level. Two copies of one decision is the twin every gate here exists to catch, so
an arm resolves each `none` line's item id to its TITLE and requires the two sets to agree in both
directions. ⛔ `NOT_AUTO_ROTATABLE` is a DIFFERENT fact — the auto-rotation ORDERING guard, asserting
only that a vault-only `--rotate` leaves the far end behind — and is deliberately not compared here.

Seat locality is not decoration. `run-capture` is decided per STORE, so a run whose persistent
transcript store was not read prints `NOT JUDGED` for its own `run-capture` lines instead of closing
them, and a `git-history` line is only as good as the last re-derive that ran the history leg — which
is why `--update-ledger` refuses to drop such a line otherwise, and why a `CLOSED` verdict on that
class is evidence rather than hope.

USE:
    python3 scripts/gate/check_secret_debt.py [--self-test] [--register F] [--all-seats]
Exit: 0 every line judged or honestly NOT JUDGED, and the two no-rotation-path sets agree;
      1 a `REFUSED` line, a disagreement between the two sets, or a malformed register line;
      2 environment boundary: no vault route, no answer, an unreadable book. Never a green.
Wired into `validate-all.sh` and listed in `scripts/README.md`.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
# The Win11 seat's locale default is cp1252, so the em-dashes in these verdict lines reach the reader
# of a captured subprocess as bytes it cannot decode. The sibling checkers pin themselves the same way
# (the HD-1202 class: the same leg must ask the same question on both seat planes).
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass
from repo_root import root as _hl_root  # noqa: E402
from vault_read import Boundary as _ReadBoundary, read_names, read_vault  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
# The ledger's row grammar and the store set are OWNED by the leak eye. Importing them, rather than
# re-spelling a parser and a store walk here, is what keeps this checker and that gate from growing
# two opinions about the same book (the argument check_registry_prose.py makes about its own twin).
import check_secret_leak as leak  # noqa: E402

ROOT = _hl_root(__file__)
VAULT = "Homelab-ansible"
# $HL_DEBT_REGISTER is a test seam, not a feature: the fixture arms read a COPY of the book. Unset in
# every normal run, where the committed file is the register.
REGISTER = Path(os.environ.get("HL_DEBT_REGISTER")
                or ROOT / "scripts" / "gate" / "secret_debt_register.txt")
PROVISIONER = ROOT / "scripts" / "secrets" / "provision-secrets.py"
PATHS = ("lane", "lane+converge", "human", "none")
SEATS = ("win11", "wsl", "oldsrv")
VERDICTS = ("NOT ROTATED", "CANDIDATE", "CLOSED", "REFUSED", "GONE", "NOT JUDGED")


class Boundary(Exception):
    """The check cannot judge this environment; it prints a reason, not a verdict."""


class Line(NamedTuple):
    item: str          # the 8-char vault id prefix
    cls: str           # one of check_secret_leak.CLASSES
    seat: str          # the seat whose store carries the hit
    version: str       # the vault version at leak time
    path: str          # lane | lane+converge | human | none
    doc: str           # the owning doc whose act closes the line
    number: int        # the line's number in the book, so a complaint is findable


# --------------------------------------------------------------------------- the book
def register_path() -> Path:
    """Resolved at call time, like the ledger's own seam: an import-time constant would let a fixture
    arm that sets the variable read the committed book anyway."""
    return Path(os.environ.get("HL_DEBT_REGISTER")
                or ROOT / "scripts" / "gate" / "secret_debt_register.txt")


def ledger_path() -> Path:
    return Path(os.environ.get("HL_LEAK_LEDGER") or ROOT / "scripts" / "gate" / "secret_leak_ledger.txt")


def read_register(path: Path) -> tuple[list[Line], list[str]]:
    """The register as LINES, plus the parse complaints. A malformed line is printed, never skipped:
    a book that reads shorter than it is has the same effect as a mute."""
    if not path.is_file():
        raise Boundary(f"{path} is not readable — the register is this check's input, and a book that "
                       "is not there is an environment mistake, not a clean fleet")
    lines: list[Line] = []
    bad: list[str] = []
    for n, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        cols = [c.strip() for c in raw.split("\t")]
        if len(cols) != 6:
            bad.append(f"{path.name}:{n}: expected 6 TAB-separated columns, found {len(cols)} — the "
                       "line is NOT judged and the run exits 1, because a book that quietly reads "
                       "shorter is the same failure as a mute")
            continue
        item, cls, seat, version, path_word, doc = cols
        if cls not in leak.CLASSES:
            bad.append(f"{path.name}:{n}: class {cls!r} is not one of {list(leak.CLASSES)}")
        if seat not in SEATS:
            bad.append(f"{path.name}:{n}: seat {seat!r} is not one of {list(SEATS)}")
        if path_word not in PATHS:
            bad.append(f"{path.name}:{n}: path {path_word!r} is not one of {list(PATHS)}")
        if not re.fullmatch(r"[a-z0-9]{8}", item):
            bad.append(f"{path.name}:{n}: item id {item!r} is not the 8-character vault prefix")
        if not version.isdigit():
            bad.append(f"{path.name}:{n}: version {version!r} is not a number — the version is what "
                       "makes `rotated?` a fact, so typing anything else is the defect this book "
                       "exists to remove")
        if not doc.startswith("docs/"):
            bad.append(f"{path.name}:{n}: rotation doc {doc!r} is not a docs/ path — the line must "
                       "name where the act is written down")
        # A line with a bad column is REPORTED and not judged: judging `version=TBD` would either
        # crash or guess, and a guessed version is the defect this book exists to remove.
        if not any(f":{n}:" in f for f in bad):
            lines.append(Line(item, cls, seat, version, path_word, doc, n))
    dupes = sorted({k for k in ((l.item, l.cls, l.seat) for l in lines)
                    if sum(1 for o in lines if (o.item, o.cls, o.seat) == k) > 1})
    for k in dupes:
        bad.append(f"{path.name}: the key {k} appears twice — two lines for one debt can carry two "
                   "versions, and the verdict would depend on which was read first")
    return lines, bad


def provision_not_rotatable() -> set[str]:
    """The titles `NOT_ROTATABLE` states in the provisioner.

    Read from the SOURCE, not by importing: `provision-secrets.py` is a vault-WRITE tool, and pulling
    it into every validation run for one literal would make a gate depend on a writer's import graph.
    The set is an assignment of string literals, so this is a read of the SSOT, not of a guess."""
    if not PROVISIONER.is_file():
        raise Boundary(f"{PROVISIONER} is not readable — the no-rotation-path ruling cannot be "
                       "cross-checked, which is a boundary and not an agreement")
    src = PROVISIONER.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^NOT_ROTATABLE\s*=\s*\{(.*?)^\}", src, re.M | re.S)
    if not m:
        raise Boundary("NOT_ROTATABLE is not stated in scripts/secrets/provision-secrets.py, so the "
                       "register's `path: none` half has nothing to be held equal to — the ruling is "
                       "then in one place and this check cannot judge it")
    return {(a or b) for a, b in re.findall(r'"([^"]+)"|\'([^\']+)\'', m.group(1))}


# --------------------------------------------------------------------------- the seat
def this_seat() -> str:
    """Which seat this run stands on — the three arms `scripts/harness/pi-seat-sync.sh` uses.

    DECLARED LIMIT, the same one that file states: these arms read the BOX, not the account. A host
    that is none of the three answers NOTHING about any seat, and every line then reads NOT JUDGED —
    which is why the seat is part of the key rather than a comment beside it."""
    if sys.platform.startswith(("win32", "cygwin", "mingw")):
        return "win11"
    try:
        if "microsoft" in Path("/proc/version").read_text(encoding="utf-8",
                                                           errors="replace").lower():
            return "wsl"
    except OSError:
        pass
    if os.uname().sysname.lower() == "linux":
        r = subprocess.run(["hostname"], capture_output=True, stdin=subprocess.DEVNULL, check=False)
        if r.stdout.decode(errors="replace").strip().split(".")[0].lower() == "oldsrv":
            return "oldsrv"
    return "unknown"


def store_state() -> tuple[bool, str]:
    """Was the PERSISTENT transcript store read here? The store set is the leak eye's own
    `capture_stores()`, imported for the same reason its ledger reader is."""
    stores = leak.capture_stores()
    gate = stores.get("pi-transcripts", {"read": False, "why": "no pi-transcripts entry"})
    return bool(gate["read"]), leak.stores_note(stores)


# --------------------------------------------------------------------------- the read
def versions_and_titles() -> tuple[dict[str, int], dict[str, str], str, str]:
    """The vault's versions and titles.

    The cheap shape is the names-only read — ONE request, no value read — but this fleet's SDK answers
    `items.list` with NO version numbers, and a read that answered no versions would judge nothing
    while printing as if it had read the vault. So: take the names-only read, USE it only if it
    carried versions, and otherwise take the batched read and SAY so. Values are held in memory, are
    never printed, and the request count is printed either way."""
    try:
        names = read_names(VAULT)
    except (_ReadBoundary, OSError, ValueError) as exc:
        raise Boundary(str(exc)) from exc
    titled = {iid: row.get("title", "?") for iid, row in names.entries.items()}
    versioned = {iid: int(row["version"]) for iid, row in names.entries.items()
                 if isinstance(row.get("version"), int)}
    if versioned:
        names.print_cost("check_secret_debt.py")
        return versioned, titled, "names-only", ""
    vr = read_vault(VAULT)
    vr.print_cost("check_secret_debt.py")
    return ({iid: int(row["version"]) for iid, row in vr.items.items()
             if isinstance(row.get("version"), int)},
            {iid: row.get("title", "?") for iid, row in vr.items.items()},
            "value-read fallback",
            "the name list carried no versions — this SDK release's list rows do not — so the batched "
            "read answered; values were read into memory and nothing was printed")


# --------------------------------------------------------------------------- the verdicts
def verdicts(lines: list[Line], pairs: set[tuple[str, str]], versions: dict[str, int],
             titles: dict[str, str], seat: str, store_read: bool) -> list[tuple[str, Line, str]]:
    """One (verdict, line, reason) per register line. The ledger half answers `is it still hit`, the
    version half answers `did the value move`, and only the two together can name a close."""
    known_seat = seat in SEATS
    out: list[tuple[str, Line, str]] = []
    for ln in lines:
        if ln.seat != seat:
            out.append(("NOT JUDGED", ln,
                        f"line of the {ln.seat} seat and this run is "
                        + (f"the {seat} seat" if known_seat else "not one of the three seats")
                        + " — a seat may never close a line it did not record"))
            continue
        if ln.cls == "run-capture" and not store_read:
            out.append(("NOT JUDGED", ln,
                        "the persistent transcript store was not read on this seat, so this hit is "
                        "not known either way and the line cannot be closed here"))
            continue
        ids = [iid for iid in versions if iid.startswith(ln.item)]
        if not ids:
            out.append(("GONE", ln,
                        "the vault answers no item with this id prefix — retired, or the register was "
                        f"not re-derived with it; the act is in {ln.doc}"))
            continue
        moved = any(v > int(ln.version) for v in (versions.get(i, 0) for i in ids))
        hit = (ln.item, ln.cls) in pairs
        if hit and moved:
            out.append(("CANDIDATE", ln,
                        f"the vault's version moved and the hit still stands — the propagation, not "
                        f"the vault write, is what closes this ({ln.doc}); prove it with "
                        "check_secret_leak.py"))
        elif hit:
            out.append(("NOT ROTATED", ln,
                        f"the value behind this debt has not moved since the debt was recorded; the "
                        f"act that closes it is in {ln.doc}"))
        elif moved:
            out.append(("CLOSED", ln,
                        "the version moved and no run since has hit the pair — rotated and proven "
                        "absent; remove the line"))
        else:
            out.append(("REFUSED", ln,
                        "the pair left the ledger and the vault version never moved. A hit that "
                        "disappears without a rotation is a redaction, a shredded store or an edited "
                        "book — never a close. Re-derive the ledger on the seat that recorded it, or "
                        f"name the act in the register's `path:` column (currently {ln.path})"))
    return out


def scope_disagreement(lines: list[Line], titles: dict[str, str]) -> tuple[list[str], bool]:
    """The twin arm: the register's `path: none` set against `NOT_ROTATABLE`, in both directions.

    Returns (findings, boundary). A boundary is NOT a finding and never a pass: the verdicts above
    stand, the equality did not get judged."""
    try:
        stated = provision_not_rotatable()
    except Boundary as exc:
        return [f"NOT CHECKED the no-rotation-path equality: {exc}"], True
    derived: dict[str, str] = {}
    for ln in lines:
        if ln.path != "none":
            continue
        name = [t for iid, t in titles.items() if iid.startswith(ln.item)]
        if not name:
            return [f"NOT CHECKED the no-rotation-path equality: register line {ln.item} "
                    f"({ln.cls}/{ln.seat}) names no item the vault answered, so its title — the key "
                    "NOT_ROTATABLE is written in — cannot be resolved"], True
        derived[name[0]] = ln.item
    out = [f"REFUSED  {derived[t]} carries `path: none` in the register and is absent from "
           f"NOT_ROTATABLE in scripts/secrets/provision-secrets.py: two copies of one ruling, "
           f"disagreeing on {t!r}" for t in sorted(set(derived) - stated)]
    out += [f"REFUSED  NOT_ROTATABLE states no rotation path for {t!r} and no register line carries "
            "`path: none` for it: the containment scope would read quieter than the ruling"
            for t in sorted(stated - set(derived))]
    return out, False


def run(register: Path | None = None, all_seats: bool = False) -> int:
    reg = register or register_path()
    lines, bad = read_register(reg)
    led = ledger_path()
    pairs = leak.read_ledger(led)
    versions, titles, route, note = versions_and_titles()
    seat = this_seat()
    store_read, snote = store_state()

    print(f"seat: {seat} — a verdict from this run is a statement about THIS seat, and about no other"
          + ("" if seat in SEATS else " (an unrecognised host judges nothing)"))
    print(f"version read: {route}; {len(versions)} item(s) answered a version, "
          f"{len(titles)} titles, ledger {led.name} carries {len(pairs)} pair(s)"
          + (f" — {note}" if note else ""))
    print(snote)
    # Which seats the book speaks for, before any verdict is read: a seat no line names is UNRECORDED,
    # and a debt sitting in a store nobody read is not a debt that closed.
    recorded = sorted({ln.seat for ln in lines})
    missing = [s_ for s_ in SEATS if s_ not in recorded]
    print("seats recorded: " + (", ".join(recorded) or "NONE")
          + (" — NOT RECORDED: " + ", ".join(missing) + "; a debt in a store no run read is unknown, "
             "not absent, and this report says nothing about it" if missing else ""))
    for complaint in bad:
        print(f"BAD LINE: {complaint}")

    got = verdicts(lines, pairs, versions, titles, seat, store_read)
    shown = got if all_seats else [g for g in got if not (g[0] == "NOT JUDGED"
                                                          and g[1].seat != seat)]
    for word in VERDICTS:
        group = [g for g in shown if g[0] == word]
        if group:
            print(f"{word}: {len(group)}")
            for verdict, ln, why in group:
                print(f"  {verdict:<11} {ln.item} {ln.cls} seat={ln.seat} path={ln.path} "
                      f"v{ln.version} — {why}")
    twin, boundary = scope_disagreement(lines, titles)
    for line in twin:
        print(line)
    counts = {w: sum(1 for g in got if g[0] == w) for w in VERDICTS}
    print(f"register: {len(lines)} line(s) from {reg.name}; "
          + ", ".join(f"{w}={n}" for w, n in counts.items() if n)
          + ("; the other seats' lines are omitted here, --all-seats prints them"
             if not all_seats and any(g[0] == "NOT JUDGED" and g[1].seat != seat for g in got) else ""))
    refused = [g for g in got if g[0] == "REFUSED"]
    if refused:
        print("REFUSED is the defect this book exists to catch: a hit that left the ledger without a "
              "rotated value. Nothing was rotated; the copy count may have moved. See "
              "docs/deployment-secrets.md §Creation & Rotation Workflow.")
    if [t for t in twin if t.startswith("REFUSED")]:
        print("The two statements of the no-rotation-path ruling disagree — containment would derive "
              "its scope from one of them and the guard from the other.")
    if boundary:
        print("NOTE: the equality arm did not get judged (boundary above) — that is not an agreement.")
    if refused or [t for t in twin if t.startswith("REFUSED")] or bad:
        return 1
    return 2 if boundary else 0


# --------------------------------------------------------------------------- self-test
def _fixture_vault(rows: list[tuple[str, str, int]]) -> Path:
    """A minted vault for the arms: titles and versions, one field each so the shape matches the
    reader's. Zero requests — an arm that read the fleet's vault would make this gate unrunnable
    offline and would spend the shared account bucket to prove a fixture."""
    fd, p = tempfile.mkstemp(suffix=".json", text=True)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump({"items": {iid: {"title": t, "version": v, "fields": [
            {"id": "password", "label": "password", "value": "unused-fixture-value",
             "type": "Concealed", "section": ""}]} for iid, t, v in rows}}, fh)
    return Path(p)


def self_test() -> int:
    fails = 0
    committed_provisioner = PROVISIONER

    def check(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        fails += not ok
        print(f"  arm {label}: {'ok' if ok else 'FAIL'}{(' — ' + detail) if (detail and not ok) else ''}")

    ids = {"debt": "aaaaaaaaaaaaaaaaaaaaaaaaaa", "rot": "bbbbbbbbbbbbbbbbbbbbbbbbbb",
           "gone": "cccccccccccccccccccccccccc", "poe": "dddddddddddddddddddddddddd",
           "soul": "eeeeeeeeeeeeeeeeeeeeeeeeee"}
    # The fixture book: one line per verdict shape the register can carry. The `poe`/`soul` lines are
    # the `path: none` half, titled as the real ones are so the twin arm has a title to resolve.
    reg_body = (
        "# book\n"
        + "".join([
            f"{ids['debt'][:8]}\trun-capture\twsl\t7\tlane+converge\tdocs/network-vpn.md\n",
            f"{ids['rot'][:8]}\trun-capture\twsl\t3\tlane\tdocs/backup.md\n",
            f"{ids['gone'][:8]}\trun-capture\twsl\t2\thuman\tdocs/deployment-secrets.md\n",
            f"{ids['poe'][:8]}\trun-capture\twsl\t1\tnone\tdocs/network-rejected.md\n",
            f"{ids['soul'][:8]}\trun-capture\twsl\t1\tnone\tdocs/services-rejected.md\n"]))
    rows = [(ids["debt"], "item_debt", 7), (ids["rot"], "item_rot", 3),
            (ids["gone"], "item_gone", 2), (ids["poe"], "pppoe_login", 1),
            (ids["soul"], "slskd_login", 1)]
    LED_ALL = "".join(f"{iid[:8]}\trun-capture\t{t}\n" for iid, t, _v in rows)
    # The same book with the `rot` pair proven ABSENT by a re-derive — the ledger half of the two
    # verdicts that differ only in the version.
    LED_NO_ROT = "".join(f"{iid[:8]}\trun-capture\t{t}\n" for iid, t, _v in rows
                         if iid != ids["rot"])
    AGREES = {"pppoe_login", "slskd_login"}

    def ask(fixture_rows: list[tuple[str, str, int]], ledger: str, register: str = reg_body,
            provision: set[str] | None = AGREES, seat: str = "wsl", store: bool = True,
            all_seats: bool = False) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as td:
            tdp = Path(td)
            reg = tdp / "register.txt"
            reg.write_text(register, encoding="utf-8")
            led = tdp / "ledger.txt"
            led.write_text(ledger, encoding="utf-8")
            fx = _fixture_vault(fixture_rows)
            home = tdp / "home"
            if store:
                (home / ".pi" / "agent" / "sessions").mkdir(parents=True)
            else:
                home.mkdir()
            keep = {k: os.environ.get(k) for k in
                    ("HL_VAULT_READ_FIXTURE", "HL_LEAK_LEDGER", "HL_DEBT_REGISTER", "HOME",
                     "USERPROFILE", "TMPDIR")}
            old_provisioner, old_seat_fn = PROVISIONER, this_seat
            os.environ.update(HL_VAULT_READ_FIXTURE=str(fx), HL_LEAK_LEDGER=str(led),
                              HL_DEBT_REGISTER=str(reg), HOME=str(home), USERPROFILE=str(home),
                              TMPDIR=str(tdp / "tmp"))
            if provision is not None:
                stub = tdp / "provision-secrets.py"
                stub.write_text("NOT_ROTATABLE = {\n"
                                + "".join(f'    "{n}",\n' for n in sorted(provision)) + "}\n",
                                encoding="utf-8")
                globals()["PROVISIONER"] = stub
            globals()["this_seat"] = lambda: seat
            try:
                buf = io.StringIO()
                with redirect_stdout(buf):
                    rc = run(reg, all_seats)
            finally:
                for k, v in keep.items():
                    if v is None:
                        os.environ.pop(k, None)
                    else:
                        os.environ[k] = v
                globals()["PROVISIONER"], globals()["this_seat"] = old_provisioner, old_seat_fn
                fx.unlink(missing_ok=True)
            return rc, buf.getvalue()

    def with_version(item_id: str, v: int) -> list[tuple[str, str, int]]:
        return [(i, t, v if i == item_id else n) for i, t, n in rows]

    # (1) the four verdicts the ledger half cannot decide on its own.
    rc, out = ask(rows, LED_ALL)
    check("a version-unmoved line whose hit stands reads NOT ROTATED and exits 0",
          "NOT ROTATED" in out and rc == 0, out[-200:])
    rc, out = ask(with_version(ids["rot"], 9), LED_ALL)
    check("a version-moved line whose hit still stands reads CANDIDATE",
          "CANDIDATE" in out and rc == 0, out[-200:])
    rc, out = ask(with_version(ids["rot"], 9), LED_NO_ROT)
    check("a version-moved line whose hit a re-derive proved absent reads CLOSED",
          "CLOSED" in out and "REFUSED" not in out and rc == 0, out[-200:])
    rc, out = ask(rows, LED_NO_ROT)
    check("a hit that left the ledger with the version UNMOVED reddens as REFUSED",
          "REFUSED" in out and rc == 1, out[-200:])

    # (2) THE CHEAP TEST from the row: bump ONE item's version in the fixture and prove exactly one
    # line's verdict moved. Without the version column the two runs print identically.
    _rc, before = ask(rows, LED_ALL)
    rc, after = ask(with_version(ids["rot"], 8), LED_ALL)
    moved = [ln for ln in after.splitlines() if ids["rot"][:8] in ln]
    still = [ln for ln in after.splitlines() if ids["debt"][:8] in ln]
    check("the version-bump arm: one line moves NOT ROTATED->CANDIDATE and no other line moves",
          any(ln.lstrip().startswith("CANDIDATE") for ln in moved)
          and any(ln.lstrip().startswith("NOT ROTATED") for ln in still)
          and any(ln.lstrip().startswith("NOT ROTATED") for ln in before.splitlines()
                  if ids["rot"][:8] in ln) and rc == 0, f"{[ln[:34] for ln in moved]}")

    # (3) seat locality: a foreign line is NOT JUDGED, is never CLOSED here, and is not printed unless
    # asked for. The ledger says its pair is gone; a foreign seat still may not close it.
    foreign = reg_body.replace("\twsl\t", "\toldsrv\t")
    rc, out = ask(with_version(ids["rot"], 9), "", register=foreign)
    check("another seat's line prints NOT JUDGED and is never CLOSED from here",
          "NOT JUDGED" in out and "CLOSED" not in out and rc == 0, out[-200:])
    rc, out = ask(with_version(ids["rot"], 9), "", register=foreign, all_seats=True)
    check("--all-seats prints the foreign lines and keeps them NOT JUDGED",
          "NOT JUDGED" in out and "seat=oldsrv" in out, out[-200:])
    check("the default print omits the foreign lines and says so",
        "omitted" in ask(with_version(ids["rot"], 9), "", register=foreign)[1], out[-120:])

    # (4) the store half: a checkout whose persistent store was not read may not close its OWN lines,
    # even with the version moved — the HD-1181 shape, one level up.
    rc, out = ask(with_version(ids["rot"], 9), LED_NO_ROT, store=False)
    check("a store-less run prints NOT JUDGED for its own run-capture lines",
          "NOT JUDGED" in out and "persistent transcript store" in out and "CLOSED" not in out,
          out[-200:])

    # (5) the twin arm, in both directions, plus its boundary.
    rc, out = ask(rows, LED_ALL, provision={"pppoe_login"})
    check("a path:none line missing from NOT_ROTATABLE reddens",
          "REFUSED" in out and "slskd_login" in out and rc == 1, out[-200:])
    rc, out = ask(rows, LED_ALL, provision=set(AGREES | {"wg_password"}))
    check("a NOT_ROTATABLE title with no path:none line reddens too",
          "wg_password" in out and rc == 1, out[-200:])
    with tempfile.TemporaryDirectory() as td:
        stub = Path(td) / "provision-secrets.py"
        stub.write_text("NOT_AUTO_ROTATABLE = {\n    'anything',\n}\n", encoding="utf-8")
        globals()["PROVISIONER"] = stub
        try:
            rc, out = ask(rows, LED_ALL, provision=None)
        finally:
            globals()["PROVISIONER"] = committed_provisioner
    check("a provisioner that states no NOT_ROTATABLE is a boundary, never an agreement",
          "NOT CHECKED" in out and rc == 2, out[-200:])

    # (6) a retired item: GONE, and it reddens nothing by itself.
    rc, out = ask([r for r in rows if r[0] != ids["gone"]], LED_ALL)
    check("a register line for an item the vault no longer answers reads GONE",
          "GONE" in out and rc == 0, out[-200:])

    # (7) the book's own grammar: a bad line prints and reddens, and is never judged on a guess.
    rc, out = ask(rows, LED_ALL, register=reg_body.replace("\t7\tlane+converge", "\tTBD\tpath"))
    check("a bad column reddens the run and is not judged, rather than shortening the book",
          "BAD LINE" in out and rc == 1 and ids["debt"][:8] not in out.split("BAD LINE")[0],
          out[-200:])
    rc, out = ask(rows, LED_ALL, register=reg_body + reg_body.splitlines()[1] + "\n")
    check("a duplicated key reddens (two versions for one debt is two answers)",
          "appears twice" in out and rc == 1, out[-160:])

    # (8) disclosure: the register holds ids, the fixture holds a minted value, and the report may
    # print neither the value nor a full item id.
    rc, out = ask(rows, LED_ALL)
    check("the report discloses no value and no full item id",
          "unused-fixture-value" not in out and ids["debt"] not in out, out[-120:])

    # (8b) the seat coverage line: a seat no line names is UNRECORDED, which is the Phase-0 rule "a
    # seat that was not read is stated as unread rather than assumed clean", one level up.
    rc, out = ask(with_version(ids["rot"], 9), "", register=foreign)
    check("a seat the book carries no line for prints NOT RECORDED rather than clean",
          "NOT RECORDED: win11, wsl" in out and "unknown, not absent" in out, out[-200:])

    # (9) one row grammar, one store walk: both are reached through the leak eye's module, so a local
    # second copy would show up as a module-level name here. (Checked through `globals()`, not by
    # grepping this file's own text — the arm's own strings would satisfy a text search.)
    check("the pair set and the store walk are the leak eye's, not a local twin",
          "read_ledger" in leak.__dict__ and "capture_stores" in leak.__dict__
          and "read_ledger" not in globals() and "capture_stores" not in globals())

    print(f"check_secret_debt.py --self-test: {fails} failing arm(s)")
    return 1 if fails else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true", help="prove the arms on minted fixtures")
    ap.add_argument("--register", help="the register to read (default: the committed book)")
    ap.add_argument("--all-seats", action="store_true",
                    help="print the other seats' lines too (they stay NOT JUDGED either way)")
    args = ap.parse_args()
    if args.self_test:
        print("check_secret_debt.py --self-test")
        return self_test()
    try:
        return run(Path(args.register) if args.register else None, args.all_seats)
    except Boundary as exc:
        print(f"SKIP: {exc} — an unreadable vault or book is an environment boundary, not a green")
        return 2
    except (_ReadBoundary, OSError, ValueError) as exc:
        print(f"SKIP: {exc} — environment boundary, not a green")
        return 2


if __name__ == "__main__":
    sys.exit(main())
