#!/usr/bin/env python3
"""
Validate docker_services compose templates from group_vars/*.yml.

Checks every compose template under templates/docker_services/ referenced by a
group_vars docker_services list (count is derived — see the count-lint below):
  1. Template file exists
  2. Jinja2 renders without error (mocked 1Password lookups)
  3. Rendered YAML parses correctly
  4. Non-stub templates pass structural checks (networks, Traefik labels, secrets)
  5. Source-level bug scans (lookup default= param, host net vs network_mode: host)

Exit codes:
  0 = all templates valid
  1 = any failure

Usage:
  python scripts/validate-docker-services.py
  python scripts/validate-docker-services.py --only traefik
"""
import sys
import re
from pathlib import Path
from jinja2 import Environment, StrictUndefined
import yaml

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES_DIR = ROOT / "IaC" / "ansible" / "templates" / "docker_services"
GROUP_VARS_DIR = ROOT / "IaC" / "ansible" / "group_vars"

# ── Network assignments ──────────────────────────────────────────────
# Per-service network allowlists were REMOVED (HD-189, decided HD-204): the
# hand-maintained NETWORK_MAP was dead code (the defined_nets escape made it
# unfireable) and had already drifted (stale immich/sunshine entries vs HD-59's
# llm-backend move). Enforcement relies on the external-networks rule below
# (every declared network must be external: true) + the assignment tables in
# docs/deployment-compose.md.

# Services that don't need Traefik labels (are their own reverse proxy)
NO_TRAEFIK_LABELS = {"traefik-ha", "qbittorrent"}  # qbittorrent labels are on gluetun sidecar

# HD-134 / KOPS-030 convention: pinned tags (never bare `latest`). A compose image that
# RESOLVES to bare `latest` (either a literal `:latest` or an undefined *_version var falling
# back to `default('latest')`) is an unpinned-tag violation and FAILS validation.
#
# ALLOWED_LATEST (HD-192 inversion): only genuinely FLUID tags with no pinnable semver
# upstream survive, each with a MUST-pin justification. Everything else was pinned into
# group_vars/all/versions.yml (registry-verified 2026-08-21).
ALLOWED_LATEST = {
    # HD-121 precedent: obscure single-maintainer image facing public federation;
    # MUST pin to a registry-verified tag at first deploy (tuwunel_version: latest).
    "matrix",
    # profilarr + profilarr-parser: upstream publishes NO versioned tags (only
    # develop/buildcache/sha256 — probe 2026-08-21); fluid by upstream design,
    # documented in the compose header + versions.yml comment.
    "profilarr",
}

# Services that use network_mode: service:<sidecar> (no own networks)
NETWORK_MODE_SERVICE = {"qbittorrent"}

# HD-202 backstop allowlist — templates deliberately WITHOUT cap_drop: [ALL].
# GPU device services (decided HD-204: GPU/VPN exempt), HA standby (its keepalived
# sidecar predates the law — primary was reworked by HD-72 and left this list),
# raspberrymatic (parked HD-13, CCU emulation).
ALLOWED_NO_CAP_DROP = {
    "ollama", "immich-ml", "jellyfin", "sunshine",          # GPU / device access
    "home-assistant-standby",                               # keepalived sidecar (HD-72 closed primary)
    "raspberrymatic",                                        # parked (HD-13)
    "metabase",                                              # stock entrypoint self-manages user + su (Wave-2 triage 2026-08-22)
    "stirling-pdf",                                          # init.sh runs root then su-drops (user 0:0 + cap_add quintet; Wave-3 R3)
    "onlyoffice-docs",                                       # supervisord per-child setuid EPERMs even WITH setuid-cap whitelist; raw setpriv works — image init incompatible with cap_drop (HD-230, metabase precedent)
}
# Per-SERVICE exemptions inside otherwise-hardened templates:
SKIP_CAP_DROP_SERVICES = {"gluetun"}   # VPN sidecar — needs NET_ADMIN (HD-204 exemption)

WEB_SERVICES = {
    "traefik", "authentik", "opencloud", "forgejo", "homepage", "metabase",
    "grafana", "headscale", "element-web", "matrix",
    "jellyfin", "seerr", "sonarr", "radarr", "lidarr", "prowlarr", "bazarr",
    "sabnzbd", "qbittorrent", "profilarr",
    "immich-app",
    "dozzle",
    "pairdrop",
    "stirling-pdf",
    "zipline",
    "open-webui",
    "technitium", "pihole", "n8n",
    "actual-budget",   # budget.kogler.si UI + :5006 API leg over WG (HD-57)
    "chat",
    "onlyoffice-docs",
}

HOST_NET_SERVICES = {"traefik-ha"}
HOST_NET_CONTAINERS = {"home-assistant-standby"}

# Extra .j2 templates per service are NOT duplicated here any more (HD-189):
# the SSOT is roles/docker_services/defaults/main.yml `_extra_templates` — the
# same mapping the deploy loop renders. Loaded once at startup (fail-loud).
def load_extra_templates():
    p = ROOT / "IaC" / "ansible" / "roles" / "docker_services" / "defaults" / "main.yml"
    try:
        data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as e:
        print(f"FAIL: cannot read docker_services role defaults ({p}): {e}", file=sys.stderr)
        sys.exit(1)
    extra = data.get("_extra_templates")
    if not isinstance(extra, dict) or not extra:
        print(f"FAIL: {p} is missing the '_extra_templates' mapping", file=sys.stderr)
        sys.exit(1)
    return extra

# ── Render context ───────────────────────────────────────────────────────
def _load_ssot_ctx():
    """Load render-context values straight from the SSOT so the validator's
    context cannot drift from group_vars (HD-189): versions.yml wholesale
    (every *_version pin, HD-156 single sheet) + selected PLAIN-valued vars
    from all.yml. Derived/Jinja-valued all.yml vars (technitium_secondary_ip,
    wg_s2s_vps, nut_exporter_host …) are NOT loaded — they stay as explicit
    mocks in BASE_CTX below."""
    ctx = {}
    vp = GROUP_VARS_DIR / "all" / "versions.yml"
    try:
        ctx.update(yaml.safe_load(vp.read_text(encoding="utf-8")) or {})
    except (OSError, yaml.YAMLError) as e:
        print(f"FAIL: cannot read version pins ({vp}): {e}", file=sys.stderr)
        sys.exit(1)
    ap = GROUP_VARS_DIR / "all" / "main.yml"
    try:
        data = yaml.safe_load(ap.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as e:
        print(f"FAIL: cannot read group_vars/all/main.yml: {e}", file=sys.stderr)
        sys.exit(1)
    for k in (
        "timezone", "op_vault", "domain_public", "domain_local",
        "letsencrypt_email", "gpu_render_gid", "gpu_video_gid",
        "crowdsec_collections", "wildcard_cert_file", "wildcard_cert_key_file",
        "wildcard_cert_domain", "ha_vip", "ha_vip_cidr", "network_ranges",
        "kopia_sftp_host", "kopia_sftp_port", "kopia_sftp_user", "kopia_sftp_path",
        "traefik_edge_ips", "traefik_edge_ip_pin",
        # smtp2go relay connection SSOT (HD-54) — consumed by metabase MB_EMAIL_SMTP_*
        # (HD-241); grafana/nut render their own copies via role vars/defaults.
        "smtp2go_host", "smtp2go_port",
    ):
        if k in data:
            ctx[k] = data[k]
    # Neutral shared-data owner (HD-94) — SSOT: roles/storage/defaults/main.yml.
    sp = ROOT / "IaC" / "ansible" / "roles" / "storage" / "defaults" / "main.yml"
    try:
        sdata = yaml.safe_load(sp.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as e:
        print(f"FAIL: cannot read storage role defaults ({sp}): {e}", file=sys.stderr)
        sys.exit(1)
    for k in ("storage_uid", "storage_gid"):
        if k in sdata:
            ctx[k] = sdata[k]
    return ctx


BASE_CTX = _load_ssot_ctx()
# True mocks only — host/instance-specific or secret stand-ins that have no
# plain group_vars equivalent. Version pins, vault name, GPU gids, network
# ranges and kopia S2S target come from the SSOT via _load_ssot_ctx() above.
BASE_CTX.update({
    "homematic_usb_by_id": "/dev/serial/by-id/usb-eQ-3__HmIP-RFUSB_TEST",
    "technitium_secondary_ip": "10.10.1.20",
    # Technitium primary binds oldsrv's Home IP (host_vars/oldsrv) — same
    # instance-specific mock class as technitium_secondary_ip above (HD-187:
    # pihole CONDITIONAL_FORWARDING_IP renders against it).
    "dns_primary_ip": "10.10.1.30",
    # Immich ML cross-host endpoint (HD-184) — derived in group_vars/all/main.yml
    # from `oldsrv_home_ip`; mocked here with the same Home-IP value.
    "immich_ml_bind": "10.10.1.30",
    "immich_ml_url": "http://10.10.1.30:3003",
    # oldsrv Home-VLAN IP (group_vars/all/main.yml, derived from network_static_hosts) —
    # consumed by actual-budget's :5006 API-leg bind (HD-57); same Home-IP mock class.
    "oldsrv_home_ip": "10.10.1.30",
    # WG S2S peer (HD-155/191) — dict var in all.yml is Jinja-valued, so it stays
    # a mock; values mirror the documented /30 (VPS .2). Consumed by the kopia-server
    # WG-bound publish guard + the kopia-agent server address.
    "wg_s2s_vps": {"ip": "10.255.40.2", "peer_public_key": "mock-router-public-key"},
    "ansible_user": "ansible-admin",
    "inventory_hostname": "oldsrv.kogler.si",
    "homelab_mode": "desktop",
    "gpu_vendor": "amd",
    "ollama_keep_alive": "5m",
    "home_assistant_version": "stable",
    "rmat_name": "raspberrymatic",
    "rmat_restart": "unless-stopped",
    "instance": "primary",

    "forgejo_api": "secret456",
    "authentik_db_name": "authentik",
    "opencloud_log_level": "info",
    "grafana_smtp_host": "localhost:25",
    # HD-181: render the ISSUER path by default (ACME flags + certresolver labels +
    # certs-dumper stay exercised); consumer-only bits (tls.yml default store,
    # cert-pull wiring) are covered by the role-default false at real deploy.
    "traefik_acme_issuer": True,
    "ha_primary_state": "MASTER",
    "ha_primary_priority": 110,
    "ha_primary_peer_priority": 90,
    # VPS wg-s2s peer (group_vars/all/main.yml `wg_s2s_vps`) — kept as a mock because
    # the real value embeds Jinja lookups/derivations; shape mirrors the SSOT.
    "wg_s2s_vps": {"ip": "10.255.40.2", "local_ip": "10.255.40.2/30", "router_ip": "10.255.40.1",
                    "listen_port": 51820, "endpoint": "", "peer_public_key": "mock-router-pubkey",
                    "allowed_ips": ["10.10.0.0/16", "10.255.20.0/24"]},
})
# ── Mock helpers ─────────────────────────────────────────────────────────

def mock_lookup(*args, **kwargs):
    """Mock 1Password lookup; returns '<secret:name>'."""
    name = args[0] if args else kwargs.get("name", "unknown")
    return f"<secret:{name}>"


def _mock_vault_fields(name):
    """HD-258: a mocked 1Password item for the `vault` dict pre-pass. Every
    field maps to the same byte-identical stub `'<secret:NAME>'` that mock_lookup
    returned — so a template using `vault['NAME'].field` renders EXACTLY the same
    bytes as the predecessor `lookup('NAME', field='field')`. This is what makes
    the bulk-pre-pass refactor provably render-equivalent offline."""
    return {
        "username": f"<secret:{name}>",
        "password": f"<secret:{name}>",
        "credential": f"<secret:{name}>",
        "bcrypt_hash": f"<secret:{name}>",
    }


def mock_default(value, default="", boolean=False):
    """Mock Jinja2 default filter (handles boolean 3rd arg)."""
    if value is None or (boolean and not value):
        return default
    return value


def ansible_comment(text, style="plain"):
    """Mock Ansible comment filter."""
    return "\n".join(f"# {l}" if l else "#" for l in str(text).splitlines())


def build_env():
    env = Environment(
        undefined=StrictUndefined,
        keep_trailing_newline=True,
        trim_blocks=True,
        lstrip_blocks=True,
    )
    env.globals["lookup"] = mock_lookup
    env.filters["default"] = mock_default
    env.filters["comment"] = ansible_comment
    # HD-258: bulk pre-pass leaves a `vault: {NAME: {field: val}}` dict in scope
    # instead of per-template `lookup()`. Mock it here so the gate renders the
    # post-refactor templates offline — every field is the same `'<secret:NAME>'`
    # stub the old lookup produced, so output is byte-identical by construction.
    # auto-materialize any requested item via __missing__ so templates that
    # reference `vault['NAME']` render offline without pre-populating the dict.
    class _Vault(dict):
        def __missing__(self, key):
            item = _mock_vault_fields(key)
            self[key] = item
            return item
    env.globals["vault"] = _Vault()
    return env


# ── Source-level bug checks ──────────────────────────────────────────────

def check_source_bugs(name, src, errors):
    """Check raw template source for common bugs before rendering."""

    # Bug: default= inside lookup() call (not Jinja2 | default filter)
    for m in re.finditer(r"lookup\([^)]*default\s*=", src):
        lineno = src[:m.start()].count("\n") + 1
        errors.append(
            f"[{name}] BUG: 'default=' inside lookup() call — "
            f"use Jinja2 | default filter instead (line {lineno})"
        )

    # Bug: '- host' in networks: without network_mode: host
    for m in re.finditer(r"^\s{4,}- host\s*$", src, re.MULTILINE):
        ctx_start = max(0, m.start() - 200)
        context = src[ctx_start:m.start()]
        if not re.search(r"network_mode:\s*host", context):
            lineno = src[:m.start()].count("\n") + 1
            errors.append(
                f"[{name}] BUG: '- host' in networks: without network_mode: host "
                f"(line {lineno})"
            )

    # Warn: duplicate top-level traefik.tls.certresolver labels
    labels = list(re.finditer(r"traefik\.(?:http\.routers\.[^.]+\.)?tls\.certresolver", src))
    top_level = [m for m in labels if "http.routers" not in m.group()]
    if len(top_level) > 1:
        errors.append(
            f"[{name}] WARN: duplicate top-level 'traefik.tls.certresolver' label "
            f"(line {src[:top_level[1].start()].count(chr(10)) + 1})"
        )


# ── Rendered-YAML validation ─────────────────────────────────────────────

def validate_render(name, j2_path, env, service):
    """Full validation: render → YAML parse → structural checks."""
    errors = []

    try:
        src = j2_path.read_text(encoding="utf-8")
    except Exception as e:
        return False, [f"[{name}] failed to read template: {e}"]

    # Skip TODO stubs
    first = src.lstrip().splitlines()[0] if src.strip() else ""
    if "TODO: define service" in first:
        return True, []

    # Source-level bug scan
    check_source_bugs(name, src, errors)

    # Build render context
    ctx = dict(BASE_CTX)
    ctx.update({k: v for k, v in service.items() if v is not None})
    ctx["instance"] = service.get("instance", "primary")

    try:
        rendered = env.from_string(src).render(**ctx)
    except Exception as e:
        return False, errors + [f"[{name}] Jinja2 render error: {e}"]

    try:
        compose = yaml.safe_load(rendered)
    except yaml.YAMLError as e:
        return False, errors + [f"[{name}] invalid YAML after render: {e}"]

    if not compose:
        return False, errors + [f"[{name}] empty compose file"]
    if "services" not in compose or not compose["services"]:
        return False, errors + [f"[{name}] no services section"]

    # Per-service checks
    defined_nets = set(compose.get("networks", {}).keys()) if compose.get("networks") else set()

    # Convention (deployment-compose.md): the docker_services role creates the
    # external networks — every declared network must be external: true so
    # compose never tries to create it.
    for net_name, net_def in (compose.get("networks", {}) or {}).items():
        if not (isinstance(net_def, dict) and net_def.get("external") is True):
            errors.append(f"[{name}] network '{net_name}' must be declared 'external: true'")

    for svc_name, svc_def in compose["services"].items():
        prefix = f"[{name}/{svc_name}]"

        # image
        if "image" not in svc_def:
            errors.append(f"{prefix} missing `image`")
        else:
            # HD-134: enforce the pinned-tag convention (never bare `latest`).
            # Flags both a literal `image: ...:latest` and an undefined *_version var that
            # resolved to `latest` via the `default('latest')` fallback at render time.
            img = svc_def.get("image", "")
            tag = img.rsplit(":", 1)[-1] if ":" in img else ""
            if tag == "latest":
                if name not in ALLOWED_LATEST:
                    errors.append(
                        f"{prefix} UNPINNED image '{img}' resolves to bare `latest` "
                        f"(HD-134/KOPS-030) — pin a semver via a `{name}` compose version var + "
                        f"group_vars, or (if it's a deliberate latest/fluid tag) add `{name}` "
                        f"to ALLOWED_LATEST with a MUST-pin comment."
                    )

        # restart policy
        restart = svc_def.get("restart", "")
        if restart and restart not in ("always", "unless-stopped", "no", ""):
            errors.append(f"{prefix} invalid restart policy: '{restart}'")

        # HD-202 backstop: container-hardening law (deployment-compose.md §Container
        # Security) — every service carries `cap_drop: [ALL]` (+ minimal cap_add),
        # rolled into the templates 2026-08-21. The allowlist below is the BACKSTOP
        # for deliberate exemptions only (GPU device services, the VPN sidecar,
        # HD-72 scope, parked) — it must stay small and commented.
        if "cap_drop" not in svc_def:
            if name not in ALLOWED_NO_CAP_DROP and svc_name not in SKIP_CAP_DROP_SERVICES:
                errors.append(
                    f"{prefix} missing 'cap_drop: [ALL]' (HD-202 container-hardening law; "
                    f"exempt only via ALLOWED_NO_CAP_DROP with justification)"
                )

        # network_mode vs networks
        net_mode = svc_def.get("network_mode", "")
        svc_nets = set()
        for n in svc_def.get("networks", []):
            if isinstance(n, str):
                svc_nets.add(n)
            elif isinstance(n, dict):
                svc_nets.update(n.keys())

        if net_mode == "host":
            if svc_nets:
                errors.append(f"{prefix} network_mode: host combined with networks: {svc_nets}")
            if svc_def.get("ports"):
                errors.append(f"{prefix} network_mode: host combined with ports:")
        elif name not in NETWORK_MODE_SERVICE:
            # Network assignment policy lives in docs/deployment-compose.md;
            # enforcement here = every referenced network must be declared
            # external: true at the top level (checked below). The old
            # per-service NETWORK_MAP allowlist was dead code, deleted HD-189.
            pass

        # every referenced network must be declared external: true at the top
        # (convention: the role creates the networks; compose must never create them)
        for net in svc_nets:
            if net not in defined_nets:
                errors.append(
                    f"{prefix} network '{net}' not declared in the file's top-level "
                    f"networks: (must be external: true)"
                )

        # Traefik labels - only check on the MAIN service (matching template name)
        labels = svc_def.get("labels", {}) or {}
        if svc_name == name and name not in NO_TRAEFIK_LABELS:
            if name in WEB_SERVICES:
                lk = " ".join(str(k) for k in labels.keys())
                if "traefik.enable" not in lk:
                    errors.append(f"{prefix} web service missing 'traefik.enable: true'")
                if "traefik.http.routers" not in lk:
                    errors.append(f"{prefix} web service missing 'traefik.http.routers.*'")
            elif name not in HOST_NET_SERVICES and name not in HOST_NET_CONTAINERS:
                # Skip secondary instances
                if service.get("instance") not in ("secondary",):
                    if isinstance(labels, dict) and labels.get("traefik.enable") in ("true", "True", True):
                        errors.append(f"{prefix} non-web service should not set traefik.enable: true")

        # Duplicate tls.certresolver
        if isinstance(labels, dict):
            top = [k for k in labels if k == "traefik.tls.certresolver"]
            router = [k for k in labels if ".tls.certresolver" in k and "http.routers" in k]
            if top and router:
                errors.append(f"{prefix} redundant top-level traefik.tls.certresolver")

    # Extra template files exist (SSOT: roles/docker_services/defaults/main.yml)
    template_dir = TEMPLATES_DIR / service.get("template_dir", name)
    for extra in EXTRA_TEMPLATES.get(service.get("template_dir", name), []):
        if not (template_dir / extra).exists():
            errors.append(f"[{name}] missing extra template: {extra}")

    return len(errors) == 0, errors


# ── Main ─────────────────────────────────────────────────────────────────

def load_all_services():
    """Load docker_services from all group_vars files (deduplicated by name).

    Fail-loud (HD-189): a malformed YAML file used to be silently skipped
    (`except: pass`) — fewer templates validated, gate still PASS. Now aborts
    with the offending file + error."""
    seen = set()
    services = []
    for gv_file in sorted(GROUP_VARS_DIR.glob("*.yml")):
        try:
            data = yaml.safe_load(gv_file.read_text(encoding="utf-8"))
        except yaml.YAMLError as e:
            print(f"FAIL: malformed YAML in {gv_file}: {e}", file=sys.stderr)
            sys.exit(1)
        for svc in (data or {}).get("docker_services", []):
            name = svc.get("name")
            if name and name not in seen:
                seen.add(name)
                services.append(svc)
    return services


def main():
    env = build_env()
    global EXTRA_TEMPLATES
    EXTRA_TEMPLATES = load_extra_templates()
    services = load_all_services()
    services_by_name = {s.get("name"): s for s in services if s.get("name")}

    # Handle --only <name>
    only_name = None
    for i, arg in enumerate(sys.argv[1:]):
        if arg == "--only" and i + 2 < len(sys.argv):
            only_name = sys.argv[i + 2]
        elif arg.startswith("--only="):
            only_name = arg[7:]

    if only_name:
        service = services_by_name.get(only_name)
        if not service:
            print(f"ERROR: service '{only_name}' not found", file=sys.stderr)
            sys.exit(1)
        exists, j2_path = check_template_exists(only_name, service)
        if not exists:
            print(f"ERROR: template not found for {only_name}", file=sys.stderr)
            sys.exit(1)
        ok, errors = validate_render(only_name, j2_path, env, service)
        if ok:
            print(f"PASS: {only_name}")
            sys.exit(0)
        else:
            for e in errors:
                print(e, file=sys.stderr)
            sys.exit(1)

    # Full run
    passed = 0
    failed = 0
    errors_out = []

    for service in services:
        name = service.get("name")
        if not name:
            continue
        exists, j2_path = check_template_exists(name, service)
        if not exists:
            errors_out.append(f"[{name}] template directory missing")
            failed += 1
            continue
        ok, errs = validate_render(name, j2_path, env, service)
        if ok:
            passed += 1
        else:
            failed += 1
            errors_out.extend(errs)

    # Count-lint: every dir under docker_services/ must be referenced by at
    # least one group_vars docker_services `template_dir:` (HD-157). This
    # catches the orphan-dir drift where a template is added/renamed but the
    # group_vars list (the deploy loop SSOT) is not updated — the mirror of
    # the per-service missing-template check above. A template dir with no
    # reference is dead code and hides that the service is NOT deployed.
    referenced_dirs = {
        s.get("template_dir") or s.get("name")
        for s in services
        if s.get("template_dir") is not None or s.get("name") is not None
    }
    referenced_dirs = {d for d in referenced_dirs if d}
    # Intentionally retained template dirs that are NOT in any docker_services
    # list right now (parked / deferred, documented in group_vars + docs). They
    # are kept so the work isn't lost, but must be re-wired on reactivation.
    #   * raspberrymatic — parked (HD-13): HmIP-RFUSB not bought; re-add to the
    #     Pi loop when local RF is purchased (see group_vars/raspberry_pi.yml).
    RETAINED_TEMPLATE_DIRS = {"raspberrymatic"}
    orphan_dirs = sorted(
        p.name for p in TEMPLATES_DIR.iterdir() if p.is_dir()
        and p.name not in referenced_dirs
        and p.name not in RETAINED_TEMPLATE_DIRS
    )
    if orphan_dirs:
        for d in orphan_dirs:
            errors_out.append(
                f"[count-lint] docker_services/{d}/ has no `template_dir:` in any "
                f"group_vars docker_services list — add it or remove the dir"
            )
        failed += len(orphan_dirs)

    for e in errors_out:
        print(e, file=sys.stderr)


    if failed == 0:
        print(f"PASS: {passed} docker_services templates valid")
        sys.exit(0)
    else:
        print(f"FAIL: {passed}/{passed + failed} templates valid", file=sys.stderr)
        sys.exit(1)


def check_template_exists(name, service):
    """Check if template file exists. Return (exists, path)."""
    template_dir = service.get("template_dir")
    if not template_dir:
        return False, None
    j2_path = TEMPLATES_DIR / template_dir / "docker-compose.yml.j2"
    return j2_path.exists(), j2_path


if __name__ == "__main__":
    main()
