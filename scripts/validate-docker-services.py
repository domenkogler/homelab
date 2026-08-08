#!/usr/bin/env python3
"""
Validate docker_services templates from group_vars/home_servers.yml.

- Baseline: reports the 8 missing NEW templates and exits 1.
- Full run: validates all 27 templates, exits 0 on success.
"""
import sys
import re
from pathlib import Path
from jinja2 import Environment, StrictUndefined
import yaml

ROOT = Path(".")
TEMPLATES_DIR = ROOT / "IaC" / "ansible" / "templates" / "docker_services"
GROUP_VARS = ROOT / "IaC" / "ansible" / "group_vars" / "home_servers.yml"

# The 8 NEW templates that need to be created (per T0)
NEW_TEMPLATES = {"homepage", "renovate", "blackbox-exporter", "prometheus", "loki", "signal-cli-rest-api", "doco-cd", "metabase"}

# Allowed networks for NEW templates only
ALLOWED_NETWORKS = {
    "homepage": {"traefik-public"},
    "renovate": {"services-internal"},
    "blackbox-exporter": {"services-internal"},
    "prometheus": {"db-internal"},
    "loki": {"db-internal"},
    "doco-cd": {"host"},  # network_mode: host
    "metabase": {"traefik-public", "services-internal"},
    "signal-cli-rest-api": {"services-internal"},
}

# Web services requiring Traefik labels (for NEW templates)
WEB_SERVICES = {"homepage", "metabase"}

# Non-web services should NOT have traefik.enable (for NEW templates)
NON_WEB_SERVICES = {"renovate", "doco-cd", "prometheus", "loki", "blackbox-exporter", "signal-cli-rest-api"}

# Base render context - matches validate_doc_templates.py style
BASE_CTX = {
    "timezone": "Europe/Ljubljana",
    "op_vault": "Homelab",
    "domain_public": "kogler.si",
    "domain_local": "kogler.si",
    "letsencrypt_email": "domen@kogler.si",
    "traefik_version": "latest",
    "certs_dumper_version": "v2.8.3",
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
}


def mock_lookup(*args, **kwargs):
    """Mock 1Password lookup: returns <secret:name>."""
    name = args[0] if args else kwargs.get("name", "unknown")
    return f"<secret:{name}>"


def mock_default(value, default="", boolean=False):
    """Jinja2 default filter mock (handles boolean 3rd arg for Ansible templates)."""
    # In Ansible, default('', true) means: if undefined, return ''; otherwise the value
    # The 'boolean' arg is used when the default should be returned even for falsy values
    if value is None or (boolean and not value):
        return default
    return value


def ansible_comment(text, style="plain"):
    """Mock Ansible comment filter."""
    return "\n".join(f"# {l}" if l else "#" for l in str(text).splitlines())


def build_env():
    """Create Jinja2 environment with Ansible-like filters."""
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


def load_services():
    """Load docker_services from group_vars/home_servers.yml."""
    if not GROUP_VARS.exists():
        print(f"ERROR: {GROUP_VARS} not found", file=sys.stderr)
        sys.exit(1)
    with open(GROUP_VARS, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return data.get("docker_services", [])


def check_template_exists(name, service):
    """Check if template exists for a service. Return (exists, j2_path)."""
    template_dir = service.get("template_dir")
    if not template_dir:
        return False, None
    j2_path = TEMPLATES_DIR / template_dir / "docker-compose.yml.j2"
    return j2_path.exists(), j2_path


def validate_render(name, j2_path, env, service, is_new=True):
    """Validate that a template can be rendered. Returns (ok, errors)."""
    errors = []
    
    try:
        src = j2_path.read_text(encoding="utf-8")
    except Exception as e:
        errors.append(f"[service] {name}: failed to read template: {e}")
        return False, errors

    # Build render context
    ctx = dict(BASE_CTX)
    ctx.update({k: v for k, v in service.items() if v is not None})

    try:
        rendered = env.from_string(src).render(**ctx)
    except Exception as e:
        errors.append(f"[service] {name}: Jinja2 render error: {e}")
        return False, errors

    # Parse rendered YAML
    try:
        compose = yaml.safe_load(rendered)
    except yaml.YAMLError as e:
        errors.append(f"[service] {name}: invalid YAML after render: {e}")
        return False, errors

    if not compose:
        errors.append(f"[service] {name}: empty compose file")
        return False, errors

    services = compose.get("services", {})
    if not services:
        errors.append(f"[service] {name}: no services section or empty")
        return False, errors

    svc_def = services.get(name)
    if not svc_def:
        errors.append(f"[service] {name}: no service named '{name}' in template")
        return False, errors

    # Validation rules apply only to NEW templates
    if not is_new:
        return True, []

    # --- NEW TEMPLATE RULES ---
    
    # Rule 1: every service defines `image`, `restart`
    if "image" not in svc_def:
        errors.append(f"[service] {name}: missing `image`")
    if "restart" not in svc_def:
        errors.append(f"[service] {name}: missing `restart`")
    elif svc_def.get("restart") not in ("always", "unless-stopped", "no"):
        errors.append(f"[service] {name}: invalid restart policy: {svc_def.get('restart')}")

    # Rule 2: networks are subset of allowed set
    svc_networks = svc_def.get("networks", [])
    doco_cd_network_mode = svc_def.get("network_mode", "") == "host"
    
    if name == "doco-cd":
        # doco-cd uses host network mode
        if not doco_cd_network_mode:
            errors.append(f"[service] {name}: doco-cd should use network_mode: host")
    else:
        allowed = ALLOWED_NETWORKS.get(name, set())
        actual_networks = set()
        for n in svc_networks:
            if isinstance(n, dict):
                actual_networks.update(n.keys())
            elif isinstance(n, str):
                actual_networks.add(n)
            else:
                actual_networks.add(str(n))
        if not actual_networks.issubset(allowed):
            errors.append(f"[service] {name}: networks {actual_networks} not allowed (should be subset of {allowed})")

    # Rule 3: web services REQUIRE Traefik labels
    if name in WEB_SERVICES:
        labels = svc_def.get("labels", {})
        if not isinstance(labels, dict):
            labels = {}
        for req in ["traefik.enable", "traefik.tls.certresolver", "traefik.http.routers"]:
            found = any(req in str(k) for k in labels.keys())
            if not found:
                errors.append(f"[service] {name}: missing required Traefik label: {req}")

    # Rule 4: non-web services must NOT have traefik.enable: true
    if name in NON_WEB_SERVICES:
        labels = svc_def.get("labels", {})
        if isinstance(labels, dict):
            enable_val = labels.get("traefik.enable", "")
            if enable_val == "true" or '"true"' in str(enable_val) or "'true'" in str(enable_val):
                errors.append(f"[service] {name}: non-web service should not set traefik.enable: true")

    # Rule 5: secret-hygiene - env vars with password/secret/token/key must use lookup
    # Check the SOURCE template for lookup() calls, since rendered values are mocked
    env_vars = svc_def.get("environment", {})
    if env_vars and isinstance(env_vars, dict):
        for key, val in env_vars.items():
            if key and re.search(r"(password|secret|token|key)", str(key), re.IGNORECASE):
                # In the source template, the value line should contain lookup( or default(
                pattern = rf"^\s*{key}[\s:]*.*lookup"
                if not re.search(pattern, src, re.MULTILINE):
                    errors.append(f"[service] {name}: secret env var '{key}' should use lookup() or default() in template")

    return len(errors) == 0, errors


def main():
    env = build_env()
    services = load_services()
    
    # Build a map of name -> service
    services_by_name = {s.get("name"): s for s in services if s.get("name")}
    
    only_name = None
    # Handle --only <name> (two separate args) or --only<name> (combined)
    for i, arg in enumerate(sys.argv[1:]):
        if arg == "--only" and i + 2 < len(sys.argv):
            only_name = sys.argv[i + 2]
            break
        elif arg.startswith("--only "):
            only_name = arg[7:]

    if only_name:
        # Single-service validation
        service = services_by_name.get(only_name)
        if not service:
            print(f"ERROR: service '{only_name}' not found", file=sys.stderr)
            sys.exit(1)
        
        exists, j2_path = check_template_exists(only_name, service)
        if not exists:
            print(f"ERROR: template not found for {only_name}")
            sys.exit(1)
        
        ok, errors = validate_render(only_name, j2_path, env, service, is_new=(only_name in NEW_TEMPLATES))
        if ok:
            print(f"PASS: {only_name}")
            sys.exit(0)
        else:
            for e in errors:
                print(e)
            sys.exit(1)
    
    # Full validation - baseline check for missing templates first
    missing_new = []
    for name in NEW_TEMPLATES:
        service = services_by_name.get(name)
        if service:
            exists, _ = check_template_exists(name, service)
            if not exists:
                missing_new.append(name)
        else:
            missing_new.append(name)
    
    if missing_new:
        # Baseline: report missing templates and exit 1
        print(f"FAIL: {len(missing_new)} missing template dirs:")
        for name in missing_new:
            print(f"  {name}")
        sys.exit(1)
    
    # All NEW templates exist - validate all
    passed = 0
    failed = 0
    for service in services:
        name = service.get("name")
        if name:
            exists, j2_path = check_template_exists(name, service)
            if exists:
                ok, errors = validate_render(name, j2_path, env, service, is_new=(name in NEW_TEMPLATES))
                if ok:
                    passed += 1
                else:
                    failed += 1
                    for e in errors:
                        print(e)
    
    if failed == 0:
        print(f"PASS: {passed} docker_services templates valid")
        sys.exit(0)
    else:
        print(f"FAIL: {passed}/{passed + failed} templates valid")
        sys.exit(1)


if __name__ == "__main__":
    main()