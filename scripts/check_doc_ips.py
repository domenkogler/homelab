#!/usr/bin/env python3
"""Lint: no internal IP literals outside the SSOT.

Enforces `docs/index.md` §Conventions — internal IPv4 ranges/addresses live ONLY in
`docs/network-addresses.md` (SSOT, generated from IaC) and in IaC; every other doc
refers to hosts by hostname/role (`oldsrv.kogler.si`, `ha-vip`, `wg-s2s`) or links
the SSOT row.

Exempt files (documented in the convention):
  * docs/network-addresses.md          — the SSOT itself
  * deployment-ansible/preseed/secrets — ★ authoring specs that define IaC values
  * docs/home-assistant-current.md     — historical decision log (strikethrough)
  * deployment-tasks.md                — legacy task log

Allowed anywhere: well-known external IPs (public DNS, third-party services) — the
patterns below only match private/special-use ranges (RFC 1918 + 100.64.0.0/10 CGNAT).

Run:   python scripts/check_doc_ips.py
Exit:  0 = clean, 1 = violations. Wire into CI once Doco-CD activates.
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
    "docs/network-addresses.md",
    "docs/deployment-ansible.md",
    "docs/deployment-preseed.md",
    "docs/deployment-secrets.md",
    "docs/home-assistant-current.md",
    "deployment-tasks.md",
}


def main() -> int:
    files = sorted([*ROOT.glob("docs/**/*.md"), ROOT / "deployment-tasks.md", ROOT / "README.md"])
    bad = 0
    for f in files:
        rel = f.relative_to(ROOT).as_posix()
        if rel in EXEMPT_FILES:
            continue
        for ln, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            for rx in SPECIAL:
                if rx.search(line):
                    print(f"{rel}:{ln}: {rx.pattern}")
                    print(f"    {line.strip()}")
                    bad += 1
                    break
    if bad:
        print(
            f"\nFAIL: {bad} internal IP literal(s) outside the SSOT — move them to "
            "network-addresses.md (or use hostnames / SSOT links)."
        )
        return 1
    print("OK: no internal IP literals outside docs/network-addresses.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())