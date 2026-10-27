#!/usr/bin/env python3
"""The ONE vault reader for the tree: one batched read, counted, values in memory only.

WHY this file exists: every vault-reading leg used to pay for its own reads. The leak leg alone
walked the vault item by item; with the legs added up, a full validation spent a multiple of the
vault's item count against the ceiling that actually binds — the 1Password ACCOUNT's 1000 requests
per 24 h, shared by every service account on the account (the token's own 1000 reads/hour rarely
binds; `op service-account ratelimit` prints both). A batched server-SDK read — ONE `items.list`
plus `items.get_all` in chunks of 50 (50 is the API cap) — returns the same whole vault for a
handful of requests instead. This module is where that read lives, so no leg re-pays for it.

THE ROUTES, in order (the LAST RESORT is the OLD one, kept honest by its name):

  1. `fixture`  — `HL_VAULT_READ_FIXTURE=<json file>` answers from a file: ZERO requests. The
                  self-test arms and any `--fake-vault`-style leg run on this route, which is what
                  makes the read gradeable on a day the account's request budget is spent.
  2. `sdk`      — the Server SDK: `items.list` (the whole vault, one call) then `items.get_all` in
                  chunks of 50 item IDs. Values exist ONLY in this process's memory — no cache, no
                  holder, no TTL, nothing on disk (a cache of values is the exposure class this
                  repo's leak gate exists for; HD-1181's lesson). When THIS interpreter cannot
                  import `onepassword` (the wheels are cp39-cp313, so a 3.14 `py -3` cannot), the
                  read crosses to the first candidate interpreter that imports it and takes the
                  JSON back over a PIPE; `--probe` prints what the probe found. A NAMES-ONLY read
                  stops after that one `items.list` — a leg that wants titles pays 1 request, not 4.
                  Both modes address the vault by **ID**, because the SDK answers a TITLE with
                  `invalid user input: … the provided ID is not in a valid format`: the ID comes from
                  the map the CLI legs share (free when warm), or from ONE `vaults.list` when the map
                  is cold — a count that includes it, never one that hides it.
  3. `op-fanout` — the FALLBACK, labelled as one: the `op` CLI, `item list` once and one
                  ID-addressed `item get` per item — a request per item against the same account
                  bucket, which is exactly why it is the fallback and not the plan. Used when the
                  SDK will not import on ANY candidate; it never silently answers where the batch
                  read was expected, because every mode prints which route answered. A NAMES-ONLY
                  read stops after the list — a name list never pays a get.

WHAT NEVER CHANGES, whichever route answers:

  * credential resolution goes through `scripts/lib/vault-env.sh` / `vault_env.py` and nowhere
    else — this module reads no token file and resolves nothing of its own. No credential is a
      boundary (rc 1 / `Boundary`), never a desktop-app fallback with a human behind it.
  * values never reach a TTY: every mode that prints a value (`--values`, `--item`) refuses a
    terminal (rc 3) exactly like `vault-env.sh --emit` does, so the only way out is a pipe held by
    the calling process — and it refuses BEFORE reading, so refusing costs nothing too. `--list`
    prints names and versions and nothing else, so it needs no refusal: titles are how the vault is
    keyed, not what it hides.
  * stderr prints the provenance — `route=`, the REQUEST count, and a digest of the per-item
    `version` numbers. The digest is over ids+versions, NEVER over the values: a digest of an
    8-char secret is a dictionary oracle (the reason is written into check_secret_leak.py, whose
    history-cache key consumes this exact formula).
  * nothing is written to disk: no cache, no holder, no TTL. Values live and die in memory.
  * a PARTIAL read is never silent. An item that did not read comes back in `VaultRead.errors` and
    the run prints one NOTE — on EVERY route, including the re-exec handoff, where the child's
    stdout is the answer and its stderr is a nobody. A leg that must not act on a half-seen value
    set (check_secret_leak.py's `--update-ledger`) reads that list, not the log line.

USE (python legs — the normal form):
    from vault_read import read_vault, read_item, read_names, Boundary
    vr = read_vault()                       # one batched read shared by the whole leg
    vr.items[item_id]                       # {"title","version","fields":[{"id","label","value","type","section"}]}
    vr.requests, vr.route, vr.vkey          # what it cost, which route answered, the versions digest
    vr.errors                               # items that did NOT read — a partial read says so
    vr.print_cost("my_leg.py")              # the leg's own quota line — ONE shape every leg prints
    one = read_item("victoria-metrics_api") # ONE item where one item is all the leg needs (1 request);
                                            # the same read shape: one.only() is the row, one.requests
    names = read_names()                    # titles+versions ONLY, 1 request on every route, values
                                            # never fetched — a name list must not pay for the vault

USE (CLI):
    python3 scripts/lib/vault_read.py --list [--vault V]    title<TAB>id<TAB>version lines — names, no
                                                           values, and ONE request on every route (the
                                                           fallback pays a list, never a get per item)
    python3 scripts/lib/vault_read.py --values [--vault V]  the whole vault as JSON, PIPE ONLY (a tty -> rc 3)
    python3 scripts/lib/vault_read.py --item TITLE          one item as JSON (ID-addressed via the vault
                                                           map), PIPE ONLY — a tty is refused (rc 3)
    python3 scripts/lib/vault_read.py --probe               which interpreter imports the SDK; the install command
    python3 scripts/lib/vault_read.py --install-sdk        pip install onepassword-sdk into the probed interpreter
                                                           (an explicit seat act; nothing here installs by itself)
    python3 scripts/lib/vault_read.py --self-test          fixture arms; ZERO requests, reads no vault

Exit: 0 ok · 1 boundary (no credential reachable here — legs print it as a SKIP, not a FAIL) ·
      2 usage · 3 a value mode (--values, --item) refused a terminal ·
      4 the SDK answered nothing where it was required.

Fixture seam for legs: `HL_VAULT_READ_FIXTURE` replaces the read with a JSON file of the `--values`
shape (ids/titles/versions/fields) and costs ZERO requests — the same role `--fake-vault` plays for
check-vault-items.sh. `HL_VAULT_READ_TTY=1` makes the pipe rule testable without a terminal.
"""
from __future__ import annotations

import argparse
import asyncio
import contextlib
import hashlib
import io
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

# The seat's locale default is not the module's encoding. The verdict lines carry em-dashes and the
# value handoff carries whatever the vault holds, so both streams are pinned to UTF-8 here — the
# HD-1202 rule (docs/harness-pi-seats.md §1); a no-op on a seat whose locale already is UTF-8.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402
from vault_env import ensure as _vault_ensure  # noqa: E402

ROOT = _hl_root(__file__)
DEFAULT_VAULT = "Homelab-ansible"
# 50 is the API cap for one `items.get_all` call; the chunking is what keeps a 143-item vault inside
# three batched gets instead of one call the server will refuse.
GET_ALL_CAP = 50
INTEGRATION_NAME = "homelab-gate"
INTEGRATION_VERSION = "1"
# Candidate interpreters for the SDK probe. The wheels are cp39-cp313 (incl. win_amd64), and the
# Win11 gate resolves `py -3` = 3.14, so the probe matters: newest compatible first. `py -0p` output
# is the discovery source when the launcher exists; the literal candidates are the fallback shape.
SDK_CANDIDATES_WIN = [["py", "-3.13"], ["py", "-3.12"], ["py", "-3.11"], ["py", "-3.10"], ["py", "-3.9"]]
SDK_CANDIDATES_POSIX = [["python3"], ["python"]]


class Boundary(Exception):
    """The vault cannot be read on this seat (no credential, no answer). A leg prints a SKIP."""


# --------------------------------------------------------------------------- provenance
def _vkey(items: dict) -> str:
    """sha256 over `id<TAB>version` rows sorted by id — the SAME formula check_secret_leak.py used
    to derive from its own `op item list` answer, kept byte-identical so the history-cache key does
    not move when the read moves. NEVER a digest of values: a digest of a short secret is a
    dictionary oracle, and the version bump is the only event that changes what a hit MEANS."""
    return hashlib.sha256("\n".join(f"{iid}\t{items[iid].get('version')}"
                                    for iid in sorted(items)).encode()).hexdigest()


def _provenance(route: str, requests: int, n_items: int, vkey: str, cred_route: str = "") -> str:
    parts = [f"route={route}"]
    if cred_route:
        parts.append(f"cred-route={cred_route}")
    parts.append(f"requests={requests}")
    parts.append(f"items={n_items}")
    parts.append(f"versions={vkey[:12]}")
    return "vault-read: " + " ".join(parts)


def _say(route: str, requests: int, n_items: int, vkey: str, cred_route: str = "") -> None:
    """Every read states its cost. A run's quota price belongs in the log, not in a guess."""
    print(_provenance(route, requests, n_items, vkey, cred_route), file=sys.stderr)


# --------------------------------------------------------------------------- normalization
def _norm_fields(raw_fields: list[dict]) -> list[dict]:
    """One field shape for both routes: {id,label,value,type,section}. `op item get` JSON and the
    SDK's Item fields name the same things differently (`label` vs `title`, `section.id` vs
    `section_id`); the leak gate's SECRET_FIELD_KEYS matching reads `id|label`, so the two routes
    must answer that key identically or the needle set would depend on which route ran."""
    out = []
    for f in raw_fields or []:
        section = f.get("section")
        if isinstance(section, dict):
            section = section.get("label") or section.get("id")
        out.append({"id": str(f.get("id") or ""),
                    "label": str(f.get("label") or f.get("title") or ""),
                    "value": f.get("value") if isinstance(f.get("value"), str) else ("" if f.get("value") is None else str(f.get("value"))),
                    "type": str(f.get("type") or f.get("field_type") or ""),
                    "section": section or ""})
    return out


# --------------------------------------------------------------------------- route: fixture
def _read_fixture(path: Path) -> tuple[dict, int, list[str]]:
    """The ZERO-request route. The file uses the --values shape; anything unparsable is a Boundary,
    never a silently empty vault. A fixture holds what it holds, so it cannot read partially."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise Boundary(f"the fixture vault {path} is unreadable ({exc}) — a fixture that cannot be "
                       "read is not an empty vault") from exc
    items = data.get("items") if isinstance(data, dict) else data
    if not isinstance(items, dict) or not items:
        raise Boundary(f"the fixture vault {path} holds no items — refusing to call that a fleet")
    out = {iid: {"title": row.get("title", "?"), "version": row.get("version"),
                 "fields": _norm_fields(row.get("fields", []))}
           for iid, row in items.items()}
    return out, 0, []


# --------------------------------------------------------------------------- route: SDK
def _sdk_available(argv: list[str]) -> bool:
    try:
        r = subprocess.run([*argv, "-c", "import onepassword"], capture_output=True,
                           stdin=subprocess.DEVNULL, timeout=60)
    except (subprocess.TimeoutExpired, OSError):
        return False
    return r.returncode == 0


def sdk_candidates() -> list[list[str]]:
    """Interpreters worth probing, current first if it can already import the SDK. Overridable with
    HL_VAULT_READ_PY_CANDIDATES (os.pathsep-separated launcher strings — a fixture arm needs to be
    able to name a stub launcher without editing the tree)."""
    over = os.environ.get("HL_VAULT_READ_PY_CANDIDATES")
    if over is not None:
        return [c.split() for c in over.split(os.pathsep) if c.strip()]
    cands = [[sys.executable]]
    cands += SDK_CANDIDATES_WIN if os.name == "nt" else SDK_CANDIDATES_POSIX
    return cands


def sdk_probe() -> tuple[list[str] | None, list[str]]:
    """(first launcher that imports `onepassword`, log lines). Discovery, not assumption: the seat's
    `py -3` may be 3.14 with no cp314 wheel, and the answer belongs in the log before a leg needs it."""
    log, found = [], None
    for cand in sdk_candidates():
        if shutil.which(cand[0]) is None:
            log.append(f"probe: {' '.join(cand)} -> absent")
            continue
        if _sdk_available(cand):
            log.append(f"probe: {' '.join(cand)} -> sdk-importable")
            found = found or cand
        else:
            log.append(f"probe: {' '.join(cand)} -> no onepassword module")
    return found, log


def _emit_values_json(items: dict, requests: int = 0, errors: list[str] | None = None,
                      names_only: bool = False) -> str:
    # ensure_ascii=True keeps the value pipe pure ASCII: every non-ASCII character, and every
    # control character including a CR, leaves here as an escape that json.loads() puts back
    # byte-exactly. The re-exec handoff then cannot depend on the seat locale (docs/harness-pi-seats.md
    # §1 — the HD-1202 rule), which the self-test pins with a planted CR and a planted non-ASCII value.
    #
    # `errors` rides along because the re-exec child is the one route whose partial read the parent
    # would otherwise never see: the child's stderr is a diagnostic, its stdout is the answer.
    return json.dumps({"items": {iid: {"title": row["title"], "version": row["version"],
                                       **({} if names_only else
                                          {"fields": row["fields"]})}
                                 for iid, row in items.items()},
                       "requests": requests,
                       "errors": list(errors or [])},
                      ensure_ascii=True)


def _read_via_launcher(launcher: list[str], vault: str,
                       names_only: bool = False) -> tuple[dict, int, list[str]]:
    """Cross to an interpreter that has the SDK and take the JSON back over a PIPE. The child runs
    THIS module in --values mode; stdout is captured (never inherited), so no value can land on a
    tty here, and the child's own pipe rule refuses one anyway.

    The child's `errors` are read, not just its items: this is the route a Win11 seat normally
    takes, and a partial read that stops at the child's stdout would be silent exactly where the
    batched read is the plan.

    `names_only` asks the child for the LIST half (`--names-only`), which is what a name-only reader
    means: no `items.get_all`, so no value crosses the pipe at all."""
    argv = [*launcher, str(Path(__file__).resolve()), "--values", "--vault", vault, "--sdk-required"]
    if names_only:
        argv.append("--names-only")
    r = subprocess.run(argv, capture_output=True, stdin=subprocess.DEVNULL)
    err = (r.stderr or b"").decode("utf-8", "replace")
    # Quote the child's FAILURE, not the head of its stack: the first 140 bytes of a traceback are
    # "Traceback (most recent call last):" plus file names, which is how a live SDK failure looked on
    # a seat for a whole session without ever saying what failed. The last line is the exception.
    tail = next((ln.strip() for ln in reversed(err.strip().splitlines()) if ln.strip()),
                "(the child answered nothing)")
    if r.returncode == 4:
        raise Boundary(f"{shlex_join(launcher)} refused the SDK read: {tail[:200]}")
    if r.returncode != 0:
        raise Boundary(f"the SDK reader ({shlex_join(launcher)}) answered rc {r.returncode}: "
                       f"{tail[:200]}")
    try:
        data = json.loads((r.stdout or b"").decode("utf-8", "replace"))
    except json.JSONDecodeError as exc:
        raise Boundary(f"the SDK reader's answer was not JSON: {exc}") from exc
    requests = int(data.get("requests", 0))
    errs = [str(e) for e in (data.get("errors") or [])]
    items = {iid: {"title": row.get("title", "?"), "version": row.get("version"),
                   "fields": _norm_fields(row.get("fields", []))}
             for iid, row in data.get("items", {}).items()}
    return items, requests, errs


async def _sdk_vault_id(vault: str, client) -> tuple[str, int]:
    """The vault ID the Server SDK demands, and what finding it cost THIS run (0 warm, 1 cold).

    `items.list` and `items.get_all` take a vault **ID**; a title answers
    `invalid user input: … the provided ID is not in a valid format` — the CLI accepts a name only
    because `op` resolves it first, so a name-addressed SDK read is not a cheap read, it is a broken
    one (HD-1207, found the first time the batched route ran against the live vault). The answer comes
    from the SAME map the CLI legs share: `cached_vault_id` never refreshes, so a warm seat pays
    NOTHING for it; a cold map pays ONE `vaults.list`, and the returned count carries it, because
    the quota proof in docs/1password.md reads that number."""
    from vault_env import cached_vault_id
    vid = cached_vault_id(vault)
    if vid:
        return vid, 0
    found = next((str(v.id) for v in await client.vaults.list()
                  if getattr(v, "title", None) == vault), "")
    if not found:
        raise Boundary(f"the SDK's vault list has no vault titled {vault!r} — a name the account does "
                       f"not answer is not a fleet; `bash scripts/lib/vault-env.sh --map {vault}` "
                       "warms the ID map the CLI legs share")
    return found, 1


def _names_sdk(vault: str) -> tuple[dict, int, list[str]]:
    """`items.list` and nothing else: the names and versions of the whole vault for ONE request, with
    no value read at all. The versions on a list row are whatever that SDK release exposes — a
    summary that carries none is stated, not guessed, and `read_names` prints that."""
    try:
        import onepassword  # noqa: F401
    except ImportError as exc:
        raise ImportError(f"onepassword SDK not importable here: {exc}") from exc
    token = os.environ.get("OP_SERVICE_ACCOUNT_TOKEN")
    if not token:
        raise Boundary("the SDK route needs the credential vault_env.ensure() exports")

    async def _main():
        from onepassword import Client
        client = await Client.authenticate(token, INTEGRATION_NAME, INTEGRATION_VERSION)
        vid, extra = await _sdk_vault_id(vault, client)
        rows = await client.items.list(vid)
        return {r.id: {"title": r.title, "version": getattr(r, "version", None)}
                for r in rows}, 1 + extra, []

    entries, requests, errs = asyncio.run(_main())
    if not entries:
        raise Boundary("items.list answered ZERO items — an empty vault answer is not an empty fleet")
    return entries, requests, errs


def shlex_join(argv: list[str]) -> str:
    return shlex.join(argv)


def _read_sdk(vault: str) -> tuple[dict, int, list[str]]:
    """In-process SDK route. `items.list` names the whole vault in one call; values come from
    `items.get_all` in chunks of GET_ALL_CAP. Nothing is stored anywhere but memory.

    An `individual_response` with no content is a MISSING item, not a harmless one: it comes back in
    `errors` so the read says it was partial — every route answers the same three-tuple for that
    reason, and a leg cannot tell "the vault holds 142 items" from "one item failed and 142 came
    back" any other way."""
    try:
        import onepassword  # noqa: F401
    except ImportError as exc:
        raise ImportError(f"onepassword SDK not importable here: {exc}") from exc
    token = os.environ.get("OP_SERVICE_ACCOUNT_TOKEN")
    if not token:
        raise Boundary("the SDK route needs the credential vault_env.ensure() exports")

    async def _main():
        from onepassword import Client
        client = await Client.authenticate(token, INTEGRATION_NAME, INTEGRATION_VERSION)
        vid, extra = await _sdk_vault_id(vault, client)
        rows = await client.items.list(vid)
        ids = [r.id for r in rows]
        vid = rows[0].vault_id if rows else vid    # the list answer is the authority, and it is free
        items, requests, errs = {}, 1 + extra, []
        for i in range(0, len(ids), GET_ALL_CAP):
            resp = await client.items.get_all(vid, ids[i:i + GET_ALL_CAP])
            requests += 1
            for r in resp.individual_responses:
                it = r.content
                if it is None:
                    errs.append(str(r.error)[:100])
                    continue
                items[it.id] = {"title": it.title, "version": it.version,
                                "fields": _norm_fields([{"id": f.id, "label": f.title,
                                                         "value": f.value, "type": f.field_type,
                                                         "section": f.section_id}
                                                        for f in it.fields])}
        return items, requests, errs

    items, requests, errs = asyncio.run(_main())
    if not items:
        raise Boundary("items.list answered ZERO items — an empty vault answer is not an empty fleet")
    return items, requests, errs


# --------------------------------------------------------------------------- route: op FALLBACK
def _op_argv() -> list[str]:
    """The `op` launcher. `HL_VAULT_READ_OP_CMD` is a test seam, not a feature: a fixture (or a
    seat where `op` hides behind a wrapper) names the launcher; every real run leaves it unset and
    gets the CLI off PATH. A python-side stub script is not executable on a Windows seat without
    this seam — an arm that cannot run its stub is an arm that silently tests nothing."""
    seam = os.environ.get("HL_VAULT_READ_OP_CMD")
    if seam:
        return shlex.split(seam.replace("\\", "/"))
    if shutil.which("op") is None:
        raise Boundary("no `op` on PATH and no importable onepassword SDK — the vault cannot be "
                       "read on this seat; that is an environment boundary, not a verdict")
    return ["op"]


def _op_run(args: list[str], timeout: int = 120) -> subprocess.CompletedProcess:
    # Explicit UTF-8, decoded STRICTLY and decoded HERE. Two reasons, both learned the hard way:
    #  * `text=True` alone decodes with the locale default (cp1252 on the Win11 seat, where one
    #    non-decodable byte leaves stdout None for the JSON readers — docs/harness-pi-seats.md §1,
    #    the HD-1202 class), and `errors="replace"` would be worse still: it turns a byte that did
    #    not decode into U+FFFD INSIDE a secret value, so the leak gate would compare a mangled
    #    secret and call the item clean.
    #  * handing `encoding=` to subprocess.run instead puts the decode in a reader THREAD, where the
    #    failure prints a traceback and leaves stdout None — invisible to the caller that has to
    #    report it. So: capture bytes, decode in this thread, let the caller name the failure
    #    (a Boundary on a list, a partial-read entry on a get).
    r = subprocess.run([*_op_argv(), *args], capture_output=True, stdin=subprocess.DEVNULL,
                       timeout=timeout)
    # stderr keeps errors="replace": a diagnostic is not a value, and an undecodable byte in an
    # error message must not be able to hide the error itself.
    return subprocess.CompletedProcess(r.args, r.returncode,
                                       (r.stdout or b"").decode("utf-8"),
                                       (r.stderr or b"").decode("utf-8", "replace"))


def _read_op_fanout(vault: str) -> tuple[dict, int]:
    """The clearly-labelled FALLBACK: one `op item list` plus one ID-addressed `op item get` per item,
    for seats where the SDK will not import. On a 143-item vault that is ~144 requests against the
    same 1000/24 h account bucket — which is the whole reason it is named a fallback in every line
    that prints it.

    The count is what the ACCOUNT pays, not what the loop ran: a list addressed by vault ID is 1
    request and by NAME 2 (the name resolution is billed), a get addressed by ID is 1 and by NAME 3,
    and a cold ID map is answered by THIS list instead of a separate discovery list; the quota proof
    in docs/1password.md is measured against this number, so a printed cost that lies is worse than no
    printed cost."""
    argv = _op_argv()
    from vault_env import cached_vault_id as _cached_vault_id
    vid = _cached_vault_id(vault)      # free: the map the bash face shares, and no discovery read
    requests = 1 if vid else 2
    try:
        r = _op_run(["item", "list", "--vault", vid or vault, "--format", "json"])
    except UnicodeDecodeError as exc:
        raise Boundary(f"`op item list` answered bytes that are not UTF-8 ({exc}) — an item list "
                       "decoded with a replacement character is not a fleet") from exc
    if r.returncode != 0:
        raise Boundary(f"`op item list` rc {r.returncode}: {(r.stderr or '').strip()[:120]}")
    try:
        rows = json.loads(r.stdout or "[]")
    except json.JSONDecodeError as exc:
        raise Boundary(f"`op item list` did not answer JSON: {exc}") from exc
    if not rows:
        raise Boundary("`op item list` answered ZERO items — an empty vault answer is not an empty fleet")
    if not vid:
        # The list carries the vault ID on every row, so a cold map costs the ONE name resolution
        # above and the gets below still go out ID-addressed.
        vid = next((str((row.get("vault") or {}).get("id") or "") for row in rows
                    if isinstance(row, dict) and (row.get("vault") or {}).get("id")), "")
    per_get = 1 if vid else 3
    items, errs = {}, []
    for row in rows:
        try:
            g = _op_run(["item", "get", row["id"], "--vault", vid or vault, "--format", "json"])
        except UnicodeDecodeError as exc:
            requests += per_get
            errs.append(f"{row['id']}: the item answer was not UTF-8 ({exc})")
            continue
        requests += per_get
        if g.returncode != 0:
            errs.append((g.stderr or "").strip()[:100])
            continue
        try:
            got = json.loads(g.stdout or "{}")
        except json.JSONDecodeError as exc:
            errs.append(f"unparsable item JSON: {exc}")
            continue
        items[row["id"]] = {"title": row.get("title", got.get("title", "?")),
                            "version": row.get("version", got.get("version")),
                            "fields": _norm_fields(got.get("fields", []))}
    if not items:
        raise Boundary("the fallback read produced ZERO items — a vault that answers nothing is an "
                       "environment boundary, not a clean fleet")
    return items, requests, errs


def _names_op_fanout(vault: str) -> tuple[dict, int, list[str]]:
    """ONE `op item list` and no gets: the list row already carries id, title and version, so a NAME
    list on the FALLBACK route costs a list. Paying a `get` per item here is how `--list` came to
    spend ~144 requests of a 1000/24 h account bucket to print a column of titles."""
    argv = _op_argv()
    from vault_env import cached_vault_id as _cached_vault_id
    vid = _cached_vault_id(vault)
    requests = 1 if vid else 2            # a NAME-addressed list resolves the name: 2 billed
    try:
        r = _op_run(["item", "list", "--vault", vid or vault, "--format", "json"])
    except UnicodeDecodeError as exc:
        raise Boundary(f"`op item list` answered bytes that are not UTF-8 ({exc}) — an item list "
                       "decoded with a replacement character is not a fleet") from exc
    if r.returncode != 0:
        raise Boundary(f"`op item list` rc {r.returncode}: {(r.stderr or '').strip()[:120]}")
    try:
        rows = json.loads(r.stdout or "[]")
    except json.JSONDecodeError as exc:
        raise Boundary(f"`op item list` did not answer JSON: {exc}") from exc
    entries, errs = {}, []
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict) or not row.get("id"):
            errs.append("an item list row carried no id — it cannot be addressed, only counted")
            continue
        entries[str(row["id"])] = {"title": row.get("title", "?"), "version": row.get("version")}
    if not entries:
        raise Boundary("the item list carried no id/title pairs — an empty vault answer is not an "
                       "empty fleet")
    return entries, requests, errs


# --------------------------------------------------------------------------- the read
def _note_partial(errs: list[str]) -> None:
    """ONE line per read, whichever route answered. An item that did not read is not a harmless
    gap: its values were never compared and its name was never seen, so the run must say PARTIAL
    rather than look quiet. The routes RETURN their errors for this; a route that printed them itself
    would print the line twice on the re-exec path, where the child answers across a pipe."""
    if errs:
        print(f"vault-read NOTE: {len(errs)} item(s) did not read (first: {errs[0]}) — a partial "
              "read is not a clean read", file=sys.stderr)


class VaultRead:
    """What one batched read answered: items in memory, the request count, the route, the versions
    digest, and the items that did NOT read. Attributes, not a dict, so a leg cannot mutate the
    shared read by accident."""

    def __init__(self, items: dict, requests: int, route: str, vkey: str, cred_route: str = "",
                 errors: list[str] | None = None):
        self.items = items
        self.requests = requests
        self.route = route
        self.vkey = vkey
        self.cred_route = cred_route
        # The partial reads travel with the read, they do not vanish into a route's stderr: the leak
        # gate's `errs` argument — and its refusal to shorten the ledger — depend on it arriving.
        self.errors = list(errors or [])

    def by_title(self, title: str) -> dict | None:
        hits = [row | {"id": iid} for iid, row in self.items.items() if row.get("title") == title]
        if len(hits) > 1:
            # Titles are the primary key of the vault (docs/deployment-secrets.md); two of them is a
            # vault defect, and guessing which copy a leg meant is worse than naming it.
            raise Boundary(f"{len(hits)} items share the title {title!r} — the vault's primary key "
                           "has collided; a leg may not guess which copy it read")
        return hits[0] if hits else None

    def only(self) -> dict:
        """The single row a one-item read answered. Refuses to pick when the read answered more than
        one — a leg that asked for ONE item may not guess which of several it got."""
        if len(self.items) != 1:
            raise Boundary(f"this read answered {len(self.items)} item(s); a leg that asked for ONE "
                           "item may not pick one of them")
        return next(iter(self.items.values()))

    def print_cost(self, leg: str) -> None:
        """The leg's own line — a run's quota price belongs in the log, not in a guess. Every leg
        prints it, which is what turns 'how much did today cost' from an archaeology question into
        a grep."""
        print(_cost_line(leg, self.requests, self.route, f"{len(self.items)} item(s) in memory"))


def read_vault(vault: str = DEFAULT_VAULT, note: str = "") -> VaultRead:
    """The ONE whole-vault read. Fixture seam: HL_VAULT_READ_FIXTURE. Boundary = no read, no guess."""
    fixture = os.environ.get("HL_VAULT_READ_FIXTURE")
    if fixture:
        items, requests, errs = _read_fixture(Path(fixture))
        route = "fixture"
        key = _vkey(items)          # digested ONCE: the line printed and the object returned agree
        _say(route, requests, len(items), key)
        _note_partial(errs)
        return VaultRead(items, requests, route, key, errors=errs)

    ok, why = _vault_ensure()
    if not ok:
        raise Boundary(f"no vault credential reachable on this seat ({why}) — an environment "
                       "boundary: reading the vault without one is the desktop-app route, i.e. a "
                       "consent dialog per read, not a verdict")
    from vault_env import STATE as _VS
    cred_route = str(_VS.get("route", "resolved"))

    forced = os.environ.get("HL_VAULT_READ_ROUTE", "")
    if forced == "op-fanout":
        items, requests, errs = _read_op_fanout(vault)
        route = "op-fanout(FALLBACK)"
    else:
        try:
            items, requests, errs = _read_sdk(vault)
            route = "sdk"
        except ImportError:
            launcher, log = sdk_probe()
            for line in log:
                print(f"vault-read {line}", file=sys.stderr)
            if launcher is None:
                print("vault-read: no interpreter imports onepassword — taking the labelled "
                      "op-fanout FALLBACK (1 request per item). The seat step that removes this "
                      "line: `python3 scripts/lib/vault_read.py --install-sdk`", file=sys.stderr)
                items, requests, errs = _read_op_fanout(vault)
                route = "op-fanout(FALLBACK)"
            else:
                items, requests, errs = _read_via_launcher(launcher, vault)
                route = f"sdk:{launcher[-1] if len(launcher) == 1 else '+'.join(launcher)}"
    if note:
        print(f"vault-read: {note}", file=sys.stderr)
    key = _vkey(items)              # digested ONCE — see the fixture arm above
    _say(route, requests, len(items), key, cred_route)
    _note_partial(errs)             # once, here, whatever route answered
    return VaultRead(items, requests, route, key, cred_route, errs)


def _cost_line(leg: str, requests: int, route: str, what: str) -> str:
    """ONE shape for a leg's quota line, so "what did today cost" is one grep across the gate."""
    return (f"{leg}: vault requests this leg: {requests} — route={route} ({what}; the account "
            "ceiling is 1000 requests/24 h across ALL its service accounts — "
            "`op service-account ratelimit`)")


class VaultNames:
    """Titles and versions only — the shape a name list needs, at ONE request on every route.

    A separate shape, on purpose: a leg that asked for the vault's NAMES must not be handed rows that
    look like a read and carry no values, and it certainly must not have paid for the values."""

    def __init__(self, entries: dict, requests: int, route: str, vkey: str,
                 errors: list[str] | None = None):
        self.entries = entries
        self.requests = requests
        self.route = route
        self.vkey = vkey
        self.errors = list(errors or [])

    def print_cost(self, leg: str) -> None:
        print(_cost_line(leg, self.requests, self.route,
                         f"{len(self.entries)} name(s), values NOT read"))


def read_names(vault: str = DEFAULT_VAULT, note: str = "") -> VaultNames:
    """The vault's TITLES and VERSIONS — one request on EVERY route, and no value read at all.

    This exists because `--list` used to call `read_vault()`: on the labelled fallback that is one
    `item list` plus one `item get` per item, ~144 requests of the account's 1000/24 h bucket spent
    to print a column of titles the list answer already carried. Same routes, same provenance line,
    same `Boundary`, one tenth of the price."""
    fixture = os.environ.get("HL_VAULT_READ_FIXTURE")
    if fixture:
        items, requests, errs = _read_fixture(Path(fixture))
        entries = {iid: {"title": row["title"], "version": row["version"]}
                   for iid, row in items.items()}
        key = _vkey(entries)
        if note:
            print(f"vault-read: {note}", file=sys.stderr)
        _say("fixture(names-only)", requests, len(entries), key)
        _note_partial(errs)
        return VaultNames(entries, requests, "fixture(names-only)", key, errs)

    ok, why = _vault_ensure()
    if not ok:
        raise Boundary(f"no vault credential reachable on this seat ({why}) — an environment "
                       "boundary: reading the vault without one is the desktop-app route, i.e. a "
                       "consent dialog per read, not a verdict")
    from vault_env import STATE as _VS
    cred_route = str(_VS.get("route", "resolved"))

    forced = os.environ.get("HL_VAULT_READ_ROUTE", "")
    if forced == "op-fanout":
        entries, requests, errs = _names_op_fanout(vault)
        route = "op-fanout(FALLBACK,names-only)"
    else:
        try:
            entries, requests, errs = _names_sdk(vault)
            route = "sdk(names-only)"
        except ImportError:
            launcher, log = sdk_probe()
            for line in log:
                print(f"vault-read {line}", file=sys.stderr)
            if launcher is None:
                print("vault-read: no interpreter imports onepassword — the name list takes the "
                      "labelled op-fanout FALLBACK, where ONE list still answers it", file=sys.stderr)
                entries, requests, errs = _names_op_fanout(vault)
                route = "op-fanout(FALLBACK,names-only)"
            else:
                items, requests, errs = _read_via_launcher(launcher, vault, names_only=True)
                entries = {iid: {"title": row["title"], "version": row["version"]}
                           for iid, row in items.items()}
                route = (f"sdk:{launcher[-1] if len(launcher) == 1 else '+'.join(launcher)}"
                         "(names-only)")
    if not entries:
        raise Boundary("the name list answered ZERO items — an empty vault answer is not an empty fleet")
    if note:
        print(f"vault-read: {note}", file=sys.stderr)
    key = _vkey(entries)
    _say(route, requests, len(entries), key, cred_route)
    if all(row["version"] is None for row in entries.values()):
        # Not a failure, and not something to leave to the reader to discover: this SDK release's
        # list rows carry no version number, so the VERSION column is empty while the NAMES are whole.
        print("vault-read NOTE: the SDK's list rows carried no versions — titles are complete, the "
              "version column is empty, and read_vault()/--values is the mode that reads versions",
              file=sys.stderr)
    _note_partial(errs)
    return VaultNames(entries, requests, route, key, errs)


def read_item(title: str, vault: str = DEFAULT_VAULT) -> VaultRead:
    """ONE item, ID-addressed — for the leg that needs exactly one item, where the batched read
    would spend a dozen requests to avoid spending one. Addressing comes from the SAME vault map
    `vault_env.item_ref` owns (a cold map costs one `op item list`; an unknown title keeps the NAME
    and says so, because a guessed ID is a wrong answer, not a cheap one).

    The answer is the SAME shape `read_vault` returns — a read of one row, so `.only()` is the row
    and `.print_cost(leg)` is the leg's quota line. One shape for both faces is what keeps a leg
    from asking "which of these two did I get back?"."""
    fixture = os.environ.get("HL_VAULT_READ_FIXTURE")
    if fixture:
        items, _, errs = _read_fixture(Path(fixture))
        vr = VaultRead(items, 0, "fixture", _vkey(items), errors=errs)
        row = vr.by_title(title)
        if row is None:
            raise Boundary(f"the fixture vault has no item titled {title!r}")
        key = _vkey({row["id"]: row})
        _say("fixture", 0, 1, key)
        return VaultRead({row["id"]: row}, 0, "fixture", key)
    ok, why = _vault_ensure()
    if not ok:
        raise Boundary(f"no vault credential reachable on this seat ({why}) — an environment "
                       "boundary: reading the vault without one is the desktop-app route, i.e. a "
                       "consent dialog per read, not a verdict")
    requests = 0
    if shutil.which("op") is None:
        vr = read_vault(vault)  # no CLI at all: the batched read is the only reader left
        row = vr.by_title(title)
        if row is None:
            raise Boundary(f"the vault read found no item titled {title!r}")
        key = _vkey({row["id"]: row})
        return VaultRead({row["id"]: row}, vr.requests, vr.route, key, vr.cred_route)
    from vault_env import item_ref as _item_ref, STATE as _VS
    v_arg, i_arg, form = _item_ref(vault, title)
    if form.startswith("names"):
        requests += 2  # the map refresh that could not name this title already cost the list read
        get_reads = 3  # a NAME-addressed get resolves the name: 3 billed, not 1
    else:
        get_reads = 1
    try:
        r = _op_run(["item", "get", i_arg, "--vault", v_arg, "--format", "json"])
    except UnicodeDecodeError as exc:
        raise Boundary(f"the read of {title!r} answered bytes that are not UTF-8 ({exc}) — a value "
                       "decoded with a replacement character is not a credential") from exc
    if r.returncode != 0:
        raise Boundary(f"the read of {title!r} failed rc {r.returncode}: "
                       f"{(r.stderr or '').strip()[:120]}")
    try:
        got = json.loads(r.stdout or "{}")
    except json.JSONDecodeError as exc:
        raise Boundary(f"the read of {title!r} was not JSON: {exc}") from exc
    item = {"id": got.get("id", i_arg), "title": got.get("title", title),
            "version": got.get("version"), "fields": _norm_fields(got.get("fields", []))}
    vkey = _vkey({item["id"]: item})
    requests += get_reads
    route = f"op-item({'ID' if get_reads == 1 else 'name-addressed, 3 billed'})"
    _say(route, requests, 1, vkey, str(_VS.get("route", "resolved")))
    return VaultRead({item["id"]: item}, requests, route, vkey, str(_VS.get("route", "resolved")))


# --------------------------------------------------------------------------- CLI
def _refuse_tty() -> bool:
    return sys.stdout.isatty() or os.environ.get("HL_VAULT_READ_TTY") == "1"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--list", action="store_true",
                    help="title<TAB>id<TAB>version per item; no values")
    ap.add_argument("--values", action="store_true",
                    help="the whole vault as JSON on a PIPE ONLY — a terminal is refused (rc 3)")
    ap.add_argument("--item", metavar="TITLE",
                    help="one item as JSON (ID-addressed) — on a PIPE ONLY, a terminal is refused (rc 3)")
    ap.add_argument("--probe", action="store_true",
                    help="print which interpreter imports the SDK, and the seat install command")
    ap.add_argument("--install-sdk", action="store_true",
                    help="pip install onepassword-sdk into the probed interpreter — an explicit seat "
                         "act, never run by the reader itself")
    ap.add_argument("--self-test", action="store_true", help="fixture arms; ZERO requests")
    ap.add_argument("--vault", default=DEFAULT_VAULT)
    ap.add_argument("--sdk-required", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--names-only", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    if args.probe:
        launcher, log = sdk_probe()
        for line in log:
            print(line)
        if launcher:
            print(f"sdk launcher: {shlex_join(launcher)}")
        else:
            print("sdk launcher: NONE — every leg takes the labelled op-fanout FALLBACK (1 request "
                  "per item). Seat step: `<compatible interpreter> -m pip install onepassword-sdk` "
                  "(cp39-cp313 wheels, incl. win_amd64) — scripted form: "
                  "python3 scripts/lib/vault_read.py --install-sdk")
        return 0 if launcher else 1

    if args.install_sdk:
        launcher, log = sdk_probe()
        for line in log:
            print(line, file=sys.stderr)
        if launcher:
            print(f"already importable via {shlex_join(launcher)} — nothing to install", file=sys.stderr)
            return 0
        # Install into the newest compatible interpreter, visibly. This is the seat step README §4.8
        # says belongs to a script and not to the runbook; it is explicit because a read tool that
        # installs its own dependencies is a supply-chain act nobody asked for.
        for cand in (SDK_CANDIDATES_WIN if os.name == "nt" else SDK_CANDIDATES_POSIX):
            if shutil.which(cand[0]) is None:
                continue
            print(f"installing onepassword-sdk for {shlex_join(cand)} (values pass through memory "
                  "only; the install itself writes the package to that interpreter's site-packages)",
                  file=sys.stderr)
            r = subprocess.run([*cand, "-m", "pip", "install", "onepassword-sdk"],
                               stdin=subprocess.DEVNULL, capture_output=True)
            sys.stderr.write((r.stderr or b"").decode("utf-8", "replace"))
            if r.returncode != 0 and b"externally-managed-environment" in (r.stderr or b""):
                # A Debian seat marks its system python PEP-668, so the plain install is REFUSED and
                # the seat act is a USER-site one: nothing in the OS package set moves, `python3`
                # still imports the SDK, and that is what the probe's candidate list needs. Said out
                # loud because it is not the command the caller typed.
                print("vault-read: PEP 668 (externally-managed-environment) — retrying as a USER-site "
                      "install into the same interpreter; no system package changes", file=sys.stderr)
                r = subprocess.run([*cand, "-m", "pip", "install", "--user", "--break-system-packages",
                                    "onepassword-sdk"], stdin=subprocess.DEVNULL, capture_output=True)
                sys.stderr.write((r.stderr or b"").decode("utf-8", "replace"))
            return 0 if r.returncode == 0 and _sdk_available(cand) else 1
        print("no candidate interpreter exists on this seat to install into", file=sys.stderr)
        return 1

    if args.values:
        if _refuse_tty():
            print("vault-read: --values refuses a terminal — a value travels down a pipe, never "
                  "onto a tty", file=sys.stderr)
            return 3
        try:
            if args.sdk_required:
                # A re-exec child: falling back HERE would pay for the fan-out a second time under
                # a line that claims the batched read, so the child that cannot do the SDK says so
                # at rc 4 and the parent decides.
                try:
                    items, requests, errs = (_names_sdk(args.vault) if args.names_only
                                             else _read_sdk(args.vault))
                except ImportError as exc:
                    print(f"vault-read: {exc}", file=sys.stderr)
                    return 4
                _say("sdk(names-only)" if args.names_only else "sdk", requests, len(items),
                     _vkey(items))
                # errors ride the ANSWER, not the child's stderr: the parent parses stdout, and a
                # partial read that stops at this pipe is the P1 this whole payload exists for.
                sys.stdout.write(_emit_values_json(items, requests, errs, names_only=args.names_only))
                return 0
            vr = read_vault(args.vault)
        except Boundary as exc:
            print(f"vault-read: {exc}", file=sys.stderr)
            return 1
        sys.stdout.write(_emit_values_json(vr.items, vr.requests, vr.errors))
        return 0

    if args.item:
        # A value mode, so the pipe rule applies here too: `--item` prints one item's FIELDS, which is
        # the whole vault value for the item asked. Refused BEFORE any read, so refusing also costs
        # nothing — the same rc 3 as `--values` and `vault-env.sh --emit`.
        if _refuse_tty():
            print(f"vault-read: --item refuses a terminal — {args.item} would print its fields onto a "
                  "tty; pipe it (a value travels down a pipe, never onto a screen)", file=sys.stderr)
            return 3
        try:
            vr = read_item(args.item, args.vault)
            item = vr.only()
        except Boundary as exc:
            print(f"vault-read: {exc}", file=sys.stderr)
            return 1
        # ASCII-only on the pipe, exactly like --values: a value that travels as \uXXXX escapes cannot
        # be re-encoded by the seat locale on the way out (docs/harness-pi-seats.md §1).
        json.dump({"item": item, "requests": vr.requests}, sys.stdout, ensure_ascii=True)
        return 0

    if args.list:
        # The names-only read: ONE request on every route, because the list answer already carries
        # id/title/version. Reaching for read_vault() here is what used to spend a get per item on the
        # fallback route to print a column of titles.
        try:
            vn = read_names(args.vault)
        except Boundary as exc:
            print(f"vault-read: {exc}", file=sys.stderr)
            return 1
        for iid in sorted(vn.entries, key=lambda k: vn.entries[k]["title"]):
            print(f"{vn.entries[iid]['title']}\t{iid}\t{vn.entries[iid].get('version')}")
        return 0

    ap.print_help(sys.stderr)
    return 2


# --------------------------------------------------------------------------- self-test
def self_test() -> int:
    """Every arm costs ZERO vault requests: the fixture route, a STUB onepassword package on
    PYTHONPATH, and a stub `op` that counts calls answer instead of the vault. The arms that matter
    most are the ones gradeable on a day the account's request budget is spent — which is every day
    this suite runs — plus the two refusals (no credential, and a tty for values)."""
    fails = 0
    n_arms = 0        # counted, not asserted: a footer that hard-codes the arm count is a line that
                      # reads confidently while quietly lying about how much was graded.

    def check(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails, n_arms
        n_arms += 1
        fails += 0 if ok else 1
        print(f"  arm {label}: {'ok' if ok else 'FAIL'}{(' — ' + detail) if (detail and not ok) else ''}")

    import tempfile

    def mint(n: int) -> str:
        return "".join("a" for _ in range(n)) + f"FIXTURE{str(n).zfill(4)}"

    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        canary = "v@" + mint(24) + "!"   # a SYNTHESISED value; a fixture never holds a fleet secret
        items = {f"iid{i:026d}": {"title": f"item_{i}", "version": 3 + i,
                                  "fields": [{"id": "password", "label": "password",
                                              "value": canary if i == 7 else f"v{i}x" * 6,
                                              "type": "Concealed", "section": ""}]}
                 for i in range(9)}
        fx = tdp / "fixture.json"
        fx.write_text(json.dumps({"items": items}), encoding="utf-8")

        env_off = dict(os.environ, OP_SERVICE_ACCOUNT_TOKEN="", HL_VAULT_FILE=str(tdp / "nope"),
                       HL_VAULT_CLASS="linux", HL_WSL="off", HL_VAULT_READ_FIXTURE="",
                       HL_VAULT_READ_ROUTE="", HL_VAULT_STATE_DIR=str(tdp / "state"))

        # (1) the fixture route answers a whole vault for ZERO requests.
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--list", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_off, HL_VAULT_READ_FIXTURE=str(fx)))
        err = (r.stderr or b"").decode("utf-8", "replace")
        check("the fixture route costs ZERO requests and says so",
              r.returncode == 0 and r.stdout.decode("utf-8", "replace").count("item_") == 9
              and "requests=0" in err and "route=fixture" in err,
              f"rc {r.returncode} err {err[:120]!r}")

        # (2) the vkey is a digest of VERSIONS, never of values: change every value, keep the
        # versions, and the key must not move (and vice versa). This is the dictionary-oracle rule
        # check_secret_leak.py states; the formula is shared, so the arm belongs here.
        v1 = _vkey(items)
        shifted = {k: dict(v, fields=[dict(f, value="rotated-" + f["value"]) for f in v["fields"]])
                   for k, v in items.items()}
        check("value changes do not move the versions digest", _vkey(shifted) == v1,
              "a value-keyed digest would be an oracle on short secrets")
        bumped = {k: dict(v, version=v["version"] + 1) for k, v in items.items()}
        check("a version bump moves the digest (a rotation invalidates what reads it)",
              _vkey(bumped) != v1)

        # (3) --values refuses a terminal and discloses nothing on it.
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--values", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_off, HL_VAULT_READ_FIXTURE=str(fx), HL_VAULT_READ_TTY="1"))
        out = (r.stdout or b"") + (r.stderr or b"")
        check("--values refuses a terminal (rc 3) and discloses nothing",
              r.returncode == 3 and canary.encode() not in out, f"rc {r.returncode}")

        # (4) down a pipe the same mode carries the JSON (what the re-exec handoff relies on).
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--values", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_off, HL_VAULT_READ_FIXTURE=str(fx)))
        try:
            got = json.loads(r.stdout.decode("utf-8", "replace"))
            n_fields = sum(len(row["fields"]) for row in got["items"].values())
        except Exception:
            got, n_fields = {}, 0
        check("--values hands the JSON down a pipe to the caller",
              r.returncode == 0 and len(got.get("items", {})) == 9 and n_fields == 9,
              f"rc {r.returncode} items {len(got.get('items', {}))}")

        # (5) no credential anywhere is a BOUNDARY (rc 1), not a desktop-app call: a stub `op` on
        # PATH must come back UNCALLED, which is the whole safety property vault-env.sh exports.
        stub = tdp / "bin"; stub.mkdir()
        calls = tdp / "op.calls"; calls.write_text("", encoding="utf-8")
        (stub / "op").write_text('#!/bin/sh\nprintf x >> "$STUB_OP_CALLS"\n'
                                 'echo "stub op should never run" >&2\nexit 1\n', encoding="utf-8")
        (stub / "op").chmod(0o755)
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--list", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_off, PATH=f"{stub}{os.pathsep}{os.environ.get('PATH','')}",
                                    STUB_OP_CALLS=str(calls)))
        err = (r.stderr or b"").decode("utf-8", "replace")
        check("no credential is rc 1 naming a boundary, and `op` was NEVER called",
              r.returncode == 1 and "boundary" in err.lower()
              and not calls.read_text(encoding="utf-8"), f"rc {r.returncode} err {err[:140]!r}")

        # (6) the SDK route on a STUB package: one list + ceil(n/50) get_all calls, chunk sizes
        # within the cap. 55 fake items exercise the split; the in-process form keeps the counting
        # free of fd tricks — the assertion is the REQUEST COUNT, which the route reports itself.
        pkg = tdp / "stublib" / "onepassword"
        pkg.mkdir(parents=True)
        (pkg / "__init__.py").write_text(
            "import os\n"
            "import sys\n"
            "CALLS = []\n"
            "SEEN = []\n"
            "class _F:\n"
            "    def __init__(s, i): s.id, s.title, s.value, s.field_type, s.section_id = 'password', 'password', 'stubvalue' + str(i), 'Concealed', None\n"
            "class _I:\n"
            "    def __init__(s, i): s.id, s.title, s.version, s.fields, s.vault_id = 'iid' + str(i).zfill(26), 'item_' + str(i), 1 + i, [_F(i)], 'vaultid'\n"
            "class _V:\n"
            "    def __init__(s, i, t): s.id, s.title = i, t\n"
            "class _R:\n"
            "    def __init__(s, c, e=None): s.content, s.error = c, e\n"
            "class _Resp:\n"
            "    def __init__(s, rs): s.individual_responses = rs\n"
            "class _Items:\n"
            "    async def list(s, v, *f):\n"
            "        CALLS.append('list'); SEEN.append(v)\n"
            "        if os.environ.get('STUB_TRACEBACK'):\n"
            "            sys.stderr.write('Traceback (most recent call last):\\n  File \"stub.py\", "
            "line 1, in <module>\\nException: invalid user input: the provided ID is not in a valid "
            "format\\n')\n"
            "            raise SystemExit(1)\n"
            "        assert v not in ('V', 'V2'), 'the SDK route must address items.list by vault "
            "ID, never by name'\n"
            "        return [_I(i) for i in range(55)]\n"
            "    async def get_all(s, v, ids):\n"
            "        assert len(ids) <= 50, 'a chunk over the API cap is a request the server refuses'\n"
            "        CALLS.append('get_all'); SEEN.append(v)\n"
            "        bad = os.environ.get('STUB_FAIL_ONE', '')\n"
            "        return _Resp([_R(None, 'item unavailable (stub)') if bad == i else _R(_I(int(i[3:])))\n"
            "                      for i in ids])\n"
            "class _Vaults:\n"
            "    async def list(s):\n"
            "        CALLS.append('vaults.list')\n"
            "        return [_V('vaultid', 'V'), _V('vaultid2' + 'b' * 17, 'V2')]\n"
            "class Client:\n"
            "    items = _Items()\n"
            "    vaults = _Vaults()\n"
            "    @classmethod\n"
            "    async def authenticate(cls, token, name, version):\n"
            "        assert token\n"
            "        return cls()\n",
            encoding="utf-8")
        # The SDK route addresses the vault by ID (see _sdk_vault_id): warm the SAME ID map the CLI
        # legs share, in the temp state dir, so these arms count what a WARM seat pays — an arm that
        # silently took the cold-map path would print a request count this suite never spends.
        (tdp / "state").mkdir(parents=True, exist_ok=True)
        (tdp / "state" / "op-map-V.tsv").write_text("# vault_id=vaultid\n", encoding="utf-8")
        st_before = os.environ.get("HL_VAULT_STATE_DIR")
        os.environ["HL_VAULT_STATE_DIR"] = str(tdp / "state")
        sys.path.insert(0, str(tdp / "stublib"))
        for m in [k for k in sys.modules if k.startswith("onepassword")]:
            sys.modules.pop(m, None)
        tok_before = os.environ.get("OP_SERVICE_ACCOUNT_TOKEN")
        os.environ["OP_SERVICE_ACCOUNT_TOKEN"] = "x" * 48
        try:
            items_s, requests_s, errs_s = _read_sdk("V")
            import onepassword as _op_pkg
            ok6 = len(items_s) == 55 and requests_s == 3 and errs_s == [] \
                and _op_pkg.CALLS.count("get_all") == 2
            detail6 = f"items {len(items_s)} requests {requests_s} errors {errs_s} calls {getattr(_op_pkg, 'CALLS', None)}"
        except Exception as exc:
            items_s, ok6, detail6 = {}, False, f"{type(exc).__name__}: {str(exc)[:140]}"
        check("the SDK route costs one list + one get_all per 50-ID chunk (55 items -> 3 calls)",
              ok6, detail6)

        # (6b) A PARTIAL read on the SDK route. An `individual_response` with no content is an item
        # this run never saw — so it must arrive as `errors`, the run must say so ONCE, and the item
        # count must not read like a whole fleet. This is the finding the leak gate's permanently-empty
        # `errs` list came from: a route that printed its note into its own stderr, on the re-exec
        # path the only route this seat takes, printed it where nobody was listening.
        try:
            bad_id = "iid" + "3".zfill(26)
            os.environ["STUB_FAIL_ONE"] = bad_id
            err_cap = io.StringIO()
            with contextlib.redirect_stderr(err_cap):
                vr_p = read_vault("V")
            got_err = err_cap.getvalue()
            check("a partial SDK read arrives as errors and the run says PARTIAL once, not twice",
                  len(vr_p.items) == 54 and len(vr_p.errors) == 1
                  and got_err.count("partial read is not a clean read") == 1
                  and "item unavailable" in vr_p.errors[0],
                  f"items {len(vr_p.items)} errors {vr_p.errors} note {got_err.count('partial')}")

            # (6c) and the SAME partial read down the re-exec handoff, the route a Win11 seat
            # actually takes: the child's errors must cross the pipe in the ANSWER, not in its
            # stderr, and the parent must still say it once.
            pp_before = os.environ.get("PYTHONPATH")
            os.environ["PYTHONPATH"] = str(tdp / "stublib")
            try:
                items_x, requests_x, errs_x = _read_via_launcher([sys.executable], "V")
                check("the re-exec SDK handoff carries the child's partial read across the pipe",
                      len(items_x) == 54 and len(errs_x) == 1 and requests_x >= 3,
                      f"items {len(items_x)} requests {requests_x} errors {errs_x}")
            finally:
                if pp_before is None:
                    os.environ.pop("PYTHONPATH", None)
                else:
                    os.environ["PYTHONPATH"] = pp_before
        except Exception as exc:
            check("a partial SDK read arrives as errors and the run says PARTIAL once, not twice",
                  False, f"{type(exc).__name__}: {str(exc)[:160]}")
        finally:
            os.environ.pop("STUB_FAIL_ONE", None)
            if tok_before is None:
                os.environ.pop("OP_SERVICE_ACCOUNT_TOKEN", None)
            else:
                os.environ["OP_SERVICE_ACCOUNT_TOKEN"] = tok_before
        check("the SDK read keys versions by item ID like every other route",
              ok6 and _vkey(items_s) == _vkey({k: {"version": v["version"]}
                                               for k, v in items_s.items()}))

        # (6d) THE VAULT ADDRESS. `items.list`/`items.get_all` take a vault ID and answer a TITLE with
        # `invalid user input: … the provided ID is not in a valid format`; `op` hides that by
        # resolving names, the SDK does not. This is the arm that would have caught the first live
        # batched read failing on every seat at once (HD-1207), so it asserts the ADDRESS, not a count.
        tok6d = os.environ.get("OP_SERVICE_ACCOUNT_TOKEN")
        os.environ["OP_SERVICE_ACCOUNT_TOKEN"] = "x" * 48     # stub auth only; these arms read no vault
        try:
            import onepassword as _op2
            _op2.CALLS.clear()
            _op2.SEEN.clear()
            try:
                _n_e, _n_r, _n_errs = _names_sdk("V")
                ok6d = _n_r == 1 and "vaults.list" not in _op2.CALLS and "V" not in _op2.SEEN
                detail6d = f"requests {_n_r} calls {_op2.CALLS} seen {_op2.SEEN}"
            except Exception as exc:
                ok6d, detail6d = False, f"{type(exc).__name__}: {str(exc)[:140]}"
            check("the SDK names route addresses items.list by vault ID; a warm ID map costs nothing",
                  ok6d, detail6d)

            # (6e) a COLD map resolves the name once, through the SDK itself, and the count carries
            # the request it spent — a route that hides a request is worse than one that never made it.
            _op2.CALLS.clear()
            _op2.SEEN.clear()
            try:
                _c_e, _c_r, _c_errs = _names_sdk("V2")
                ok6e = (_c_r == 2 and _op2.CALLS.count("vaults.list") == 1
                        and "V2" not in _op2.SEEN)
                detail6e = f"requests {_c_r} calls {_op2.CALLS} seen {_op2.SEEN}"
            except Exception as exc:
                ok6e, detail6e = False, f"{type(exc).__name__}: {str(exc)[:140]}"
            check("a cold ID map costs the SDK route ONE vaults.list, and says so in the count",
                  ok6e, detail6e)

            # (6f) and a vault the account does not answer is a Boundary that names the remedy — never
            # an empty fleet, and never a guessed ID.
            try:
                _names_sdk("NoSuchVault")
                ok6f, detail6f = False, "no Boundary raised"
            except Boundary as exc:
                ok6f, detail6f = "no vault titled" in str(exc), str(exc)[:140]
            except Exception as exc:
                ok6f, detail6f = False, f"{type(exc).__name__}: {str(exc)[:140]}"
            check("an unknown vault name is a Boundary that names the ID map, never an empty fleet",
                  ok6f, detail6f)

            # (6g) a failing child must name the FAILURE. Quoting the head of its stderr is how a live
            # SDK failure read as `Traceback (most recent call last):` for a whole session and never
            # said what broke; the last line is the exception, so that is the line a Boundary carries.
            pp6g = os.environ.get("PYTHONPATH")
            os.environ["PYTHONPATH"] = str(tdp / "stublib")
            os.environ["STUB_TRACEBACK"] = "1"
            try:
                _read_via_launcher([sys.executable], "V")
                ok6g, detail6g = False, "no Boundary raised"
            except Boundary as exc:
                ok6g = ("not in a valid format" in str(exc)
                        and "Traceback (most recent call last)" not in str(exc))
                detail6g = str(exc)[:180]
            except Exception as exc:
                ok6g, detail6g = False, f"{type(exc).__name__}: {str(exc)[:140]}"
            finally:
                os.environ.pop("STUB_TRACEBACK", None)
                if pp6g is None:
                    os.environ.pop("PYTHONPATH", None)
                else:
                    os.environ["PYTHONPATH"] = pp6g
            check("a failing SDK child names its exception, not the word Traceback", ok6g, detail6g)
        finally:
            if tok6d is None:
                os.environ.pop("OP_SERVICE_ACCOUNT_TOKEN", None)
            else:
                os.environ["OP_SERVICE_ACCOUNT_TOKEN"] = tok6d
            if st_before is None:
                os.environ.pop("HL_VAULT_STATE_DIR", None)
            else:
                os.environ["HL_VAULT_STATE_DIR"] = st_before

        sys.path.remove(str(tdp / "stublib"))
        for m in [k for k in sys.modules if k.startswith("onepassword")]:
            sys.modules.pop(m, None)

        # (7) the FALLBACK is ID-addressed: a stub `op` proves the fan-out never addresses an item
        # by NAME (3 requests each) and counts exactly list + one get per item.
        fakebin = tdp / "fbin"; fakebin.mkdir()
        rows = [{"id": f"iid{i:026d}", "title": f"item_{i}", "version": 1,
                 "vault": {"id": "vaultid00000000000000000"}} for i in range(4)]
        (tdp / "list.json").write_text(json.dumps(rows), encoding="utf-8")
        # A PYTHON stub, not a sh script: `bash` from a python subprocess can resolve the WSL
        # launcher on a Win11 seat, and an arm whose stub silently fails to exec tests nothing.
        (fakebin / "op_stub.py").write_text(
            "import json, os, sys\n"
            "args = sys.argv[1:]\n"
            "with open(os.environ['OP_STUB_LOG'], 'a', encoding='utf-8') as fh:\n"
            "    fh.write(' '.join(args) + '\\n')\n"
            "if 'list' in args:\n"
            "    sys.stdout.write(open(os.environ['OP_STUB_LIST'], encoding='utf-8').read())\n"
            "elif 'get' in args:\n"
            "    if args[2] == os.environ.get('OP_STUB_FAIL_ID', ''):\n"
            "        sys.stderr.write('stub: this item did not read'); sys.exit(1)\n"
            "    json.dump({'id': args[2], 'title': 't', 'version': 1,\n"
            "               'fields': [{'id': 'password', 'label': 'password',\n"
            "                           'value': 'vvvvvvvvvv', 'type': 'Concealed'}]}, sys.stdout)\n",
            encoding="utf-8")
        log = tdp / "op.log"; log.write_text("", encoding="utf-8")
        mmap = tdp / "state"; mmap.mkdir(exist_ok=True)   # the SDK arms above create it to warm a map
        (mmap / "op-map-V.tsv").write_text("# vault_id=vaultid00000000000000000\n"
                                           + "".join(f"{r['title']}\t{r['id']}\n" for r in rows),
                                           encoding="utf-8")
        env_fall = dict(env_off, PATH=f"{fakebin}{os.pathsep}{os.environ.get('PATH','')}",
                        OP_SERVICE_ACCOUNT_TOKEN="x" * 48, OP_STUB_LOG=str(log),
                        OP_STUB_LIST=str(tdp / "list.json"), HL_VAULT_STATE_DIR=str(mmap),
                        HL_VAULT_READ_ROUTE="op-fanout",
                        # the seam, not a feature: the arm names its own stub launcher so the
                        # fallback shape is graded identically on both seat planes.
                        HL_VAULT_READ_OP_CMD=f"{sys.executable} {fakebin / 'op_stub.py'}")
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--values", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL, env=env_fall)
        calls_txt = log.read_text(encoding="utf-8")
        get_calls = [ln for ln in calls_txt.splitlines() if " item get " in f" {ln} "]
        # ID-addressed means: the positional is an item ID (iid… from the map), never a title, and
        # the --vault slot carries the vault ID, never the name — a NAME anywhere in a get line is
        # the 3-read shape this fallback exists to avoid.
        mis = [ln for ln in get_calls if " iid" not in f" {ln} " or "vaultid00000000000000000" not in ln]
        try:
            got = json.loads(r.stdout.decode("utf-8", "replace"))
        except Exception:
            got = {}
        err7 = (r.stderr or b"").decode("utf-8", "replace")
        check("the op fan-out FALLBACK is ID-addressed and counts 1 list + 1 get per item",
              r.returncode == 0 and len(got.get("items", {})) == 4
              and len(get_calls) == 4 and calls_txt.count("item list") == 1 and not mis
              and "route=op-fanout" in err7 and "requests=5" in err7,
              f"rc {r.returncode} gets {len(get_calls)} misaddressed {mis[:1]}")

        # (7e) a PARTIAL read on the FALLBACK route: one get answers rc != 0. The read must say so,
        # the count must still include the request that failed (the account paid for it), and the
        # --values payload must carry the error so a leg on the other side of the pipe can act on it.
        log7e = tdp / "op-partial.log"; log7e.write_text("", encoding="utf-8")
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--values", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_fall, OP_STUB_LOG=str(log7e), OP_STUB_FAIL_ID=rows[1]["id"]))
        try:
            got7e = json.loads(r.stdout.decode("utf-8", "replace"))
        except Exception:
            got7e = {}
        err7e = (r.stderr or b"").decode("utf-8", "replace")
        check("a failed `op item get` is a named partial read, counted, and carried in the payload",
              r.returncode == 0 and len(got7e.get("items", {})) == 3
              and len(got7e.get("errors", [])) == 1
              and err7e.count("partial read is not a clean read") == 1 and "requests=5" in err7e,
              f"rc {r.returncode} items {len(got7e.get('items', {}))} errors {got7e.get('errors')} "
              f"err {err7e[-120:]!r}")

        # (7b) a COLD ID map: the fan-out must answer it with its OWN list (2 billed for the name
        # resolution), never with a separate discovery list, and the gets must still go out
        # ID-addressed off the list answer. The count the line prints is what the account pays.
        cold = tdp / "state-cold"; cold.mkdir()
        log7 = tdp / "op-cold.log"; log7.write_text("", encoding="utf-8")
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--values", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_fall, OP_STUB_LOG=str(log7), HL_VAULT_STATE_DIR=str(cold)))
        calls7 = log7.read_text(encoding="utf-8")
        err7b = (r.stderr or b"").decode("utf-8", "replace")
        lists7 = [ln for ln in calls7.splitlines() if " item list " in f" {ln} "]
        check("a cold ID map costs the fallback ONE name-addressed list, not a discovery read + a list",
              r.returncode == 0 and len(lists7) == 1 and "--vault V" in lists7[0]
              and "requests=6" in err7b,
              f"rc {r.returncode} lists {lists7} err {err7b[:120]!r}")

        # (7c) the bytes of the value pipe: a value carrying a CR and non-ASCII characters must come
        # back byte-exactly AND the pipe itself must be pure ASCII, so no seat locale sits between
        # the vault and the leg (docs/harness-pi-seats.md §1 — the HD-1202 class this pins).
        odd_v = "a\r\nb\u00e9\u4e2d"          # CR, LF, é, 中 — synthesised, never a fleet value
        fx_u = tdp / "fixture-utf8.json"
        fx_u.write_text(json.dumps({"items": {"iid" + "0" * 23 + "u8": {
            "title": "item_utf8", "version": 4, "fields": [
                {"id": "password", "label": "password", "value": odd_v, "type": "Concealed"}]}}}),
            encoding="utf-8")
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--values", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_off, HL_VAULT_READ_FIXTURE=str(fx_u)))
        raw = (r.stdout or b"").strip()
        try:
            back = json.loads(raw.decode("ascii"))["items"]["iid" + "0" * 23 + "u8"]["fields"][0]["value"]
        except Exception:
            back = None
        check("a CR and a non-ASCII byte cross the value pipe byte-exactly, as ASCII",
              r.returncode == 0 and raw.isascii() and back == odd_v,
              f"rc {r.returncode} ascii={raw.isascii()} back={back!r}")

        # (7d) a byte that is NOT utf-8 in an `op` answer must never arrive as a value. Decoding it
        # with errors="replace" would put U+FFFD inside a secret and let the leak gate compare a
        # mangled needle; here the item is simply a partial read that names the reason.
        (fakebin / "op_raw.py").write_text(
            "import json, os, sys\n"
            "args = sys.argv[1:]\n"
            "if 'list' in args:\n"
            "    sys.stdout.write(open(os.environ['OP_STUB_LIST'], encoding='utf-8').read())\n"
            "elif args[2] == os.environ.get('OP_STUB_BAD_ID'):\n"
            "    raw = json.dumps({'id': args[2], 'title': 't', 'version': 1,\n"
            "                      'fields': [{'id': 'password', 'label': 'password',\n"
            "                                  'value': 'PLACEHOLDERvalue'}]}).encode()\n"
            "    sys.stdout.buffer.write(raw.replace(b'PLACEHOLDER', bytes([0xff, 0xfe, 0xc3, 0x28])))\n"
            "else:\n"
            "    json.dump({'id': args[2], 'title': 't', 'version': 1,\n"
            "               'fields': [{'id': 'password', 'label': 'password',\n"
            "                           'value': 'goodvalue00000', 'type': 'Concealed'}]}, sys.stdout)\n",
            encoding="utf-8")
        log8 = tdp / "op-raw.log"; log8.write_text("", encoding="utf-8")
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--values", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_fall, OP_STUB_LOG=str(log8),
                                    HL_VAULT_READ_OP_CMD=f"{sys.executable} {fakebin / 'op_raw.py'}",
                                    OP_STUB_BAD_ID=rows[2]["id"]))
        try:
            got8 = json.loads(r.stdout.decode("utf-8", "replace"))
        except Exception:
            got8 = {}
        err8 = (r.stderr or b"").decode("utf-8", "replace") + (r.stdout or b"").decode("utf-8", "replace")
        check("a non-UTF-8 byte in an item answer is a named partial read, never a U+FFFD value",
              r.returncode == 0 and len(got8.get("items", {})) == 3
              and "not UTF-8" in err8 and "\\xfffd" not in err8 and "\ufffd" not in err8,
              f"rc {r.returncode} items {len(got8.get('items', {}))} err {err8[:140]!r}")

        # (8) the provenance line never carries a value: run the fixture route with a canary value
        # and require the canary to be ABSENT from everything the module wrote to stderr.
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--list", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_off, HL_VAULT_READ_FIXTURE=str(fx)))
        err = (r.stderr or b"").decode("utf-8", "replace")
        check("stderr proves route/requests/versions and discloses NO value",
              "route=fixture" in err and "requests=0" in err and "versions=" in err
              and canary not in err and canary not in (r.stdout or b"").decode("utf-8", "replace"),
              err[:140])

        # (8b) `--list` is the NAME mode, so it must cost ONE request on the FALLBACK route: the list
        # row already carries id/title/version, and paying a `get` per item here was ~144 requests of
        # the account's day for a column of titles. Asserted on the stub's CALL LOG, not on the
        # module's own arithmetic: zero get lines, one list line.
        log8b = tdp / "op-list.log"; log8b.write_text("", encoding="utf-8")
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--list", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_fall, OP_STUB_LOG=str(log8b)))
        calls8b = log8b.read_text(encoding="utf-8")
        err8b = (r.stderr or b"").decode("utf-8", "replace")
        check("--list on the FALLBACK route pays ONE item list and ZERO gets",
              r.returncode == 0 and calls8b.count("item list") == 1
              and "item get" not in calls8b and "requests=1" in err8b
              and "names-only" in err8b and len(r.stdout.decode().splitlines()) == 4,
              f"rc {r.returncode} calls {calls8b.count('item list')} list/"
              f"{calls8b.count('item get')} get err {err8b[-120:]!r}")

        # (8c) the same on the SDK route: `items.list` alone — one request, and no get_all at all
        # (the count is the route's own, so requests=1 IS the proof that no chunk was fetched).
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--list", "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_off, OP_SERVICE_ACCOUNT_TOKEN="x" * 48,
                                    HL_VAULT_READ_FIXTURE="",
                                    PYTHONPATH=str(tdp / "stublib")))
        err8c = (r.stderr or b"").decode("utf-8", "replace")
        check("--list on the SDK route pays items.list alone (1 request, no get_all)",
              r.returncode == 0 and "requests=1" in err8c and "sdk(names-only)" in err8c
              and len(r.stdout.decode().splitlines()) == 55,
              f"rc {r.returncode} err {err8c[-140:]!r}")

        # (9) the probe answers without a network or a vault, and --install-sdk never runs from here.
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--probe"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_off, HL_VAULT_READ_PY_CANDIDATES=os.pathsep.join(
                               [sys.executable, str(tdp / "no-such-interpreter")])))
        out = (r.stdout + r.stderr).decode("utf-8", "replace")
        check("--probe names every candidate and its verdict", "probe:" in out and "absent" in out,
              out[:140])

        # (10) read_item on the fixture seam answers one item for ZERO requests.
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--item", "item_3",
                            "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_off, HL_VAULT_READ_FIXTURE=str(fx)))
        try:
            got = json.loads(r.stdout.decode("utf-8", "replace"))
        except Exception:
            got = {}
        check("--item on the fixture route answers one item, ZERO requests",
              r.returncode == 0 and got.get("requests") == 0
              and got.get("item", {}).get("title") == "item_3", f"rc {r.returncode} {str(got)[:100]}")

        # (10b) `--item` is a VALUE mode — it prints an item's fields — so the pipe rule binds there
        # too: a terminal is rc 3, nothing is printed, and because the refusal happens before any
        # read, refusing costs ZERO requests as well. The canary sits in item_7 on purpose.
        r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--item", "item_7",
                            "--vault", "V"],
                           capture_output=True, stdin=subprocess.DEVNULL,
                           env=dict(env_off, HL_VAULT_READ_FIXTURE=str(fx), HL_VAULT_READ_TTY="1"))
        out10 = (r.stdout or b"") + (r.stderr or b"")
        check("--item refuses a terminal (rc 3) and discloses no field value", r.returncode == 3
              and canary.encode() not in out10 and b"v7x" not in out10,
              f"rc {r.returncode} out {out10[:110]!r}")

    if fails:
        print(f"vault_read.py --self-test: FAILED — {fails} arm(s)")
        return 1
    print(f"vault_read.py --self-test: OK ({n_arms} arms — the fixture path costs ZERO requests, the "
          "SDK path counts list + get_all chunks and addresses the VAULT by ID, the FALLBACK counts "
          "what the account pays and is ID-addressed, the digest is of versions and never of values, "
          "the value pipe is ASCII and byte-exact whatever the seat locale, and both refusals "
          "(no credential, a tty for values) hold)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
