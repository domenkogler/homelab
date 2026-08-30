#!/usr/bin/env python3
"""Lint: no literal credential values in the IaC variable layer + templates.

Enforces the repo's secret policy (CONVENTIONS.md §secrets, deployment-secrets.md):
secrets live in the 1Password `Homelab-ansible` vault and are injected via
`lookup('community.general.onepassword', ...)` at template render time. A literal
secret VALUE must never be committed.

Scan scope (HD-189): group_vars/host_vars/*.yml, role defaults/tasks/vars/*.yml,
roles/*/files/*, and every rendered template (templates/**/*.j2) — a literal
credential pasted into a compose template is caught by no other gate.

This linter greps for literal credential *values* in the IaC variable layer:
  * PEM/OpenSSH private-key blocks
  * `*_password:` / `*_secret:` / `*_token:` / `*_api_key:` / `secret:` /
    `client_secret:` … YAML keys whose value is a non-empty, non-Jinja, non-placeholder
    literal.

Exempt by design (not leaks):
  * values that are (or contain) Jinja `{{ ... }}` / `lookup(...)` templates
  * documented placeholders (`changeme`, `CHANGE_ME`, `<...>`, `...`, `example`,
    `your-...`) and empty / `null`
  * yaml pointers/URLs (`vault=`, `item:`, `field=`)
  * comment-only lines

Run:   python scripts/validate-secrets.py
Exit:  0 = clean, 1 = violations found.  Wired into `validate-all.sh`.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANSIBLE = ROOT / "IaC" / "ansible"

# Keys that may carry a literal secret value. Match the tail so both
# `postgres_password:` and `postgres: password:` forms are caught.
_CRED_TAIL = re.compile(
    r"(?:_|-|^)(?:"
    r"password|passwd|pwd|secret|token|client_secret|api[_-]?key|apikey|"
    r"password_hash|private[_-]?key|public[_-]?key|credential"
    r")(?:_|-|$)",
    re.IGNORECASE,
)

# Keys that merely *point at* credentials, never hold their value.
_NON_CRED = re.compile(
    r"(?:_|-|^)(?:"
    r"dir|directory|path|file|filename|host|hostname|port|url|uri|endpoint|"
    r"name|username|user|type|id|vault|item|field|label|description|desc|"
    r"comment|format|required|prompt|help|hint|info|note|ref|scheme|method|"
    r"key_name|key_id|cert|ca_cert|client_cert"
    r")(?:_|-|$)",
    re.IGNORECASE,
)

_PEM = re.compile(
    r"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED |DSA |\S+ )?PRIVATE KEY-----"
)


def _is_comment(line: str) -> bool:
    stripped = line.strip()
    return not stripped or stripped.startswith(("#", "---"))


def _yaml_key_val(line: str):
    """Split a `key: value` / `key = value` line. Returns (key, value) or None."""
    m = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_\-]*)\s*[:=]\s*(.*)$", line)
    if not m:
        return None
    return m.group(1), m.group(2)


def _is_credential_key(key: str) -> bool:
    """True if the YAML key itself indicates a credential-bearing field."""
    return bool(_CRED_TAIL.search(key)) and not _NON_CRED.search(key)


def _is_placeholder(value: str) -> bool:
    """True if a value is not a real secret (template / placeholder / empty)."""
    v = value.strip().strip('"\'')
    if not v or v.lower() in {"null", "none", "~", "{}", "[]", "''", '""'}:
        return True
    if "{{" in v or "lookup(" in v.lower():
        return True
    # Boolean / numeric knobs are policy flags, not credentials (e.g.
    # `OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD: "true"`, `AUTHENTIK_TOKEN_LENGTH: "86"`).
    if v.lower() in {"true", "false", "yes", "no", "on", "off"} or re.fullmatch(r"\d+", v):
        return True
    # Env-var indirection, never a literal (LiteLLM `api_key: os.environ/OPENROUTER_API_KEY`,
    # Python `os.environ.get('HA_FAILOVER_TOKEN', '')`).
    if "os.environ" in v:
        return True
    low = v.lower()
    if any(
        t in low
        for t in (
            "changeme",
            "change_me",
            "your_",
            "your-",
            "example",
            "xxxx",
            "<",
            ">",
            "todo",
            "replace",
            "…",
        )
    ):
        return True
    # A lone value with an inline comment placeholder
    if v in (".", ".."):
        return True
    return False


def _is_pointer_value(key: str, value: str) -> bool:
    """A bare-identifier value on a bare `secret:` key is a 1Password item
    reference (e.g. `secret: meteoblue_api`), not the secret itself — the
    documented pattern in this repo's `*_vars` schemas (subscriptions.yml).
    """
    if key.lower() != "secret":
        return False
    v = value.strip().strip('\"\'')
    # Must be a single token with no whitespace; allow item names like
    # `meteoblue_api`, `Hetzner-SB-Data`, `sub.item`, env-style refs.
    return bool(re.fullmatch(r"[A-Za-z0-9_.@:/-]+", v))


def _lint_file(path: Path) -> list[str]:
    violations: list[str] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (UnicodeDecodeError, OSError):
        return violations

    for lno, raw in enumerate(lines, 1):
        line = raw.rstrip()
        if _is_comment(line):
            continue

        # PEM private-key blocks anywhere in the file are an instant violation.
        if _PEM.search(line):
            violations.append(
                f"{path.relative_to(ROOT)}:{lno}: literal PRIVATE KEY block"
            )
            continue

        kv = _yaml_key_val(line)
        if kv is None:
            continue
        key, value = kv
        if not _is_credential_key(key):
            continue
        if _is_placeholder(value):
            continue

        # Strip trailing comment (but keep the value itself meaningful).
        val = value.split("#")[0].strip().strip('"\'')
        if not val or _is_placeholder(val):
            continue
        # Bare-identifier on a bare `secret:` key = 1Password item reference.
        if _is_pointer_value(key, val):
            continue
        # WireGuard/SSH *public* keys are NOT credentials — they are derived from the
        # private key (kept in 1Password) and are meant to be committed/rendered (e.g.
        # `wg_s2s_router_public_key`, the WG S2S peer pubkey on both sides). The private
        # half still trips `_PEM` above. Match:
        #   * 44-char base64 WG pubkey (WireGuard)
        #   * `ssh-ed25519 AAAA...` / `ssh-rsa AAAA...` OpenSSH public-key line
        if re.search(r"public[_-]?key", key, re.IGNORECASE) and re.search(
            r"(?:ssh-(?:ed25519|rsa|ecdsa|dss)\s+AAAA|[A-Za-z0-9+/]{43}=)\s*$", val
        ):
            continue
        # A credential that survived placeholder & jinja checks is a violation.
        violations.append(
            f"{path.relative_to(ROOT)}:{lno}: possible literal credential on "
            f"'{key}' (use a 1Password lookup)"
        )
    return violations


def _targets() -> list[Path]:
    paths: list[Path] = []
    for sub in ("group_vars", "host_vars"):
        base = ANSIBLE / sub
        if base.is_dir():
            paths.extend(p for p in base.rglob("*.yml") if p.is_file())
    for role_glob in (
        "roles/*/defaults/*.yml",
        "roles/*/tasks/*.yml",
        "roles/*/vars/*.yml",   # HD-189: role vars layer was not scanned
    ):
        for p in ANSIBLE.glob(role_glob):
            if p.is_file() and p not in paths:
                paths.append(p)
    # HD-189: rendered templates + role files were blind spots — a literal
    # credential pasted into a compose template was caught by nothing.
    if (ANSIBLE / "templates").is_dir():
        paths.extend(p for p in (ANSIBLE / "templates").rglob("*.j2") if p.is_file())
    files_dir = ANSIBLE / "roles"
    if files_dir.is_dir():
        for p in files_dir.glob("*/files/*"):
            if p.is_file() and not p.is_symlink():
                paths.append(p)
    return sorted(set(paths))


def main() -> int:
    bad = 0
    for path in _targets():
        for v in _lint_file(path):
            print(v)
            bad += 1
    if bad:
        print(
            f"\nFAIL: {bad} possible literal credential(s) in IaC — move them to "
            "1Password `Homelab-ansible` vault and reference via "
            "lookup('community.general.onepassword', ...) in templates.",
            file=sys.stderr,
        )
        return 1
    print("OK: no literal credentials in group_vars/host_vars/role defaults/templates")
    return 0


if __name__ == "__main__":
    sys.exit(main())
