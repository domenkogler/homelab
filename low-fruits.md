# Low-Hanging Fruit — Highest ROI Changes

> **Source:** Architecture audit findings from `Qwen-architecture.md`.
> **Philosophy:** Changes where minutes of work eliminate an entire class of problems.

---

## 1. Split CrowdSec out of the Forward-Auth chain

**What:** `middlewares.yml.j2` bundles CrowdSec + Authentik into one middleware chain. Six public-facing services skip this chain because they have their own auth — and inadvertently lose CrowdSec too.

**Fix — add to `middlewares.yml.j2`:**
```yaml
http:
  middlewares:
    crowdsec-only:
      chain:
        middlewares:
          - crowdsec-bouncer
```

Then apply `crowdsec-only@file` to every route that skips Forward-Auth:
- `ha.kogler.si` (HA native auth) — KOPS-004
- `media.kogler.si` (Jellyfin login) — KOPS-018
- `seerr.kogler.si` (Seerr login) — KOPS-047/048
- `matrix.kogler.si` (Matrix-native OIDC) — KOPS-018
- `chat.kogler.si` (Element Web, homeserver SSO) — KOPS-025
- HA standby via VIP — KOPS-018

**Effort:** ~30 min (edit `middlewares.yml.j2`, add middleware label to 6 compose templates)
**Impact:** Every internet-facing login surface with its own auth immediately gets community blocklist filtering + behavioral detection. Closes 6 KOPS findings at once. Cost is zero — CrowdSec container already runs.

---

## 2. Pin Traefik version

**What:** `traefik_version: latest` in `group_vars/all.yml`.

**Fix:** One line:
```yaml
traefik_version: "v3.3"   # or current stable minor
```

Same pattern for every service with `| default('latest')` in compose templates. Set explicit versions in group_vars instead. Also pin Ollama from mutable `rocm` tag → `0.6.x-rocm` (KOPS-027).

**Effort:** ~5 min
**Impact:** Traefik is the single ingress point for all public and internal services. With `latest`, any Docker daemon restart pulls whatever revision was just published — breaking changes or supply-chain incidents silently deploy to your entire edge. Pinning makes Renovate actually useful for your most critical service. KOPS-005/013.

---

## 3. Remove Signal CLI host port binding

**What:** `signal-cli-rest-api/docker-compose.yml.j2` maps `"8080:8080"` on `0.0.0.0`. The comment says "not exposed publicly" but that only means not internet-facing. Any device on Home VLAN can reach it.

**Fix:** Delete the host port mapping. n8n reaches Signal via Docker overlay network hostname.

```yaml
ports:
  # - "8080:8080"      ← DELETE THIS LINE
```

Apply same review to:
- Prometheus `"9090:9090"` → bind loopback `"127.0.0.1:9090:9090"` (KOPS-017)
- Sunshine game-streaming ports → restrict to Home VLAN IP (KOPS-007)
- Technitium DNS `"53:53"` → bind to specific VLAN IPs (KOPS-015/049)

**Effort:** ~10 sec per service
**Impact:** Eliminates LAN-level impersonation via Signal REST API (social engineering against family contacts), infrastructure intelligence leakage from Prometheus, and open-resolver amplification from Technitium. KOPS-002/017/007/015.

---

## 4. Uncomment immich DB backup

**What:** In `db-backup/docker-compose.yml.j2`, the Immich postgres block (DB03+) is commented out. OpenCloud backup approach also missing.

**Fix:** Uncomment DB03 block, correct hostname to `immich-postgres`. For OpenCloud: add tar of `/var/lib/opencloud` data dir (embedded DB, not external Postgres).

**Effort:** ~2 min
**Impact:** If Immich's Postgres dies, originals survive on ZFS but all albums, face recognition results, labels, smart-search embeddings, and timeline organization are lost irretrievably. Re-importing originals does NOT reconstruct metadata. Two minutes of uncommenting vs days of manual reconstruction. KOPS-026.

---

## 5. Fix Loki schema date

**What:** `loki/loki.yaml.j2` has `from: 2026-01-01`. Loki silently drops ALL logs until that date.

**Fix:** Change to `from: "2025-01-01"` (or use Jinja2 `{{ ansible_date_time.date }}`).

```yaml
schema_config:
  configs:
    - from: "2025-01-01"
      store: tsdb
```

**Effort:** 4 characters
**Impact:** Complete observability black hole until January 2026. Zero log collection, zero log-based alerts, zero audit trail. Almost certainly a typo — but as written you troubleshoot blind when things break in production. KOPS-050.

---

## 6. Fail loudly when secrets are missing

**What:** Pi-hole template has `| default('')` on its password lookup. If the 1Password item doesn't exist, Pi-hole deploys with no admin password. Same pattern may exist elsewhere.

**Fix:** Remove all `default('')` fallbacks on security-critical lookups. Templates should fail loudly:

```yaml
# Bad — deploys unprotected:
WEBPASSWORD: "{{ lookup('community.general.onepassword', 'pihole_password', field='password', vault=op_vault) | default('') }}"

# Good — fails if secret absent:
WEBPASSWORD: "{{ lookup('community.general.onepassword', 'pihole_password', field='password', vault=op_vault) }}"
```

For extra safety, add pre-render asserts:
```yaml
- name: Assert critical secrets exist before rendering
  fail:
    msg: "1Password item '{{ item }}' not found — refusing deploy"
  when: lookup('community.general.onepassword', item, field='password', vault=op_vault) == ''
  loop: ['pihole_password', 'kopia_password', ...]
```

**Effort:** ~15 min to audit all templates
**Impact:** Deploy-time feedback beats post-deploy discovery. You get a loud Ansible error telling you exactly which secret is missing instead of a service going live unprotected. KOPS-010.

---

## Summary by ROI

| # | Change | Time | Risk Eliminated | Files |
|---|--------|------|-----------------|-------|
| 1 | Split CrowdSec from Forward-Auth | ~30 min | Entire Flaw A class (6 internet-facing services with zero WAF) | `middlewares.yml.j2` + 6 compose templates |
| 2 | Pin Traefik version | ~30 sec | Supply-chain / silent regression on single ingress point | `group_vars/all.yml` |
| 3 | Remove Signal host port + review others | ~2 min | Account impersonation via LAN; infra intel leakage | Signal, Prometheus, Sunshine, Technitium templates |
| 4 | Uncomment immich DB backup | ~2 min | Irretrievable metadata loss on Postgres failure | `db-backup/docker-compose.yml.j2` |
| 5 | Fix Loki schema date | ~5 sec | Complete log blindness | `loki/loki.yaml.j2` |
| 6 | Remove `default('')` on secrets | ~15 min | Silent deployment of unprotected services | Multiple templates |

**Total effort: ~50 min.**
**Net result:** 6 KOPS findings eliminated, edge WAF coverage restored across all self-authenticated services, backup completeness improved, observability unblinded, LAN attack surface reduced, deploy-time feedback hardened.
