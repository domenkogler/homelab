# prompt-hd190 — Overlay header-trust hardening (S15/S16)

> **Role:** Task handoff for **HD-190** (todo.md §2.8). **Linked from:** [todo.md](todo.md);
> audit evidence: `security.md` §5 S15/S16; precedent: HD-81/KOPS-039 (the same fix for HA).

## Problem

Two services trust spoofable headers from anywhere on the `traefik-public` overlay. Any compromised
container on that network can bypass Traefik and speak to them directly:

1. **Authentik** — `AUTHENTIK_TRUSTED_PROXIES: "{{ traefik-public CIDR }}"` (the whole /16).
   Spoofed `X-Forwarded-For` poisons client-IP decisions: rate-limit views, logs, and any future
   "internal network → skip MFA" conditional-access rule.
2. **Grafana** — `GF_AUTH_PROXY_HEADER_NAME: X-authentik-email` + `GF_AUTH_PROXY_AUTO_SIGN_UP: "true"`.
   A forged email header on a direct `grafana:3000` overlay request auto-creates an account
   (admin if it matches the admin email). The route's forward-auth only protects the edge path.

## Fix pattern (established by HD-81 for HA)

Pin the exact Traefik edge container IP(s) instead of the /16:

1. Add a group_var (e.g. `traefik_edge_ips`, list) in `group_vars/all.yml` with a comment: fill the
   per-host traefik-public bridge default IP (`.2`) at deploy — same contract as `ha_trusted_proxies`
   (see `smart-home-failover.md` / `all.yml` for the existing shape and the "verify at deploy" note).
2. Authentik: `AUTHENTIK_TRUSTED_PROXIES: "{{ traefik_edge_ips | join(',') }}"`.
3. Grafana: switch the proxy auth to a **signed** header — Authentik forwards `X-authentik-jwt`;
   configure Grafana `auth.proxy` with `header_name: X-authentik-jwt` + JWKS validation
   (`jwt_auth_claim` = email; Grafana OSS supports `jwks_url` via `[auth.proxy] jwt_config_path`… —
   verify against the pinned Grafana version's docs and adjust; if OSS lacks JWT validation in that
   version, fall back to `GF_AUTH_PROXY_AUTO_SIGN_UP: "false"` + explicit user mapping and note the
   residual risk).
4. Both templates: update the header comments (why /32-pinning; HD-81 precedent).

## Steps

1. Implement per above; keep `GF_SECURITY_ADMIN_USER/PASSWORD` bootstrap fallback as-is.
2. `bash scripts/validate-all.sh` green.
3. todo HD-190 ✅ IaC with `⏳ Deploy-gated:` tail: "verify real edge container IPs at first deploy;
   forged-header request from a sibling container must be rejected (401/403)".
4. changelog row; strike S15/S16 in the audit trail by linking the row (reports are ephemeral — the
   todo/changelog entries are the durable record).

## Constraints

- No IP literals (derive/parametrize; `check_doc_ips` gate).
- Don't break the Authentik forward-auth flow for edge routes — the forward-auth outpost callback
  path (`/outpost.goauthentik.io/`) must keep working from Traefik.

**Cleanup:** delete this handoff (`prompt-hd190.md`) in the same closing change (A3 lifecycle, CONVENTIONS §4; HD-203 sweeps any leftovers).
