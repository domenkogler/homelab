#!/usr/bin/env python3
"""
Validate Authentik Blueprint YAML files (HD-149).

Authentik Blueprints use custom YAML tags (`!Find`, `!KeyOf`, `!Key`, `!Value`,
`!Env`, `!Context`, `!If`, `!Format`, `!Index`, `!Custom`) that PyYAML's stock
SafeLoader rejects. This loader + checker makes blueprints locally parseable and
catches the structural mistakes documented in services-authentik.md
(Blueprint authoring notes, verified 2026-08-19):

  - both default flow slugs carry the `default-` prefix
  - the provider->application binding lives INSIDE the application entry
    (`provider: !KeyOf <id>`), NOT in a separate
    `authentik_providers_oauth2.application` link entry (that model does not exist)

Exit codes:
  0 = all blueprints valid
  1 = any failure

Usage:
  python scripts/validate_blueprints.py
  python scripts/validate_blueprints.py IaC/ansible/templates/docker_services/authentik/blueprints/ks-oidc.yml
"""
import sys
from pathlib import Path

import yaml

# Authentik's custom blueprint tags. Loaded as plain (deep) YAML nodes so the
# structure can be inspected without executing anything.
BLUEPRINT_TAGS = (
    "!Find", "!KeyOf", "!Key", "!Value", "!Env", "!Context",
    "!If", "!Format", "!Index", "!Custom",
)

# Flow slugs verified against goauthentik/authentik main (2026-08-19, HD-149):
#   blueprints/default/flow-default-authentication-flow.yaml              -> default-authentication-flow
#   blueprints/default/flow-default-provider-authorization-implicit-consent.yaml
#     -> default-provider-authorization-implicit-consent
DEFAULT_AUTHENTICATION_FLOW_SLUG = "default-authentication-flow"
DEFAULT_PROVIDER_AUTHORIZATION_FLOW_SLUG = "default-provider-authorization-implicit-consent"

# Provider model -> the binding field the application entry must carry.
PROVIDER_MODEL = "authentik_providers_oauth2.oauth2provider"
APPLICATION_MODEL = "authentik_core.application"
# Models that used to be (wrongly) used as a separate provider<->app link entry.
NONEXISTENT_LINK_MODELS = ("authentik_providers_oauth2.application",)


class BlueprintLoader(yaml.SafeLoader):
    """SafeLoader that tolerates Authentik's custom tags."""


def _any_constructor(loader, node):
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node, deep=True)
    return loader.construct_scalar(node)


for _tag in BLUEPRINT_TAGS:
    BlueprintLoader.add_constructor(_tag, _any_constructor)


def check_blueprint(path: Path) -> list[str]:
    """Validate one blueprint file. Returns a list of error strings (empty = OK)."""
    errors: list[str] = []
    try:
        data = yaml.load(path.read_text(encoding="utf-8"), Loader=BlueprintLoader)
    except yaml.YAMLError as exc:
        return [f"{path.name}: YAML parse error: {exc}"]

    if not isinstance(data, dict) or "entries" not in data:
        return [f"{path.name}: missing top-level `entries:` list"]

    entries = data["entries"]
    providers: dict[str, dict] = {}
    apps: dict[str, dict] = {}

    for i, entry in enumerate(entries):
        if not isinstance(entry, dict):
            errors.append(f"{path.name} entry[{i}]: not a mapping")
            continue
        model = entry.get("model")
        eid = entry.get("id")
        if model == PROVIDER_MODEL:
            if eid:
                providers[eid] = entry
            _check_provider(path, entry, i, errors)
        elif model == APPLICATION_MODEL:
            if eid:
                apps[eid] = entry
        elif model in NONEXISTENT_LINK_MODELS:
            errors.append(
                f"{path.name} entry[{i}]: model {model!r} does not exist in Authentik — "
                "bind the provider via `provider: !KeyOf <id>` inside the "
                "authentik_core.application entry instead (HD-149)."
            )

    # Every application must carry the provider binding.
    for app_id, app in apps.items():
        attrs = app.get("attrs", {})
        provider_ref = attrs.get("provider")
        if not provider_ref:
            errors.append(
                f"{path.name}: application '{app_id}' has no `provider: !KeyOf <id>` "
                "binding in attrs (HD-149)."
            )

    return errors


def _check_provider(path: Path, entry: dict, index: int, errors: list[str]) -> None:
    attrs = entry.get("attrs", {})
    authn = attrs.get("authentication_flow")
    authz = attrs.get("authorization_flow")

    # 1. Flow slugs: both must carry the default- prefix, and the authentication
    #    flow must NOT be the authorization slug.
    def slug_of(tag_value) -> str | None:
        # !Find [model, [key, value]] parses to a nested list
        if isinstance(tag_value, (list, tuple)) and len(tag_value) >= 2:
            inner = tag_value[1]
            if isinstance(inner, (list, tuple)) and len(inner) >= 2:
                return inner[1]
        return None

    s_authn = slug_of(authn)
    s_authz = slug_of(authz)
    if s_authn and s_authn != DEFAULT_AUTHENTICATION_FLOW_SLUG:
        errors.append(
            f"{path.name} entry[{index}] ({entry.get('id')}): authentication_flow slug "
            f"{s_authn!r} — expected {DEFAULT_AUTHENTICATION_FLOW_SLUG!r} (HD-149)."
        )
    if s_authz and s_authz != DEFAULT_PROVIDER_AUTHORIZATION_FLOW_SLUG:
        errors.append(
            f"{path.name} entry[{index}] ({entry.get('id')}): authorization_flow slug "
            f"{s_authz!r} — expected {DEFAULT_PROVIDER_AUTHORIZATION_FLOW_SLUG!r} "
            "(note: the `default-` prefix is required, HD-149)."
        )

    # 2. signing_key must reference the default self-signed cert name.
    sk = attrs.get("signing_key")
    if sk:
        inner = sk[1] if isinstance(sk, (list, tuple)) and len(sk) >= 2 else None
        if isinstance(inner, (list, tuple)) and inner and inner[0] == "name" and inner[1] != "authentik Self-signed Certificate":
            errors.append(
                f"{path.name} entry[{index}] ({entry.get('id')}): signing_key name "
                f"{inner[1]!r} — expected 'authentik Self-signed Certificate' (HD-149)."
            )

    # 3. sub_mode must be hashed_user_id.
    if attrs.get("sub_mode") and attrs["sub_mode"] != "hashed_user_id":
        errors.append(
            f"{path.name} entry[{index}] ({entry.get('id')}): sub_mode "
            f"{attrs['sub_mode']!r} — expected 'hashed_user_id' (HD-149)."
        )


def main() -> int:
    if len(sys.argv) > 1:
        paths = [Path(a) for a in sys.argv[1:]]
    else:
        # Default: the repo's ks-oidc.yml blueprint (and any sibling blueprints).
        base = (
            Path(__file__).resolve().parent.parent
            / "IaC/ansible/templates/docker_services/authentik/blueprints"
        )
        paths = sorted(base.glob("*.yml")) if base.exists() else []

    if not paths:
        print("error: no blueprint files found", file=sys.stderr)
        return 1

    all_errors: list[str] = []
    for p in paths:
        errs = check_blueprint(p)
        if errs:
            all_errors.extend(errs)
            print(f"FAIL {p}")
            for e in errs:
                print(f"  - {e}")
        else:
            print(f"PASS {p}")

    if all_errors:
        print(f"\n{len(all_errors)} error(s) — see above", file=sys.stderr)
        return 1
    print("OK: all blueprints valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
