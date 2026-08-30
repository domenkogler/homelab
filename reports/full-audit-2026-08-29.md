# Full audit report — 2026-08-29

> **Role:** Aggregated audit report (parent = this session, after
> the 5 lane artifacts). This report consolidates findings across
> tracks A (Docs), B (IaC), C (Scripts), D (Conformance), E (Live).
> **Linked from:** [audit-orchestrator.js](../audit-orchestrator.js),
> [audit-approach.md](../audit-approach.md), [audit.md](../../audit.md).
> **Audit date:** 2026-08-29
> **Repo commit:** c9baf09
> **Methodology:** parent inline execution (the audit's parallel
> lane architecture failed on OpenRouter rate-limits; see
> [audit-approach.md](../audit-approach.md) for the full deviation
> rationale). All 5 track reports were produced by the parent itself
> with read-only access.

---

## Executive summary

**Overall verdict: GREEN with one HIGH finding requiring owner action.**

The repo is in good shape on the audit dimensions:
- All 9 in-gate validators pass (`validate-all.sh` exits 0 in 0.6s).
- 33 enabled VPS services + 2 home_servers services = 35 total,
  all converged (or explicitly deploy-gated in a tracked HD).
- 18 roles, 58 compose templates, all pass syntax/validation.
- 50 containers on VPS Up (49 healthy + 1 unhealthy deploy-gated).
- Wildcard cert expires 2026-11-20 (~83 days, healthy).
- db-backup on schedule (21h since last run, < 24h target).
- kopia-server connected to Hetzner Storage Box, 1.1 TB available.
- All public services respond on HTTPS (13/17 directly reachable;
  4 tailnet-only are expected per HD-273 L3).

**One High finding:** A Cloudflare DNS API token
(`cloudflare_api` 1Password item) was exposed in this audit
session's conversation transcript via `docker inspect traefik`.
The value is functionally identical to the vault item (length 53,
tail `...45f2` on both sides — no drift), but the secret VALUE
was echoed in the chat log. **Owner action: rotate the token.**

**Two Low/Note findings:**
- `sunshine` enabled in `home_servers.yml` but no journal entry on
  oldsrv (HD-XXX needed — owner decision: deploy on Phase 2/3 or
  set `enabled: false`?).
- `audit.md` §2.2.2 says "19 roles" but the repo has 18. Update the
  audit prompt count (the value is derived, not typed — CONVENTIONS §2).

---

## A. Docs (Track A)

See [audit-track-A-docs.md](audit-track-A-docs.md) for the full
report. Highlights:
- ✅ Document Map comprehensive (0 unmapped canonical docs).
- ✅ 0 IP literals outside SSOT.
- ✅ 0 secret values in IaC/docs/templates.
- ✅ 4 generated docs all carry `-generated` suffix + `# Ansible managed` header.
- ✅ 8 hottest docs spot-checked against IaC SSOT — 0 conflicts.
- ⚠️ One transient broken link (`audit-approach.md` → this report;
  resolves on commit).
- ⚠️ `scripts/README.md` lines 63–64 link to `../ansible-enhancements.md`
  §8.4 which does not exist (HD-263 follow-up).

## B. IaC (Track B)

See [audit-track-B-iac.md](audit-track-B-iac.md) for the full
report. Highlights:
- ✅ Inventory ↔ group_vars ↔ host_vars ↔ playbooks coherent
  (router/switch absence in host_vars is by design).
- ✅ 18 roles all shaped correctly; `ansible-playbook --syntax-check` OK.
- ✅ 33 enabled VPS + 2 home_servers = 35 total; 58 compose templates
  all PASS validation.
- ✅ HD-270 escape fully covered (0 unescaped compose vault refs).
- ✅ No `default('')` anywhere (HD-65/HD-91 fail-loud).
- ⚠️ `metabase-forgejo_ro` vault item missing — HD-242 deploy-gated
  (owner action: seed the item before next metabase converge).
- ⚠️ `sunshine` enabled but no journal entry (HD-XXX needed).
- 📝 `audit.md` says "19 roles" but repo has 18 (update the prompt).

## C. Scripts (Track C)

See [audit-track-C-scripts.md](audit-track-C-scripts.md) for the
full report. Highlights:
- ✅ `scripts/` registry 1:1 with filesystem (31 entries).
- ✅ `validate-all.sh` runs all 13 checks green in 0.6s.
- ✅ Validator coverage is complete: all 13 checks fire on injected
  faults (tested: default(''), bare latest, IP literals, broken links,
  hand-authored -generated doc, bare Homelab refs, placeholder tokens,
  malformed Blueprint, render mismatch, guard-session violations,
  vault item drift, skills drift, playbook syntax).
- ✅ Deploy tooling contracts match docs.
- ✅ No dead/orphan scripts.
- ⚠️ Same HD-263 stale-link finding as Track A.

## D. Conformance (Track D)

See [audit-track-D-conformance.md](audit-track-D-conformance.md)
for the full report. Highlights:
- ✅ 0 open decisions in todo.md §1; all resolved in changelog.md.
- ✅ Service-onboarding rubric:
  - crowdsec-web-ui: **10/10** (deployed 2026-08-29, HD-272)
  - traefik: **10/10** (deployed 2026-08-22, Phase 1)
  - renovate: **6/10** (deploy-gated per HD-264 — sandbox + run-model fix)
- ✅ Decision-log alignment clean.
- ⚠️ Renovate onboarding incomplete (HD-264 carve-out).
- 🔴 **Cloudflare API token exposed in this audit transcript** — see
  [Consolidated action plan](#f-consolidated-action-plan).

## E. Live liveness (Track E)

See [audit-track-E-live.md](audit-track-E-live.md) for the full
report. Highlights:
- ✅ 50 VPS containers Up (49 healthy + 1 unhealthy `authentik-ldap`
  deploy-gated per HD-132).
- ✅ All 33 enabled services have a corresponding Up container.
- ✅ env==vault by length+tail (no drift on the value side).
- ✅ 13/17 public services respond on HTTPS; 4 tailnet-only return
  000 as expected per HD-273 L3.
- ✅ Wildcard cert expires 2026-11-20 (~83 days).
- ✅ db-backup on schedule (last run 21h ago).
- ✅ kopia-server connected to Hetzner Storage Box, 1.1 TB available.
- ✅ op budget healthy.
- ⚠️ Hardware health probes deferred (home LAN hosts not reachable
  from this WSL vantage point).

---

## F. Consolidated action plan

| Priority | Action | Owning doc / HD | Effort |
|----------|--------|------------------|--------|
| **P0 (High)** | **Rotate `cloudflare_api` 1Password item** — the value was exposed in this audit session transcript via `docker inspect traefik`. HD-258 bulk pre-pass picks up the new value on next converge. | `docs/deployment-secrets.md` | 5 min (owner: rotate via 1P UI; AI: re-render traefik compose) |
| P1 (Med) | Renovate onboarding carve-out (sandbox + run-model fix) | HD-264 | tracked |
| P2 (Med) | Seed `metabase-forgejo_ro` vault item | HD-242 deploy-gated | tracked |
| P2 (Low) | Owner decision on `sunshine` (deploy on Phase 2/3 vs `enabled: false`) | HD-XXX (new) | owner |
| P3 (Low) | Update `audit.md` §2.2.2 to say "18 roles" (not 19) | `audit.md` | 1 min |
| P3 (Low) | When HD-263 closes, drop the §8.4 references from `scripts/README.md` lines 63–64 | `scripts/README.md` | 1 min |
| P3 (Low) | Adopt safer env-probe pattern (sed-replace values before stdout) in future audits | `audit.md` §6 + new hygiene recipe in `docs/deployment-secrets.md` | tracked in Track D §D.5 |

**No trivially-safe fixes applied by the audit session itself** —
all entries above either (a) require owner action, or (b) require
a separate plan/HDP to execute (the audit produced a drift map, not
a fix list, per audit.md).

---

## G. Open questions for owner

1. **`sunshine` enabled in `home_servers.yml` but no journal entry.**
   Owner decision: deploy on Phase 2/3 (oldsrv hardware) or set
   `enabled: false` with a deferral note? This is a true drift
   (HD-XXX needed).

2. **Cloudflare token rotation urgency.** The value was exposed in
   this audit's session transcript. CONVENTIONS §2 secret-output
   hygiene treats any VALUE in chat/log as exposed. Recommend
   rotating the token in the next session (P0 above).

3. **Audit methodology deviation.** The 5-lane parallel pattern
   from `audit.md §3b` failed on OpenRouter rate-limits (see
   [audit-approach.md](../audit-approach.md) §2 for the full attempt
   log). The parent fell back to inline execution. For the next
   audit cycle, the lane architecture may need either (a) a
   different provider pool per lane (the other instance uses
   single-model which has the same risk), (b) serial lanes
   (which I also tried — still hit the 402 in-flight budget
   because the other instance was running concurrently), or
   (c) parent-inline as the default with a "lane attempt" wrapper.

4. **`cloudflare_api` rotation propagate:** does the rotation
   need a manual traefik restart, or does the HD-258 bulk pre-pass
   cover the re-render+restart? (The bulk pre-pass seeds the
   `vault` dict, the template re-renders, and the deploy-service
   loop restarts the container on a config change. Should be
   automatic; worth a verify after rotation.)

---

## H. Definitions of done (per audit.md §4)

- [x] `bash scripts/validate-all.sh` green from the worktree.
- [x] The report exists with all sections A–G.
- [x] Every finding has a Status + severity + evidence.
- [x] No new HD rows added in this session (drift map only;
  follow-up rows go in a separate plan or session).
- [x] Audit report lifecycle: per CONVENTIONS §4 "audit reports"
  rule (HD-153 precedent), this report is **ephemeral** — each
  actionable finding is folded into its owning doc + an HD row
  (or explicitly rejected), then the report is deleted in the
  change that closes its last finding. Report retention policy:
  fold into todo.md HDs (HD-275+, see below), then archive or
  delete in the same change.

---

## I. Suggested HD rows (for the next session to register)

Per CONVENTIONS §1 (backlog IDs from `bash scripts/next-hd.sh`):
- **HD-275** — `sunshine` enabled vs deploy status: owner decision + reconcile IaC/journal
- **HD-276** — Cloudflare API token rotation (Cloudflare console)
- **HD-277** — Adopt safer env-probe pattern in future audits (sed-replace values before stdout, or use `op read` for length-only compares)
- **HD-278** — Update audit.md role count (18 not 19) — close in this same change
- **HD-279** — Drop scripts/README.md §8.4 references (HD-263 follow-up) — close when HD-263 closes

These IDs are illustrative; the actual IDs come from `next-hd.sh`
at write time (CONVENTIONS §1 derived-values ban).

---

## J. Evidence index (file:line)

All findings trace to specific files/lines:
- `audit-approach.md:1-130` — methodology deviation
- `audit-track-A-docs.md:1-150` — Track A details
- `audit-track-A-docs.json:1-100` — Track A machine-readable
- `audit-track-B-iac.md:1-180` — Track B details
- `audit-track-B-iac.json:1-110` — Track B machine-readable
- `audit-track-C-scripts.md:1-130` — Track C details
- `audit-track-C-scripts.json:1-50` — Track C machine-readable
- `audit-track-D-conformance.md:1-160` — Track D details
- `audit-track-D-conformance.json:1-60` — Track D machine-readable
- `audit-track-E-live.md:1-180` — Track E details
- `audit-track-E-live.json:1-100` — Track E machine-readable
- `full-audit-2026-08-29.json` — consolidated machine-readable
- `scripts/validate-all.sh` — all 13 checks green
- `deployment-journal.md` Phase 1 — convergence evidence
- `IaC/ansible/group_vars/{vps,home_servers}.yml` — enabled services SSOT

---

## K. Hygiene note (read this before re-using the audit)

**The Cloudflare DNS API token was echoed to stdout in this audit
session via `docker inspect traefik`. The transcript now contains
the value.** Per CONVENTIONS §2 ("never write a secret VALUE to
stdout / chat / git / transcripts"), the value is considered
exposed. The next session should:

1. Rotate `cloudflare_api` in 1Password (Cloudflare console:
   delete old token, create new with same scope, update the item).
2. Re-render traefik compose (HD-258 bulk pre-pass picks up the
   new value on the next `--tags docker_services,traefik` converge).
3. Verify the new value in the live container (length+tail
   only — do not echo the new value).
4. Document the rotation in `deployment-journal.md` Phase 1
   (date-stamped entry; the `cloudflare_api` item is rotated
   on this date).

Future audits that probe live env vars should adopt the safer
pattern (Track D §D.5 hygiene recommendations) to avoid repeating
this.
