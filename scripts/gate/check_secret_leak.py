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

(c) **A vault that cannot be read is a boundary, never a green.** No `op`, no importable Server
    SDK, an unreachable credential, or a read that answers nothing → exit 2 with the reason. The
    whole-vault read is the SHARED batched one — `scripts/lib/vault_read.py` is the ONE reader for
    the tree (Server SDK `items.list` + `items.get_all` in 50-ID chunks; a labelled `op item get`
    fan-out FALLBACK where the SDK will not import), values held in this process's memory only,
    and every run prints the request count and the route it took. This check only READS, so a
    read-scoped token is sufficient and is NOT a reason to skip: what gets probed is the read,
    because the read is what the check needs — scope is measured here, never inherited from prose
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
makes a NEW leak in a NEW item loud while the known ones stay on the books. `--strict` ignores the book.
A ledger line whose hit is gone is reported so the book cannot rot into a standing free pass. Capture
lines are keyed per ITEM because capture paths are session ids that rotate — a declared limit: the
ledger is emptied by rotating, not by waiting. `--update-ledger` is NON-DESTRUCTIVE across seats: it
drops a line only when THIS run read that line's class and did not hit that pair, it carries through
every line of a class it could not see, and `--class` scopes the rewrite to the one class a lane was
actually looking at. A ledger line in a class this run did not read prints `NOT JUDGED`, never `STALE`.

(e) **History is a class, not a blind spot.** `spark-llm_api` sat in a tracked bench capture for 13
    days; `git rm` of the artifact made the TREE scan go clean while the blob stayed reachable from
    `origin/main` forever, and both scanners read `git ls-files` — so the suite read green over a
    published credential (HD-1170). This leg reads the blobs, not the tip. Its finding is
    `<blob-sha> matches item <vault-id-prefix>` and nothing else: no value, no line, no length, no
    title. It is bounded by a cache in the object store's own directory, keyed on scanner version + the
    blob set + the vault's per-item VERSION numbers (never a hash of a secret, which would be both a
    disclosure and an oracle), so a repeat run on an unchanged store reads no blob at all — and SAYS
    so, because a cached verdict that prints as a fresh read is a green the run did not earn. Rotating
    an item bumps its version, which invalidates the cache: a rotated-out value in history stops being
    a finding, exactly as in (d).

(f) **A partial sweep never reads as a full green.** Every class the run did not look at prints with its
    reason (`--tree-only`/`--no-captures`, `--no-history`, or a class whose scan set resolved to zero
    files), the OK line carries `PARTIAL`, and a ledger line in an unread class prints `NOT JUDGED`
    rather than `STALE` — a class this run never read cannot prove a debt closed, and it cannot delete
    that class's lines either (see `--update-ledger`). The `run-capture` class is decided per STORE,
    not per corpus: every run names the stores it read (`pi-transcripts`, `pi-subagents-scratch`,
    `session-dir`), and the class is judged only when the PERSISTENT transcript store was READ — the
    `/tmp` scratch roots are wiped, so their presence says nothing about a debt recorded in `$HOME`
    and a checkout without the store cannot call such a debt closed.

Scan set (the class today's leaks landed in):
  * `repo-tree` — `git ls-files --cached --others --exclude-standard`, plus repo `logs/*.log`;
  * `run-capture` — `$SESSION_DIR/output-*.log`, and the same patterns under every pi run-capture root
    (`$TMPDIR`/`pi-subagents-*`, `/tmp/pi-subagents-*`): `output-*.log`, `events.jsonl`, `logs/*.log`;
    and `~/.pi/agent/sessions/**/*.jsonl` — the parent transcripts and the child `session.jsonl` files;
  * `git-history` — every BLOB reachable from any ref (`git rev-list --objects --all`), so a value that
    was in the tree once and was edited out stays a finding. Declared limit: a blob reachable ONLY from
    a reflog or as a dangling object is not in that set — which is why a `git cat-file
    --batch-all-objects` sweep can name a hit blob this leg does not;
  * every `--path` given on the command line (file or directory, counted in `repo-tree`).

Run:    python3 scripts/gate/check_secret_leak.py [--strict] [--self-test] [--path P …]
                                                   [--retired-file F] [--max-file-mb N]
                                                   [--tree-only | --no-captures] [--no-history]
                                                   [--update-ledger [--class C] …]
Exit:   0 = no current value outside the ledger was found in anything scanned;
        1 = at least one CURRENT value sits where a transcript can be read, or --update-ledger refused;
        2 = environment boundary: no `op`, no auth, an empty vault answer, nothing scanned.
Wired into `validate-all.sh` (full profile only — the vault read makes it seat-dependent) and listed in
`scripts/README.md`.
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import io
import json
import os
import re
import secrets
import shutil
import string
import subprocess
import sys
import tempfile
import time
from contextlib import redirect_stdout
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
# On a Win11 seat the locale default is cp1252, so the em-dashes in this file's own verdict lines
# encode as bytes the READER of a captured subprocess cannot decode (the sibling checkers pin
# themselves the same way — the HD-1202 class: the same leg must ask the same question on both
# seat planes). Pin stdout/stderr to UTF-8; a no-op where the locale already is.
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass
from repo_root import root as _hl_root  # noqa: E402
from vault_read import Boundary as _ReadBoundary, read_vault as _read_vault  # noqa: E402
from vault_env import provenance as _vault_provenance  # noqa: E402

ROOT = _hl_root(__file__)
VAULT = "Homelab-ansible"
# $HL_LEAK_LEDGER is a test seam, not a feature: `--update-ledger` WRITES, so a fixture (or a
# demonstration of a refusal) must be able to aim it at a COPY. Unset in every normal run, where the
# committed file is the book.
LEDGER = Path(os.environ.get("HL_LEAK_LEDGER") or ROOT / "scripts" / "gate" / "secret_leak_ledger.txt")
# The classes. A finding carries its own, because the ledger mutes one (item, class) pair at a time and
# a run has to be able to name the classes it did NOT look at.
CLASSES = ("repo-tree", "run-capture", "git-history")
# A finding: (target, line, vault item id, item title, class). `target` is a path for a file class and a
# blob sha for `git-history`, where `line` is 0 because a blob has no line a report may print.
Finding = tuple[str, int, str, str, str]

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
# Run-capture patterns under the pi temp roots and $SESSION_DIR.
CAPTURE_PATTERNS = ("output-*.log", "events.jsonl", "session.jsonl", "logs/*.log")
# A ceiling on printed findings: 200 lines of the same item is a wall, not a report.
MAX_PRINTED = 40
# Bump when the needle selection or the matching changes: it is part of the history cache key, so the
# bump is what stops an old verdict from being read as a verdict this scanner produced.
HISTORY_SCANNER = "leak-gate/1"
HISTORY_CACHE_NAME = "homelab-leak-history-cache.tsv"
# One `git cat-file --batch` read per this many bytes of history: 500 blobs at a time would spawn 24
# processes over this store, and a 40 MB object would arrive whole.
HISTORY_READ_BYTES = 32 * 1024 * 1024


class Boundary(Exception):
    """The check cannot judge this environment; it must print a reason, not a verdict."""


# --------------------------------------------------------------------------- vault read
# The whole-vault read is the SHARED batched one — scripts/lib/vault_read.py is the ONE reader for
# the tree (Server SDK: `items.list` + `items.get_all` in 50-ID chunks; labelled FALLBACK: the
# ID-addressed `op item get` fan-out). This file holds no fan-out, no timeouts of its own and no
# address book: the ceilings and the request counting belong to the reader, which prints `route=`,
# the request count and the per-item versions digest on stderr for every read.


def _secret_fields(raw: dict) -> list[str]:
    out = []
    for f in raw.get("fields", []) or []:
        key = f"{f.get('id') or ''}|{f.get('label') or ''}".lower()
        if any(k in key for k in SECRET_FIELD_KEYS):
            v = f.get("value")
            if isinstance(v, str) and v:
                out.append(v)
    return out


def load_values() -> tuple[dict[bytes, list[str]], dict[str, str], list[str], list[str], str]:
    """The fleet's CURRENT secret values, off the ONE shared read.
    Returns (needles, id→title, short-value item ids, read errors, vault version key)."""
    try:
        vr = _read_vault(VAULT)
    except (_ReadBoundary, OSError, ValueError) as exc:
        raise Boundary(str(exc)) from exc
    needles: dict[bytes, list[str]] = {}
    short: list[str] = []
    # The reader's OWN partial-read list, not an empty one declared here: an item that failed to read
    # is an item whose value was never compared, and the report's "a partial read is not a clean
    # read" line is only true if it arrives. (It used to stay empty forever, which made that line
    # unreachable prose and the ledger below it unsafe to re-derive.)
    errs: list[str] = list(vr.errors)
    titles = {iid: row.get("title", "?") for iid, row in vr.items.items()}
    for iid, row in vr.items.items():
        for v in _secret_fields(row):
            if len(v) < MIN_VALUE_LEN:
                short.append(iid)
                continue
            needles.setdefault(v.encode("utf-8", "surrogateescape"), []).append(iid)
    # The leg's own quota line is the READER's line — same shape on every leg, so "what did today
    # cost" is one grep across the gate rather than one format per file.
    vr.print_cost("check_secret_leak.py")
    if not needles:
        raise Boundary("the vault read produced ZERO secret values — a vault that answers nothing "
                       "is an environment boundary, not a clean fleet")
    # vr.vkey is the sha256 of the per-item `id<TAB>version` rows — deliberately NOT a digest of
    # the values: a digest of an 8-char secret is a dictionary oracle, and the version bump is the
    # only event that changes what a history hit MEANS. The formula lives in the reader so every
    # leg's cache key moves together or not at all.
    return needles, titles, short, errs, vr.vkey


# --------------------------------------------------------------------------- scan set
def repo_tree_files() -> list[str]:
    r = subprocess.run(["git", "-C", str(ROOT), "ls-files", "--cached", "--others",
                        "--exclude-standard", "-z"], capture_output=True,
                       stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        return []
    # git emits UTF-8 filenames; decoding them with the locale default (cp1252 on the Win11 seat)
    # turns a non-decodable byte into stdout=None and this line into an AttributeError (docs/harness-pi-seats.md §1).
    out = [str(ROOT / p) for p in (r.stdout or b"").decode("utf-8", "replace").split("\0") if p]
    out += [str(p) for p in (ROOT / "logs").glob("*.log")]
    return out


def capture_files(home: Path | None = None) -> list[str]:
    """Flat view of every store — the scan set. The VERDICT view is `capture_stores()`; a run that
    decides per class on "is the corpus non-empty" without naming its stores is the HD-1181 failure
    shape (scratch keeping a store-less checkout green)."""
    return sorted({p for s in capture_stores(home).values() for p in s["files"]})


# The run-capture class is not one corpus, it is STORES, and they are not interchangeable:
# `pi-transcripts` (~/.pi/agent/sessions) is the PERSISTENT store the ledger debts sit in — it
# survives a reboot, so its ABSENCE proves nothing while its PRESENCE proves absence of a hit;
# `pi-subagents-*` scratch roots and a per-session `$SESSION_DIR` live under /tmp, so they are
# wiped (their absence can be evidence of closure, their presence is no evidence about the
# persistent store at all). A guard that judges the class on "corpus non-empty" lets scratch keep
# the corpus non-empty when the transcript store is absent — that is how a store-less checkout
# exits 0 and prints live debts as STALE. So: every run-capture verdict NAMES the stores it read,
# and the class is JUDGED only when the persistent store was READ.
def capture_stores(home: Path | None = None) -> dict[str, dict]:
    """store name -> {files, read, why}. READ means the store's root exists and was scanned — zero
    files in a READ store still proves absence there; a root that is not there was NOT READ and
    cannot close a debt recorded in it."""
    home = Path(home) if home else Path.home()
    stores: dict[str, dict] = {}
    sess = home / ".pi" / "agent" / "sessions"
    files = [str(p) for p in sess.rglob("*.jsonl")] if sess.is_dir() else []
    stores["pi-transcripts"] = {
        "files": files,
        "read": sess.is_dir(),
        "why": f"scanned {sess}" if sess.is_dir() else f"no store at {sess} on this seat",
    }
    scratch: list[str] = []
    roots: list[str] = []
    tmp = os.environ.get("TMPDIR", "/tmp")
    roots += sorted(glob.glob(os.path.join(tmp, "pi-subagents-*")))
    if tmp != "/tmp":
        roots += sorted(glob.glob("/tmp/pi-subagents-*"))
    for root in roots:
        for pat in CAPTURE_PATTERNS:
            scratch += [p for p in glob.glob(os.path.join(root, "**", pat), recursive=True)
                        if os.path.isfile(p)]
    stores["pi-subagents-scratch"] = {
        "files": sorted(set(scratch)),
        "read": bool(roots),
        "why": f"scanned {len(roots)} root(s)" if roots else f"no pi-subagents-* root under {tmp}",
    }
    if os.environ.get("SESSION_DIR"):
        sd = os.environ["SESSION_DIR"]
        sfiles: list[str] = []
        if os.path.isdir(sd):
            for pat in CAPTURE_PATTERNS:
                sfiles += [p for p in glob.glob(os.path.join(sd, "**", pat), recursive=True)
                           if os.path.isfile(p)]
        stores["session-dir"] = {"files": sorted(set(sfiles)), "read": os.path.isdir(sd),
                                 "why": f"scanned {sd}" if os.path.isdir(sd)
                                        else f"SESSION_DIR points nowhere ({sd})"}
    return stores


def stores_note(stores: dict[str, dict]) -> str:
    """The line that makes the verdict name its stores — a run must say WHERE it looked, because
    'checked the captures' is false whenever only scratch answered."""
    read = [f"{name} ({len(s['files'])} file(s); {s['why']})" for name, s in sorted(stores.items())
            if s["read"]]
    unread = [f"{name} ({s['why']})" for name, s in sorted(stores.items()) if not s["read"]]
    line = "run-capture stores read: " + (", ".join(read) or "NONE")
    if unread:
        line += " — NOT READ: " + ", ".join(unread)
    return line


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
class ScanRun(NamedTuple):
    """What one invocation actually looked at. `not_scanned` is part of the verdict, not a footnote: a
    partial sweep that prints like a full green is the mute-the-gate failure mode wearing a green coat,
    and a ledger line in a class that was never read cannot be called STALE (no evidence either way)."""
    findings: list[Finding]
    counts: dict[str, int]
    n_paths: int
    scanned: set[str]
    not_scanned: dict[str, str]
    notes: list[str]


def zero_counts() -> dict[str, int]:
    return {"scanned": 0, "bytes": 0, "too_big": 0, "binary": 0, "unreadable": 0}


def scan_files(files: list[str], needles: dict[bytes, list[str]], max_bytes: int,
               titles: dict[str, str]) -> tuple[list[Finding], dict[str, int]]:
    """Whole-file containment. Findings: (path, line, item id, title, class); counts are never implied."""
    findings: list[Finding] = []
    counts = zero_counts()
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
                    findings.append((path, line, iid, titles.get(iid, "?"), _class_of(path)))
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
             titles: dict[str, str]) -> tuple[list[Finding], dict[str, int]]:
    findings, counts = scan_files(files, needles, max_mb * 1024 * 1024, titles)
    # One finding per (item, path): a value repeated through a 12 MB log is ONE exposure, not 4 000.
    uniq: dict[tuple[str, str], Finding] = {}
    for f in findings:
        uniq.setdefault((f[2], f[0]), f)
    return sorted(uniq.values()), counts


def scan_run(files_by_class: dict[str, list[str]], needles: dict[bytes, list[str]], max_mb: int,
             titles: dict[str, str]) -> tuple[list[Finding], dict[str, int], dict[str, int]]:
    """Scan each class's own scan set, so `which classes did this run judge` is a fact the run carries
    instead of something the reporter has to remember. Returns (findings, counts, files per class)."""
    findings: list[Finding] = []
    counts = zero_counts()
    corpus: dict[str, int] = {}
    for cls, files in sorted(files_by_class.items()):
        got, got_counts = scan_all(files, needles, max_mb, titles)
        findings += got
        for k, v in got_counts.items():
            counts[k] += v
        corpus[cls] = len(files)
    return sorted(findings), counts, corpus


def class_verdict(corpus: dict[str, int], skipped: dict[str, str],
                  stores: dict[str, dict] | None = None) -> tuple[set[str], dict[str, str]]:
    """Which classes this run may JUDGE — with the run-capture class decided by its PERSISTENT
    store, not by the corpus: a scratch root can keep a corpus non-empty while the store the debts
    live in was never read, and a class you cannot see cannot prove a debt closed — nor delete that
    debt's ledger line next run."""
    judged, not_scanned = set(), dict(skipped)
    for cls, n in corpus.items():
        if cls == "run-capture" and stores is not None:
            gate = stores["pi-transcripts"]
            if gate["read"]:
                judged.add(cls)
            else:
                not_scanned[cls] = ("the persistent transcript store was NOT read "
                                    f"({gate['why']}) — scratch roots say nothing about it, so no "
                                    "run-capture debt is proven closed here")
            continue
        if n:
            judged.add(cls)
        else:
            not_scanned[cls] = ("its scan set resolved to ZERO files here — nothing was read, so nothing "
                                "about that class is proven")
    return judged, not_scanned


# --------------------------------------------------------------------------- history leg
def _git(repo: Path, args: list[str], stdin: bytes | None = None) -> subprocess.CompletedProcess:
    fed = {"input": stdin} if stdin is not None else {"stdin": subprocess.DEVNULL}
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, check=False, **fed)


def history_cache_path(repo: Path | None = None) -> Path:
    """The cache lives in the OBJECT STORE's directory, not in the work tree: it is a property of the
    store (so every worktree of one clone shares one cache instead of paying a cold sweep each), and an
    untracked file in the work tree is something every tree-walking gate would have to explain — this
    one included, since it scans `git ls-files --others`."""
    if os.environ.get("HL_LEAK_HISTORY_CACHE"):
        return Path(os.environ["HL_LEAK_HISTORY_CACHE"])
    r = _git(repo or ROOT, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
    if r.returncode != 0 or not r.stdout.strip():
        raise Boundary("the history leg cannot locate the object store (`git rev-parse --git-common-dir` "
                       "failed) — no cache, no verdict, not a green")
    return Path(r.stdout.decode().strip()) / HISTORY_CACHE_NAME


def ref_blobs(repo: Path) -> tuple[dict[str, int], str]:
    """The blobs reachable from ANY ref, with their sizes, plus a fingerprint of that set.

    `--all` is every ref, so a value published on `main` stays a finding after the file holding it is
    deleted — that is the whole point of the leg. Declared limit: a blob reachable only from a reflog,
    or dangling, is NOT here, so a `git cat-file --batch-all-objects` sweep can name more hit blobs."""
    r = _git(repo, ["rev-list", "--objects", "--all"])
    if r.returncode != 0:
        raise Boundary(f"the history leg cannot enumerate the object store: `git rev-list --objects "
                       "--all` rc {r.returncode} — not a green")
    shas = [ln.split(" ")[0] for ln in r.stdout.decode(errors="replace").splitlines() if ln]
    chk = _git(repo, ["cat-file", "--batch-check"], stdin=("\n".join(shas) + "\n").encode())
    if chk.returncode != 0:
        raise Boundary("`git cat-file --batch-check` failed on the reachable object list — the history "
                       "leg has no scan set, which is a boundary, not a clean store")
    blobs: dict[str, int] = {}
    for ln in chk.stdout.decode(errors="replace").splitlines():
        parts = ln.split(" ")
        if len(parts) == 3 and parts[1] == "blob":
            blobs[parts[0]] = int(parts[2])
    fp = hashlib.sha256("\n".join(sorted(blobs)).encode()).hexdigest()
    return blobs, fp


def read_blobs(repo: Path, shas: list[str], sizes: dict[str, int]):
    """Yield (sha, bytes) for the named blobs, one `git cat-file --batch` per HISTORY_READ_BYTES so a
    big object cannot arrive whole next to 500 small ones."""
    batch: list[str] = []
    total = 0
    for sha in [*shas, None]:
        if sha is not None:
            batch.append(sha)
            total += sizes.get(sha, 0)
        if sha is None or total >= HISTORY_READ_BYTES:
            if not batch:
                return
            r = _git(repo, ["cat-file", "--batch"], stdin=("\n".join(batch) + "\n").encode())
            data = r.stdout or b""
            pos = 0
            while pos < len(data):
                nl = data.find(b"\n", pos)
                if nl < 0:
                    break
                parts = data[pos:nl].decode(errors="replace").split(" ")
                if len(parts) == 3 and parts[1] == "blob":
                    size = int(parts[2])
                    yield parts[0], data[nl + 1:nl + 1 + size]
                    pos = nl + 1 + size + 1
                else:
                    pos = nl + 1          # "<sha> missing", or a commit/tree asked for by mistake
            batch, total = [], 0
        if sha is None:
            return


def _history_cache(path: Path, vkey: str) -> tuple[dict[str, list[str]], str, dict[str, str]]:
    """Load the cache: (per-blob verdicts, why the cache was NOT usable — empty when usable, header).

    A row is reusable because a blob is addressed BY ITS CONTENT: the same sha is the same bytes, so the
    only things that can stale a row are a different scanner or a different current-value set."""
    if not path.is_file():
        return {}, "no cache file in this object store yet", {}
    rows: dict[str, list[str]] = {}
    hdr: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        return {}, f"the cache file could not be read ({exc})", {}
    for line in lines:
        if line.startswith("#") or not line.strip():
            continue
        cols = line.split("\t")
        if len(cols) != 2:
            continue
        if cols[0] in ("scanner", "values", "blobset", "written", "head"):
            hdr[cols[0]] = cols[1]
        elif len(cols[0]) == 40:
            rows[cols[0]] = [c for c in cols[1].split(",") if c]
    if hdr.get("scanner") != HISTORY_SCANNER:
        return {}, f"written by scanner {hdr.get('scanner', '?')}, this run is {HISTORY_SCANNER}", hdr
    if hdr.get("values") != vkey:
        # The interesting invalidation: the vault changed, so a value in history may be dead now.
        return {}, ("the vault's item versions changed since the cache was written (a ROTATION?) — a "
                    "rotated-out value in history is DEAD and must stop being a finding"), hdr
    if not rows:
        return {}, "the cache holds no blob verdicts", hdr
    return rows, "", hdr


def history_note(info: dict) -> str:
    """The history leg's line — including what it did NOT read. A cache hit that prints like a fresh
    sweep is a green the run did not earn, so the inherited half names its provenance."""
    if info["read"] == 0:
        src = (f"{info['cached']} carried from the cache written {info.get('written', '?')} at "
               f"{info.get('head', '?')} (scanner {info['scanner']}, values {info['values'][:12]}, blob set "
               f"{info['blobset'][:12]}) — NO blob was read for those: that half of the verdict is "
               "INHERITED, not re-derived by this run")
    else:
        src = f"{info['read']} read by this run, {info['cached']} carried from the cache"
    why = f" (cache not usable: {info['stale_why']})" if info.get("stale_why") else ""
    return (f"git-history: {info['blobs']} blob(s) reachable from refs, {info['bytes'] / 1e6:.0f} MB, "
            f"{info['hit_blobs']} hit blob(s) — {src}{why}")


def scan_history(needles: dict[bytes, list[str]], titles: dict[str, str], vkey: str,
                 repo: Path | None = None, cache: Path | None = None) -> tuple[list[Finding], dict]:
    """The `git-history` class: CURRENT values inside blobs reachable from refs, with the cache the
    sweep needs to stay bounded. Never reads a working-tree file and never prints a value."""
    repo = repo or ROOT
    cache = cache or history_cache_path(repo)
    sizes, blobs_fp = ref_blobs(repo)
    shas = sorted(sizes)
    seen, stale_why, hdr = _history_cache(cache, vkey)
    need = [s for s in shas if s not in seen]
    read = 0
    for sha, body in read_blobs(repo, need, sizes):
        read += 1
        hits = {iid for needle, iids in needles.items() if len(needle) >= MIN_VALUE_LEN
                and b"\0" not in body[:8192] and needle in body for iid in iids}
        seen[sha] = sorted(hits)
    findings: list[Finding] = [(s, 0, iid, titles.get(iid, "?"), "git-history")
                               for s in shas for iid in seen.get(s, [])]
    head = _git(repo, ["rev-parse", "--short", "HEAD"]).stdout.decode().strip()
    info = {"blobs": len(shas), "read": read, "cached": len(shas) - read,
            "hit_blobs": len({f[0] for f in findings}), "bytes": sum(sizes.values()),
            "blobset": blobs_fp, "stale_why": stale_why, "cache": str(cache), "values": vkey,
            "scanner": HISTORY_SCANNER, "head": head, "written": hdr.get("written", "now")}
    _write_history_cache(repo, cache, vkey, blobs_fp, seen)
    return sorted(findings), info


def _write_history_cache(repo: Path, path: Path, vkey: str, blobs_fp: str,
                         seen: dict[str, list[str]]) -> None:
    head = _git(repo, ["rev-parse", "--short", "HEAD"]).stdout.decode().strip()
    body = "\n".join(f"{sha}\t{','.join(sorted(iids))}" for sha, iids in sorted(seen.items()))
    text = ("# check_secret_leak.py git-history cache — blob shas, vault item IDS and version numbers.\n"
            "# A blob sha IS its content, so a row is reusable until the scanner or the current-value set\n"
            "# changes; those two are the header. Nothing here is a secret value, a line or a length.\n"
            f"scanner\t{HISTORY_SCANNER}\nvalues\t{vkey}\nblobset\t{blobs_fp}\n"
            f"written\t{time.strftime('%Y-%m-%dT%H:%M:%S%z')}\nhead\t{head}\n"
            f"{body}\n")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(text, encoding="utf-8")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except OSError as exc:
        # Losing the cache costs time on the next run, never a verdict — but it says so.
        print(f"NOTE: the git-history cache was not written ({exc}) — the next run pays the full sweep")


# --------------------------------------------------------------------------- ledger
def _class_of(path: str) -> str:
    """The class of a FILE finding. A `git-history` finding names a blob rather than a path, so it
    carries its class where it is built — the alternative is guessing which class a string is, which is
    how a mute ends up wider than the pair the book names."""
    return "repo-tree" if str(path).startswith(str(ROOT) + os.sep) else "run-capture"


def finding_text(target: str, line: int, iid: str, title: str, cls: str = "repo-tree") -> str:
    """A finding's ENTIRE disclosure. For a file: file, line, item id prefix, title. For a blob: the sha
    and the id prefix, and NOTHING else — no line, no length, not even the title. No value and no
    captured line in either case: ids and titles are already in docs/deployment-secrets.md, values are
    not, and this is the only place a finding is ever formatted (`--self-test` mutates it and must go
    red)."""
    if cls == "git-history":
        return f"{target} matches item {iid[:8]}"
    return f"{target}:{line} matches item {iid[:8]} ({title})"


def extra_comments(path: Path) -> list[str]:
    """Comment lines a human added to EXPLAIN a debt, kept across a re-derivation.

    They are not derived data, so dropping them would delete an argument someone made (the ledger names
    its HD rows in comments, and HD-1171's note is the reason its line exists). Everything that is not
    the canonical header is preserved, in file order."""
    if not path.is_file():
        return []
    keep = set(LEDGER_HEADER)
    return [ln for ln in path.read_text(encoding="utf-8", errors="replace").splitlines()
            if ln.startswith("#") and ln not in keep]


def read_ledger_rows(path: Path) -> list[tuple[str, str, str]]:
    """The book as ROWS: (item-id-prefix, class, title). Comments are skipped, so the comments a human
    added to explain a debt survive a re-derivation only if `--update-ledger` keeps them — it writes its
    own header and keeps the rows, never the other way round."""
    rows: list[tuple[str, str, str]] = []
    if not path.is_file():
        return rows
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        cols = [c.strip() for c in line.split("\t")]
        if len(cols) >= 2 and cols[0] and cols[1]:
            rows.append((cols[0], cols[1], cols[2] if len(cols) > 2 else "?"))
    return rows


def read_ledger(path: Path) -> set[tuple[str, str]]:
    """The known-exposure book, keyed on `(item-id-prefix, class)`."""
    return {(item, cls) for item, cls, _t in read_ledger_rows(path)}


LEDGER_HEADER = [
    "# secret_leak_ledger.txt — CURRENT vault values KNOWN to sit in a run capture, the repo tree, or a",
    "# blob that is still reachable from a ref.",
    "# One line per exposure: <item-id-prefix><TAB><class><TAB><item title>. Never a value, a length,",
    "# or a captured line. A line here is a DEBT: the only thing that closes a transcript leak is",
    "# ROTATING the item (docs/deployment-secrets.md §Creation & Rotation Workflow), after which",
    "# `check_secret_leak.py --update-ledger` re-derives this file and the line drops out. Any hit that",
    "# is NOT listed here reddens scripts/gate/check_secret_leak.py — the book is a debt register, not",
    "# a mute button, and a line whose hit is gone is printed as stale on every run until it is removed.",
    "# A `git-history` line is a value that is PUBLISHED and cannot be removed from the tree at all;",
    "# only rotation closes it, and a rewrite of the public history would not, because GitHub keeps old",
    "# commits reachable by SHA. `--update-ledger` never drops such a line unless the history leg ran.",
]


def update_ledger(path: Path, findings: list[Finding], judged: set[str],
                  class_scope: list[str] | None = None,
                  partial: list[str] | None = None) -> int:
    """Rewrite the book from this run — without ever deleting a debt this run could not see.

    The old behaviour was `write_ledger(findings)`: derive everything from what THIS seat's scan set
    reached. On a seat whose captures are elsewhere that rewrote 24 lines to 2, which is not a re-derive
    but an erasure — the items stay exposed, and the next run on the seat that recorded them prints them
    as fresh FAILs. So a line may only be dropped when this run PROVED the pair absent, which needs the
    class to have been scanned AND to have had a non-empty corpus. Everything else is carried through
    unchanged, and a scope that reaches a class this run could not read is a refusal, not a rewrite.

    `judged` is the set of classes this run actually read with a non-empty corpus — the only classes
    entitled to prove a pair absent.

    `partial` is the reader's list of items that did NOT read. A run holding one cannot prove any
    pair absent, because a hit is a match against the CURRENT value set and part of that set is
    unknown to it — so the rewrite is refused, not narrowed. (The unread item's own id is not carried
    here on purpose: the SDK's `individual_responses` do not promise the order the IDs went in, and a
    ledger pruned by a guess is the erasure this function exists to prevent.)
    Returns 0 when the file was written, 1 when the rewrite was refused (the file is then untouched).
    """
    if partial:
        print(f"REFUSED: --update-ledger will not re-derive the book after a PARTIAL vault read — "
              f"{len(partial)} item(s) did not read (first: {partial[0][:80]})")
        print("Refusing to write: the file is unchanged. A value this run never saw cannot be proven "
              "absent, and dropping its line would print a live debt as a fresh FAIL on the next "
              "seat that could read the item. Re-run when the read is clean.")
        return 1
    scope = set(class_scope) if class_scope else set(judged)
    blind = sorted(scope - judged)
    rows = read_ledger_rows(path)
    hit = {ledger_key(f) for f in findings if f[4] in scope}
    carried = [r for r in rows if r[1] not in scope]
    dropped = [r for r in rows if r[1] in scope and (r[0], r[1]) not in hit]
    if blind:
        would = [r for r in rows if r[1] in blind]
        print(f"REFUSED: --update-ledger would delete {len(would)} line(s) it cannot prove — "
              f"scope reached {', '.join(blind)}, which this run did not scan with a non-empty corpus")
        for item, cls, title in would:
            print(f"  would remove {item} {cls} ({title}) — this run read NOTHING of that class, so it "
                  "has no evidence the exposure closed; the line belongs to the seat that recorded it "
                  "and deleting it there would print a live debt as a fresh FAIL")
        print("Refusing to write: the file is unchanged. Name only the classes actually scanned "
              "(--class), or drop --update-ledger.")
        return 1
    derived = sorted({(f[2][:8], f[4], f[3]) for f in findings if f[4] in scope})
    final = sorted(set(carried) | set(derived))
    body = "\n".join(f"{a}\t{b}\t{c}" for a, b, c in final)
    comments = extra_comments(path)
    path.write_text("\n".join(LEDGER_HEADER + comments) + (("\n" + body) if body else "") + "\n",
                    encoding="utf-8")
    print(f"ledger rewritten: {len(final)} line(s) in {path.name}, derived from {sorted(scope)}"
          + (f" ({len(comments)} explanatory comment line(s) kept)" if comments else ""))
    for item, cls, title in dropped:
        print(f"  dropped {item} {cls} ({title}) — proven ABSENT this run: the class was scanned with a "
              "corpus and did not hit that pair")
    if carried:
        print(f"  carried through unchanged: {len(carried)} line(s) of class(es) this run did not "
              f"rewrite ({sorted({r[1] for r in carried})})")
    return 0


# --------------------------------------------------------------------------- verdict
def ledger_key(f: Finding) -> tuple[str, str]:
    """The ONE shape of a ledger key: (item-id-prefix, class). A mute that is wider than the pair the
    book names is the failure this register exists to avoid, so it is spelled here and nowhere else."""
    return (f[2][:8], f[4])


def ledger_split(findings: list[Finding], known: set[tuple[str, str]]) -> tuple[list, list]:
    """Split findings into (fresh, ledgered). The ONE place the ledger decides anything, so the
    self-test's ledger arm and the gate's verdict cannot drift apart."""
    fresh = [f for f in findings if ledger_key(f) not in known]
    ledgered = [f for f in findings if ledger_key(f) in known]
    return fresh, ledgered


def report(res: ScanRun, n_values: int, n_items: int, short: list[str], errs: list[str],
           ledger_path: Path, strict: bool, max_mb: int,
           retired_hits: list[tuple[str, int]]) -> int:
    for note in res.notes:
        print(note)
    # Which credential answered is part of the verdict: the two service accounts list the same one
    # vault, so a run that does not name its route cannot be told apart from one reading the fleet
    # with the write-scoped credential (or none at all).
    print(_vault_provenance())
    if retired_hits:
        for path, line in retired_hits[:MAX_PRINTED]:
            print(f"INFO retired value (a DEAD secret, informational only) at {path}:{line}")
        print(f"INFO retired: {len(retired_hits)} file(s) still hold a SUPERSEDED value; superseded "
              "values are dead and are not findings")
    else:
        print("note: retired values NOT compared — superseded values are dead by definition; pass "
              "--retired-file <0600> for a probe window")
    print(f"scanned {res.counts['scanned']} of {res.n_paths} path(s) / {res.counts['bytes'] / 1e6:.0f} MB "
          f"({res.counts['too_big']} over {max_mb} MB, {res.counts['binary']} binary, "
          f"{res.counts['unreadable']} unreadable); {n_values} current secret values from {n_items} items; "
          f"classes judged: {sorted(res.scanned) or 'NONE'}")
    for cls, why in sorted(res.not_scanned.items()):
        print(f"NOT SCANNED {cls}: {why} — a finding of that class would NOT appear in this report, so "
              "this is a PARTIAL sweep, not a clean fleet")
    if errs:
        print(f"NOTE: {len(errs)} item(s) did not read, so their values were NOT compared "
              f"(first: {errs[0]}) — a partial read is not a clean read")
    if short:
        print(f"note: {len(short)} secret field value(s) are under the {MIN_VALUE_LEN}-char containment "
              f"floor and were NOT matched, across {len(set(short))} item(s); "
              "scripts/gate/check_secrets.py is the instrument for those")

    known = set() if strict else read_ledger(ledger_path)
    fresh, ledgered = ledger_split(res.findings, known)
    if ledgered:
        items = sorted({f"{iid[:8]} {cls} ({title})" for _t, _l, iid, title, cls in ledgered})
        print(f"KNOWN-EXPOSED {len(items)} item+class pair(s) from {ledger_path.name} — each is closed "
              "by ROTATING the item, then re-deriving the ledger:")
        for it in items:
            print(f"  {it}")
    hit_keys = {ledger_key(f) for f in res.findings}
    stale = sorted(k for k in known - hit_keys if k[1] in res.scanned)
    if stale:
        print(f"STALE ledger lines (no hit this run — rotate-and-remove, or the book becomes a "
              f"standing free pass): {len(stale)}")
        for k in stale[:10]:
            print(f"  {k[0]} {k[1]}")
    unjudged = sorted(k for k in known - hit_keys if k[1] not in res.scanned)
    if unjudged:
        print(f"NOT JUDGED ledger lines: {len(unjudged)} — their class was not scanned this run, so they "
              "are NEITHER confirmed NOR stale (a class you cannot see cannot prove a debt closed, and "
              "`--update-ledger` will not delete them either)")
        for k in unjudged[:10]:
            print(f"  {k[0]} {k[1]}")
    if fresh:
        print(f"FAIL: {len(fresh)} hit(s) outside the ledger — a CURRENT vault value is readable in a "
              "run capture, the working tree, or a blob still reachable from a ref. Rotate it; do not "
              "grep it, do not shred the transcript and call it closed:")
        for f in fresh[:MAX_PRINTED]:
            print(finding_text(*f))
        if len(fresh) > MAX_PRINTED:
            print(f"  … {len(fresh) - MAX_PRINTED} more hit(s), same items, not listed")
        return 1
    tail = " — PARTIAL: see NOT SCANNED above" if res.not_scanned else ""
    print(f"OK: no current vault value outside the ledger appears in what this run scanned{tail}")
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


def _fixture_repo(dirpath: Path, value: str) -> None:
    """A throwaway repo whose HISTORY holds a minted canary and whose tip does not — the exact shape of
    the HD-1170 gap: `git rm` of the artifact made the tree scan go clean while the blob stayed
    reachable. The value is MINTED by the caller, never taken from the fleet."""
    dirpath.mkdir(parents=True, exist_ok=True)
    (dirpath / "capture.txt").write_text(f"engine boot --api-key {value}\n", encoding="utf-8")
    ident = ["-c", "user.email=fixture@example.invalid", "-c", "user.name=fixture",
             "-c", "commit.gpgsign=false"]
    for args in (["init", "-q"], ["add", "-A"], [*ident, "commit", "-q", "-m", "add the capture"],
                 ["rm", "-q", "capture.txt"], [*ident, "commit", "-q", "-m", "remove the artifact"]):
        r = _git(dirpath, args)
        if r.returncode != 0:
            raise Boundary(f"the history fixture could not be built: git {' '.join(args)}: "
                           f"{(r.stderr or b'').decode(errors='replace')[:120]}")


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

    def verdict(res: ScanRun, ledger: Path, errs: list[str] | None = None) -> tuple[int, str]:
        """Ask the reporter and keep its text: several arms are about what the run PRINTS, and a verdict
        nobody can read is not an instrument."""
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = report(res, 1, 1, [], list(errs or []), ledger, False, DEFAULT_MAX_FILE_MB, [])
        return rc, buf.getvalue()

    def rewrite(path: Path, findings: list[Finding], judged: set[str],
                scope: list[str] | None = None,
                partial: list[str] | None = None) -> tuple[int, str]:
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = update_ledger(path, findings, judged, scope, partial)
        return rc, buf.getvalue()

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
        text = "\n".join(finding_text(*f) for f in found)
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
        rewrite(led, [f for f in found if f[3] == "api"], {"run-capture"})
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
                           capture_output=True, text=True, encoding="utf-8", errors="replace",
                           env=dict(os.environ, PATH=td),
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

    # (8) THE HISTORY LEG. A value that was in the tree once and was `git rm`'d out of it is still
    # published — this is the leg HD-1170 had to ask for by hand, so its canary is minted, never taken
    # from the fleet, and the repo is a throwaway.
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td) / "repo"
        cache = Path(td) / "hist-cache.tsv"
        canary, titles_h = _mint(), {"histitem": "fixture_canary"}
        _fixture_repo(repo, canary)
        cold, info = scan_history({canary.encode(): ["histitem"]}, titles_h, "vault-v1", repo, cache)
        text = "\n".join(finding_text(*f) for f in cold)
        check("a value deleted from the tree is still a finding, as git-history",
              len(cold) == 1 and cold[0][4] == "git-history" and len(cold[0][0]) == 40, f"{text[:90]}")
        check("a history finding discloses the blob sha and the id prefix and NOTHING else",
              bool(cold) and canary not in text and "fixture_canary" not in text
              and str(len(canary)) not in text.split() and text.count(" matches item ") == 1, text[:90])
        _c2, warm = scan_history({canary.encode(): ["histitem"]}, titles_h, "vault-v1", repo, cache)
        note = history_note(warm)
        check("the cached repeat reads NO blob and says the verdict is INHERITED",
              warm["read"] == 0 and warm["cached"] >= 1 and "INHERITED" in note, note)
        # the book turns the blob into named debt instead of silence
        led = Path(td) / "hist-ledger.txt"
        rc, _o = rewrite(led, cold, {"git-history"})
        rc, out = verdict(ScanRun(cold, zero_counts(), 1, {"git-history"}, {}, [history_note(info)]), led)
        check("a ledgered git-history hit reads KNOWN-EXPOSED, not green-by-silence",
              rc == 0 and "KNOWN-EXPOSED" in out and "STALE" not in out, f"rc {rc}: {out[-140:]}")
        rc, out = verdict(ScanRun([], zero_counts(), 1, {"git-history"}, {}, []), led)
        check("a git-history line whose hit is gone prints STALE", rc == 0 and "STALE" in out, out[-140:])
        # rotate the item: the value in history is now DEAD, so it must stop being a finding AND the
        # cache must know that its own rows are about a value nobody holds any more
        dead, info_r = scan_history({_mint().encode(): ["histitem"]}, titles_h, "vault-v2", repo, cache)
        check("a rotated-out value in history stops being a finding (the cache invalidated)",
              not dead and "version" in info_r["stale_why"].lower(), str(info_r["stale_why"])[:90])

    # (9) a PARTIAL sweep may never read as a full green, and may not judge what it did not read.
    with tempfile.TemporaryDirectory() as td:
        led = Path(td) / "led.txt"
        led.write_text("# book\naaaa\trun-capture\titem_a\nbbbb\tgit-history\titem_b\n", encoding="utf-8")
        res = ScanRun([], zero_counts(), 3, {"repo-tree"},
                      {"run-capture": "--tree-only: no capture file was opened",
                       "git-history": "--no-history: no blob was read"}, [])
        rc, out = verdict(res, led)
        ok_line = [ln for ln in out.splitlines() if ln.startswith("OK:")]
        check("a partial run names every class it did NOT look at and marks its OK line PARTIAL",
              rc == 0 and "NOT SCANNED run-capture" in out and "NOT SCANNED git-history" in out
              and bool(ok_line) and "PARTIAL" in ok_line[0], out[-200:])
        check("an unread class's ledger line is NOT JUDGED, never STALE",
              "NOT JUDGED" in out and "bbbb git-history" in out and "STALE" not in out, out[-200:])
        rc, out = verdict(ScanRun([], zero_counts(), 3, {"repo-tree", "run-capture", "git-history"},
                                  {}, []), led)
        check("a full run over the same book prints no PARTIAL tag", rc == 0 and "PARTIAL" not in out,
              out[-200:])
        check("a class with an empty scan set is never judged", class_verdict(
            {"repo-tree": 4, "run-capture": 0}, {})[0] == {"repo-tree"}, str(class_verdict(
            {"repo-tree": 4, "run-capture": 0}, {})))

    # (10) --update-ledger across seats: a run may only delete a line it PROVED absent.
    with tempfile.TemporaryDirectory() as td:
        led = Path(td) / "led.txt"
        book = ("# book\naaaa\trun-capture\titem_a\nbbbb\tgit-history\titem_b\n"
                "cccc\trun-capture\titem_c\n")
        led.write_text(book, encoding="utf-8")
        rc, out = rewrite(led, [], {"repo-tree"})
        pairs = {k for k in read_ledger(led)}
        check("a tree-only run cannot delete the classes it could not see",
              rc == 0 and {("aaaa", "run-capture"), ("bbbb", "git-history"), ("cccc", "run-capture")}
              <= pairs and "carried through" in out, f"rc {rc}: {sorted(pairs)}")
        led.write_text(book, encoding="utf-8")
        rc, out = rewrite(led, [], {"repo-tree"}, ["git-history"])
        check("--class naming a class this run did not scan REFUSES, and the file does not move",
              rc == 1 and led.read_text() == book and "would remove bbbb git-history" in out,
              f"rc {rc}: {out[-140:]}")
        led.write_text(book, encoding="utf-8")
        hit = [("p", 1, "aaaa", "item_a", "run-capture")]
        rc, out = rewrite(led, hit, {"run-capture"})
        pairs = {k for k in read_ledger(led)}
        check("a pair this run PROVED absent does drop, with the reason printed",
              rc == 0 and pairs == {("aaaa", "run-capture"), ("bbbb", "git-history")}
              and "proven ABSENT" in out, f"rc {rc}: {sorted(pairs)} {out[-120:]}")
        # and the history leg has to have RUN to clear a git-history line
        led.write_text(book, encoding="utf-8")
        rc, out = rewrite(led, [], {"repo-tree", "run-capture"}, ["run-capture", "git-history"])
        check("a run without the history leg cannot clear a git-history line",
              rc == 1 and led.read_text() == book, f"rc {rc}: {led.read_text()[-80:]}")

    # (11) A PARTIAL vault read — the shape the reader used to hide. An item that did not read holds
    # a value this run never compared, so (a) the errors must REACH the leg, (b) the report must say
    # PARTIAL, and (c) `--update-ledger` must not re-derive the book from a half-seen value set: a
    # line it cannot prove present would be dropped, and the debt would come back as a fresh FAIL on
    # the next seat that could read the item. Planted through the labelled FALLBACK with a stub `op`
    # whose ONE get fails — zero vault requests, and the route a seat with no importable SDK takes.
    with tempfile.TemporaryDirectory() as td:
        bin_dir = Path(td) / "bin"; bin_dir.mkdir()
        (bin_dir / "op_stub.py").write_text(
            "import json, os, sys\n"
            "args = sys.argv[1:]\n"
            "if 'list' in args:\n"
            "    sys.stdout.write(open(os.environ['STUB_LIST'], encoding='utf-8').read())\n"
            "elif args[2] == os.environ.get('STUB_FAIL_ID', ''):\n"
            "    sys.stderr.write('stub: this item did not read'); sys.exit(1)\n"
            "else:\n"
            "    json.dump({'id': args[2], 'title': 't', 'version': 5, 'fields': [\n"
            "        {'id': 'password', 'label': 'password',\n"
            "         'value': 'readvalue' + args[2][-4:], 'type': 'Concealed'}]}, sys.stdout)\n",
            encoding="utf-8")
        vrows = [{"id": f"iid{i:026d}", "title": f"item_{i}", "version": 5,
                  "vault": {"id": "vaultid00000000000000000"}} for i in range(3)]
        (Path(td) / "list.json").write_text(json.dumps(vrows), encoding="utf-8")
        st = Path(td) / "state"; st.mkdir()
        # The map is the one the reader addresses by — VAULT is this file's own vault name.
        (st / f"op-map-{VAULT.replace('/', '_')}.tsv").write_text(
            "# vault_id=vaultid00000000000000000\n"
            + "".join(f"{r['title']}\t{r['id']}\n" for r in vrows), encoding="utf-8")
        keep = {k: os.environ.get(k) for k in
                ("HL_VAULT_READ_FIXTURE", "HL_VAULT_READ_ROUTE", "HL_VAULT_READ_OP_CMD",
                 "HL_VAULT_STATE_DIR", "OP_SERVICE_ACCOUNT_TOKEN", "STUB_LIST", "STUB_FAIL_ID")}
        os.environ.update(HL_VAULT_READ_FIXTURE="", HL_VAULT_READ_ROUTE="op-fanout",
                          HL_VAULT_READ_OP_CMD=f"{sys.executable} {bin_dir / 'op_stub.py'}",
                          HL_VAULT_STATE_DIR=str(st), OP_SERVICE_ACCOUNT_TOKEN="x" * 48,
                          STUB_LIST=str(Path(td) / "list.json"), STUB_FAIL_ID=vrows[1]["id"])
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                n_p, _t_p, _s_p, e_p, _k_p = load_values()
            out_p = buf.getvalue()
            check("a partial read reaches the leg as read errors, not as a quietly smaller value set",
                  len(e_p) == 1 and len(n_p) == 2 and "op-fanout" in out_p,
                  f"errors={e_p} needles={len(n_p)} out={out_p[:120]!r}")
            led = Path(td) / "led.txt"
            book = "# book\naaaa\trun-capture\titem_a\n"
            led.write_text(book, encoding="utf-8")
            rc, out = verdict(ScanRun([], zero_counts(), 1, {"run-capture"}, {}, []), led, errs=e_p)
            check("a run that read part of the vault prints that on its own report",
                  "partial read is not a clean read" in out, out[-160:])
            rc, out = rewrite(led, [], {"run-capture"}, None, partial=e_p)
            check("--update-ledger REFUSES to shorten the register after a partial read",
                  rc == 1 and led.read_text(encoding="utf-8") == book
                  and "PARTIAL vault read" in out, f"rc {rc}: {out[-140:]}")
            rc, out = rewrite(led, [], {"run-capture"}, None)
            check("the same rewrite on a CLEAN read still works (the refusal is the partial, not the flag)",
                  rc == 0 and "ledger rewritten" in out, f"rc {rc}: {out[-140:]}")
        finally:
            for _k, _v in keep.items():
                if _v is None:
                    os.environ.pop(_k, None)
                else:
                    os.environ[_k] = _v

    # (24) the read-budget half moved to the ONE reader (lib/vault_read.py --self-test proves the
    # ID-addressed fallback and the get_all chunking there). What THIS file pins is that its needle
    # grammar runs on the shared read: the fixture route (ZERO requests) must produce the needles,
    # the titles, the short-value list and a versions key the history cache can key on.
    with tempfile.TemporaryDirectory() as td:
        fx = Path(td) / "vault-fixture.json"
        secret_v, short_v, login_v = _mint(), _mint(5), _mint()
        fx.write_text(json.dumps({"items": {
            "aaaaaaaaaaaaaaaaaaaaaaaaaa": {"title": "item_secret", "version": 7, "fields": [
                {"id": "password", "label": "password", "value": secret_v,
                 "type": "Concealed", "section": ""}]},
            "bbbbbbbbbbbbbbbbbbbbbbbbbb": {"title": "item_short", "version": 2, "fields": [
                {"id": "credential", "label": "credential", "value": short_v,
                 "type": "Concealed", "section": ""}]},
            "cccccccccccccccccccccccccc": {"title": "item_login", "version": 9, "fields": [
                {"id": "username", "label": "username", "value": login_v,
                 "type": "Text", "section": ""},
                {"id": "password", "label": "password", "value": login_v,
                 "type": "Password", "section": ""}]}}}), encoding="utf-8")
        prev_fx_env = os.environ.get("HL_VAULT_READ_FIXTURE")
        os.environ["HL_VAULT_READ_FIXTURE"] = str(fx)
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                n2, t2, short2, errs2, vkey2 = load_values()
            out2 = buf.getvalue()
            check("the shared read feeds the needle grammar at ZERO requests",
                  {tuple(v) for v in n2.values()} == {("aaaaaaaaaaaaaaaaaaaaaaaaaa",),
                                                      ("cccccccccccccccccccccccccc",)}
                  and short2 == ["bbbbbbbbbbbbbbbbbbbbbbbbbb"]
                  and t2.get("cccccccccccccccccccccccccc") == "item_login"
                  and "route=fixture" in out2 and "requests this leg: 0" in out2,
                  f"needles={[v for vv in n2.values() for v in vv]} short={short2} out={out2[:120]!r}")
            check("the versions key the history cache keys on comes from the reader's version rows",
                  vkey2 == hashlib.sha256("\n".join(
                      f"{i}\t{v}" for i, v in sorted({"aaaaaaaaaaaaaaaaaaaaaaaaaa": 7,
                                                      "bbbbbbbbbbbbbbbbbbbbbbbbbb": 2,
                                                      "cccccccccccccccccccccccccc": 9}.items())
                  ).encode()).hexdigest(), vkey2[:20])
        finally:
            if prev_fx_env is None:
                os.environ.pop("HL_VAULT_READ_FIXTURE", None)
            else:
                os.environ["HL_VAULT_READ_FIXTURE"] = prev_fx_env

    # (25) HD-1181: the run-capture class must NAME the stores it read, and a checkout whose
    # transcript store is absent must not report live debts STALE — even when scratch keeps the
    # corpus non-empty. Three arms, one per store shape; the ledger line is the live debt.
    with tempfile.TemporaryDirectory() as td:
        prev_tmp = os.environ.get("TMPDIR")
        led = Path(td) / "led.txt"
        book = "# book\naaaa\trun-capture\titem_a\n"
        tmp_root = Path(td) / "tmp"
        tmp_root.mkdir()
        os.environ["TMPDIR"] = str(tmp_root)

        def store_case(name: str, make_scratch: bool, want_judged: bool) -> None:
            home = Path(td) / f"home-{name}"
            scratch = tmp_root / f"pi-subagents-{name}"
            if make_scratch:
                (scratch / "run-0").mkdir(parents=True)
                (scratch / "run-0" / "output-0.log").write_text("clean scratch line\n", encoding="utf-8")
            os.environ["TMPDIR"] = str(tmp_root)
            if name == "present":
                sess = home / ".pi" / "agent" / "sessions"
                sess.mkdir(parents=True)
                (sess / "session.jsonl").write_text("clean transcript\n", encoding="utf-8")
            stores = capture_stores(home)
            corpus = {"repo-tree": 1,
                      "run-capture": sum(len(s["files"]) for s in stores.values())}
            judged, not_scanned = class_verdict(corpus, {}, stores)
            note = stores_note(stores)
            led.write_text(book, encoding="utf-8")
            rc, out = verdict(ScanRun([], zero_counts(), corpus["run-capture"], judged, not_scanned,
                                      [note]), led)
            named = "pi-transcripts" in note
            no_stale = ("STALE" not in out) if not want_judged else True
            check(f"run-capture names its stores and judges per store: {name}",
                  named and no_stale and (("run-capture" in judged) == want_judged)
                  and ("NOT JUDGED" in out) == (not want_judged),
                  f"judged={sorted(judged)} rc {rc} out {out[-160:]!r}")

        store_case("present", make_scratch=False, want_judged=True)
        store_case("absent", make_scratch=False, want_judged=False)
        store_case("absent-but-scratch", make_scratch=True, want_judged=False)
        # the STALE half stays alive: with the store READ and the hit gone, the debt prints STALE
        home = Path(td) / "home-stale"
        sess = home / ".pi" / "agent" / "sessions"
        sess.mkdir(parents=True)
        (sess / "session.jsonl").write_text("clean transcript\n", encoding="utf-8")
        stores = capture_stores(home)
        judged, not_scanned = class_verdict({"run-capture": 1}, {}, stores)
        led.write_text(book, encoding="utf-8")
        rc, out = verdict(ScanRun([], zero_counts(), 1, judged, not_scanned, [stores_note(stores)]), led)
        check("a store-READ run with the hit gone still prints the debt STALE (the guard has teeth both ways)",
              rc == 0 and "STALE" in out and "aaaa run-capture" in out, out[-160:])
        if prev_tmp is None:
            os.environ.pop("TMPDIR", None)
        else:
            os.environ["TMPDIR"] = prev_tmp

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
     'findings.append((path, line, iid, titles.get(iid, "?"), _class_of(path)))',
     'findings.append((path, line, iid, needle.decode("utf-8", "replace"), _class_of(path)))',
     "disclosure arm"),
    ("no `op` on PATH reads green",
     'is. Environment boundary, not a green.")\n            return 2',
     'is. Environment boundary, not a green.")\n            return 0',
     "vault-unreachable"),
    ("the ledger is ignored",
     "    fresh = [f for f in findings if ledger_key(f) not in known]",
     "    fresh = [f for f in findings if ledger_key(f) not in set()]",
     "ledger"),
    ("the ledger mutes every item, not the one it names",
     "    fresh = [f for f in findings if ledger_key(f) not in known]",
     "    known = {ledger_key(f) for f in findings}\n"
     "    fresh = [f for f in findings if ledger_key(f) not in known]",
     "ledger (both arms)"),
    ("an over-capacity file is skipped without saying so",
     '            if size > max_bytes:\n                counts["too_big"] += 1\n                continue',
     '            if size > max_bytes:\n                continue',
     "bounds"),
    ("the retired leg is dead code",
     '    for path in files:\n        try:\n            data = Path(path).read_bytes()\n        except OSError:\n            continue\n        if len(data) > max_bytes or b"\\0" in data[:8192]:',
     '    for path in []:\n        try:\n            data = Path(path).read_bytes()\n        except OSError:\n            continue\n        if len(data) > max_bytes or b"\\0" in data[:8192]:',
     "retired"),
    # The legs added with the git-history class, the partial-sweep honesty and the non-destructive
    # ledger — each is a claim, so each has to be seen to be breakable.
    ("a value published in history is invisible (no blob is ever read)",
     "    for sha, body in read_blobs(repo, need, sizes):",
     "    for sha, body in []:",
     "the git-history arms"),
    ("the history cache is trusted after a rotation",
     '    if hdr.get("values") != vkey:',
     "    if False:",
     "the rotation arm"),
    ("a cached history verdict prints as a fresh read",
     '    if info["read"] == 0:',
     "    if False:",
     "the cache-provenance arm"),
    ("a partial sweep reads as a full green",
     '    tail = " — PARTIAL: see NOT SCANNED above" if res.not_scanned else ""',
     '    tail = ""',
     "the PARTIAL arm"),
    ("an unread class's debt is reported as STALE",
     "    stale = sorted(k for k in known - hit_keys if k[1] in res.scanned)",
     "    stale = sorted(k for k in known - hit_keys)",
     "the NOT JUDGED arm"),
    ("an empty scan set still counts as a judged class",
     "        if n:\n            judged.add(cls)",
     "        if True:\n            judged.add(cls)",
     "the empty-corpus arm"),
    ("--update-ledger re-derives from whatever the run happened to see",
     "    scope = set(class_scope) if class_scope else set(judged)",
     "    scope = set(class_scope) if class_scope else set(CLASSES)",
     "the carried-through arm"),
    ("a --class scope wider than the run's eyes is accepted",
     "    if blind:",
     "    if False:",
     "the refusal arm"),
    # The partial-read plumbing (docs/1password.md §What a gate run costs the vault): both halves
    # made the NOTE unreachable prose and the ledger unsafe to re-derive.
    ("the reader's partial read never reaches the leg (errs empty again)",
     "    errs: list[str] = list(vr.errors)",
     "    errs: list[str] = []",
     "the partial-read arms"),
    ("--update-ledger re-derives the book after a partial read",
     "    if partial:",
     "    if False:",
     "the partial-read refusal arm"),
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
        # The mutant needs `scripts/lib/repo_root.py` AND `scripts/lib/vault_env.py` on its import
        # path — the module resolves its root the same way every gate script does, and resolves its
        # credential through the lib twin — so it goes into a throwaway `scripts/gate/` with a copied
        # lib, and $REPO points it back at THIS checkout. A copy left inside the tree would be an
        # untracked file every other tree-walking gate has to explain. A missing second copy is not a
        # skipped mutant but a `ModuleNotFoundError` that reads as "nothing broke".
        with tempfile.TemporaryDirectory() as td:
            fake = Path(td) / "scripts"
            (fake / "lib").mkdir(parents=True)
            (fake / "gate").mkdir()
            for _lib in ("repo_root.py", "vault_env.py", "vault_read.py"):
                shutil.copy(ROOT / "scripts" / "lib" / _lib, fake / "lib" / _lib)
            mutant = fake / "gate" / "leak-mutant.py"
            mutant.write_text(mutated, encoding="utf-8")
            r = subprocess.run([sys.executable, str(mutant), "--self-test"], capture_output=True,
                               text=True, encoding="utf-8", errors="replace",
                               env=dict(os.environ, LEAK_GATE_MUTANT="1", REPO=str(ROOT)),
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
def build_run(needles: dict[bytes, list[str]], titles: dict[str, str], vkey: str, args
              ) -> tuple[ScanRun, list[str]]:
    """Assemble the scan set CLASS by CLASS. A flag that narrows the sweep subtracts a class from the
    verdict rather than making the run look quiet, which is the whole difference between a partial sweep
    and a green one."""
    by_class: dict[str, list[str]] = {"repo-tree": repo_tree_files() + expand(args.path)}
    skipped: dict[str, str] = {}
    stores: dict[str, dict] | None = None
    notes: list[str] = []
    if args.tree_only:
        skipped["run-capture"] = ("--tree-only/--no-captures: no capture file was opened, so a value in a "
                                  "session transcript or a pi run log is invisible to this run")
    else:
        stores = capture_stores()
        by_class["run-capture"] = sorted({p for s in stores.values() for p in s["files"]})
        notes.append(stores_note(stores))
    findings, counts, corpus = scan_run(by_class, needles, args.max_file_mb, titles)
    if args.no_history:
        skipped["git-history"] = ("--no-history: no history blob was read, so a value that was in the tree "
                                  "once and was edited out stays invisible — the HD-1170 gap, on purpose "
                                  "this time")
    else:
        hist, hinfo = scan_history(needles, titles, vkey)
        findings += hist
        corpus["git-history"] = hinfo["blobs"]
        notes.append(history_note(hinfo))
    judged, not_scanned = class_verdict(corpus, skipped, stores)
    if not judged:
        raise Boundary("every scan set resolved to ZERO files — nothing to read is not a clean fleet")
    files = sorted({p for group in by_class.values() for p in group})
    return ScanRun(sorted(findings), counts, len(files), judged, not_scanned, notes), files


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true", help="prove the arms on minted fixtures")
    ap.add_argument("--path", action="append", default=[], help="extra file or directory to scan")
    ap.add_argument("--strict", action="store_true", help="ignore the exposure ledger")
    ap.add_argument("--retired-file", help="0600 file of SUPERSEDED values, reported as INFO only")
    ap.add_argument("--max-file-mb", type=int, default=DEFAULT_MAX_FILE_MB)
    ap.add_argument("--tree-only", "--no-captures", dest="tree_only", action="store_true",
                    help="scan the working tree only — the flag that replaces the "
                         "`HOME=/tmp/empty-home TMPDIR=…` trick. The run-capture class is then NOT read, "
                         "and the report says so instead of reading as a full green")
    ap.add_argument("--no-history", action="store_true",
                    help="skip the git-history leg: a value published once and edited out of the tree "
                         "becomes invisible, which the report prints and --update-ledger refuses to act on")
    ap.add_argument("--update-ledger", action="store_true",
                    help="rewrite the ledger from THIS run — only for the classes this run actually read")
    ap.add_argument("--class", dest="classes", action="append", default=[], metavar="CLASS",
                    help=f"with --update-ledger: rewrite only this class ({', '.join(CLASSES)}); naming "
                    "one this run did not scan is a refusal, not a rewrite")
    args = ap.parse_args()

    if args.self_test:
        print("check_secret_leak.py --self-test")
        return self_test()

    # The reader needs SOME vault route: the CLI or an importable Server SDK. Neither is an
    # environment boundary (rc 2), printed — the check compares captured bytes against CURRENT
    # values, so without a headless read it has no idea what a leak looks like, and a desktop-app
    # fallback is a dialog, not a verdict.
    if shutil.which("op") is None:
        import importlib.util
        from vault_read import sdk_probe
        launcher, probe_log = (None, []) if importlib.util.find_spec("onepassword") else sdk_probe()
        if launcher is None and importlib.util.find_spec("onepassword") is None:
            for line in probe_log:
                print(f"SKIP note: {line}")
            print("SKIP: no `op` on PATH and no interpreter imports the onepassword SDK — a leak "
                  "check needs the vault to know what a leak is. Environment boundary, not a green.")
            return 2
    if set(args.classes) - set(CLASSES):
        print(f"SKIP: unknown class(es) {sorted(set(args.classes) - set(CLASSES))} — the classes are "
              f"{list(CLASSES)}. An unrecognised scope is an environment mistake, not a verdict")
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
        needles, titles, short, errs, vkey = load_values()
        res, files = build_run(needles, titles, vkey, args)
        if args.update_ledger:
            return update_ledger(LEDGER, res.findings, res.scanned, args.classes, errs)
        hits = scan_retired(files, retired, args.max_file_mb * 1024 * 1024) if retired else []
        return report(res, len(needles), len(titles), short, errs, LEDGER, args.strict,
                      args.max_file_mb, hits)
    except Boundary as exc:
        print(f"SKIP: {exc} — an unavailable vault is an environment boundary, not a green")
        return 2


if __name__ == "__main__":
    sys.exit(main())
