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

=== Self-test ===
    python3 scripts/secrets/provision-secrets.py --self-test
Runs every WRITE branch against a stubbed `op` CLI — no vault, no token, no network, nothing to
converge. It is the proof that a write is judged by the re-read value, not by the `op` exit code:
landed, spurious-error-on-a-landed-write, genuine failure, a zero-rc edit that landed nothing or
landed only half a pair, partial write, unprovable re-read, absent item, duplicate title (through
`rotate()` AND through the `--rotate` entry path, where the ids come from the listing), an empty field
set, create-when-absent, create-failure (one attempt, never retried), --rotate-all's mixed and clean
verdicts, a call that never answers at all (the timeout leg: UNPROVEN, never a success, never retried),
and the fail-closed legs where a vault listing that fails OR answers rc 0 with a body that is not a JSON
list must attempt ZERO writes.

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
(`op-write_api`, renamed 2026-09-19; `op_creation` during initial provisioning).
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import secrets
import shutil
import string
import subprocess
import sys
import tempfile
from pathlib import Path

VAULT = "Homelab-ansible"


def _bcrypt_ok(py: list[str]) -> bool:
    """Return True if `py` can actually `import bcrypt`."""
    try:
        r = subprocess.run(py + ["-c", "import bcrypt"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
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
    # RETIRED 2026-09-10 (pihole -> Technitium Advanced Blocking): row kept so the
    # item stays provisioned if pihole is ever re-enabled; the deploy entry is
    # enabled:false (home_servers.yml) so no running container consumes it.
    ("Password",    "pihole_password",        lambda: [f"password={gen_pw()}"]),   # Pi-hole admin WEBPASSWORD (catalog-generated, owner-authorized 2026-09-07)
    ("Password",    "ha-vrrp_password",       lambda: [f"password={gen_pw()}"]),
    ("Password",    "nut_password",           lambda: [f"password={gen_pw()}"]),
    ("Password",    "nut-exporter_password",  lambda: [f"password={gen_pw()}"]),
    # --- Cockpit (cockpit-project.org) break-glass management identity — HD-361 ---
    # Owner-decided 2026-09-21 (scope: every host that runs cockpit = nas + oldsrv) and never
    # created: no catalog row, no docs row. Measured 2026-09-23: `getent passwd maint` on oldsrv
    # is ABSENT, so cockpit-oldsrv.kogler.si has a deployed route, a live 9090 socket and no way
    # to log in (Cockpit is PAM-only; every account here is key-only with a locked password).
    # Catalog-generated is correct for these two (unlike cockpit-pi-web_api, whose value must
    # match a live env file): the account does not exist, so there is nothing to match. The
    # consumer renders the hash FROM the vault and adds sudo-group membership only — never
    # NOPASSWD, an SSH key, or AllowUsers membership (HD-361: break-glass != automation).
    ("Password",    "oldsrv-cockpit_login",   lambda: [f"password={gen_pw()}"]),   # HD-361 maint PAM identity, oldsrv
    ("Password",    "nas-cockpit_login",      lambda: [f"password={gen_pw()}"]),   # HD-361 maint PAM identity, nas
    ("Password",    "n8n_password",           lambda: [f"password={gen_pw()}"]),
    ("Password",    "matrix_password",        lambda: [f"password={gen_pw()}"]),
    ("Password",    "opencloud-collab_password", lambda: [f"password={gen_pw()}"]),
    ("Password",    "zipline_password",          lambda: [f"password={gen_pw()}"]),   # CORE_SECRET (HD-112)
    ("Login",       "onlyoffice-rabbitmq_login", lambda: [f"username=onlyoffice", f"password={gen_pw()}"]),
    ("Password",    "openwebui_secret",       lambda: [f"password={gen_pw()}"]),
    # --- API Credential ---
    ("API Credential", "litellm_api",      lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "immich-ml-internal_api",  lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "n8n-webhook_api",         lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "signal-internal_api",     lambda: [f"credential={gen_pw()}"]),
    # HD-1091: soularr→slskd bridge credential. gen_token's alphabet, not gen_pw's: this value is
    # rendered into a compose env AND soularr's config.ini, which configparser reads with
    # ExtendedInterpolation — the pool must contain no character either parser means something by.
    ("API Credential", "soulseek-internal_api",   lambda: [f"credential={gen_token()}"]),
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
    # RETIRED 2026-10-07 (Authentik-as-LDAP for Samba, HD-132/HD-360 → docs/storage-rejected.md):
    # nothing consumes `authentik-ldap_bind` any more — the LDAP outpost left the authentik
    # compose and the Samba passdb went back to local tdbsam. Out of the CATALOG for the same
    # reason as `dsh_forgejo_api` above: `--create` would re-mint a secret no service reads,
    # and a permanently MISSING-looking item in check-vault-items.sh is noise that trains
    # people to ignore it. It STAYS in NOT_AUTO_ROTATABLE below so --rotate-all can never
    # regenerate the live item while it still exists in the vault (owner deletes it, by hand).
    # ("Password",       "authentik-ldap_bind",     lambda: [f"password={gen_pw()}"]),
    # NAS Samba share logins (HD-1093): the credentials `roles/storage/tasks/samba.yml` writes
    # into the NAS passdb with `smbpasswd -a -s`. username is FIXED (the unix/Samba account name
    # in host_vars storage_samba_users) — it must match, or the entry is created but unmountable.
    # Propagation exists (the converge writes the passdb), so rotation = rotate + re-run with
    # `-e storage_samba_password_force=<name>`; see docs/storage.md §Samba.
    ("Login",          "smb-domen_login",         lambda: [f"username=domen", f"password={gen_pw()}"]),
    ("Login",          "smb-shared_login",        lambda: [f"username=shared", f"password={gen_pw()}"]),
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
    # qbittorrent_api: qBittorrent's OWN WebUI login (username `admin` + this password) — the login
    # the Sonarr/Radarr/Lidarr torrent download clients authenticate with. The reverse of the *_api
    # items above: those are consumer-side COPIES of a key the app issued, while this one is the
    # SOURCE — the vault value is what tasks/qbittorrent-seed.yml writes INTO qBittorrent.conf as
    # WebUI\Password_PBKDF2 (PBKDF2-SHA512/100000, `@ByteArray(base64(salt):base64(dk))`), because the
    # image translates no credential env and qbit regenerates a random 9-char password at every start
    # while the stored hash is empty. Rotatable: a docker_services converge rewrites the conf AND the
    # three arr client configs (qbittorrent_seed + arr_client_seed), so propagation exists — between
    # the vault write and that converge the arrs 401 against qbit (nothing downloads; nothing else
    # breaks). The username is NOT a secret and lives in `qbit_webui_username` (role defaults).
    ("API Credential", "qbittorrent_api",         lambda: [f"credential={gen_pw()}"]),
    ("API Credential", "openclaw_gateway_token",  lambda: [f"password={gen_pw()}"]),
    ("API Credential", "openclaw-opencloud_api",  lambda: [f"username=openclaw", f"credential={gen_pw()}"]),
    # HD-268c dual harness: Forgejo service-account PR-only tokens (per-agent) — issued by
    # the Forgejo UI after boot, same class as `forgejo_api`. Granting scoped PR-only on the
    # homelab repo, NO merge rights. `dsh_api` / `pi-harness_openai_api` are NOT here — they
    # are LiteLLM glue-minted scoped virtual keys (HD-247, defined in litellm_scoped_keys).
    ("API Credential", "pi-harness_forgejo_api",    lambda: [f"credential={gen_pw()}"]),   # pi PR-only Forgejo PAT
    # DSH PR-only Forgejo PAT — OUT OF THE CATALOG 2026-10-07. DeepSeekHarness is PARKED (HD-386,
    # services-ai.md decision #26; `enabled: false` in group_vars/home_servers.yml) and the owner
    # DELETED this item from the vault on 2026-09-27 (HD-383) precisely so a re-enable fails closed at
    # the vault lookup. Leaving it here undid that act: `--create` re-minted it on any vault seed, with
    # a random string that is NOT a valid Forgejo token — a parked harness resurrected as a broken one,
    # and a permanently MISSING row in check-vault-items.sh. `dsh_forgejo_api` stays in
    # NOT_AUTO_ROTATABLE below so a hand-seeded value can never be regenerated by --rotate-all.
    # To re-onboard the harness: create the item by hand from a real Forgejo service-account token.
    # ("API Credential", "dsh_forgejo_api",           lambda: [f"credential={gen_pw()}"]),
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
    # HD-362 Tube Archivist: ES 'elastic' superuser password — the TA app requires
    # ELASTIC_PASSWORD (its env-check fails hard without it; upstream uses the ES
    # bootstrap password because the ES image runs with security enabled). Catalog-
    # generated (never coupled to a live ES cluster password — this is the FIRST
    # bootstrap value both sides share).
    ("API Credential", "tube-archivist-es", lambda: [f"username=elastic", f"password={gen_pw()}"]),
    # HD-370: spark engine API key — vLLM/SGLang `--api-key` bearer auth on the llm.kogler.si
    # OpenAI-API endpoint (spark's own Traefik edge fronts the loopback engine :8000). The
    # key gates the raw inference endpoint on every path (LAN :443 + VPS/Tailnet via WG/S2S);
    # consumed by spark-ai compose (`--api-key`) + the two LiteLLMs as `llm_api` for the
    # llm.kogler.si base_url. First vault item for the spark node (was vault-free by design).
    ("API Credential", "spark-llm_api", lambda: [f"credential={gen_token(32)}"]),
    # HD-384 (owner shape (a), 2026-10-09): the gateway's OWN credential for the engine leg, so
    # `spark-llm_api` stops being triple-used (engine `--api-key` + both LiteLLM `OPENAI_API_KEY`
    # values + the direct harness). The vLLM engine accepts BOTH (`--api-key` is nargs='+'). The
    # LiteLLM containers consume it as `OPENAI_API_KEY` once the spark half has converged (the
    # engine only starts accepting it at its next boot) — ordering is in services-ai.md §4.
    ("API Credential", "litellm-engine_api", lambda: [f"credential={gen_token(32)}"]),
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
    "authentik-ldap_bind",  # RETIRED 2026-10-07 (LDAP outpost gone); guard kept so --rotate-all
                            # cannot regenerate the item while it still sits in the vault
    "forgejo_api",          # real token issued by the Forgejo UI after first boot
    "openrouter_api",       # external provider API key
    "cohere_api",           # external provider API key
    "sonarr_api",           # real key issued by the Sonarr instance config.xml after first boot (HD-318)
    "radarr_api",           # real key issued by the Radarr instance config.xml after first boot (HD-318)
    "openclaw_gateway_token",   # consumed by the running gateway
    "openclaw-opencloud_api",   # OpenCloud app-password pair
    "pi-harness_forgejo_api",   # pi-dev PR-only Forgejo token (HD-268c)
    "dsh_forgejo_api",            # DSH PR-only Forgejo token (HD-268c)
    "spark-llm_api",        # HD-384 (2026-10-09): the engine's ACCEPTED-KEY list lives in vLLM's argv,
                            # so any rotation of either engine-side key needs a spark converge (engine
                            # restart) to take effect — rotating the vault value alone leaves the running
                            # engine accepting the OLD value and the re-rendered consumers holding a new one.
    "litellm-engine_api",   # HD-384: same coupling as above (the gateway's own engine credential is an
                            # accepted-key value on the engine as well as OPENAI_API_KEY in two containers).
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


# ONE seam for every `op` invocation, so --self-test can point the whole tool at a stubbed CLI and
# exercise each write branch without a vault. It is a module constant, deliberately NOT an env var: an
# env seam would let a stray variable in someone else's shell redirect a vault WRITE somewhere nobody
# reviewed. stdin is DEVNULL on every leg: with a non-TTY stdin `op item create` tries to parse piped
# JSON and dies with "invalid JSON in piped input" (found live 2026-08-22 under WSL), and an `op` that
# inherits the caller's stdin is the CONVENTIONS §6 ssh class — stdin is whatever the parent was
# reading, so the call can consume the loop or script that launched it.
OP_ARGV = ["op"]

# A hung `op` must not hang the caller. Every call this tool makes is ONE single-item, single-vault
# request (`item list` once per write command, one `item get` per re-read, one `edit`/`create` per
# item) — the repo's other `op` seam budgets 120 s for a whole-fleet list+fan-out
# (scripts/lib/vault_read.py `_op_run`) and this script's own local bcrypt probe waits 30 s, so 60 s
# per call is generous for the slowest one-item round trip and short enough that a wedged CLI cannot
# hold a rotation lane past its window. Not an env seam, for the OP_ARGV reason above: a stray
# `OP_TIMEOUT` in someone's shell would silently turn a slow vault into failing writes.
OP_TIMEOUT = 60

# The rc `op()` reports for its own killed call, `timeout(1)`'s conventional 124. It is a distinct
# value because `rotate` must be able to tell "the call never answered" from "`op` answered an error".
OP_TIMEOUT_RC = 124


def op(*args: str) -> subprocess.CompletedProcess:
    try:
        return subprocess.run([*OP_ARGV, *args], capture_output=True, text=True,
                              encoding="utf-8", errors="replace", stdin=subprocess.DEVNULL,
                              timeout=OP_TIMEOUT)
    except subprocess.TimeoutExpired:
        # A timeout is a FAILED read, and it keeps the existing verdict shapes: `item_field_values`
        # turns a non-zero rc into None and `rotate` calls that UNPROVEN, `existing_items` aborts the
        # command with zero writes, `create` reports the item FAILED. Nothing here retries.
        # The message names the VERB only: the argv of an `item edit` carries the generated values.
        return subprocess.CompletedProcess([*OP_ARGV, *args], OP_TIMEOUT_RC, "",
                                           f"op {' '.join(args[:2])} timed out after {OP_TIMEOUT}s "
                                           "and was killed without an answer")


def field_map(fields: list[str]) -> dict[str, str]:
    """{label: value} for the `label=value` argv form `op` takes. The FIRST '=' splits: a generated
    value may itself contain '='."""
    out: dict[str, str] = {}
    for f in fields:
        label, _sep, value = f.partition("=")
        out[label] = value
    return out


def redact(text: str, values: dict[str, str]) -> str:
    """Scrub the values THIS process generated out of anything it is about to print.

    `op` echoes its own argv in argument-resolution errors, and a write's argv CARRIES the values — so
    a failure print is a disclosure path (CONVENTIONS §6: a probe prints verdicts, never values).
    Short values are skipped so a fixed label like `username=admin` is not mangled into noise.
    """
    for value in values.values():
        if len(value) >= 8 and value in text:
            text = text.replace(value, "<redacted>")
    return text


def item_field_values(item_id: str, labels: list[str]) -> dict[str, str] | None:
    """Re-read ONE item by id and return {label: value} for `labels`; None when the read FAILED.

    This is the verify half of a write. A non-zero `op item edit` rc proves nothing on its own: op CLI
    2.39 answers a write that has ALREADY LANDED with a spurious post-edit HTTP error
    (docs/1password.md §Troubleshooting) — the same defect the fix in
    IaC/ansible/roles/docker_services/tasks/kopia-fingerprint-sync.yml removed on the host side. It
    goes through the `op` CLI rather than scripts/lib/vault_read.py so the re-read answers on the SAME
    surface the write used, which is also what lets --self-test stub it. `--reveal` is mandatory: a
    Concealed field's JSON carries no `value` without it. Values are compared in-process and never
    printed, and the read is ID-addressed — a title held by two items resolves arbitrarily.
    """
    r = op("item", "get", item_id, "--vault", VAULT, "--format", "json", "--reveal")
    if r.returncode != 0:
        return None
    try:
        item = json.loads(r.stdout)
    except json.JSONDecodeError:
        return None
    want = {label.lower(): label for label in labels}
    got: dict[str, str] = {}
    for field in item.get("fields") or []:
        for key in (field.get("id"), field.get("label")):
            label = want.get(str(key or "").lower())
            if label is not None and label not in got and field.get("value") is not None:
                got[label] = str(field["value"])
    return {label: got[label] for label in labels if label in got}


def require_write_token() -> int:
    if "OP_SERVICE_ACCOUNT_TOKEN" not in os.environ:
        print("error: OP_SERVICE_ACCOUNT_TOKEN (write-scoped) not set", file=sys.stderr)
        return 1
    return 0


def existing_items() -> dict[str, list[str]] | None:
    """Return {title: [item id, ...]} for the vault, or None if the lookup FAILED.

    A failed lookup is FATAL for any write command (HD-205): proceeding with an
    empty map would make `--create` try to create EVERY item and `--rotate-all`
    skip everything — both silently masking an auth/scope/vault problem. So a
    failure returns None and every caller ABORTS loudly instead of proceeding.
    That listing is also what makes `op item create` a proven-absent act and never
    a duplicate mint. FAILED covers the non-zero rc AND a zero-rc body that is not a JSON
    list, because an unparseable listing and an empty vault are indistinguishable downstream:
    both take the abort path, never a traceback and never a guess.

    A title maps to a LIST because two items CAN carry the same title, and then the
    CLI resolves that title arbitrarily: a title-addressed write can land on the
    other item and its re-read would "prove" the wrong object. `rotate` refuses that
    state and names the ids instead of writing through it.
    """
    r = op("item", "list", "--vault", VAULT, "--format", "json")
    if r.returncode != 0:
        print(f"error: cannot list items in vault '{VAULT}': {r.stderr.strip()}",
              file=sys.stderr)
        print("  check OP_SERVICE_ACCOUNT_TOKEN scope and vault name", file=sys.stderr)
        return None
    # rc 0 with a body that is not JSON (empty, truncated, an HTML error page) is a FAILED lookup, not
    # an empty vault. `json.loads` alone raises JSONDecodeError out of every write command as a
    # traceback, and the tempting guard — `or "[]"` — answers an EMPTY map, which is precisely the state
    # this function exists to refuse: `--create` would then mint the entire catalog. So an unreadable
    # listing takes the identical exit: name it, return None, attempt ZERO writes.
    try:
        listed = json.loads(r.stdout)
    except json.JSONDecodeError as exc:
        print(f"error: cannot read the item listing for vault '{VAULT}' — `op item list` answered rc 0 "
              f"with a body that is not JSON ({exc})", file=sys.stderr)
        print("  treating it as a failed lookup: nothing was created, edited or rotated", file=sys.stderr)
        return None
    if not isinstance(listed, list):
        # `{}` and `null` are valid JSON but not a listing: iterating them raises or yields no titles,
        # and a silently-empty map is the one outcome this function exists to refuse.
        print(f"error: cannot read the item listing for vault '{VAULT}' — `op item list` answered JSON "
              f"that is not a list ({type(listed).__name__})", file=sys.stderr)
        print("  treating it as a failed lookup: nothing was created, edited or rotated", file=sys.stderr)
        return None
    out: dict[str, list[str]] = {}
    for it in listed:
        # A row with no title or id is not a catalog entry. Refuse it rather than let `it["title"]`
        # raise mid-loop, or let `.get()` invent a title-less row that reads to `--create` as "absent".
        if not isinstance(it, dict) or not it.get("title") or not it.get("id"):
            print(f"error: the item listing for vault '{VAULT}' has a row with no title or id: "
                  f"{it!r:.120}", file=sys.stderr)
            print("  treating it as a failed lookup: nothing was created, edited or rotated", file=sys.stderr)
            return None
        out.setdefault(str(it["title"]), []).append(str(it["id"]))
    return out


def bcrypt_hash(password: str) -> str:
    """Return a bcrypt hash of `password` via a separate python with bcrypt.

    The password is passed over STDIN (not argv) so it never appears in the
    process list or shell history (HD-205)."""
    py = BCRYPT_PY
    r = subprocess.run(
        py + ["-c",
              "import bcrypt,sys; print(bcrypt.hashpw(sys.stdin.read().encode(), bcrypt.gensalt(rounds=12)).decode())"],
        input=password, capture_output=True, text=True, encoding="utf-8", errors="replace")
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
    # Reached ONLY for a title the listing proved absent (cmd_create), so a non-zero rc here is a real
    # failure with nothing to re-read: the next `--create` re-derives absence from the listing, so
    # there is no create-on-failure branch that could mint the duplicate. A timeout lands in the same
    # branch — the item MAY exist by then, and the next run's listing is what resolves it, which is
    # why nothing here ever retries the create.
    r = op("item", "create", "--category", category, "--title", title, "--vault", VAULT, *fields)
    if r.returncode != 0:
        print(f"FAILED {title}: {redact(r.stderr.strip(), field_map(fields))}", file=sys.stderr)
        return False
    print(f"created {title}")
    return True


def timed_out(r: subprocess.CompletedProcess) -> bool:
    """True when the answer is `op()`'s killed-call sentinel rather than something `op` said."""
    return r.returncode == OP_TIMEOUT_RC


def rotate(title: str, category: str, fields_builder, item_ids: list[str] | None = None) -> bool:
    """Regenerate + overwrite a single existing item's secret fields in place.

    The verdict comes from the VALUE, never from the `op` exit code, and from a
    re-read of the SAME id on BOTH legs: op CLI 2.39 answers a write that landed
    with a spurious post-edit error (see item_field_values and docs/1password.md
    §Troubleshooting) AND can answer 0 while applying only some of the assignments
    (the append-a-field shape), so an rc of 0 is not evidence that a field changed.
    A half-written `username`+`password` pair is a FAILURE, not a rotation — the
    catalog's pairs are consumed as a unit.

    One exception to reading the value: a WRITE call that never answered. A killed `op item edit` may
    still be in flight, so BOTH re-read outcomes are UNPROVEN — a value that already matches is not
    proof the call completed, and a value that does not is not proof it failed.

    There is no create fallback on this path: the item is HERE, so a create would
    only mint the duplicate whose title-based reads then resolve arbitrarily — the
    defect the sibling fix in kopia-fingerprint-sync.yml removed.
    """
    if title in NOT_AUTO_ROTATABLE:
        print(f"SKIP {title}: externally-coupled item (see NOT_AUTO_ROTATABLE); rotate manually.", file=sys.stderr)
        return False
    ids = list(item_ids or [])
    if len(ids) != 1:
        print(f"FAILED rotate {title}: {len(ids)} items are titled {title} — resolve the duplicates "
              f"first (ids: {', '.join(ids)}); an ambiguous title cannot be written and verified", file=sys.stderr)
        return False
    item_id = ids[0]
    fields = fields_builder()
    if not fields:
        # An empty field set makes the landed test degenerate to `{} == {}`, which reports a rotation
        # that wrote nothing. Reachable today only via `kopia-server_fingerprint`, which the guard
        # above keeps shut — this is the leg that stays shut if that name ever leaves the list.
        print(f"FAILED rotate {title}: the catalog row generates no fields, so there is nothing to "
              f"write and nothing to verify — not attempted", file=sys.stderr)
        return False
    want = field_map(fields)
    r = op("item", "edit", item_id, "--vault", VAULT, *fields)
    said = "" if r.returncode == 0 else f" op said: {redact(r.stderr.strip(), want)}"
    now = item_field_values(item_id, list(want))
    if timed_out(r):
        # A killed WRITE call is UNPROVEN whatever the re-read says: the request may still be in
        # flight, so a re-read that already shows the new value is not proof the call completed and a
        # re-read that shows the old one is not proof it failed. Hence no success print on this leg,
        # no retry and no create — the operator confirms the item, then re-runs.
        seen = ("the re-read already shows the new value" if now == want
                else "the re-read still shows the previous value" if now is not None
                else "the re-read failed too")
        print(f"FAILED rotate {title}: {redact(r.stderr.strip(), want)}, so the write is UNPROVEN — "
              f"{seen}; confirm the item's current value before retrying, nothing was retried",
              file=sys.stderr)
        return False
    if now is None:
        print(f"FAILED rotate {title}: the re-read failed, so the write is UNPROVEN — confirm the "
              f"item's current value before retrying{said}", file=sys.stderr)
        return False
    if now == want:
        if r.returncode == 0:
            print(f"rotated {title}")
        else:
            print(f"rotated {title} (op reported an error; the re-read proves the write landed)")
        return True
    stuck = sorted(label for label, value in want.items() if now.get(label) != value)
    print(f"FAILED rotate {title}: the re-read shows field(s) "
          f"{', '.join(stuck)} still hold the previous value — not retried, not re-created{said}",
          file=sys.stderr)
    return False


# ---------------------------------------------------------------------------
# Self-test: every write branch against a STUBBED `op` — no vault, no token, no network.
#
# Why a stub rather than the live vault: the branch under test exists because a non-zero `op` rc can
# arrive on a write that LANDED, and that is not an exit code anyone can summon on purpose. So the CLI
# itself is replaced (OP_ARGV) by a script that answers list/get/edit/create from a JSON state file and
# can be told to fail in each of the ways the real one fails. Every call is logged, because "no create
# was attempted" is a claim only the call log can prove — a `--rotate` that reports FAILED and then
# mints a second item is exactly the defect this arm exists to keep dead.
# ---------------------------------------------------------------------------
_STUB_ENV = ("HL_STUB_VAULT", "HL_STUB_LOG", "HL_STUB_EDIT_RC", "HL_STUB_EDIT_LANDS",
             "HL_STUB_SKIP_FIELDS", "HL_STUB_GET_RC", "HL_STUB_LIST_RC", "HL_STUB_CREATE_RC",
             "HL_STUB_ECHO_ARGV", "HL_STUB_HANG", "HL_STUB_LIST_BODY", "OP_SERVICE_ACCOUNT_TOKEN")

_STUB_OP = r'''#!/usr/bin/env python3
"""Stub 1Password CLI for provision-secrets.py --self-test.

State is one JSON file: {"items":[{"id","title","fields":{label:value}}]}. Knobs, all env:
  HL_STUB_VAULT    the state file
  HL_STUB_LOG      call log, one line per invocation, argv joined with \x01
  HL_STUB_LIST_RC / HL_STUB_GET_RC / HL_STUB_EDIT_RC / HL_STUB_CREATE_RC   forced exit codes
  HL_STUB_EDIT_LANDS   0 = a failing edit leaves the state untouched (default 1 = it was applied)
  HL_STUB_SKIP_FIELDS  comma-separated labels an edit does NOT apply (a partial write)
  HL_STUB_ECHO_ARGV    1 = echo argv on stderr, the error shape that can carry a value
  HL_STUB_HANG         verbs that never answer ("edit", "get", "edit,get"): the call runs until the
                       provisioner's own timeout kills it — the hung-CLI class no rc can summon. On
                       the edit/create legs the state change is applied FIRST, i.e. the request went
                       out and only the answer is missing, which is what a hung CLI actually means.
  HL_STUB_LIST_BODY    when SET, `item list` prints exactly this instead of the JSON rows and exits 0 —
                       the zero-rc body that is not a listing (empty, truncated, an HTML error page)
"""
import json
import os
import sys
import time

SEP = "\x01"
STATE = os.environ["HL_STUB_VAULT"]
LOG = os.environ.get("HL_STUB_LOG")
ARGV = sys.argv[1:]


def code(name):
    return int(os.environ.get(name, "0"))


def load():
    with open(STATE, encoding="utf-8") as fh:
        return json.load(fh)


def save(doc):
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump(doc, fh)


def find(doc, ref):
    # ID first, then title — the CLI's own order, and the reason the provisioner addresses by ID.
    for it in doc["items"]:
        if it["id"] == ref:
            return it
    for it in doc["items"]:
        if it["title"] == ref:
            return it
    return None


def hang(verb):
    if verb in [s for s in os.environ.get("HL_STUB_HANG", "").split(",") if s]:
        time.sleep(600)  # killed by OP_TIMEOUT in the arm; the length only has to be "forever"


def assigns(args):
    for a in args:
        if a.startswith("--") or "=" not in a:
            continue
        yield a.partition("=")[0], a.partition("=")[2]


if LOG:
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(SEP.join(ARGV) + "\n")

if ARGV[:2] == ["item", "list"]:
    if code("HL_STUB_LIST_RC"):
        sys.exit(code("HL_STUB_LIST_RC"))
    hang("list")
    if "HL_STUB_LIST_BODY" in os.environ:
        print(os.environ["HL_STUB_LIST_BODY"], end="")
    else:
        print(json.dumps([{"id": i["id"], "title": i["title"]} for i in load()["items"]]))
    sys.exit(0)

if ARGV[:2] == ["item", "get"]:
    if code("HL_STUB_GET_RC"):
        sys.exit(code("HL_STUB_GET_RC"))
    hang("get")
    it = find(load(), ARGV[2])
    if it is None:
        sys.exit(1)
    fields = [{"id": k, "label": k, "type": "Concealed", "value": v} for k, v in it["fields"].items()]
    print(json.dumps({"id": it["id"], "title": it["title"], "fields": fields}))
    sys.exit(0)

if ARGV[:2] == ["item", "edit"]:
    if os.environ.get("HL_STUB_ECHO_ARGV") == "1":
        sys.stderr.write("error: while resolving arguments: " + " ".join(ARGV) + "\n")
    skip = [s for s in os.environ.get("HL_STUB_SKIP_FIELDS", "").split(",") if s]
    doc = load()
    it = find(doc, ARGV[2])
    if it is not None and os.environ.get("HL_STUB_EDIT_LANDS", "1") == "1":
        for label, value in assigns(ARGV[3:]):
            if label not in skip:
                it["fields"][label] = value
        save(doc)
    hang("edit")  # the write went out and the CLI never came back
    sys.exit(code("HL_STUB_EDIT_RC"))

if ARGV[:2] == ["item", "create"]:
    if code("HL_STUB_CREATE_RC"):
        sys.exit(code("HL_STUB_CREATE_RC"))
    doc = load()
    title = ARGV[ARGV.index("--title") + 1]
    doc["items"].append({"id": "stub-" + str(len(doc["items"])), "title": title,
                         "fields": dict(assigns(ARGV[ARGV.index("--vault") + 2:]))})
    save(doc)
    hang("create")  # same shape as the edit leg: the request went out, the answer never came
    print("created " + title)
    sys.exit(0)

sys.stderr.write("stub op: unsupported invocation\n")
sys.exit(64)
'''


def cmd_self_test(_args) -> int:
    """Run every write branch against the stub. Prints one line per arm, then the count."""
    tally = {"n": 0, "bad": []}

    def check(label: str, ok: bool, detail: str = "") -> None:
        tally["n"] += 1
        if not ok:
            tally["bad"].append(label if not detail else f"{label} — {detail}")
        print(f"  arm {label}: {'ok' if ok else 'FAIL'}" + (f" — {detail}" if (detail and not ok) else ""))

    def opts(**kw):
        return argparse.Namespace(**kw)

    old_pw, new_pw = "selftest-previous-value", "selftest-generated-value"
    new_db_pw, user_new = "selftest-generated-db-password", "selftest-svc"
    t_single, t_pair = "selftest-rotatable_api", "selftest-rotatable_db"
    t_coupled, t_absent = "selftest-coupled_api", "selftest-absent_api"
    id_a, id_p, id_c = "stub-id-a", "stub-id-p", "stub-id-c"
    test_catalog = [
        ("API Credential", t_single, lambda: [f"credential={new_pw}"]),
        ("Database", t_pair, lambda: [f"username={user_new}", f"password={new_db_pw}"]),
        ("Password", t_coupled, lambda: [f"password={new_pw}"]),
    ]

    with tempfile.TemporaryDirectory(prefix="provision-selftest-") as tmp:
        stub = Path(tmp) / "op_stub.py"
        with open(stub, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(_STUB_OP)
        state, log = Path(tmp) / "vault.json", Path(tmp) / "calls.log"

        def entry(item_id, title, fields):
            return {"id": item_id, "title": title, "fields": dict(fields)}

        def items_in_state():
            return json.loads(state.read_text(encoding="utf-8"))["items"]

        def value_of(item_id, label):
            return next((it["fields"].get(label) for it in items_in_state() if it["id"] == item_id), None)

        def verbs(calls):
            return ["/".join(c[:2]) for c in calls]

        def edit_targets(calls):
            return [c[2] for c in calls if c[:2] == ["item", "edit"]]

        def created_titles(calls):
            return [c[c.index("--title") + 1] for c in calls if c[:2] == ["item", "create"]]

        def run(fn, *, items, env=None, catalog=None, coupled=None, op_timeout=None):
            """Seed a stub vault, point the tool at the stub, run fn(), return the verdict + the log."""
            state.write_text(json.dumps({"items": [dict(i) for i in items]}), encoding="utf-8")
            log.write_text("", encoding="utf-8")
            saved = {k: os.environ.get(k) for k in _STUB_ENV}
            saved_cat, saved_auto, saved_op = CATALOG, NOT_AUTO_ROTATABLE, OP_ARGV
            saved_to = OP_TIMEOUT
            for key in _STUB_ENV:
                os.environ.pop(key, None)
            os.environ["HL_STUB_VAULT"] = str(state)
            os.environ["HL_STUB_LOG"] = str(log)
            os.environ["OP_SERVICE_ACCOUNT_TOKEN"] = "selftest-token-is-not-a-vault-credential"
            os.environ.update(env or {})
            globals()["OP_ARGV"] = [sys.executable, str(stub)]
            # The hung-CLI arms cannot wait out the real 60 s bound, so the clock under test is the
            # only thing scaled — same in-place swap the OP_ARGV seam already does, never an env var.
            globals()["OP_TIMEOUT"] = OP_TIMEOUT if op_timeout is None else op_timeout
            if catalog is not None:
                globals()["CATALOG"] = catalog
            if coupled is not None:
                globals()["NOT_AUTO_ROTATABLE"] = set(NOT_AUTO_ROTATABLE) | set(coupled)
            out, err = io.StringIO(), io.StringIO()
            try:
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    got = fn()
            finally:
                globals()["CATALOG"], globals()["NOT_AUTO_ROTATABLE"] = saved_cat, saved_auto
                globals()["OP_ARGV"], globals()["OP_TIMEOUT"] = saved_op, saved_to
                for key, val in saved.items():
                    if val is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = val
            calls = [ln.split("\x01") for ln in log.read_text(encoding="utf-8").splitlines() if ln]
            return got, out.getvalue(), err.getvalue(), calls

        def rotate_single(ids=None):
            return lambda: rotate(t_single, "API Credential", lambda: [f"credential={new_pw}"],
                                  [id_a] if ids is None else ids)

        seed_single = [entry(id_a, t_single, {"credential": old_pw})]

        # 1 — the ordinary write.
        got, out, err, calls = run(rotate_single(), items=seed_single)
        check("edit rc 0 -> rotated", got is True and value_of(id_a, "credential") == new_pw,
              f"got {got}, vault holds {value_of(id_a, 'credential')!r}")
        check("edit rc 0 -> one ID-addressed edit, no create", edit_targets(calls) == [id_a]
              and created_titles(calls) == [], str(calls))

        # 2 — THE DEFECT: op-2.39's spurious error on a write that landed.
        got, out, err, calls = run(rotate_single(), items=seed_single,
                                  env={"HL_STUB_EDIT_RC": "1", "HL_STUB_EDIT_LANDS": "1"})
        check("edit rc != 0 + re-read proves the value -> rotated", got is True
              and "the re-read proves the write landed" in out, f"got {got}: {err.strip()}")
        check("edit rc != 0 + landed -> zero creates (no duplicate mint)", created_titles(calls) == [],
              str(verbs(calls)))

        # 3 — a write that genuinely failed.
        got, out, err, calls = run(rotate_single(), items=seed_single,
                                  env={"HL_STUB_EDIT_RC": "1", "HL_STUB_EDIT_LANDS": "0"})
        check("edit rc != 0 + not landed -> FAILED", got is False and "FAILED rotate" in err,
              f"got {got}")
        check("edit rc != 0 + not landed -> old value intact, zero creates",
              value_of(id_a, "credential") == old_pw and created_titles(calls) == [], str(verbs(calls)))

        # 4 — a two-field item where only ONE field landed: the re-read must judge the whole set.
        got, out, err, calls = run(
            lambda: rotate(t_pair, "Database",
                           lambda: [f"username={user_new}", f"password={new_db_pw}"], [id_p]),
            items=[entry(id_p, t_pair, {"username": "selftest-old-svc", "password": old_pw})],
            env={"HL_STUB_EDIT_RC": "1", "HL_STUB_SKIP_FIELDS": "password"})
        check("partial write -> FAILED and names the stuck field", got is False
              and "password still hold" in err, f"got {got}: {err.strip()}")
        check("partial write is really partial (the arm can fail)",
              value_of(id_p, "username") == user_new and value_of(id_p, "password") == old_pw)

        # 5 — the re-read itself failed: an unproven write is never a success.
        got, out, err, calls = run(rotate_single(), items=seed_single,
                                  env={"HL_STUB_EDIT_RC": "1", "HL_STUB_EDIT_LANDS": "1",
                                       "HL_STUB_GET_RC": "1"})
        check("re-read fails -> UNPROVEN, reported as FAILED", got is False and "UNPROVEN" in err,
              f"got {got}")

        # 6 — the duplicate-title class: ambiguous, so nothing gets written anywhere.
        got, out, err, calls = run(rotate_single([id_a, "stub-id-b"]),
                                  items=[seed_single[0], entry("stub-id-b", t_single, {"credential": old_pw})])
        check("duplicate title -> refuses to write", got is False and edit_targets(calls) == []
              and created_titles(calls) == [], str(verbs(calls)))
        check("duplicate title -> names both ids", "stub-id-b" in err and id_a in err, err.strip())

        # 7 — the missing-item path, through the CLI flag.
        got, out, err, calls = run(lambda: cmd_rotate(opts(rotate=t_absent, rotate_all=False, yes=True)),
                                  items=[], catalog=test_catalog)
        check("--rotate on an absent title -> rc 1, zero writes", got == 1
              and edit_targets(calls) == [] and created_titles(calls) == [], f"got {got}: {verbs(calls)}")

        # 8 — the externally-coupled guard still fires before any argv is built.
        got, out, err, calls = run(lambda: rotate(t_coupled, "Password", lambda: [f"password={new_pw}"], [id_c]),
                                   items=[entry(id_c, t_coupled, {"password": old_pw})], coupled=[t_coupled])
        check("NOT_AUTO_ROTATABLE -> skipped, zero writes", got is False
              and edit_targets(calls) == [] and "externally-coupled" in err, f"got {got}")

        # 9 — create, both halves of the proven-absent rule.
        got, out, err, calls = run(lambda: cmd_create(opts(yes=True)), items=[], catalog=test_catalog)
        check("--create seeds each proven-absent title once", got == 0
              and sorted(i["title"] for i in items_in_state()) == sorted([t_single, t_pair, t_coupled])
              and len(created_titles(calls)) == 3, f"got {got}: {created_titles(calls)}")
        got, out, err, calls = run(lambda: cmd_create(opts(yes=True)),
                                   items=[entry(id_a, t_single, {"credential": old_pw}),
                                          entry(id_p, t_pair, {"username": "selftest-old-svc", "password": old_pw}),
                                          entry(id_c, t_coupled, {"password": old_pw})],
                                   catalog=test_catalog)
        check("--create never re-mints a title that exists", got == 0 and created_titles(calls) == []
              and edit_targets(calls) == [], str(verbs(calls)))

        # 10 — a vault listing that fails must attempt NOTHING (HD-205 fail-closed).
        got, out, err, calls = run(lambda: cmd_create(opts(yes=True)), items=seed_single,
                                   env={"HL_STUB_LIST_RC": "1"}, catalog=test_catalog)
        check("listing fails -> --create aborts, zero creates", got == 1 and created_titles(calls) == [],
              f"got {got}: {verbs(calls)}")
        got, out, err, calls = run(lambda: cmd_rotate(opts(rotate=t_single, rotate_all=False, yes=True)),
                                   items=seed_single, env={"HL_STUB_LIST_RC": "1"}, catalog=test_catalog)
        check("listing fails -> --rotate aborts, zero writes", got == 1 and edit_targets(calls) == [],
              f"got {got}: {verbs(calls)}")

        # 11 — canary for the print path: `op` echoes argv, the tool must not echo the value with it.
        got, out, err, calls = run(rotate_single(), items=seed_single,
                                  env={"HL_STUB_EDIT_RC": "1", "HL_STUB_EDIT_LANDS": "0",
                                       "HL_STUB_ECHO_ARGV": "1"})
        check("failure text was printed (the canary ran)", "while resolving arguments" in err)
        check("failure text discloses no generated value", got is False and new_pw not in out + err)

        # 12 — --rotate-all: every rotatable item by id, the coupled one untouched.
        got, out, err, calls = run(lambda: cmd_rotate(opts(rotate=None, rotate_all=True, yes=True)),
                                   items=[seed_single[0],
                                          entry(id_p, t_pair, {"username": "selftest-old-svc", "password": old_pw}),
                                          entry(id_c, t_coupled, {"password": old_pw})],
                                   catalog=test_catalog, coupled=[t_coupled])
        check("--rotate-all edits each rotatable item by id, creates nothing",
              got == 0 and sorted(edit_targets(calls)) == sorted([id_a, id_p])
              and created_titles(calls) == [], f"got {got}: {edit_targets(calls)}")
        check("--rotate-all leaves the coupled item's value alone", value_of(id_c, "password") == old_pw)

        # 13 — rc 0 is not evidence either: the re-read judges the success leg too, so a zero-rc edit
        # that applied nothing (or only part of a pair) can never print `rotated`.
        got, out, err, calls = run(rotate_single(), items=seed_single,
                                   env={"HL_STUB_EDIT_RC": "0", "HL_STUB_EDIT_LANDS": "0"})
        check("edit rc 0 + value not landed -> FAILED, never rotated", got is False
              and "FAILED rotate" in err and "rotated" not in out, f"got {got}: {out.strip()}")
        check("edit rc 0 + not landed -> old value intact, zero creates",
              value_of(id_a, "credential") == old_pw and created_titles(calls) == [], str(verbs(calls)))
        got, out, err, calls = run(
            lambda: rotate(t_pair, "Database",
                           lambda: [f"username={user_new}", f"password={new_db_pw}"], [id_p]),
            items=[entry(id_p, t_pair, {"username": "selftest-old-svc", "password": old_pw})],
            env={"HL_STUB_EDIT_RC": "0", "HL_STUB_SKIP_FIELDS": "password"})
        check("edit rc 0 + half a pair -> FAILED and names the stuck field", got is False
              and "password still hold" in err and "rotated" not in out, f"got {got}: {err.strip()}")

        # 14 — a builder that generates nothing must not satisfy the landed test with `{} == {}`.
        got, out, err, calls = run(lambda: rotate(t_single, "API Credential", lambda: [], [id_a]),
                                   items=seed_single)
        check("no generated fields -> FAILED before any write", got is False
              and edit_targets(calls) == [] and created_titles(calls) == [], f"got {got}: {verbs(calls)}")
        check("no generated fields -> nothing printed as rotated, value untouched",
              "rotated" not in out and value_of(id_a, "credential") == old_pw, out.strip())

        # 15 — create's failure branch: reported, counted, and never retried, so it cannot mint a
        # duplicate. This is the leg HL_STUB_CREATE_RC exists for.
        got, out, err, calls = run(lambda: cmd_create(opts(yes=True)), items=[],
                                   env={"HL_STUB_CREATE_RC": "1"}, catalog=test_catalog)
        check("--create rc != 0 -> rc 1", got == 1, f"got {got}")
        check("--create rc != 0 -> one attempt per title, zero items created (no retry, no duplicate)",
              created_titles(calls) == [t_single, t_pair, t_coupled] and items_in_state() == [],
              f"{created_titles(calls)} -> {items_in_state()}")

        # 16 — --rotate-all with a mixed outcome: one item landed, one did not. The run must NOT
        # report a completed window (arm 12 above is the all-success -> rc 0 case).
        got, out, err, calls = run(lambda: cmd_rotate(opts(rotate=None, rotate_all=True, yes=True)),
                                   items=[seed_single[0],
                                          entry(id_p, t_pair, {"username": "selftest-old-svc", "password": old_pw}),
                                          entry(id_c, t_coupled, {"password": old_pw})],
                                   catalog=test_catalog, coupled=[t_coupled],
                                   env={"HL_STUB_EDIT_RC": "0", "HL_STUB_SKIP_FIELDS": "password"})
        check("--rotate-all with a not-landed item -> rc 1", got == 1,
              f"got {got}: {out.strip()} {err.strip()}")
        check("--rotate-all names the item that did not land; the landed one did rotate",
              t_pair in err and value_of(id_p, "password") == old_pw
              and value_of(id_a, "credential") == new_pw, f"got {got}: {err.strip()}")

        # 17 — the hung `op`. An unbounded call blocks a rotation lane forever, so every call carries
        # a deadline; the arm shrinks the deadline, never the behaviour under test. A timeout is the
        # one verdict that must NEVER become a `rotated` line even when the re-read already shows the
        # new value: a killed call may still be in flight, so the answer is UNPROVEN and a human
        # confirms the item. The state is written by the stub to model exactly that ambiguity.
        got, out, err, calls = run(rotate_single(), items=seed_single,
                                   env={"HL_STUB_HANG": "edit", "HL_STUB_EDIT_LANDS": "1"},
                                   op_timeout=0.3)
        check("edit never answers + the value landed -> UNPROVEN, never rotated", got is False
              and "UNPROVEN" in err and "rotated" not in out, f"got {got}: {out.strip()}")
        check("edit never answers -> the edit was attempted ONCE, nothing created",
              edit_targets(calls) == [id_a] and created_titles(calls) == [], str(calls))
        got, out, err, calls = run(rotate_single(), items=seed_single,
                                   env={"HL_STUB_HANG": "edit", "HL_STUB_EDIT_LANDS": "0"},
                                   op_timeout=0.3)
        check("edit never answers + not landed -> FAILED, old value intact, no traceback", got is False
              and "UNPROVEN" in err and "Traceback" not in out + err
              and value_of(id_a, "credential") == old_pw, f"got {got}: {err.strip()}")
        got, out, err, calls = run(rotate_single(), items=seed_single,
                                   env={"HL_STUB_HANG": "edit,get", "HL_STUB_EDIT_LANDS": "1"},
                                   op_timeout=0.3)
        check("edit + re-read both never answer -> UNPROVEN with no traceback", got is False
              and "UNPROVEN" in err and "the re-read failed too" in err
              and "Traceback" not in out + err, f"got {got}: {err.strip()}")
        got, out, err, calls = run(lambda: cmd_rotate(opts(rotate=t_single, rotate_all=False, yes=True)),
                                   items=seed_single, env={"HL_STUB_HANG": "list"},
                                   catalog=test_catalog, op_timeout=0.3)
        check("listing never answers -> --rotate aborts, zero writes", got == 1
              and edit_targets(calls) == [] and created_titles(calls) == [], f"got {got}: {verbs(calls)}")
        got, out, err, calls = run(lambda: cmd_create(opts(yes=True)), items=seed_single,
                                   env={"HL_STUB_HANG": "list"}, catalog=test_catalog, op_timeout=0.3)
        check("listing never answers -> --create aborts, zero creates", got == 1
              and created_titles(calls) == [], f"got {got}: {verbs(calls)}")
        got, out, err, calls = run(lambda: cmd_create(opts(yes=True)), items=[],
                                   env={"HL_STUB_HANG": "create"}, catalog=test_catalog, op_timeout=0.3)
        check("create never answers -> rc 1, ONE attempt per title, never retried", got == 1
              and created_titles(calls) == [t_single, t_pair, t_coupled]
              and "timed out" in err, f"got {got}: {created_titles(calls)}")

        # 18 — a listing that answers rc 0 with something that is not a JSON list. Downstream it is
        # indistinguishable from an EMPTY vault, and an empty map is the one state the fail-closed rule
        # (arm 10) exists to refuse: `--create` would mint the whole catalog, which is the duplicate-
        # mint invariant wearing a different hat. So the unparseable body must abort, not raise.
        for label, body in (("empty", ""), ("not JSON", "op: command not found"), ("JSON but a dict", "{}")):
            got, out, err, calls = run(lambda: cmd_create(opts(yes=True)), items=seed_single,
                                       env={"HL_STUB_LIST_BODY": body}, catalog=test_catalog)
            check(f"--create on a rc-0 listing that is {label} -> rc 1, zero creates, no traceback",
                  got == 1 and created_titles(calls) == [] and "Traceback" not in out + err
                  and "failed lookup" in err, f"got {got}: {verbs(calls)}")
        got, out, err, calls = run(lambda: cmd_rotate(opts(rotate=t_single, rotate_all=False, yes=True)),
                                   items=seed_single, env={"HL_STUB_LIST_BODY": ""},
                                   catalog=test_catalog)
        check("--rotate on an unparseable listing -> rc 1, zero writes", got == 1
              and edit_targets(calls) == [] and created_titles(calls) == [], f"got {got}: {verbs(calls)}")

        # 19 — THE DUPLICATE TITLE THROUGH THE ENTRY PATH. Arm 6 hands rotate() its ids directly, so a
        # title->ids collapse anywhere in cmd_rotate — a `[0]`, a dict built last-wins, an
        # `existing[name][:1]` — would still pass it. Here the ids come from the stub's OWN listing,
        # which is the only route a real `--rotate` takes: two items, one title, and the refusal has to
        # name both before anything is written.
        got, out, err, calls = run(lambda: cmd_rotate(opts(rotate=t_single, rotate_all=False, yes=True)),
                                   items=[seed_single[0],
                                          entry("stub-id-b", t_single, {"credential": old_pw})],
                                   catalog=test_catalog)
        check("--rotate on a duplicate title -> rc 1 and zero writes", got == 1
              and edit_targets(calls) == [] and created_titles(calls) == [], f"got {got}: {verbs(calls)}")
        check("--rotate on a duplicate title -> names both ids", id_a in err and "stub-id-b" in err,
              err.strip())

    print(f"\nprovision-secrets.py self-test: {tally['n']} checks, "
          f"{len(tally['bad'])} failure(s) — zero vault contact, zero writes outside the fixture")
    for bad in tally["bad"]:
        print(f"  FAIL {bad}", file=sys.stderr)
    return 1 if tally["bad"] else 0


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
        done, failed = 0, []
        for cat, name, fb in CATALOG:
            if name not in existing:
                print(f"skip (absent): {name}")
                continue
            if name in NOT_AUTO_ROTATABLE:
                # A skip BY DESIGN, not a failure — rotate() refuses it too, and a --rotate-all that
                # exited 1 on every run (the guard list is long) would train the caller to ignore the
                # verdict this command exists to be trusted for.
                print(f"skip (coupled): {name}")
                continue
            if rotate(name, cat, fb, existing[name]):
                done += 1
            else:
                failed.append(name)
        print(f"\nRotated {done} item(s).")
        if failed:
            print(f"Not rotated ({len(failed)}): {sorted(failed)} — see the FAILED lines above",
                  file=sys.stderr)
        # A window where an item did not land is NOT a completed rotation: `--rotate-all --yes ||
        # ABORT` and the ledger verdict both read this rc.
        return 1 if failed else 0
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
    return 0 if rotate(name, _cat, fb, existing[name]) else 1


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
    p.add_argument("--self-test", action="store_true",
                   help="run every write branch against a stubbed `op` (no vault, no token)")
    a = p.parse_args()

    if a.self_test:
        return cmd_self_test(a)
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
