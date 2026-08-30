#!/usr/bin/env python3
"""Lint: no internal IP literals outside the SSOT.

Enforces `docs/index.md` §Conventions — internal IPv4 ranges/addresses live ONLY in
`docs/network-addresses-generated.md` (SSOT, generated from IaC) and in IaC; every other doc
refers to hosts by hostname/role (`oldsrv.kogler.si`, `ha-vip`, `wg-s2s`) or links
the SSOT row.

Exempt files (documented in the convention):
  * docs/network-addresses-generated.md          — the SSOT itself
  * deployment-ansible/secrets — ★ authoring specs that define IaC values
  * docs/home-assistant-current.md     — historical decision log (strikethrough)
  * deployment-tasks.md                — legacy task log
  * changelog.md                       — append-only history (rows stay as written)

Allowed anywhere: well-known external IPs (public DNS, third-party services) — the
patterns below only match private/special-use ranges (RFC 1918 + 100.64.0.0/10 CGNAT).

Scan scope (HD-197 F5): every canonical root *.md (prompt-* handoffs excluded),
every docs/**/*.md, and every IaC/**/*.md.

Run:   python scripts/check_doc_ips.py
Exit:  0 = clean, 1 = violations. Wired into `validate-all.sh`.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# private / special-use ranges that must not appear outside the SSOT
SPECIAL = [
    re.compile(r"\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}(?:/\d{1,2})?\b"),                    # 10.0.0.0/8
    re.compile(r"\b172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}(?:/\d{1,2})?\b"),        # 172.16.0.0/12
    re.compile(r"\b192\.168\.\d{1,3}\.\d{1,3}(?:/\d{1,2})?\b"),                       # 192.168.0.0/16
    re.compile(r"\b100\.64\.\d{1,3}\.\d{1,3}(?:/\d{1,2})?\b"),                        # 100.64.0.0/10 (CGNAT)
]

EXEMPT_FILES = {
    "docs/network-addresses-generated.md",
    "docs/deployment-ansible.md",
    "docs/deployment-secrets.md",
    "docs/home-assistant-current.md",
    "deployment-tasks.md",
    "changelog.md",                    # append-only history (HD-197 F5)
    "deployment-journal.md",            # append-only as-built record (same class as changelog); IPs appear as command/verify evidence
}

# Ephemeral round-2 audit reports at repo root were fold+deleted by HD-203 (A3
# lifecycle, CONVENTIONS §4); no name list is kept here — deleted files simply no
# longer match the glob.


def _scan_files() -> list[Path]:
    """Canonical root *.md (minus prompt-* handoffs), all docs/**/*.md, all IaC/**/*.md."""
    files: set[Path] = set(ROOT.glob("*.md"))
    files |= set((ROOT / "docs").rglob("*.md"))
    iac = ROOT / "IaC"
    if iac.is_dir():
        files |= set(iac.rglob("*.md"))
    out = []
    for f in sorted(files):
        if f.name.startswith("prompt-"):
            continue
        out.append(f)
    return out


def main() -> int:
    bad = 0
    for f in _scan_files():
        rel = f.relative_to(ROOT).as_posix()
        if rel in EXEMPT_FILES:
            continue
        for ln, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            for rx in SPECIAL:
                if rx.search(line):
                    # ASCII-sanitize the echoed line: Windows consoles default to
                    # cp1252 and a non-ASCII doc char would crash the report itself.
                    safe = line.strip().encode("ascii", "replace").decode("ascii")
                    print(f"{rel}:{ln}: {rx.pattern}")
                    print(f"    {safe}")
                    bad += 1
                    break
    if bad:
        print(
            f"\nFAIL: {bad} internal IP literal(s) outside the SSOT — move them to "
            "network-addresses-generated.md (or use hostnames / SSOT links)."
        )
        return 1
    print("OK: no internal IP literals outside docs/network-addresses-generated.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())