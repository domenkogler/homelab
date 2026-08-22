#!/usr/bin/env python3
"""Lint: placeholder tokens only in designated bootstrap artifacts (HD-201).

Bootstrap artifacts (preseeds, post_install scripts, the Pi first-boot
script) intentionally ship greppable placeholders — they are injection
points for real 1Password values at generation time. Anywhere ELSE a
placeholder token is a defect: it means an injection point was copied
into IaC/docs/scripts and would silently render or ship a broken value.

Flagged tokens (the B5 greppable-token set, mirrored by the runtime
assertions in `IaC/host/post_install.sh` + `IaC/host/pi/first-boot-config.sh`):
  * REPLACE_ME_                                — B5 mandated marker
  * <SERIAL>                                   — oldsrv preseed disk/bootdev
  * VNESI_MODEL_IN_SERIJSKO_SSD_STEVILKO /
    VNESI_SERIJSKO_USB_KLJUCA                  — nas preseed disk/bootdev
  * _FROM_1PASSWORD>                           — placeholder pubkeys
  * <PLACEHOLDER>                              — pi first-boot key stub

Designated files (placeholders are the design, never flagged): see ALLOWLIST
below — the bootstrap artifacts (injection points) plus the owning-spec doc that
quotes the token set.

Scan scope: every text file in the repo except .git/, brainstorming/
(ephemeral), reports/ (raw snapshots) and prompt-* handoffs; undecodable
(binary) files are skipped.

Run:   python scripts/check_placeholders.py
Exit:  0 = clean, 1 = violations found.  Wired into `validate-all.sh`.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Greppable placeholder tokens (B5). Keep in sync with the runtime
# assertions in IaC/host/post_install.sh + pi/first-boot-config.sh.
_PLACEHOLDER_RE = re.compile(
    r"REPLACE_ME_"
    r"|<SERIAL>"
    r"|VNESI_MODEL_IN_SERIJSKO_SSD_STEVILKO"
    r"|VNESI_SERIJSKO_USB_KLJUCA"
    r"|_FROM_1PASSWORD>"
    r"|<PLACEHOLDER>"
)

# Files where placeholders are intentional injection points / quoted spec.
ALLOWLIST = {
    "IaC/host/post_install.sh",
    "IaC/host/nas/preseed.cfg",
    "IaC/host/oldsrv/preseed.cfg",
    "IaC/host/vps/preseed.cfg",
    "IaC/host/vps/post_install.sh",
    "IaC/host/vps/gen-custom-script.sh",   # generator — matches the tokens by design (sed injection)
    "IaC/host/gen-media-post-install.sh",  # generator (homelab USB media) — matches the tokens by design (sed injection)
    "IaC/host/post_install_with_secrets.sh",  # EPHEMERAL generator output (git-ignored, deleted after USB copy) — carries the same runtime assertion block
    "IaC/host/pi/first-boot-config.sh",
    "docs/deployment-preseed.md",   # owning spec — quotes the tokens
    "changelog.md",                 # append-only history — exempt
}

# Directories never scanned (ephemeral / binary-heavy / raw snapshots).
SKIP_DIRS = {".git", "brainstorming", "reports", "docs/assets"}


def _iter_scan_files() -> list[Path]:
    """All repo files minus skip-dirs, prompt-* handoffs, allowlist, self."""
    me = Path(__file__).resolve()
    out: list[Path] = []
    for p in sorted(ROOT.rglob("*")):
        if not p.is_file() or p.is_symlink():
            continue
        rel = p.relative_to(ROOT).as_posix()
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        if p.name.startswith("prompt-"):
            continue
        if rel in ALLOWLIST or rel == "scripts/check_placeholders.py":
            continue
        if p.resolve() == me:
            continue
        out.append(p)
    return out


def main() -> int:
    violations: list[str] = []
    scanned = 0
    for path in _iter_scan_files():
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError):
            continue                      # binary / undecodable — skip
        scanned += 1
        for lno, line in enumerate(lines, 1):
            if _PLACEHOLDER_RE.search(line):
                violations.append(
                    f"{path.relative_to(ROOT)}:{lno}: placeholder token outside "
                    f"a designated bootstrap artifact"
                )
    if violations:
        print(f"FAIL: {len(violations)} committed placeholder(s) outside "
              f"designated files:")
        for v in violations:
            print(f"  - {v}")
        print("Placeholders belong only in the bootstrap artifacts "
              "(see scripts/check_placeholders.py ALLOWLIST).")
        return 1
    print(f"OK: no placeholder tokens outside designated files "
          f"({scanned} files scanned)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
