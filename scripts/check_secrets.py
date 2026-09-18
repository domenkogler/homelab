#!/usr/bin/env python3
"""Secret-shape scanner for the tracked tip (added 2026-09-18).

Why this exists: a live `spark-llm_api` bearer reached `origin/main` inside stability
bench logs — `vllm bench serve` echoes its own request headers, and the step logs were
archived verbatim, including inside `chain-bundle.tar`. A credential in the tree is
invisible to `--check`, to `validate-all`, and to a plain grep that skips binaries, so
this gates on the *shapes* instead.

Scan scope
  * every file in the git INDEX, read from the working copy when present, PLUS every
    untracked non-ignored file — so the gate sees what would be committed next, and a
    new leaky file is caught before it is ever staged;
  * the MEMBERS of every tracked `.tar` / `.tar.gz` / `.tgz` / `.zip` — an archive is
    precisely where a leak hides from grep. An archive that cannot be opened is itself
    reported: three chain bundles turned out to be truncated, and an unreadable
    artifact is a defect whether or not it hides a secret.

Severity
  * FATAL  — an `Authorization:`/`Bearer` credential, or a prefixed provider token
             (`sk-`, `ops_`, `otp-`, `ghp_`, `AKIA`, `xox*-`), or a private-key block.
  * WARN   — weaker shapes (inline `api_key=/password=/token=` assignments) and any
             FATAL-shaped hit under `brainstorming/`, which is a verbatim archive of
             deleted working notes full of fictional examples (see docs/…§Import
             archive). Warnings are printed and do NOT fail the build: a gate that
             cannot pass on a legitimate tree gets ignored within a week.

Output is always MASKED (shape + length + salted hash + 4-char head), never the value:
docs/1password.md §Output hygiene. Exit 0 clean · 1 fatal hits or unreadable archive ·
2 scanner error (an unreadable blob is an error, not a silent skip).
"""
from __future__ import annotations

import hashlib
import io
import os
import re
import subprocess
import sys
import tarfile
import zipfile

FATAL = [
    ("bearer-header", re.compile(r"(?i)\bauthorization\s*(?:=|:)\s*[\"']?\s*bearer\s+([A-Za-z0-9._\-]{16,})")),
    ("bearer-loose", re.compile(r"(?i)\bbearer\s+([A-Za-z0-9._\-]{20,})")),
    ("openai-style-key", re.compile(r"\bsk-[A-Za-z0-9_\-]{20,}")),
    ("1password-sa-token", re.compile(r"\bops_[A-Za-z0-9_\-]{20,}")),
    ("1password-auth-token", re.compile(r"\botp-[A-Za-z0-9]{20,}")),
    ("github-token", re.compile(r"\b(?:ghp|gho|ghs|ghu)_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}")),
    ("aws-access-key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("slack-token", re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{20,}")),
    ("private-key-block", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----")),
]
WARN = [
    ("inline-assignment", re.compile(
        r"(?i)\b(?:api_key|apikey|secret|password|passwd|token)\s*(?:=|:)\s*[\"']?([A-Za-z0-9+/._\-]{24,})[\"']?")),
]

# Paths whose FATAL-shaped hits downgrade to WARN (fictional examples, immutable archive).
WARN_PATHS = re.compile(r"^brainstorming/")
# This scanner's own source contains the shapes it looks for.
SELF = re.compile(r"^scripts/check_secrets\.py$")
ARCHIVE_EXT = (".tar", ".tar.gz", ".tgz", ".zip")

# Not-secrets, by construction: template refs, env lookups, redaction markers, and
# lowercase-dash PROSE (`sk-master-key-here`, `fastgpt-dev-token-string-here`) — every
# real generated token here is mixed-case/base64, so prose never masks a real hit.
ALLOW_VALUE = re.compile(
    r"(?i)^(?:x+|\*+|\.+|<[^>]*>|\$\{[^}]*\}|\{\{[^}]*\}|«[^»]*»|"
    r"(?:os\.[a-z_]+/|process\.env\.|cfg\.|app\.|self\.)\S+|"
    r"[a-z][a-z0-9]*\.[a-z][a-z0-9]*\.[a-z][a-z0-9]*|"
    r"changeme\w*|example\w*|dummy\w*|placeholder\w*|test\w*|your[_\-]\w*|redacted\w*)$")
PROSE = re.compile(r"^[a-z0-9]+(?:[-_][a-z0-9]+){2,}$")   # ≥3 lowercase dash/underscore segments
CODEISH = re.compile(r"[();{}]")                          # an expression, not a credential


def masked(kind: str, value: str) -> str:
    h = hashlib.sha256(("homelab-scan-salt:" + value).encode()).hexdigest()[:10]
    return f"{kind} len={len(value)} hash={h} head={value[:4]!r}…"


def ignorable(value: str) -> bool:
    v = value.strip().strip("\"'")
    if len(v) < 16 or ALLOW_VALUE.match(v) or PROSE.match(v) or CODEISH.search(v):
        return True
    # Placeholder bodies made of filler characters behind a provider prefix:
    # `ghp_xxxxx…`, `hf_xxxx…`, `sk-0000…` — a token whose whole body is one repeated
    # filler char is an example, and no generated credential looks like that.
    body = re.sub(r"^(?:sk|ghp|gho|ghs|ghu|ops|otp|hf|xox[baprs])[_\-]?", "", v)
    return bool(re.fullmatch(r"[x\*0\.\-]+", body))


def scan_bytes(label: str, data: bytes) -> tuple[list[str], list[str]]:
    fatal, warn = [], []
    text = data.decode("utf-8", errors="ignore")
    for kind, pat in FATAL:
        for m in pat.finditer(text):
            val = (m.group(m.lastindex or 1) if m.lastindex else m.group(0)).strip().strip("\"'")
            if ignorable(val):
                continue
            hit = f"{label}:{text.count(chr(10), 0, m.start()) + 1}: {masked(kind, val)}"
            (warn if WARN_PATHS.search(label) else fatal).append(hit)
    for kind, pat in WARN:
        for m in pat.finditer(text):
            val = (m.group(m.lastindex or 1) if m.lastindex else m.group(0)).strip().strip("\"'")
            if ignorable(val):
                continue
            warn.append(f"{label}:{text.count(chr(10), 0, m.start()) + 1}: {masked(kind, val)}")
    return fatal, warn


def read_targets() -> list[tuple[str, bytes]]:
    """Everything that could be committed NEXT: the git index, read from the WORKING COPY
    when the file is present (so a redaction that is staged but not yet committed is
    credited), plus every untracked, non-ignored file — so a leak is caught before the
    first `git add`, not after it. Working-copy content is stricter than HEAD: a dirty
    tree with a fresh secret fails the gate here instead of passing it and landing later."""
    idx = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True).stdout
    others = subprocess.run(["git", "ls-files", "-z", "--others", "--exclude-standard"],
                            capture_output=True, check=True).stdout
    out = []
    for p in (x.decode() for x in idx.split(b"\0") if x):
        if os.path.isfile(p):
            try:
                with open(p, "rb") as fh:
                    out.append((p, fh.read()))
            except OSError as e:
                print(f"ERROR: cannot read {p}: {e}", file=sys.stderr)
                raise SystemExit(2)      # unreadable is an error, never a silent skip
        else:                            # deleted in the worktree but still tracked
            r = subprocess.run(["git", "cat-file", "blob", f":{p}"], capture_output=True)
            if r.returncode != 0:
                print(f"ERROR: cannot read index blob :{p} — {r.stderr.decode().strip()}", file=sys.stderr)
                raise SystemExit(2)
            out.append((p, r.stdout))
    for p in (x.decode() for x in others.split(b"\0") if x):
        try:
            with open(p, "rb") as fh:
                out.append((p, fh.read()))
        except OSError:
            continue                     # sockets/fifos/locked files are not candidates
    return out


def archive_members(path: str, data: bytes) -> list[tuple[str, bytes]]:
    low, out = path.lower(), []
    try:
        if low.endswith((".tar.gz", ".tgz")):
            tf = tarfile.open(fileobj=io.BytesIO(data), mode="r:gz")
        elif low.endswith(".tar"):
            tf = tarfile.open(fileobj=io.BytesIO(data), mode="r:")
        elif low.endswith(".zip"):
            zf = zipfile.ZipFile(io.BytesIO(data))
            return [(f"{path}!{i.filename}", zf.read(i)) for i in zf.infolist() if not i.is_dir()]
        else:
            return []
        with tf:
            for m in tf.getmembers():
                f = tf.extractfile(m) if m.isfile() else None
                if f:
                    out.append((f"{path}!{m.name}", f.read()))
    except Exception as e:
        out.append((f"{path}!<UNREADABLE {type(e).__name__}>", b""))
    return out


def main() -> int:
    if subprocess.run(["git", "rev-parse", "--git-dir"], capture_output=True).returncode:
        print("ERROR: not a git repository", file=sys.stderr)
        return 2
    fatal: list[str] = []
    warn: list[str] = []
    broken: list[str] = []
    n = 0
    for path, data in read_targets():
        n += 1
        if SELF.search(path):
            continue
        if path.lower().endswith(ARCHIVE_EXT):
            units = archive_members(path, data)
        else:
            units = [(path, data)]
        for label, mdata in units:
            if "!<UNREADABLE" in label:
                broken.append(label)
                continue
            f, w = scan_bytes(label, mdata)
            fatal += f
            warn += w

    if broken:
        print("Unreadable archive members (a corrupt artifact is a defect on its own):")
        for b in sorted(broken):
            print(f"  {b}")
    if fatal:
        print(f"FATAL secret shapes in the tracked tip ({len(set(fatal))}):")
        for h in sorted(set(fatal)):
            print(f"  {h}")
        print("\nRemediate in this order: (1) ROTATE the credential — it is burned once pushed;")
        print("(2) one-way redact the file; (3) scrub history if it was ever pushed;")
        print("(4) fix the producer — a log writer that echoes its own Authorization header")
        print("    is the real bug (see spark/bench/run-scenario.sh §SCRUB).")
    if warn:
        print(f"note: {len(set(warn))} weak/example-shaped hits (not blocking):")
        for h in sorted(set(warn))[:12]:
            print(f"  {h}")
        if len(set(warn)) > 12:
            print(f"  … {len(set(warn)) - 12} more")
    if fatal or broken:
        return 1
    print(f"OK: no secret shapes in {n} files (index + untracked; archive members scanned too)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
