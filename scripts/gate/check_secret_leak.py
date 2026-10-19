#!/usr/bin/env python3
"""Fail when a CURRENT vault value is sitting in a run capture — by CONTENT, not by name.

Why this file exists: three times on 2026-10-19 the same thing happened in three different lanes.
Someone read a rendered secret file to *inspect* it — `cat` of a rendered compose, `docker exec cat`
of an app's `config.ini` — and the value travelled into the session's run capture
(`SESSION_DIR/output-<n>.log`, the `session.jsonl` transcript, `logs/*.log`). The file on the host was
`0600`, the commit was clean, every shape scanner stayed green, and the value was readable in a
transcript afterwards. A prose rule loses to a reflex command, so this is the eye.

The four requirements, each one a lesson from those three leaks:

(a) **Content, not name.** A redactor written against `KEY=value` missed the SAME value rendered as
    `SLSKD_API_KEY: "…"` in a compose-shaped line. So the check is `bytes.find(value)` over the whole
    file: no key-name pattern, no secret-shape regex, no trust in the punctuation around it. That is
    also why the shape scanner (`check_secrets.py`, ten regexes over the tracked tip) missed all
    three — a value is matched against a VALUE here, not against a shape.

(b) **The instrument must not become a fourth leak.** No vault value, no scanned line and no value
    LENGTH ever reaches stdout. A finding is `<file>:<line> matches item <vault-id-prefix> (<title>)`
    — ids and titles are already in `docs/deployment-secrets.md`; values are not. `--self-test`
    asserts this on the tool's own output: a canary planted in a fixture may not appear in the text
    the run prints, and neither may its length.

(c) **A vault that cannot be read is a boundary, never a green.** No `op`, an unauthenticated `op`,
    or a `list` that answers nothing → exit 2 with the reason. This check only READS, so a
    read-scoped token is sufficient and is NOT a reason to skip: what gets probed is the read, because
    the read is what the check needs — scope is measured here, never inherited from prose
    (docs/deployment-secrets.md §"Token scope: PROBE it, do not inherit it").

(d) **Bounded, and honest about rotated values.** File sizes are capped, binaries are skipped, and
    both counts are printed instead of implied. A value that was rotated OUT is a DEAD secret: this
    check compares CURRENT values. Superseded values are compared only when a `--retired-file` is
    handed to it — a `0600` file held for the probe window and shredded afterwards, because the fleet
    keeps no plaintext record of a dead value — and then they print `INFO retired …`, never a finding.

Standing exposure, and the ledger. A hit in a capture is not fixed by editing a file: only rotating
the item closes it, which is an owner act. So a pre-existing exposure is a DEBT, not a regression, and
`scripts/gate/secret_leak_ledger.txt` names the known set (item id + class + title — never a value).
The gate exits 0 when only ledger-listed `(item, class)` pairs hit and reddens on anything else, which
makes a NEW leak in a NEW item loud while the known ones stay on the books. `--update-ledger` re-derives
the file from a scan (derived, never hand-typed, CONVENTIONS §2) and `--strict` ignores it. A ledger
line whose hit is gone is reported so the book cannot rot into a standing free pass. Capture lines are
keyed per ITEM because capture paths are session ids that rotate — a declared limit: the ledger is
emptied by rotating, not by waiting.

Scan set (the class today's leaks landed in):
  * the repo working tree — `git ls-files --cached --others --exclude-standard`, plus repo `logs/*.log`;
  * `$SESSION_DIR/output-*.log`, and the same patterns under every pi run-capture root
    (`$TMPDIR`/`pi-subagents-*`, `/tmp/pi-subagents-*`): `output-*.log`, `events.jsonl`, `logs/*.log`;
  * `~/.pi/agent/sessions/**/*.jsonl` — the parent transcripts and the child `session.jsonl` files;
  * every `--path` given on the command line (file or directory).

Run:    python3 scripts/gate/check_secret_leak.py [--strict] [--self-test] [--path P …]
                                                   [--retired-file F] [--max-file-mb N] [--update-ledger]
Exit:   0 = no current value outside the ledger was found in anything scanned;
        1 = at least one CURRENT value sits where a transcript can be read;
        2 = environment boundary: no `op`, no auth, an empty vault answer, nothing scanned.
Wired into `validate-all.sh` (full profile only — the vault read makes it seat-dependent) and listed in
`scripts/README.md`.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import secrets
import shutil
import string
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)
VAULT = "Homelab-ansible"
LEDGER = ROOT / "scripts" / "gate" / "secret_leak_ledger.txt"

# A field is secret-bearing by its OWN id/label, never by the item's name: a `*_login` item keeps its
# credential in `password`, a `*_api` item in `credential`, and a section field can carry the label
# under a random id. `username`/`url`/`notesPlain`/`public_key` are NOT here — they are config or the
# public half, and matching them over half a gigabyte of transcripts reports noise, not exposure.
# Same config-vs-credential split as docs/deployment-secrets.md.
SECRET_FIELD_KEYS = ("password", "old-password", "credential", "token", "secret", "private_key",
                     "bcrypt_hash", "|api", "apikey")
# Below this length a containment match cannot be told apart from ordinary prose and paths, so those
# values are COUNTED and named by item rather than matched. The shape scanner is the instrument there.
MIN_VALUE_LEN = 8
DEFAULT_MAX_FILE_MB = 64
# The documented 1Password fan-out budget (docs/deployment-secrets.md §5): never exceed ~6.
PARALLEL_MAX = 6
# Run-capture patterns under the pi temp roots and $SESSION_DIR.
CAPTURE_PATTERNS = ("output-*.log", "events.jsonl", "session.jsonl", "logs/*.log")
# A ceiling on printed findings: 200 lines of the same item is a wall, not a report.
MAX_PRINTED = 40


class Boundary(Exception):
    """The check cannot judge this environment; it must print a reason, not a verdict."""


# --------------------------------------------------------------------------- vault read
def _op(args: list[str], timeout: int = 60) -> subprocess.CompletedProcess:
    return subprocess.run(["op", *args], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=timeout)


def _secret_fields(raw: dict) -> list[str]:
    out = []
    for f in raw.get("fields", []) or []:
        key = f"{f.get('id') or ''}|{f.get('label') or ''}".lower()
        if any(k in key for k in SECRET_FIELD_KEYS):
            v = f.get("value")
            if isinstance(v, str) and v:
                out.append(v)
    return out


def load_values(parallel: int) -> tuple[dict[bytes, list[str]], dict[str, str], list[str], list[str]]:
    """The fleet's CURRENT secret values. Returns (needles, id→title, short-value item ids, read errors)."""
    r = _op(["item", "list", "--vault", VAULT, "--format", "json"])
    if r.returncode != 0:
        raise Boundary(f"`op item list` rc {r.returncode}: {(r.stderr or '').strip()[:120]}")
    try:
        rows = json.loads(r.stdout)
    except json.JSONDecodeError as exc:
        raise Boundary(f"`op item list` did not answer JSON: {exc}") from exc
    if not rows:
        raise Boundary("`op item list` answered ZERO items — an empty vault answer is not an empty fleet")
    titles = {row["id"]: row.get("title", "?") for row in rows}

    def one(row: dict) -> tuple[str, list[str], str]:
        g = _op(["item", "get", row["id"], "--vault", VAULT, "--format", "json"], timeout=90)
        if g.returncode != 0:
            return row["id"], [], (g.stderr or "").strip()[:100]
        try:
            return row["id"], _secret_fields(json.loads(g.stdout)), ""
        except json.JSONDecodeError as exc:
            return row["id"], [], f"unparsable item JSON: {exc}"

    needles: dict[bytes, list[str]] = {}
    short: list[str] = []
    errs: list[str] = []
    with ThreadPoolExecutor(max_workers=max(1, min(parallel, PARALLEL_MAX))) as ex:
        for iid, vals, err in ex.map(one, rows):
            if err:
                errs.append(err)
            for v in vals:
                if len(v) < MIN_VALUE_LEN:
                    short.append(iid)
                    continue
                needles.setdefault(v.encode("utf-8", "surrogateescape"), []).append(iid)
    if not needles:
        raise Boundary("the vault read produced ZERO secret values — a vault that answers nothing "
                       "is an environment boundary, not a clean fleet")
    return needles, titles, short, errs


# --------------------------------------------------------------------------- scan set
def repo_tree_files() -> list[str]:
    r = subprocess.run(["git", "-C", str(ROOT), "ls-files", "--cached", "--others",
                        "--exclude-standard", "-z"], capture_output=True, text=True,
                       stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        return []
    out = [str(ROOT / p) for p in r.stdout.split("\0") if p]
    out += [str(p) for p in (ROOT / "logs").glob("*.log")]
    return out


def capture_files() -> list[str]:
    roots: list[str] = []
    if os.environ.get("SESSION_DIR"):
        roots.append(os.environ["SESSION_DIR"])
    tmp = os.environ.get("TMPDIR", "/tmp")
    roots += sorted(glob.glob(os.path.join(tmp, "pi-subagents-*")))
    if tmp != "/tmp":
        roots += sorted(glob.glob("/tmp/pi-subagents-*"))
    sess = Path.home() / ".pi" / "agent" / "sessions"
    files: list[str] = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for pat in CAPTURE_PATTERNS:
            files += [p for p in glob.glob(os.path.join(root, "**", pat), recursive=True)
                      if os.path.isfile(p)]
    if sess.is_dir():
        files += [str(p) for p in sess.rglob("*.jsonl")]
    return files


def expand(paths: list[str]) -> list[str]:
    out: list[str] = []
    for p in paths:
        path = Path(p)
        if path.is_file():
            out.append(str(path))
        elif path.is_dir():
            out += [str(f) for f in path.rglob("*") if f.is_file()]
    return out


# --------------------------------------------------------------------------- scan
def scan_files(files: list[str], needles: dict[bytes, list[str]], max_bytes: int,
               titles: dict[str, str]) -> tuple[list[tuple[str, int, str, str]], dict[str, int]]:
    """Whole-file containment. Findings: (path, line, item id, title); counts are never implied."""
    findings: list[tuple[str, int, str, str]] = []
    counts = {"scanned": 0, "bytes": 0, "too_big": 0, "binary": 0, "unreadable": 0}
    for path in files:
        try:
            size = os.path.getsize(path)
            if size > max_bytes:
                counts["too_big"] += 1
                continue
            data = Path(path).read_bytes()
        except OSError:
            counts["unreadable"] += 1
            continue
        if b"\0" in data[:8192]:
            counts["binary"] += 1
            continue
        counts["scanned"] += 1
        counts["bytes"] += size
        for needle, iids in needles.items():
            start = 0
            while True:
                i = data.find(needle, start)
                if i < 0:
                    break
                line = data.count(b"\n", 0, i) + 1
                for iid in iids:
                    findings.append((path, line, iid, titles.get(iid, "?")))
                start = i + 1
    return findings, counts


def scan_retired(files: list[str], retired: list[bytes], max_bytes: int) -> list[tuple[str, int]]:
    hits: list[tuple[str, int]] = []
    for path in files:
        try:
            data = Path(path).read_bytes()
        except OSError:
            continue
        if len(data) > max_bytes or b"\0" in data[:8192]:
            continue
        for needle in retired:
            i = data.find(needle)
            if i >= 0:
                hits.append((path, data.count(b"\n", 0, i) + 1))
    return hits


def scan_all(files: list[str], needles: dict[bytes, list[str]], max_mb: int,
             titles: dict[str, str]) -> tuple[list[tuple[str, int, str, str]], dict[str, int]]:
    findings, counts = scan_files(files, needles, max_mb * 1024 * 1024, titles)
    # One finding per (item, path): a value repeated through a 12 MB log is ONE exposure, not 4 000.
    uniq: dict[tuple[str, str], tuple[str, int, str, str]] = {}
    for path, line, iid, title in findings:
        uniq.setdefault((iid, path), (path, line, iid, title))
    return sorted(uniq.values()), counts


# --------------------------------------------------------------------------- ledger
def _class_of(path: str) -> str:
    return "repo-tree" if str(path).startswith(str(ROOT) + os.sep) else "run-capture"


def finding_text(path: str, line: int, iid: str, title: str) -> str:
    """A finding's ENTIRE disclosure: file, line, item id prefix, title. No value, no length, no
    captured line — ids and titles are already in docs/deployment-secrets.md, values are not, and this
    is the only place a finding is ever formatted (`--self-test` mutates it and must go red)."""
    return f"{path}:{line} matches item {iid[:8]} ({title})"


def read_ledger(path: Path) -> set[tuple[str, str]]:
    """The known-exposure book, keyed on `(item-id-prefix, class)`."""
    known: set[tuple[str, str]] = set()
    if not path.is_file():
        return known
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        cols = [c.strip() for c in line.split("\t")]
        if len(cols) >= 2 and cols[0] and cols[1]:
            known.add((cols[0], cols[1]))
    return known


LEDGER_HEADER = [
    "# secret_leak_ledger.txt — CURRENT vault values KNOWN to sit in a run capture or the repo tree.",
    "# One line per exposure: <item-id-prefix><TAB><class><TAB><item title>. Never a value, a length,",
    "# or a captured line. A line here is a DEBT: the only thing that closes a transcript leak is",
    "# ROTATING the item (docs/deployment-secrets.md §Creation & Rotation Workflow), after which",
    "# `check_secret_leak.py --update-ledger` re-derives this file and the line drops out. Any hit that",
    "# is NOT listed here reddens scripts/gate/check_secret_leak.py — the book is a debt register, not",
    "# a mute button, and a line whose hit is gone is printed as stale on every run until it is removed.",
]


def write_ledger(path: Path, findings: list[tuple[str, int, str, str]]) -> int:
    rows = sorted({(iid[:8], _class_of(path), title) for path, _l, iid, title in findings})
    body = "\n".join(f"{a}\t{b}\t{c}" for a, b, c in rows)
    path.write_text("\n".join(LEDGER_HEADER) + (("\n" + body) if body else "") + "\n", encoding="utf-8")
    return len(rows)


# --------------------------------------------------------------------------- verdict
def scan_run(files: list[str], needles: dict[bytes, list[str]], max_mb: int, titles: dict[str, str]
             ) -> tuple[list[tuple[str, int, str, str]], dict[str, int]]:
    if not files:
        raise Boundary("the scan set resolved to ZERO files — nothing to read is not a clean fleet")
    return scan_all(files, needles, max_mb, titles)


def ledger_split(findings: list[tuple[str, int, str, str]],
                 known: set[tuple[str, str]]) -> tuple[list, list]:
    """Split findings into (fresh, ledgered). The ONE place the ledger decides anything, so the
    self-test's ledger arm and the gate's verdict cannot drift apart."""
    fresh = [f for f in findings if (f[2][:8], _class_of(f[0])) not in known]
    ledgered = [f for f in findings if (f[2][:8], _class_of(f[0])) in known]
    return fresh, ledgered


def report(findings: list[tuple[str, int, str, str]], counts: dict[str, int], n_files: int,
           n_values: int, n_items: int, short: list[str], errs: list[str],
           ledger_path: Path, strict: bool, max_mb: int, retired_hits: list[tuple[str, int]]) -> int:
    if retired_hits:
        for path, line in retired_hits[:MAX_PRINTED]:
            print(f"INFO retired value (a DEAD secret, informational only) at {path}:{line}")
        print(f"INFO retired: {len(retired_hits)} file(s) still hold a SUPERSEDED value; superseded "
              "values are dead and are not findings")
    else:
        print("note: retired values NOT compared — superseded values are dead by definition; pass "
              "--retired-file <0600> for a probe window")
    print(f"scanned {counts['scanned']} of {n_files} path(s) / {counts['bytes'] / 1e6:.0f} MB "
          f"({counts['too_big']} over {max_mb} MB, {counts['binary']} binary, "
          f"{counts['unreadable']} unreadable); {n_values} current secret values from {n_items} items")
    if errs:
        print(f"NOTE: {len(errs)} item(s) did not read, so their values were NOT compared "
              f"(first: {errs[0]}) — a partial read is not a clean read")
    if short:
        print(f"note: {len(short)} secret field value(s) are under the {MIN_VALUE_LEN}-char containment "
              f"floor and were NOT matched, across {len(set(short))} item(s); "
              "scripts/gate/check_secrets.py is the instrument for those")

    known = set() if strict else read_ledger(ledger_path)
    fresh, ledgered = ledger_split(findings, known)
    if ledgered:
        items = sorted({f"{iid[:8]} {_class_of(path)} ({title})" for path, _l, iid, title in ledgered})
        print(f"KNOWN-EXPOSED {len(items)} item+class pair(s) from {ledger_path.name} — each is closed "
              "by ROTATING the item, then re-deriving the ledger:")
        for it in items:
            print(f"  {it}")
        hit_keys = {(f[2][:8], _class_of(f[0])) for f in findings}
        stale = sorted(known - hit_keys)
        if stale:
            print(f"STALE ledger lines (no hit this run — rotate-and-remove, or the book becomes a "
                  f"standing free pass): {len(stale)}")
            for k in stale[:10]:
                print(f"  {k[0]} {k[1]}")
    if fresh:
        print(f"FAIL: {len(fresh)} hit(s) outside the ledger — a CURRENT vault value is readable in a "
              "run capture or the repo tree. Rotate it; do not grep it, do not shred the transcript "
              "and call it closed:")
        for path, line, iid, title in fresh[:MAX_PRINTED]:
            print(finding_text(path, line, iid, title))
        if len(fresh) > MAX_PRINTED:
            print(f"  … {len(fresh) - MAX_PRINTED} more hit(s), same items, not listed")
        return 1
    print(f"OK: no current vault value outside the ledger appears in the {n_files} scanned path(s)")
    return 0


# --------------------------------------------------------------------------- self-test
def _mint(n: int = 32) -> str:
    return "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(n))


def _fixture_tree(dirpath: Path, values: dict[str, str], plant: tuple[str, ...] = ()) -> None:
    """A temp copy of the run-capture class. The values are MINTED here — a fixture never holds a
    fleet secret, which is what keeps a RED demo from becoming another leak."""
    lines = {"compose": f'  SLSKD_API_KEY: "{values["api"]}"\n',
             "env": f"export SLSKD_API_KEY={values['api']}\n",
             # No separator at all around the value: only a whole-file content search finds this,
             # which is the half a shape- or name-based redactor cannot reach.
             "glued": f"scanned prefix/z{values['key']}q/tail\n",
             "ini": f"api_key = {values['pw']}\n"}
    (dirpath / "logs").mkdir(parents=True, exist_ok=True)
    clean = ("converge: ok=12 changed=3 failed=0\n"
             "TASK [docker_services : deploy] ***\n"
             'SLSKD_API_KEY: "not-a-real-value-just-shape"\n'
             "arr root folder /media/music ok\n")
    # The clean file stays clean so an arm that counts findings counts plants, not copies.
    (dirpath / "logs" / "run.log").write_text(clean, encoding="utf-8")
    run_dir = dirpath / "run-0"
    run_dir.mkdir(exist_ok=True)
    (run_dir / "output-0.log").write_text(clean + "".join(lines[s] for s in plant), encoding="utf-8")
    (run_dir / "session.jsonl").write_text(
        json.dumps({"type": "message", "text": "ordinary transcript text"}) + "\n", encoding="utf-8")


def self_test() -> int:
    fails = 0
    values = {"api": _mint(), "pw": _mint(), "key": _mint()}
    needles_all = {v.encode(): [f"fixture{i}"] for i, v in enumerate(values.values())}
    titles_all = {f"fixture{i}": n for i, n in enumerate(values)}
    MB = 1024 * 1024

    def check(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        fails += not ok
        print(f"  arm {label}: {'ok' if ok else 'FAIL'}{(' — ' + detail) if (detail and not ok) else ''}")

    # (1) a clean tree reads GREEN — a check that cannot say so cannot be trusted to say otherwise.
    with tempfile.TemporaryDirectory() as td:
        tree = Path(td) / "clean"
        _fixture_tree(tree, values)
        found, _c = scan_all([str(p) for p in tree.rglob("*") if p.is_file()], needles_all,
                             DEFAULT_MAX_FILE_MB, titles_all)
        check("clean-tree GREEN", not found, f"{len(found)} finding(s) on a clean fixture")

    # (2) every shape of the SAME value reddens — compose-shaped is the one that beat a redactor.
    for shape, needle_item in (("compose", "api"), ("env", "api"), ("glued", "key"), ("ini", "pw")):
        with tempfile.TemporaryDirectory() as td:
            tree = Path(td) / shape
            _fixture_tree(tree, values, plant=(shape,))
            found, _c = scan_all([str(p) for p in tree.rglob("*") if p.is_file()], needles_all,
                                 DEFAULT_MAX_FILE_MB, titles_all)
            hit = [f for f in found if f[3] == needle_item]
            check(f"{shape}-shaped value REDDENS", len(hit) == 1 and "output-0.log" in hit[0][0],
                  f"{len(found)} finding(s), {len(hit)} for the planted item")

    # (3) the finding text discloses NOTHING: no value, no length, no captured line.
    with tempfile.TemporaryDirectory() as td:
        tree = Path(td) / "noecho"
        _fixture_tree(tree, values, plant=("compose", "glued", "ini"))
        found, _c = scan_all([str(p) for p in tree.rglob("*") if p.is_file()], needles_all,
                             DEFAULT_MAX_FILE_MB, titles_all)
        text = "\n".join(finding_text(p, l, i, t) for p, l, i, t in found)
        bad_values = [n for n, v in values.items() if v in text]
        bad_lengths = [n for n, v in values.items() if str(len(v)) in text.split()]
        check("finding text carries no value and no length", len(found) == 3 and not bad_values
              and not bad_lengths, f"disclosed: {bad_values or bad_lengths}")

    # (4) a rotated-out value is DEAD: INFO, never a finding.
    with tempfile.TemporaryDirectory() as td:
        tree = Path(td) / "retired"
        _fixture_tree(tree, values, plant=("compose",))
        ret = Path(td) / "retired-values"
        ret.write_bytes(values["api"].encode() + b"\n")
        os.chmod(ret, 0o600)
        files = [str(p) for p in tree.rglob("*") if p.is_file()]
        live = {k: v for k, v in needles_all.items() if k != values["api"].encode()}
        found, _c = scan_all(files, live, DEFAULT_MAX_FILE_MB, titles_all)
        hits = scan_retired(files, [values["api"].encode()], DEFAULT_MAX_FILE_MB * MB)
        check("retired value INFO-not-finding", not found and len(hits) == 1,
              f"findings={len(found)} retired-hits={len(hits)}")

    # (5) the ledger mutes ONLY the pair it names: a value outside it still reddens.
    with tempfile.TemporaryDirectory() as td:
        tree = Path(td) / "ledger"
        _fixture_tree(tree, values, plant=("compose", "glued"))
        led = Path(td) / "ledger.txt"
        files = [str(p) for p in tree.rglob("*") if p.is_file()]
        found, _c = scan_all(files, needles_all, DEFAULT_MAX_FILE_MB, titles_all)
        write_ledger(led, [f for f in found if f[3] == "api"])
        fresh, ledgered = ledger_split(found, read_ledger(led))
        check("ledger mutes the named item only",
              len(found) == 2 and len(fresh) == 1 and len(ledgered) == 1
              and fresh[0][3] == "key" and ledgered[0][3] == "api",
              f"found={len(found)} fresh={[f[3] for f in fresh]}")
        # and an EMPTY ledger must see all of them — the mute button cannot be the default.
        fresh_none, _ = ledger_split(found, read_ledger(Path(td) / "none"))
        check("no ledger file = no muting", len(fresh_none) == len(found) and bool(found),
              f"{len(fresh_none)} vs {len(found)}")

    # (6) an unreachable vault is a boundary: rc 2 with SKIP, never rc 0.
    with tempfile.TemporaryDirectory() as td:
        r = subprocess.run([sys.executable, str(Path(__file__).resolve())],
                           capture_output=True, text=True, env=dict(os.environ, PATH=td),
                           stdin=subprocess.DEVNULL)
        detail = f"rc {r.returncode}: {(r.stdout + r.stderr).strip()[:90]}"
        check("vault-unreachable prints SKIP and exits 2",
              r.returncode == 2 and "SKIP" in (r.stdout + r.stderr), detail)

    # (7) bounds are counted, not implied: a binary and an over-capacity file must be reported.
    with tempfile.TemporaryDirectory() as td:
        tree = Path(td) / "bounds"
        _fixture_tree(tree, values)
        (tree / "blob.bin").write_bytes(b"\x00\x01\x02" * 64)
        (tree / "huge.log").write_bytes(b"a" * (3 * MB))
        _f, counts = scan_all([str(p) for p in tree.rglob("*") if p.is_file()], needles_all, 1,
                              titles_all)
        check("binary + oversize skipped AND counted",
              counts["binary"] == 1 and counts["too_big"] == 1 and counts["scanned"] >= 3, str(counts))

    print(f"check_secret_leak.py --self-test: {fails} failing arm(s)")
    if fails:
        return 1
    # The self-mutation leg is skipped inside a mutant (it would recurse); the outer run pays it.
    if os.environ.get("LEAK_GATE_MUTANT") == "1":
        return 0
    failed = mutation_test()
    print(f"check_secret_leak.py --self-test mutations: {failed} mutant(s) escaped")
    return 1 if failed else 0


MUTATIONS = [
    # (label, old source text, new source text, which arm must go red)
    ("shape-only scan (a `=` before the value)",
     "        for needle, iids in needles.items():\n            start = 0",
     "        for needle, iids in needles.items():\n            needle = b\"=\" + needle\n            start = 0",
     "compose/ini/glued-shaped"),
    ("name-based scan, not content",
     "                i = data.find(needle, start)",
     "                i = data.find(('_' + titles.get(iids[0], '?') + '_api_key').encode(), start)",
     "leak arms"),
    ("a finding prints what it matched",
     'findings.append((path, line, iid, titles.get(iid, "?")))',
     'findings.append((path, line, iid, needle.decode("utf-8", "replace")))',
     "disclosure arm"),
    ("no `op` on PATH reads green",
     '              "Environment boundary, not a green.")\n        return 2',
     '              "Environment boundary, not a green.")\n        return 0',
     "vault-unreachable"),
    ("the ledger is ignored",
     "    fresh = [f for f in findings if (f[2][:8], _class_of(f[0])) not in known]",
     "    fresh = [f for f in findings if (f[2][:8], _class_of(f[0])) not in set()]",
     "ledger"),
    ("the ledger mutes every item, not the one it names",
     "    fresh = [f for f in findings if (f[2][:8], _class_of(f[0])) not in known]",
     "    known = {(f[2][:8], _class_of(f[0])) for f in findings}\n"
     "    fresh = [f for f in findings if (f[2][:8], _class_of(f[0])) not in known]",
     "ledger (both arms)"),
    ("an over-capacity file is skipped without saying so",
     '            if size > max_bytes:\n                counts["too_big"] += 1\n                continue',
     '            if size > max_bytes:\n                continue',
     "bounds"),
    ("the retired leg is dead code",
     '    for path in files:\n        try:\n            data = Path(path).read_bytes()\n        except OSError:\n            continue\n        if len(data) > max_bytes or b"\\0" in data[:8192]:',
     '    for path in []:\n        try:\n            data = Path(path).read_bytes()\n        except OSError:\n            continue\n        if len(data) > max_bytes or b"\\0" in data[:8192]:',
     "retired"),
]


def mutate(src: str, old: str, new: str) -> str | None:
    """Patch the CODE occurrence of `old`. The table below contains the same strings as data, so the
    table region is excluded — a checker that edited its own mutation table would prove nothing."""
    start = src.index("MUTATIONS = [")
    end = src.index("\n]", start)
    for m in re.finditer(re.escape(old), src):
        if not start <= m.start() < end:
            return src[:m.start()] + new + src[m.end():]
    return None


def mutation_test() -> int:
    """Self-mutation: patch THIS file's own scanning/reporting in a copy and require the arms to go red.
    A checker that cannot be broken is a claim, not a check — this is the leg that would have caught the
    redactor that missed a compose-shaped value on the day this gate shipped."""
    src = Path(__file__).read_text(encoding="utf-8")
    failed = 0
    for label, old, new, must_break in MUTATIONS:
        mutated = mutate(src, old, new)
        if mutated is None:
            print(f"  mutate {label}: FAIL — the source anchor moved")
            failed += 1
            continue
        # The mutant needs `scripts/lib/repo_root.py` on its import path — the module resolves its
        # root the same way every gate script does — so it goes into a throwaway `scripts/gate/` with
        # a copied lib, and $REPO points it back at THIS checkout. A copy left inside the tree would
        # be an untracked file every other tree-walking gate has to explain.
        with tempfile.TemporaryDirectory() as td:
            fake = Path(td) / "scripts"
            (fake / "lib").mkdir(parents=True)
            (fake / "gate").mkdir()
            shutil.copy(ROOT / "scripts" / "lib" / "repo_root.py", fake / "lib" / "repo_root.py")
            mutant = fake / "gate" / "leak-mutant.py"
            mutant.write_text(mutated, encoding="utf-8")
            r = subprocess.run([sys.executable, str(mutant), "--self-test"], capture_output=True,
                               text=True, env=dict(os.environ, LEAK_GATE_MUTANT="1", REPO=str(ROOT)),
                               stdin=subprocess.DEVNULL)
        broke = sorted({ln.split(" arm ")[1].split(":")[0] for ln in (r.stdout or "").splitlines()
                        if ": FAIL" in ln})
        ok = r.returncode == 1 and broke
        failed += not ok
        detail = (f"{len(broke)} arm(s) red: {', '.join(broke[:3])}" if ok else
                  f"rc {r.returncode}, nothing broke: {(r.stdout or r.stderr).strip()[-90:]}")
        print(f"  mutate {label} (must break the {must_break} arm): {'ok' if ok else 'FAIL'} — {detail}")
    return failed


# --------------------------------------------------------------------------- main
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true", help="prove the arms on minted fixtures")
    ap.add_argument("--path", action="append", default=[], help="extra file or directory to scan")
    ap.add_argument("--strict", action="store_true", help="ignore the exposure ledger")
    ap.add_argument("--retired-file", help="0600 file of SUPERSEDED values, reported as INFO only")
    ap.add_argument("--max-file-mb", type=int, default=DEFAULT_MAX_FILE_MB)
    ap.add_argument("--parallel", type=int, default=PARALLEL_MAX)
    ap.add_argument("--update-ledger", action="store_true", help="re-derive the ledger from this scan")
    args = ap.parse_args()

    if args.self_test:
        print("check_secret_leak.py --self-test")
        return self_test()

    if shutil.which("op") is None:
        print("SKIP: no `op` on PATH — a leak check needs the vault to know what a leak is. "
              "Environment boundary, not a green.")
        return 2

    retired: list[bytes] = []
    if args.retired_file:
        rf = Path(args.retired_file)
        if not rf.is_file():
            print(f"SKIP: --retired-file {rf} is not readable — environment boundary, not a green")
            return 2
        if rf.stat().st_mode & 0o077:
            print(f"NOTE: --retired-file is mode {rf.stat().st_mode & 0o777:o}; a retired value belongs "
                  "in a 0600 file that is shredded when the probe is done")
        retired = [ln.strip() for ln in rf.read_bytes().splitlines() if ln.strip()]

    try:
        needles, titles, short, errs = load_values(args.parallel)
        files = sorted(set(capture_files() + repo_tree_files() + expand(args.path)))
        findings, counts = scan_run(files, needles, args.max_file_mb, titles)
        if args.update_ledger:
            n = write_ledger(LEDGER, findings)
            print(f"ledger re-derived: {n} line(s) in {LEDGER.relative_to(ROOT)}")
            return 0
        hits = scan_retired(files, retired, args.max_file_mb * 1024 * 1024) if retired else []
        return report(findings, counts, len(files), len(needles), len(titles),
                      short, errs, LEDGER, args.strict, args.max_file_mb, hits)
    except Boundary as exc:
        print(f"SKIP: {exc} — an unavailable vault is an environment boundary, not a green")
        return 2


if __name__ == "__main__":
    sys.exit(main())
