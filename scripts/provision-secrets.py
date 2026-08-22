#!/usr/bin/env python3
"""1Password item create/rotate helper for the `Homelab-ansible` vault.

Persisted in the repo as a *reference* tool only. It is SAFE-BY-DEFAULT:

  * Running with NO arguments prints usage and does NOTHING (no token needed).
  * Every write action (`--create`, `--rotate`, `--rotate-all`) is explicit
    AND requires `--yes` to proceed.
  * The item catalog below is ONLY consumed under an explicit write flag; a
    bare invocation can never create or overwrite anything.

=== Create ===
    OP_SERVICE_ACCOUNT_TOKEN=op_xxx python provision-secrets.py --create --yes
Creates any GENERATED items from the catalog that are missing. Never edits an
existing item (skips present ones), so it can never overwrite a value.

=== Rotate ===
    OP_SERVICE_ACCOUNT_TOKEN=op_xxx python provision-secrets.py --rotate ITEM --yes
Regenerates the secret value of ONE existing item and updates it in place.
    OP_SERVICE_ACCOUNT_TOKEN=op_xxx python provision-secrets.py --rotate-all --yes
Rotates every whitelisted, safely-rotatable item in the catalog (skips items
flagged as externally-coupled).

=== Rotate + reprovision with Ansible (the clean workflow) ===
1Password is the single source of truth: Ansible resolves every secret at
deploy-time via `lookup('community.general.onepassword', ..., vault=op_vault)`
and re-renders the compose/config that consumes it. So rotating a 1P item is
ALL the change you need; a subsequent
    ansible-playbook -i inventory.ini <playbook>     # e.g. site.yml / per-role
re-renders templates with the new value and `docker compose up -d` restarts the
affected containers. No repo change, no manual templating. The Renovate ->
Forgejo Actions -> Ansible path applies the same way after a rotation.

CAVEATS (by design):
  * Coupled fields rotate together: e.g. prometheus-internal_api regenerates
    its `password` AND its `bcrypt_hash` in lockstep.
  * Externally-coupled items (`wg_password`, `matrix_password`, and the OIDC /
    Authentik / DB items) are NOT auto-rotatable by this tool — they have
    consumers outside 1Password (router/VPS tunnel, Matrix shared secret, the
    running Postgres) that must handle the change explicitly. `--rotate-all`
    skips them; `--rotate` refuses them.
  * The old running container keeps the old value until the redeploy — rotate
    and redeploy must be paired (see workflow above).

Auth: OP_SERVICE_ACCOUNT_TOKEN must be a WRITE-scoped Service Account token
(`op_creation` during initial provisioning). It is one-time; revoke it after.
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import string
import subprocess
import sys

VAULT = "Homelab-ansible"
BCRYPT_PY = os.environ.get("BCRYPT_PY", "py -3")  # temp venv python that has `bcrypt`

# ---------------------------------------------------------------------------
# Item catalog. DISABLED BY DEFAULT: it is only consulted when an explicit
# write flag (`--create` / `--rotate-all`) AND `--yes` are given.
#
# Each entry: (1Password category, item name, field-set builder, rotatable?)
#   - rotatable True  -> safe to regenerate value (no external consumer).
#   - rotatable False -> externally/app-coupled; rotate manually.
# ---------------------------------------------------------------------------
CATALOG = [
    # --- Database items (username + password) ---
    ("Database",    "authentik_db",           lambda: [f"username=authentik", f"password={gen_pw()}"]),
    ("Database",    "opencloud_db",           lambda: [f"username=opencloud", f"password={gen_pw()}"]),
    ("Database",    "immich_db",              lambda: [f"username=immich",    f"password={gen_pw()}"]),
    ("Database",    "forgejo_db",             lambda: [f"username=forgejo",   f"password={gen_pw()}"]),
    ("Database",    "pgvector_db",            lambda: [f"username=pgvector",  f"password={gen_pw()}"]),
    # --- Password items ---
    ("Password",    "authentik_password",     lambda: [f"password={gen_pw()}"]),
    ("Password",    "kopia_password",         lambda: [f"password={gen_pw()}"]),
    ("Password",    "ha-vrrp_password",       lambda: [f"password={gen_pw()}"]),
    ("Password",    "nut_password",           lambda: [f"password={gen_pw()}"]),
    ("Password",    "nut-exporter_password",  lambda: [f"password={gen_pw()}"]),
    ("Password",    "n8n_password",           lambda: [f"password={gen_pw()}"]),
    ("Password",    "matrix_password",        lambda: [f"password={gen_pw()}"]),
    ("Password",    "opencloud-collab_password", lambda: [f"password={gen_pw()}"]),
    ("Password",    "openwebui_secret",       lambda: [f"password={gen_pw()}"]),
    # --- API Credential ---
    ("API Credential", "litellm_master_key",      lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "immich-ml-internal_api",  lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "n8n-webhook_api",         lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "signal-internal_api",     lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "network-snmp_api",       lambda: [f"credential={gen_pw()}"]),
    # Phase 1 first-deploy additions (found live 2026-08-22 — render failed on missing items):
    # generated placeholders where the real value arrives later (forgejo token after the
    # Forgejo UI is up; openrouter/cohere keys from the provider dashboards — swap in the
    # vault, re-run playbook).
    ("Password",       "authentik_login",         lambda: [f"password={gen_pw()}"]),
    ("Password",       "authentik-ldap_bind",     lambda: [f"password={gen_pw()}"]),
    ("Login",          "opencloud_login",         lambda: [f"username=admin", f"password={gen_pw()}"]),
    ("API Credential", "forgejo_api",             lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "openrouter_api",          lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "cohere_api",              lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "openclaw_gateway_token",  lambda: [f"password={gen_pw()}"]),
    ("API Credential", "openclaw-opencloud_api",  lambda: [f"username=openclaw", f"credential={gen_pw()}"]),
    # grafana_login: Grafana admin password — generated (no external source);
    # the SMTP relay creds are the shared `smtp_login` item (not auto-gen here).
    ("Login",       "grafana_login",              lambda: [f"password={gen_pw()}"]),
    ("API Credential", "kopia-server-internal_api", lambda: [f"username=kopia@{gen_token(16)}", f"credential={gen_pw()}"]),
    # prometheus-internal_api: username + password + bcrypt_hash rotate together.
    ("API Credential", "prometheus-internal_api", lambda: bcrypt_item()),
]
# Items never auto-rotated by this tool (external/app coupling). Kept here as a
# guard list so `--rotate-all`/`--rotate` cannot clobber them.
NOT_AUTO_ROTATABLE = {
    "wg_password",          # WireGuard S2S private key — BOTH router (.rsc) + VPS (.netdev)
                             # consume it as a WG key. Stored manually with a `wg genkey` value;
                             # NEVER generated as a random password by this tool (it is also
                             # absent from CATALOG).
    "matrix_password",      # Matrix shared secret — reissue breaks rooms/sessions
    "authentik_db", "opencloud_db", "immich_db", "forgejo_db", "pgvector_db",  # running Postgres
    "authentik_password",   # Django SECRET_KEY — invalidates the running instance
    "kopia_password",       # repo master password on live repo
    # Phase 1 additions (2026-08-22): external/app-coupled — rotate via vault + redeploy,
    # never auto-regenerate:
    "authentik_login",      # bootstrap admin — created at Authentik first boot from this value
    "authentik-ldap_bind",  # consumed by the LDAP outpost binding
    "forgejo_api",          # real token issued by the Forgejo UI after first boot
    "openrouter_api",       # external provider API key
    "cohere_api",           # external provider API key
    "openclaw_gateway_token",   # consumed by the running gateway
    "openclaw-opencloud_api",   # OpenCloud app-password pair
    "opencloud_login",      # admin login created at first boot
}


def gen_pw(n: int = 32) -> str:
    pool = string.ascii_letters + string.digits + "!@#$%^&*()-_=+[]{}<>"
    return "".join(secrets.choice(pool) for _ in range(n))


def gen_token(n: int = 32) -> str:
    al = string.ascii_letters + string.digits + "-_"
    return "".join(secrets.choice(al) for _ in range(n))


def gen_wg_key() -> str:
    """Generate a valid WireGuard private key (base64 of 32 random bytes) — same
    format `wg genkey` emits. Used ONLY for a manual `op item edit wg_password`;
    the provisioner itself never writes `wg_password` (see NOT_AUTO_ROTATABLE)."""
    import base64
    return base64.b64encode(os.urandom(32)).decode()


def op(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["op", *args], capture_output=True, text=True)


def require_write_token() -> int:
    if "OP_SERVICE_ACCOUNT_TOKEN" not in os.environ:
        print("error: OP_SERVICE_ACCOUNT_TOKEN (write-scoped) not set", file=sys.stderr)
        return 1
    return 0


def existing_items() -> dict[str, str]:
    """Return {title: id} for the vault."""
    r = op("item", "list", "--vault", VAULT, "--format", "json")
    if r.returncode != 0:
        print(f"warning: cannot list items: {r.stderr.strip()}", file=sys.stderr)
        return {}
    return {it["title"]: it["id"] for it in json.loads(r.stdout)}


def bcrypt_hash(password: str) -> str:
    py = BCRYPT_PY.split()
    r = subprocess.run(
        py + ["-c",
              "import bcrypt,sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(rounds=12)).decode())",
              password],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"bcrypt failed: {r.stderr.strip()}")
    return r.stdout.strip()


def bcrypt_item() -> list[str]:
    pw = gen_pw()
    return [f"username=prometheus", f"password={pw}", f"bcrypt_hash={bcrypt_hash(pw)}"]


def create(category: str, title: str, fields: list[str]) -> bool:
    # stdin=DEVNULL: with a non-TTY stdin, `op item create` tries to parse piped JSON
    # and fails with "invalid JSON in piped input" (found live 2026-08-22 under WSL).
    r = subprocess.run(
        ["op", "item", "create", "--category", category,
         "--title", title, "--vault", VAULT] + fields,
        capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        print(f"FAILED {title}: {r.stderr.strip()}", file=sys.stderr)
        return False
    print(f"created {title}")
    return True


def rotate(title: str, category: str, fields_builder):
    """Regenerate + overwrite a single existing item's secret fields in place."""
    if title in NOT_AUTO_ROTATABLE:
        print(f"SKIP {title}: externally-coupled item (see NOT_AUTO_ROTATABLE); rotate manually.", file=sys.stderr)
        return False
    fields = fields_builder()
    edit_args = ["op", "item", "edit", title, "--vault", VAULT] + fields
    r = subprocess.run(edit_args, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"FAILED rotate {title}: {r.stderr.strip()}", file=sys.stderr)
        return False
    print(f"rotated {title}")
    return True


def cmd_list(_args) -> int:
    print("Catalog (generated items):")
    for cat, name, _fb in CATALOG:
        flag = "" if name not in NOT_AUTO_ROTATABLE else "   [manual rotate]"
        print(f"  {cat:<16} {name}{flag}")
    print(f"\nNot auto-rotatable: {sorted(NOT_AUTO_ROTATABLE)}")
    return 0


def cmd_create(_args) -> int:
    if require_write_token():
        return 1
    existing = existing_items()
    created, skipped, failed = [], [], 0
    print(f"Vault: {VAULT}")
    for cat, name, fb in CATALOG:
        if name in existing:
            print(f"skip (exists): {name}")
            skipped.append(name)
            continue
        if create(cat, name, fb()):
            created.append(name)
        else:
            failed += 1
    print(f"\nCreated ({len(created)}): {created}")
    print(f"Skipped existing ({len(skipped)}): {sorted(skipped)}")
    return 1 if failed else 0


def cmd_rotate(args) -> int:
    if require_write_token():
        return 1
    if not args.yes:
        print("error: --yes required to rotate", file=sys.stderr)
        return 1
    existing = existing_items()
    if args.rotate_all:
        if not args.yes:
            print("error: --yes required for --rotate-all", file=sys.stderr)
            return 1
        n = 0
        for cat, name, fb in CATALOG:
            if name not in existing:
                print(f"skip (absent): {name}")
                continue
            if rotate(name, cat, fb):
                n += 1
        print(f"\nRotated {n} item(s).")
        return 0
    # single-item rotate
    name = args.rotate
    if name not in existing:
        print(f"error: '{name}' is not an existing item in {VAULT}", file=sys.stderr)
        return 1
    entry = next((e for e in CATALOG if e[1] == name), None)
    if entry is None:
        print(f"error: '{name}' is not in the generated catalog; not auto-rotating.", file=sys.stderr)
        return 1
    _cat, _nm, fb = entry
    return 0 if rotate(name, _cat, fb) else 1


def main() -> int:
    p = argparse.ArgumentParser(
        description="Create/rotate 1Password items in Homelab-ansible (safe-by-default).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="No arguments = no-op help. Writes require an explicit flag + --yes.")
    p.add_argument("--list", action="store_true", help="print the generated-item catalog")
    p.add_argument("--create", action="store_true",
                   help="create missing generated items (requires --yes)")
    p.add_argument("--rotate", metavar="ITEM",
                   help="rotate one existing item's value (requires --yes)")
    p.add_argument("--rotate-all", action="store_true",
                   help="rotate all whitelisted items (requires --yes)")
    p.add_argument("--yes", action="store_true",
                   help="confirm an explicit write action")
    a = p.parse_args()

    if a.list:
        return cmd_list(a)
    if a.create:
        if not a.yes:
            print("error: --create requires --yes", file=sys.stderr)
            return 1
        return cmd_create(a)
    if a.rotate or a.rotate_all:
        return cmd_rotate(a)
    # No action -> safe help no-op (never auto-runs anything).
    p.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
