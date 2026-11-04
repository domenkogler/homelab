#!/usr/bin/env python3
"""redact.py — contain a leaked value on a seat that holds NO vault (the HD-1181 family, seat leg).

WHY THIS EXISTS ALONGSIDE `contain-leaked-values.py` AND NOT INSTEAD OF IT. The containment tool for
this repo derives its scope from `gate/secret_debt_register.txt` and its values from the 1Password
vault — the right design for a debt the ledger names, and impossible on a Stroka seat, which has
neither the register nor a vault route and would exit on an environment boundary before it looked at a
transcript. Those seats leak too: a token pasted into a `cat`, a `.npmrc` printed into a tool result,
a credential quoted in an error. The only act available there is the one this file performs: **exposure
reduction, never closure**, with the value supplied by the human at the prompt instead of by a vault.

WHAT IT REUSES RATHER THAN RE-SPELLS.
  * the store walk — `scripts/lib/capture_stores.py`, the ONE answer to where a seat keeps its own
    conversation (`~/.pi/agent/sessions/**/*.jsonl`, the `pi-subagents-*` scratch roots, `$SESSION_DIR`).
    A hand-rolled `find` here would report a confident 0 for a value that landed in a child session's
    `session.jsonl`, and then a redaction and the leak eye would disagree about what "nothing found"
    means. The store line is printed on every run for that reason.
  * the act — `secrets/contain-leaked-values.py`'s `contain()`, loaded by path. Its by-value matching,
    its longest-needle-first ordering, its refusal list (`.git/`, this repo's SSOT, live service
    config, the invoking session's own capture, its own receipt) and its unreadable/too-big counters
    are NOT restated here, because a second copy of a refusal list is how a scrubber starts writing
    where it was told not to. This file supplies the two inputs that tool normally takes from the
    vault and the register: the needle, and a scope of exactly one synthetic id.

WHAT IT NEVER DOES. Never a value, never a length, never a captured line in anything that outlives
the run (CONVENTIONS §6). The first/last/length confirmation is printed ONLY on a terminal, because
that is the one moment a human needs to see the paste landed — under an agent, stdout is a pipe, and
the run then prints a `sha256[:12]` and a count instead. Never argv, never a temp file: the value
travels from the prompt into this process's memory and into nothing else. And it never edits history:
a `.git/` object store is rotation's problem, with a different owner (HD-1170).

A redaction is NOT a close. Every secret reachable from a seat without a vault is rotatable, and
rotation is the only act that closes a leak; a masked transcript with a live credential still in the
far end reads as a clean seat and is not one. The run says so on purpose.

USE:
    python3 scripts/secrets/redact.py                       # dry run over every store on this seat
    python3 scripts/secrets/redact.py 01a1a61d              # only the session whose id matches
    python3 scripts/secrets/redact.py --path D:/logs --apply
    python3 scripts/secrets/redact.py --self-test           # fixture arms, nothing outside a temp dir
Exit: 0 nothing to contain (or the act was performed; a dry run counts as performed)
      1 a refusal, or a paste that found nothing
      2 an environment boundary: no store to read, a marker with no {id8}, no value to work with.
"""
from __future__ import annotations

import argparse
import getpass
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import script_path as _hl_script_path  # noqa: E402
from capture_stores import capture_stores, capture_files, stores_note  # noqa: E402


def load_act():
    """Load `contain-leaked-values.py` by path — the sanctioned loader for a hyphenated name, the
    same one `render_all.py` uses. Importing it is not a dependency on the vault: the vault is read
    inside its `run()`, which this file never calls. Only `contain()` is used."""
    path = _hl_script_path("contain-leaked-values.py", __file__)
    spec = importlib.util.spec_from_file_location("contain_leaked_values_for_redact", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def fingerprint(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()[:12]


def default_id(value: bytes) -> str:
    """The synthetic item id a paste stands in for. The FIRST 8 characters are what the marker
    carries (`contain()` takes `id[:8]`), so the digest goes at the FRONT: an id like
    `seat-local:<name>` would give every paste the same id8 and a redacted transcript could no
    longer say which value was masked."""
    return "sl-" + hashlib.sha256(value).hexdigest()[:8]


def read_secret(args, floor: int) -> bytes:
    """The value, from the pipe or from a blind prompt — never argv, never a file. `getpass` keeps
    terminal echo off; the CR strip is the Windows/WSL paste trap (a `\\r` silently matches nothing,
    and a run that reports a clean 0 because the paste carried an invisible byte is worse than one
    that errors)."""
    if args.from_stdin:
        if sys.stdin.isatty():
            print("FATAL --from-stdin needs the value on the pipe, not a terminal", file=sys.stderr)
            raise SystemExit(2)
        raw = sys.stdin.buffer.read()
    else:
        if not sys.stdin.isatty() and not sys.stdout.isatty():
            print("FATAL no terminal to prompt on — pipe the value in with --from-stdin\n"
                  "     (pasting it into an agent's command line would write it into the very "
                  "transcript this tool exists to clean)", file=sys.stderr)
            raise SystemExit(2)
        raw = getpass.getpass("secret> ").encode("utf-8", "surrogateescape")
    raw = raw.strip().strip(b"\r\n")
    if len(raw) < floor:
        print(f"FATAL the value is {len(raw)} character(s), below the {floor}-character floor — "
              f"below it a containment match cannot be told from prose (that is the leak eye's "
              f"ruling, inherited not restated)", file=sys.stderr)
        raise SystemExit(2)
    return raw


def resolve(args, act) -> tuple[list[str], list[str], list[str]]:
    """The scan set, and the two lists that must never be silently merged: paths refused before the
    walk, and paths the walk could not read. With no positional argument the scope is every store the
    lib walk reports; with arguments it is exactly those files, plus any session whose id contains a
    given fragment — narrow on purpose, since this tool has no register to keep it honest."""
    refused: list[str] = []
    live = os.environ.get("PI_SESSION_FILE")
    files: list[str] = []
    if args.path:
        for p in args.path:
            path = Path(p)
            if path.is_file():
                files.append(str(path))
            elif path.is_dir():
                files += [str(f) for f in path.rglob("*") if f.is_file()]
            else:
                print(f"FATAL --path {p} is neither a file nor a directory", file=sys.stderr)
                raise SystemExit(2)
    targets = list(files)
    for a in args.target:
        p = Path(a)
        if p.exists():
            targets += [str(p)] if p.is_file() else [str(f) for f in p.rglob("*") if f.is_file()]
            continue
        hits = [f for f in capture_files() if a in Path(f).name]
        if not hits:
            print(f"FATAL {a!r} matches no file here and no session in the stores this seat exposes"
                  f" — {stores_note(capture_stores())}", file=sys.stderr)
            raise SystemExit(2)
        if len(hits) > 1:
            print(f"FATAL {a!r} is ambiguous across {len(hits)} sessions; name a longer fragment",
                  file=sys.stderr)
            for h in sorted(hits)[:12]:
                print(f"     {h}")
            raise SystemExit(2)
        targets += hits
    if not targets:
        stores = capture_stores()
        targets = sorted({p for s in stores.values() if s["read"] for p in s["files"]})
        if not targets:
            print(f"FATAL no capture store to read — {stores_note(stores)}", file=sys.stderr)
            raise SystemExit(2)
    if live:
        lp = str(Path(live).resolve())
        kept = []
        for t in targets:
            if str(Path(t).resolve()) == lp:
                refused.append(f"{t} — the invoking session's own capture (PI_SESSION_FILE): the "
                               "harness is appending to it, and editing it from inside is a fourth "
                               "leak. Close the session and run this from a plain terminal.")
            else:
                kept.append(t)
        targets = kept
    return sorted(set(targets)), [], refused


def report(tally, refusals, skipped, notes, store_line, applied, ids_seen) -> None:
    tag = "APPLIED" if applied else "DRY RUN — nothing was written"
    print(f"\n{tag} · NO REGISTER · NO LEDGER · CONTAINED-BY-PASTE")
    print(f"  synthetic id  : {', '.join(sorted(ids_seen))}")
    print(f"  {store_line}")
    if not any(t["occurrences"] for t in tally.values()):
        print("  hits: 0 occurrence(s) — the value is not in what this run read (that is NOT proof "
              "it was never there: see the store line for what was NOT READ)")
    for id8, t in sorted(tally.items()):
        print(f"  {id8}: {t['occurrences']} occurrence(s) in {len(t['paths'])} file(s)")
        for p in t["paths"]:
            print(f"     {p}")
    for r in refusals:
        print(f"  REFUSED {r}")
    for n in notes:
        print(f"  NOTE {n}")
    if skipped.get("unreadable") or skipped.get("too_big"):
        print(f"  not checked: {skipped.get('unreadable', 0)} unreadable, "
              f"{skipped.get('too_big', 0)} over the size ceiling")
    if applied:
        print("  a mask, not a close: ROTATE the credential, then re-run this to prove the count is 0.")


def main() -> int:
    ap = argparse.ArgumentParser(description="Contain a leaked value in a seat's own transcripts, "
                                             "with the value supplied at the prompt (no vault).")
    ap.add_argument("target", nargs="*", help="file(s) or a session-id fragment; default = every store")
    ap.add_argument("--path", action="append", help="a file or tree to sweep (repeatable)")
    ap.add_argument("--apply", action="store_true", help="write; default is a dry run")
    ap.add_argument("--yes", action="store_true", help="skip the confirmation prompt")
    ap.add_argument("--marker", help='replacement text; MUST contain {id8} (default "[contained:{id8}]")')
    ap.add_argument("--id", help="synthetic item id (default sl-<sha256[:8]>; the marker carries "
                                "its first 8 characters)")
    ap.add_argument("--from-stdin", action="store_true", help="read the value from a pipe, not a prompt")
    ap.add_argument("--self-test", action="store_true", help="fixture arms; nothing outside a temp dir")
    args = ap.parse_args()
    if args.self_test:
        return self_test()

    act = load_act()
    floor = int(act.leak.MIN_VALUE_LEN)
    if args.marker and "{id8}" not in args.marker:
        print('FATAL --marker must contain "{id8}" — that is where the item identity goes, and a '
              "marker without it cannot be traced back to what was masked", file=sys.stderr)
        raise SystemExit(2)
    if args.marker:
        act.MARKER = args.marker

    value = read_secret(args, floor)
    targets, _pre, refused = resolve(args, act)
    idv = args.id or default_id(value)
    if len(idv) < 8:
        print("FATAL --id is shorter than 8 characters; the marker would truncate it", file=sys.stderr)
        raise SystemExit(2)
    needles = {value: [idv]}
    tally, refusals, skipped, notes = act.contain(targets, needles, {idv}, args.apply)
    refused += refusals

    if sys.stdout.isatty():
        print(f"read {len(value)} character(s), first {chr(value[0])!r}, last {chr(value[-1])!r} "
              f"· sha256:{fingerprint(value)}")
    else:
        print(f"value: sha256:{fingerprint(value)} (shape hidden: stdout is not a terminal)")
    print(f"scan set: {len(targets)} file(s) considered")

    if args.apply and not args.yes:
        n = sum(t["occurrences"] for t in tally.values())
        if n and sys.stdin.isatty():
            if input(f"rewrite {n} occurrence(s) in {len(tally)} id(s)? [y/N] ").strip().lower() != "y":
                print("declined — nothing was written")
                return 0
    report(tally, refused, skipped, notes, stores_note(capture_stores()), args.apply, {idv[:8]})
    # A refusal is the actionable outcome: it says a copy lives where this tool may not go. A dry run
    # counts as performed even at 0 hits, which is why 0 hits alone is never red.
    return 1 if refused else 0


# ------------------------------------------------------------------------ self-test
def self_test() -> int:
    """Six arms, all inside a temp dir. The planted transcripts deliberately sit OUTSIDE
    `$SESSION_DIR`: `contain()` refuses the invoking session's own capture, so a fixture that planted
    its target inside the session dir would test the refusal and report it as a match — which is how
    a self-test goes quietly green while testing the opposite of what its labels say. The refusal is
    its own arm, from both directions (`$SESSION_DIR`, and `$PI_SESSION_FILE` through THIS file's
    guard), and the report is asserted to leak neither the value nor its length."""
    fails: list[str] = []
    secret = b"Zk9tPasteProbe-8f2c41a7e0"
    with tempfile.TemporaryDirectory(prefix="redact-selftest-") as td:
        root = Path(td)
        store = root / "store" / "--D--x--"
        store.mkdir(parents=True)
        mine = store / "session-a.jsonl"
        mine.write_text(json.dumps({"a": f"token={secret.decode()}", "b": "prose"}) + "\n",
                        encoding="utf-8")
        sd = root / "sd"
        sd.mkdir()
        own = sd / "session-b.jsonl"
        own.write_text(json.dumps({"a": secret.decode()}) + "\n", encoding="utf-8")
        live = root / "live" / "01a1deadbeef-0000-7000-8000-000000000000.jsonl"
        live.parent.mkdir()
        live.write_text("{}\n", encoding="utf-8")

        saved = dict(os.environ)
        try:
            os.environ["TMPDIR"] = str(root / "tmp")
            os.environ.pop("SESSION_DIR", None)
            os.environ.pop("PI_SESSION_FILE", None)
            act = load_act()
            if act.leak.MIN_VALUE_LEN < 1:
                fails.append("floor arm: MIN_VALUE_LEN stopped being readable through the act")
            needles, scoped = {secret: ["sl-deadbeef"]}, {"sl-deadbeef"}

            tally, refusals, _sk, _n = act.contain([str(mine)], needles, scoped, False)
            if sum(t["occurrences"] for t in tally.values()) != 1 or refusals:
                fails.append(f"dry-run arm: tally={tally} refusals={refusals}")
            if secret not in mine.read_bytes():
                fails.append("dry-run arm: a dry run WROTE")

            tally, refusals, _sk, _n = act.contain([str(mine)], needles, scoped, True)
            data = mine.read_bytes()
            if secret in data or b"contained:sl-deadb" not in data:
                fails.append("apply arm: the marker did not land")
            if not tally:
                fails.append("apply arm: an applied rewrite tallied nothing")

            buf = io.StringIO()
            with redirect_stdout(buf):
                report(tally, [], {"unreadable": 0}, [], "stores", True, {"sl-deadb"})
            out = buf.getvalue()
            if secret.decode() in out or "character" in out:
                fails.append("disclosure arm: the report printed the value or its length")

            os.environ["SESSION_DIR"] = str(sd)
            _t, refusals, _sk, _n = act.contain([str(own)], needles, scoped, True)
            if not refusals or secret not in own.read_bytes():
                fails.append("own-capture arm ($SESSION_DIR): it was rewritten instead of refused")
            os.environ.pop("SESSION_DIR", None)

            args = argparse.Namespace(path=None, target=[str(live)])
            kept, _pre, refused = resolve(args, act)
            os.environ["PI_SESSION_FILE"] = str(live)
            args = argparse.Namespace(path=None, target=[str(live)])
            kept2, _pre2, refused2 = resolve(args, act)
            if kept != [str(live)] or refused:
                fails.append(f"own-transcript arm: an unguarded run refused a fair target "
                             f"(kept={kept} refused={refused})")
            if kept2 or not refused2:
                fails.append(f"own-transcript arm ($PI_SESSION_FILE): the live transcript was left "
                             f"in the scan set (kept={kept2})")
            os.environ.pop("PI_SESSION_FILE", None)

            argv = sys.argv
            sys.argv = ["redact.py", "--marker", "no id here"]
            try:
                main()
                fails.append("marker arm: a marker with no {id8} reached the prompt")
            except SystemExit as exc:
                if exc.code != 2:
                    fails.append(f"marker arm: rc {exc.code}, expected the boundary rc 2")
            finally:
                sys.argv = argv

            stdin = sys.stdin
            sys.stdin = _PipeInput(secret[:3])
            sys.argv = ["redact.py", "--from-stdin"]
            try:
                main()
                fails.append("floor arm: a value below the floor was accepted")
            except SystemExit as exc:
                if exc.code != 2:
                    fails.append(f"floor arm: rc {exc.code}, expected the boundary rc 2")
            finally:
                sys.stdin, sys.argv = stdin, argv
        finally:
            os.environ.clear()
            os.environ.update(saved)
    for f in fails:
        print(f"FAIL {f}")
    print("redact.py self-test: " + (f"FAIL {len(fails)} arm(s)" if fails else
          "GREEN — by-value match, marker landed, dry run wrote nothing, own capture refused from "
          "both seams, and the report leaked neither the value nor its length"))
    return 1 if fails else 0


class _PipeInput:
    """A stdin that answers `isatty()` false and yields a fixed payload, so the floor arm exercises
    the real `--from-stdin` path instead of restating its arithmetic in the test."""

    def __init__(self, payload: bytes) -> None:
        self.buffer = io.BytesIO(payload)

    def isatty(self) -> bool:
        return False


if __name__ == "__main__":
    sys.exit(main())
