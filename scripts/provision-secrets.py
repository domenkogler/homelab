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
  * Coupled fields rotate together: e.g. the victoria-metrics_api/victoria-logs_api pairs
    regenerate their `username` + `password` in lockstep.
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
import shutil
import string
import subprocess
import sys

VAULT = "Homelab-ansible"


def _bcrypt_ok(py: list[str]) -> bool:
    """Return True if `py` can actually `import bcrypt`."""
    try:
        r = subprocess.run(py + ["-c", "import bcrypt"],
                           capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return r.returncode == 0


def _detect_bcrypt_py() -> list[str]:
    """Resolve the python to run the bcrypt snippet with.

    The generated `bcrypt` bcrypt_hash field is computed by shelling out to a
    python that has `bcrypt` installed (a temp bootstrap venv), because this
    repo's `op` target may not. Prefer `BCRYPT_PY` (env override, e.g. to point
    at a specific temp venv) -> else the first of `python3`, `py -3` that BOTH
    exists AND can `import bcrypt`. `py -3` is the Windows launcher and fails
    on the WSL/Debian primary even when `python3` is present (HD-205), so
    `python3` is probed first. Falls back to this process's own interpreter.
    """
    env = os.environ.get("BCRYPT_PY")
    if env:
        cand = env.split()
        if _bcrypt_ok(cand):
            return cand
        print(f"warning: BCRYPT_PY '{env}' cannot import bcrypt; probing others",
              file=sys.stderr)
    for cand in ("python3", "py -3"):
        argv = cand.split()
        if shutil.which(argv[0]) is not None and _bcrypt_ok(argv):
            return argv
    return [sys.executable]


BCRYPT_PY = _detect_bcrypt_py()  # temp venv python

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
    ("Database",    "onlyoffice_db",          lambda: [f"username=onlyoffice", f"password={gen_pw()}"]),
    ("API Credential", "qdrant_db",             lambda: [f"credential={gen_pw()}"]),   # HD-268 Qdrant vector-store API key (replaces PGVector; no username, single static key) — QDRANT__SERVICE__API_KEY
    ("API Credential", "crowdsec-webui_lapi_api", lambda: [f"credential={gen_token()}"]),  # HD-272 CrowdSec Web UI LAPI watcher password (cscli machines add crowdsec-web-ui --password ... -f /dev/null); url-safe token, not externally-coupled
    ("Database",    "zipline_db",             lambda: [f"username=zipline",   f"password={gen_pw()}"]),   # HD-112
    ("Database",    "litellm_db",             lambda: [f"username=litellm",   f"password={gen_pw()}"]),   # HD-247 LiteLLM runtime DB (STORE_MODEL_IN_DB) — keys/models/spend live here; CRITICAL state, dumped via db-backup DB06
    # --- Password items ---
    ("Password",    "authentik_password",     lambda: [f"password={gen_pw()}"]),
    ("Password",    "kopia_password",         lambda: [f"password={gen_pw()}"]),
    ("Password",    "pihole_password",        lambda: [f"password={gen_pw()}"]),   # HD-318 Pi-hole admin WEBPASSWORD (catalog-generated, owner-authorized 2026-09-07)
    ("Password",    "ha-vrrp_password",       lambda: [f"password={gen_pw()}"]),
    ("Password",    "nut_password",           lambda: [f"password={gen_pw()}"]),
    ("Password",    "nut-exporter_password",  lambda: [f"password={gen_pw()}"]),
    ("Password",    "n8n_password",           lambda: [f"password={gen_pw()}"]),
    ("Password",    "matrix_password",        lambda: [f"password={gen_pw()}"]),
    ("Password",    "opencloud-collab_password", lambda: [f"password={gen_pw()}"]),
    ("Password",    "zipline_password",          lambda: [f"password={gen_pw()}"]),   # CORE_SECRET (HD-112)
    ("Login",       "onlyoffice-rabbitmq_login", lambda: [f"username=onlyoffice", f"password={gen_pw()}"]),
    ("Password",    "openwebui_secret",       lambda: [f"password={gen_pw()}"]),
    # --- API Credential ---
    ("API Credential", "litellm_master_key",      lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "immich-ml-internal_api",  lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "n8n-webhook_api",         lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "signal-internal_api",     lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "network-snmp_api",       lambda: [f"credential={gen_pw()}"]),   # HD-205: catalog-created ONCE, but NOT_AUTO_ROTATABLE — the RO community is applied to the router/switch as a manual `/snmp community` step (HD-03); auto-rotating the vault value alone would silently diverge from the live device (deployment-secrets §3 rotation contract)
    # HD-313: router read-only logpipe API user — Password item (role reads field='password',
    # the RouterOS /user password; NOT an API-Credential like network-snmp). Non-VPS role item,
    # outside check-vault-items docker_services scope — seed via provision-vault.sh.
    ("Password",       "mikrotik-logpipe_api",    lambda: [f"password={gen_pw()}"]),
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
    # HD-318: sonarr/radarr API keys — catalog-created PLACEHOLDER so the Phase-3
    # render (recyclarr needs them) can run before the services are up. After first
    # boot, OVERWRITE the vault value with the instance's real config.xml ApiKey and
    # re-run recyclarr (same pattern as forgejo_api above).
    ("API Credential", "sonarr_api",              lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "radarr_api",              lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "openclaw_gateway_token",  lambda: [f"password={gen_pw()}"]),
    ("API Credential", "openclaw-opencloud_api",  lambda: [f"username=openclaw", f"credential={gen_pw()}"]),
    # HD-268c dual harness: Forgejo service-account PR-only tokens (per-agent) — issued by
    # the Forgejo UI after boot, same class as `forgejo_api`. Granting scoped PR-only on the
    # homelab repo, NO merge rights. `dsh_api` / `pi-harness_openai_api` are NOT here — they
    # are LiteLLM glue-minted scoped virtual keys (HD-247, defined in litellm_scoped_keys).
    ("API Credential", "pi-harness_forgejo_api",    lambda: [f"credential={gen_pw()}"]),   # pi PR-only Forgejo PAT
    ("API Credential", "dsh_forgejo_api",           lambda: [f"credential={gen_pw()}"]),   # DSH PR-only Forgejo PAT
    # metabase-forgejo_ro: read-only analytics role in forgejo-db (HD-242). Rotation-safe by
    # design: the deploy-service db_ro_sync task re-applies password + grants every converge.
    ("Login",          "metabase-forgejo_ro",      lambda: [f"username=metabase_ro", f"password={gen_pw()}"]),
    # grafana_login: Grafana admin password — generated (no external source);
    # the SMTP relay creds are the shared `smtp_login` item (not auto-gen here).
    ("Login",       "grafana_login",              lambda: [f"password={gen_pw()}"]),
    ("API Credential", "kopia-server-internal_api", lambda: [f"username=kopia@{gen_token(16)}", f"credential={gen_pw()}"]),
    # HD-318a: kopia-server TLS trust anchor — NOT a generated password: it is the SHA-256
    # fingerprint of the persisted self-signed cert under /srv/docker/kopia-server/config/tls.crt
    # (lowercase hex). The catalog CANNOT generate it (it must equal the live cert's fingerprint) —
    # provision-vault.sh seeds it by RE-READING the host file after the server cert is in place.
    # Kept in the catalog as a Password item for vault-lineage/NOT_AUTO_ROTATABLE bookkeeping;
    # --create would fail the fingerprint-must-match-live-cert assertion, so it is guarded.
    ("Password", "kopia-server_fingerprint", lambda: []),  # value seeded from the host cert, not generated
    # HD-341/342 Victoria* migration: VictoriaMetrics + VictoriaLogs replace Prometheus +
    # Loki on the VPS. Both use Victoria's OWN -httpAuth.username / -httpAuth.password
    # (plaintext basic-auth — NOT bcrypt like the retired prometheus web.yml), so the items
    # carry username + password only. Rotatable (no external/app coupling beyond the re-render).
    ("API Credential", "victoria-metrics_api",  lambda: [f"username=victoria", f"password={gen_pw()}"]),
    ("API Credential", "victoria-logs_api",     lambda: [f"username=victoria", f"password={gen_pw()}"]),
    # --- Homelable (HD-45, oldsrv network/rack topology visualizer) ---
    # homelable_login: Login w/ username=admin, password=plaintext admin password, and
    # bcrypt_hash (the value the compose renders as AUTH_PASSWORD_HASH). bcrypt_hash is
    # generated at item-creation via homelable_login_item() (bcrypt-on-separate-python,
    # HD-205); rotation-safe (a fresh hash is written on --rotate).
    ("Login", "homelable_login", lambda: homelable_login_item()),
    # homelable_secret: SECRET_KEY (JWT/session signing, >= 32 bytes) — also the shared
    # MCP_SERVICE_KEY source when the MCP container is enabled. Rotatable (no external
    # app coupling beyond re-render; sessions reset on rotation).
    ("Password", "homelable_secret", lambda: [f"password={gen_pw(48)}"]),
    # homelable_mcp: MCP_API_KEY for the optional Homelable MCP server (AI-tool topology
    # read/write). Catalog-created so flipping homelable_mcp_enabled never needs a manual
    # seed; unused (and unreferenced by the compose) while the flag is false.
    ("API Credential", "homelable_mcp", lambda: [f"credential={gen_token(32)}"]),
]
# Items never auto-rotated by this tool (external/app coupling). Kept here as a
# guard list so `--rotate-all`/`--rotate` cannot clobber them.
NOT_AUTO_ROTATABLE = {
    "wg_password",          # WireGuard S2S private key (ROUTER side) — stored manually with a `wg genkey` value; NEVER generated as a random password by this tool (it is also absent from CATALOG).
    "wg_password_vps",       # WireGuard S2S private key (VPS side) — HD-285 fix: distinct per-side key. Same manual `wg genkey` discipline; not in CATALOG.
    "network-snmp_api",      # MikroTik SNMP RO community — catalog-created ONCE (HD-205), but the value is applied to the router/switch as a MANUAL `/snmp community` step (HD-03, snmp.yml.j2 header); auto-rotating the vault value alone would silently diverge from the live device. Rotate via vault edit + manual device re-apply.
    "matrix_password",      # Matrix shared secret — reissue breaks rooms/sessions
    "authentik_db", "opencloud_db", "immich_db", "forgejo_db",  # running Postgres
    "onlyoffice_db",           # running Postgres (sidecar cluster init-once password)
    "zipline_db",             # running Postgres sidecar — init-once password (HD-112)
    "litellm_db",             # running Postgres sidecar — init-once password (HD-247); holds the virtual-key/model runtime (models-in-DB), so rotation = re-init = data loss without a dump/restore cycle
    "zipline_password",       # Zipline CORE_SECRET — rotation invalidates all sessions
    "onlyoffice-rabbitmq_login",  # RABBITMQ_DEFAULT_* applies at first mnesia init; AMQP_URI couples both sides
    "authentik_password",   # Django SECRET_KEY — invalidates the running instance
    "kopia_password",       # repo master password on live repo
    "kopia-server_fingerprint",  # HD-318a: TLS trust anchor — must match the live kopia-server cert; rotate = regenerate cert + re-pin BOTH sides manually
    # Phase 1 additions (2026-08-22): external/app-coupled — rotate via vault + redeploy,
    # never auto-regenerate:
    "authentik_login",      # bootstrap admin — created at Authentik first boot from this value
    "authentik-ldap_bind",  # consumed by the LDAP outpost binding
    "forgejo_api",          # real token issued by the Forgejo UI after first boot
    "openrouter_api",       # external provider API key
    "cohere_api",           # external provider API key
    "sonarr_api",           # real key issued by the Sonarr instance config.xml after first boot (HD-318)
    "radarr_api",           # real key issued by the Radarr instance config.xml after first boot (HD-318)
    "openclaw_gateway_token",   # consumed by the running gateway
    "openclaw-opencloud_api",   # OpenCloud app-password pair
    "pi-harness_forgejo_api",   # pi-dev PR-only Forgejo token (HD-268c)
    "dsh_forgejo_api",            # DSH PR-only Forgejo token (HD-268c)
    "opencloud_login",      # admin login created at first boot
    # HD-268 tailnet sidecars: headscale preauth keys (mint via the running
    # headscale: `docker exec headscale headscale preauthkeys create --reusable
    # --expiration 90d --tags tag:dsh`; paste the value into 1Password manually).
    # NOT in CATALOG -- provision-secrets.py never auto-creates these (random
    # strings would not be valid headscale keys). Re-mint + 1Password edit on
    # rotation; rare. The compose templates reference them via
    # `vault['tailscale_<svc>_api'].credential` only when the matching
    # `<svc>_tailnet_sidecar_enabled` flag is true (see group_vars/vps.yml).
    "tailscale_dsh_api",
    "tailscale_pi_dev_api",
}


def gen_pw(n: int = 32) -> str:
    # NO '$' in the pool (HD-270): docker compose interpolates a literal `$` in a rendered compose
    # file BEFORE YAML parse, silently truncating the secret at the `$`. Keeping `$` out of generated
    # values makes every rotation natively compose-safe. Escaping at render (| replace('$','$$'))
    # stays as the defensive layer for hand/vendor-sourced values (see docs/deployment-secrets.md).
    # NO '&' in the pool (HD-346): RouterOS /import treats `&` as a command separator — a community/
    # password containing `&` fails the .rsc import with "expected end of command" (live 2026-09-08:
    # network-snmp_api community broke the converge import). Keeping `&` out of generated values makes
    # every rotation RouterOS-import-safe at the generator level.
    # NO '#' in the pool (live 2026-09-08 HD-06 pre-req): NUT/INI-style configs (upsd.users,
    # upsmon.conf MONITOR line, upssched-cmd) treat `#` as a comment marker — a password with `#`
    # truncates the MONITOR line to 5 args and NUT 2.8.1 hard-fails:
    #   "Unable to use old-style MONITOR line without a username" (<numargs==5> check in upsmon.c).
    # Both nas (master) and oldsrv (client) upsmon were down with exactly this. Excluding `#`
    # makes every generated value NUT-config-safe at the generator level (same class as $/&).
    # (`{`/`}`/`!` stay: they are fine in NUT config as long as no `#` truncates the line.)
    pool = string.ascii_letters + string.digits + "!@%^*()-_=+[]{}<>"
    return "".join(secrets.choice(pool) for _ in range(n))


def gen_token(n: int = 32) -> str:
    al = string.ascii_letters + string.digits + "-_"
    return "".join(secrets.choice(al) for _ in range(n))


def op(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["op", *args], capture_output=True, text=True)


def require_write_token() -> int:
    if "OP_SERVICE_ACCOUNT_TOKEN" not in os.environ:
        print("error: OP_SERVICE_ACCOUNT_TOKEN (write-scoped) not set", file=sys.stderr)
        return 1
    return 0


def existing_items() -> dict[str, str] | None:
    """Return {title: id} for the vault, or None if the lookup FAILED.

    A failed lookup is FATAL for any write command (HD-205): proceeding with an
    empty map would make `--create` try to create EVERY item and `--rotate-all`
    skip everything — both silently masking an auth/scope/vault problem. So a
    failure returns None and every caller ABORTS loudly instead of proceeding.
    """
    r = op("item", "list", "--vault", VAULT, "--format", "json")
    if r.returncode != 0:
        print(f"error: cannot list items in vault '{VAULT}': {r.stderr.strip()}",
              file=sys.stderr)
        print("  check OP_SERVICE_ACCOUNT_TOKEN scope and vault name", file=sys.stderr)
        return None
    return {it["title"]: it["id"] for it in json.loads(r.stdout)}


def bcrypt_hash(password: str) -> str:
    """Return a bcrypt hash of `password` via a separate python with bcrypt.

    The password is passed over STDIN (not argv) so it never appears in the
    process list or shell history (HD-205)."""
    py = BCRYPT_PY
    r = subprocess.run(
        py + ["-c",
              "import bcrypt,sys; print(bcrypt.hashpw(sys.stdin.read().encode(), bcrypt.gensalt(rounds=12)).decode())"],
        input=password, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"bcrypt failed: {r.stderr.strip()}")
    return r.stdout.strip()


def homelable_login_item() -> list[str]:
    """Homelable admin Login (HD-45): username + plaintext password + its bcrypt hash.

    The Homelable backend stores AUTH_USERNAME + AUTH_PASSWORD_HASH (bcrypt) in env; the
    compose renders the hash from the item's `bcrypt_hash` field. Keeping the plaintext
    password alongside is what lets the owner log in (and a recoverer re-derive the hash).
    Uses the same bcrypt-on-separate-python helper as the retired prometheus item (HD-205).
    """
    pw = gen_pw()
    return [f"username=admin", f"password={pw}", f"bcrypt_hash={bcrypt_hash(pw)}"]


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
    if existing is None:
        return 1  # loud abort already printed
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
    if existing is None:
        return 1  # loud abort already printed
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
