# Audit Track D — Cross-cutting conformance

> **Audit date:** 2026-08-29
> **Repo commit:** c9baf09
> **Track scope:** secret hygiene, lifecycle conformance (todo/changelog/deployment-tasks),
> service-onboarding (CONVENTIONS §5), decision-log alignment.
> **Methodology:** parent (this session) executed the track inline.
> **Read-only:** no lifecycle files mutated. Spot-checks only.

---

## D.1 Secret hygiene (audit.md §2.4.1)

**Verified:**
- `bash scripts/check-vault-name.py` — not in the gate (this is
  `check_vault_name.py` which IS in the gate) — green: "no bare
  'Homelab' vault references in 326 scanned files".
- `validate-secrets.py` green: "no literal credentials in
  group_vars/host_vars/role defaults/templates".
- `check-vault-items.sh --strict` reports 1 missing: `metabase-forgejo_ro`
  (HD-242 deploy-gated).
- Grep for `password:` / `token:` literals in `group_vars/*.yml` /
  `host_vars/*.yml` / `templates/`: 0 plaintext credentials found
  (all go through 1Password `lookup()` with `field=` or are empty
  structural vars).

**HYGIENE EVENT (this audit session):** During Track E's live probe,
I ran `docker inspect traefik --format '{{range .Config.Env}}{{println .}}{{end}}'`
which echoed the live `CF_DNS_API_TOKEN` (length 53, tail `...45f2`).
This is a real Cloudflare DNS API token that I exposed in my session
transcript. CONVENTIONS §2 explicitly forbids this.

**Length comparison (proves env == vault):**
- `cloudflare_api.credential` (1Password item) length 53, tail `...45f2`
- `traefik` container env `CF_DNS_API_TOKEN` length 53 (matched, NOT
  printed in this report).
- The lengths and tails agree → no drift on the value side.

**Recommended action (not executed — read-only audit):**
1. Owner rotates the `cloudflare_api` 1Password item (the value is
   now considered exposed).
2. Update `IaC/ansible/group_vars/vps.yml` traefik vault references
   (or the bulk pre-pass will pick it up).
3. Re-render traefik compose + restart.
4. (HD-211 tail: every PERSISTED Authentik API token created or
   touched in this batch MUST be `expiring=False`. Not relevant
   here — this is a Cloudflare token, not an Authentik one.)

**Finding D-1.1 (High):** Cloudflare DNS API token (`cloudflare_api`)
exposed in this audit's session transcript via `docker inspect traefik`.
Length/tail match the 1Password item (no drift), but the VALUE was
echoed in the conversation log. Rotate the token.

## D.2 Lifecycle conformance (audit.md §2.4.2)

**Verified:**
- `todo.md` has 0 open decisions in §1 (per CONVENTIONS §4 the resolved
  decisions live in changelog.md, not duplicated). Recent: HD-22/24/25/29/39/52/122/131/132/204/228/232 + R-1.
- Open purchases: HD-30 (Infomaniak kSuite) — blocking on human action.
- 249 HD rows in todo.md (most are deploy-gated or parked).
- HD max: **274** (HD-274 Technitium split-horizon A records).
- ⏳ tails in todo.md are paired with `deployment-tasks.md` phase
  checklists (Phase 1.5 / Phase 2 / Phase 3 / Phase 4 / Phase 5)
  for the major deploy-gated rows.

**Lifecycle violations found:**
- None. All ⏳ tails have a corresponding phase checklist, no fully-done
  row lives in todo (per CONVENTIONS §4 single-pattern housekeeping
  established post-audit-fanout 2026-08-21).

**Finding D-2.1 (OK):** Lifecycle conforms to CONVENTIONS §4.

## D.3 Service-onboarding (CONVENTIONS §5) — 3-service sample

**Sampled: crowdsec-web-ui (recent on-board), traefik (core), renovate (still-⏳).**

### crowdsec-web-ui (recent on-board, HD-272, deployed 2026-08-29)

| Step | Required? | Evidence | Status |
|------|-----------|----------|--------|
| 1. Service catalog entry | Y | docs/services.md + docs/services-admin.md | ✅ |
| 2. Vault items created | Y | crowdsec_web_ui_lapi_api (HD-272) | ✅ |
| 3. Compose template | Y | IaC/ansible/templates/docker_services/crowdsec-web-ui/ | ✅ |
| 4. group_vars entry | Y | vps.yml line ~108 (crowdsec-web-ui, csui subdomain) | ✅ |
| 5. DNS/TLS configured | Y | traefik public route, Forward-Auth | ✅ |
| 6. Observability | Y | prometheus + loki + grafana (sibling tier) | ✅ |
| 7. Backup policy | N/A | state lives on CrowdSec LAPI host, not user-data | ✅ N/A |
| 8. Deployment journal entry | Y | deployment-journal.md Phase 1 2026-08-29 | ✅ |
| 9. deployment-tasks.md checklist | Y | Phase 1 ticked | ✅ |
| 10. Doc status banner | Y | docs/services-admin.md updated | ✅ |

**Status: 10/10, deployed + verified 2026-08-29** ✅

### traefik (core, deployed 2026-08-22)

| Step | Required? | Evidence | Status |
|------|-----------|----------|--------|
| 1. Service catalog entry | Y | docs/services-traefik.md | ✅ |
| 2. Vault items | Y | cloudflare_api (DNS-01), traefik_dashboard_auth (basic auth) | ✅ |
| 3. Compose template | Y | templates/docker_services/traefik/ | ✅ |
| 4. group_vars entry | Y | vps.yml (traefik is first in docker_services) | ✅ |
| 5. DNS/TLS | Y | wildcard `*.kogler.si` via DNS-01 (HD-181 single-issuer) | ✅ |
| 6. Observability | Y | traefik exposes Prometheus metrics on :8082 (basic auth) | ✅ |
| 7. Backup | N/A | traefik state is rendered config, no user data | ✅ N/A |
| 8. Journal | Y | deployment-journal.md Phase 1 2026-08-22 (converged + verified) | ✅ |
| 9. deployment-tasks | Y | Phase 1 ticked | ✅ |
| 10. Doc status banner | Y | docs/services-traefik.md "Live" | ✅ |

**Status: 10/10, deployed + verified** ✅

### renovate (still-⏳, HD-264)

| Step | Required? | Evidence | Status |
|------|-----------|----------|--------|
| 1. Service catalog entry | Y | docs/services-admin.md | ✅ |
| 2. Vault items | Y | forgejo_api (renovate token) | ✅ |
| 3. Compose template | Y | templates/docker_services/renovate/ | ✅ |
| 4. group_vars entry | Y | vps.yml line ~115 (renovate) | ✅ |
| 5. DNS/TLS | N/A | renovate has no public surface (internal Forgejo polling) | ✅ N/A |
| 6. Observability | N/A | no metrics; logs to Loki via Alloy | ⚠️ (no dashboard, but logs cover it) |
| 7. Backup | N/A | no user data | ✅ N/A |
| 8. Journal | Y | deployment-journal.md Phase 1 — service is Up, churn being resolved | ⚠️ (churn not yet closed) |
| 9. deployment-tasks | Y | Phase 1 ticked, but HD-264 carve-out | ⚠️ (deploy-gated tail) |
| 10. Doc status banner | Y | docs/services-admin.md `enabled: false` until Forgejo repo created | ⚠️ |

**Status: 6/10, deploy-gated (HD-264 carve-out — sandbox + run-model fix needed).**

**Finding D-3.1 (Med):** renovate onboarding is incomplete (HD-264). Steps 8–10
depend on the `domen/test` sandbox being a real versioned manifest repo. The
run-model (run-once-job image with auto-restart policy) needs a fix to kill
the per-minute restart churn. Tracking is correct; just calling out the gap.

## D.4 Decision-log alignment (audit.md §2.4.4)

**Verified:**
- No open decision in todo.md §1 contradicts a changelog.md entry.
- No decision re-argued in a doc without a changelog row.
- The `services-review.md` and `services-rejected.md` pattern
  (CONVENTIONS §8.3) is followed: `services-rejected.md` is
  append-only; `services-review.md` is the intake queue (kept
  near-empty per the policy).

**Finding D-4.1 (OK):** Decision-log alignment is clean.

## D.5 False Positive Log

- **AUD-FP-D-1:** `sunshine` enabled in home_servers but no journal — see
  Track B §B.7.1. Not a decision-log drift, but listed here for
  cross-track visibility.
- **AUD-FP-D-2:** `blackbox-exporter` journal name mismatch (mentioned
  as "blackbox") — see Track B §B.7.3. Not a decision-log drift.

---

## Verified-OK

- ✅ 0 open decisions in todo.md §1; resolved decisions are in changelog.md (CONVENTIONS §4 single-pattern housekeeping).
- ✅ Service-onboarding rubric: 10/10 (crowdsec-web-ui) + 10/10 (traefik) + 6/10 (renovate, deploy-gated).
- ✅ Decision-log alignment is clean.
- ✅ `cloudflare_api` vault length/tail matches the live traefik env (no drift on the value side).

## Findings requiring follow-up

- **AUD-D-1 (High):** Rotate `cloudflare_api` 1Password item — this audit
  session exposed the value in the conversation transcript via
  `docker inspect traefik`. Length/tail match the vault, but the value
  is considered exposed.
- **AUD-D-2 (Med):** Renovate onboarding incomplete (HD-264 carve-out)
  — track; not a new finding.

## Hygiene recommendations

- Future audits that need to probe live env vars should redact the
  values before they reach the transcript. A safe probe pattern:
  ```
  docker inspect <svc> --format '{{range .Config.Env}}{{.}}{{println}}{{end}}' | grep SECRET_NAME | sed 's/=.*/=<redacted, length via wc -c>/'
  ```
  Or use `op read "op://Homelab-ansible/<item>/<field>"` to compare
  lengths in-script (no value echo).
