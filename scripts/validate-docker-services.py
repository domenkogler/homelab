#!/usr/bin/env python3
"""
Validate docker_services compose templates from group_vars/*.yml.

Checks all 41 compose templates:
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

ROOT = Path(".")
TEMPLATES_DIR = ROOT / "IaC" / "ansible" / "templates" / "docker_services"
GROUP_VARS_DIR = ROOT / "IaC" / "ansible" / "group_vars"

# ── Network assignments per deployment-compose.md ────────────────────────
NETWORK_MAP = {
    "traefik":           {"traefik-public"},
    "crowdsec":          {"traefik-public"},
    "authentik":         {"traefik-public", "services-internal", "db-internal"},
    "opencloud":         {"traefik-public"},
    "immich-app":        {"traefik-public", "services-internal"},
    "forgejo":           {"traefik-public", "services-internal", "db-internal"},
    "ollama":            {"services-internal"},
    "immich-ml":         {"services-internal"},
    "technitium":        {"traefik-public", "services-internal"},
    "pihole":            {"services-internal"},
    "home-assistant-standby": {"services-internal"},
    "raspberrymatic":    {"homematic"},
    "technitium-secondary": {"traefik-public", "services-internal"},
    "headscale":         {"traefik-public"},
    "kopia-server":      {"services-internal"},
    "db-backup":         {"services-internal", "db-internal"},
    "homepage":          {"traefik-public"},
    "metabase":          {"traefik-public", "services-internal"},
    "blackbox-exporter": {"services-internal"},
    "loki":              {"db-internal"},
    "prometheus":        {"db-internal"},
    "grafana":           {"traefik-public", "db-internal"},
    "signal-cli-rest-api": {"services-internal"},
    "dozzle":            {"traefik-public"},
    "sunshine":          {"services-internal"},
    "n8n":               {"traefik-public", "services-internal"},
    "doco-cd":           set(),
    "renovate":          {"services-internal"},
    "sunshine":          {"services-internal"},
    "jellyfin":          {"services-internal", "traefik-public"},
    "seerr":             {"services-internal", "traefik-public"},
    "sonarr":            {"services-internal", "traefik-public"},
    "radarr":            {"services-internal", "traefik-public"},
    "lidarr":            {"services-internal", "traefik-public"},
    "prowlarr":          {"services-internal", "traefik-public"},
    "immich-app":        {"traefik-public", "services-internal", "db-internal"},
    "immich-ml":         {"services-internal"},
    "bazarr":            {"services-internal", "traefik-public"},
    "sabnzbd":           {"services-internal", "traefik-public"},
    "qbittorrent":       {"services-internal", "traefik-public"},
    "profilarr":         {"services-internal", "traefik-public"},
    "recyclarr":         {"services-internal"},
    "matrix":            {"traefik-public", "services-internal"},
    "element-web":       {"traefik-public"},
    "chat":              {"traefik-public"},
    "traefik-ha":        set(),
}

# Services that don't need Traefik labels (are their own reverse proxy)
NO_TRAEFIK_LABELS = {"traefik-ha", "qbittorrent"}  # qbittorrent labels are on gluetun sidecar

# Services that use network_mode: service:<sidecar> (no own networks)
NETWORK_MODE_SERVICE = {"qbittorrent"}

WEB_SERVICES = {
    "traefik", "authentik", "opencloud", "forgejo", "homepage", "metabase",
    "grafana", "headscale", "element-web", "matrix",
    "jellyfin", "seerr", "sonarr", "radarr", "lidarr", "prowlarr", "bazarr",
    "traefik",
    "sabnzbd", "qbittorrent", "profilarr",
    "immich-app",
    "dozzle",
    "pairdrop",
    "stirling-pdf",
    "technitium", "pihole", "n8n",
    "chat",
}

HOST_NET_SERVICES = {"doco-cd", "traefik-ha"}
HOST_NET_CONTAINERS = {"home-assistant-standby"}

_EXTRA_TEMPLATES = {
    "element-web": ["config.json.j2"],
    "home-assistant-standby": ["keepalived.conf.j2"],
    "loki": ["loki.yaml.j2"],
    "matrix": ["tuwunel.toml.j2"],
    "litellm": ["config.yaml.j2"],
    "prometheus": ["prometheus.yml.j2"],
    "headscale": ["config.yaml.j2"],
    "recyclarr": ["recyclarr.yml.j2"],
    "traefik": ["dynamic/routes.yml.j2", "dynamic/middlewares.yml.j2"],
    "traefik-ha": ["dynamic/routes.yml.j2"],
}

# ── Render context ───────────────────────────────────────────────────────
BASE_CTX = {
    "timezone": "Europe/Ljubljana",
    "op_vault": "Homelab",
    "domain_public": "kogler.si",
    "domain_local": "kogler.si",
    "letsencrypt_email": "domen@kogler.si",
    "traefik_version": "latest",
    "certs_dumper_version": "v2.8.3",
    "keepalived_version": "2.3.4",
    "pairdrop_version": "1.11.2",
    "stirling_pdf_version": "2.14.3-fat",
    "pgvector_version": "0.8.6-pg16-trixie",
    "docling_version": "v1.30.0",
    "litellm_version": "main-stable",
    "storage_uid": "1005",
    "storage_gid": "1005",
    "tuwunel_version": "latest",
    "homematic_usb_by_id": "/dev/serial/by-id/usb-eQ-3__HmIP-RFUSB_TEST",
    "wildcard_cert_file": "kogler.si.pem",
    "wildcard_cert_key_file": "kogler.si-key.pem",
    "wildcard_cert_domain": "kogler.si",
    "technitium_secondary_ip": "10.10.1.20",
    "ha_vip": "10.10.1.200",
    "ha_vip_cidr": "24",
    "ansible_user": "ansible-admin",
    "inventory_hostname": "oldsrv.kogler.si",
    "homelab_mode": "desktop",
    "gpu_vendor": "amd",
    "ollama_keep_alive": "5m",
    "gpu_render_gid": "123",
    "gpu_video_gid": "124",
    "crowdsec_bouncer_plugin_version": "v0.4.0",
    "crowdsec_version": "latest",
    "crowdsec_collections": "crowdsecurity/traefik crowdsecurity/linux",
    "minio_version": "latest",
    "authentik_db_name": "authentik",
    "authentik_version": "latest",
    "opencloud_version": "7.4.0",
    "forgejo_version": "latest",
    "home_assistant_version": "stable",
    "headscale_version": "latest",
    "kopia_version": "latest",
    "db_backup_version": "latest",
    "grafana_version": "latest",
    "immich_version": "release",
    "n8n_version": "latest",
    "rmat_name": "raspberrymatic",
    "rmat_restart": "unless-stopped",
    "instance": "primary",
    "doco_cd_password": "secret123",
    "forgejo_api": "secret456",
    "opencloud_log_level": "info",
    "kopia_s3_bucket": "kogler-homelab",
    "kopia_s3_endpoint": "https://e2.idy.io",
    "grafana_smtp_host": "localhost:25",
    "ha_primary_state": "MASTER",
    "ha_primary_priority": 110,
    "ha_primary_peer_priority": 90,
    "network_ranges": [
        {"name": "traefik-public",    "cidr": "172.20.0.0/16", "purpose": "docker edge"},
        {"name": "services-internal", "cidr": "172.21.0.0/16", "purpose": "app mesh"},
        {"name": "db-internal",       "cidr": "172.22.0.0/16", "purpose": "database"},
        {"name": "site",              "cidr": "10.10.0.0/16",  "purpose": "site"},
    ],
}
# ── Mock helpers ─────────────────────────────────────────────────────────

def mock_lookup(*args, **kwargs):
    """Mock 1Password lookup; returns '<secret:name>'."""
    name = args[0] if args else kwargs.get("name", "unknown")
    return f"<secret:{name}>"


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

        # restart policy
        restart = svc_def.get("restart", "")
        if restart and restart not in ("always", "unless-stopped", "no", ""):
            errors.append(f"{prefix} invalid restart policy: '{restart}'")

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
            allowed = NETWORK_MAP.get(name, set())
            if svc_nets and not svc_nets.issubset(allowed | defined_nets):
                unexpected = svc_nets - allowed - defined_nets
                if unexpected:
                    errors.append(f"{prefix} unexpected networks {unexpected}")

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

    # Extra template files exist
    template_dir = TEMPLATES_DIR / service.get("template_dir", name)
    for extra in _EXTRA_TEMPLATES.get(service.get("template_dir", name), []):
        if not (template_dir / extra).exists():
            errors.append(f"[{name}] missing extra template: {extra}")

    return len(errors) == 0, errors


# ── Main ─────────────────────────────────────────────────────────────────

def load_all_services():
    """Load docker_services from all group_vars files (deduplicated by name)."""
    seen = set()
    services = []
    for gv_file in sorted(GROUP_VARS_DIR.glob("*.yml")):
        try:
            data = yaml.safe_load(gv_file.read_text(encoding="utf-8"))
            for svc in data.get("docker_services", []):
                name = svc.get("name")
                if name and name not in seen:
                    seen.add(name)
                    services.append(svc)
        except Exception:
            pass
    return services


def main():
    env = build_env()
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
            sys
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

    if errors_out:
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
