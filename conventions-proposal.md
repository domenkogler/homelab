# Conventions Changes — Proposed Additions & Amendments to `CONVENTIONS.md`

> **Role:** Proposal — changes to the cross-cutting conventions registry (`CONVENTIONS.md`) plus new conventions.
> **Pairs with:** `docs-vs-iac.md` (drift to prevent), `docs-changes.md`, `iac-changes.md`.
> **Convention:** each proposal is additive or a clarifying amendment; the owning doc remains authoritative where stated.

---

## P0 — close the drift classes found in the audit (prevent recurrence)

### A. Amend §1 (Naming) — [NEW] "generated-doc + count claims must not be hand-maintained"
Amend the *"Generated docs never hand-edit"* row (§1 Values & SSOT / §2) to add a **new rule**:

> **Convention:** any doc-stated **count** (templates, roles, files, services) must be **derived**, not hand-entered; quote the validator/dir as the source (`scripts/validate-docker-services.py` for templates, `roles/` dir for roles). A stale *number in prose* is a real defect, not a cosmetic one.

**Owner:** `docs/index.md` (Validation) + `scripts/validate-all.sh`. **Why:** the audit found the "41/42/48 templates" and "15/20 roles" claims drifted (§3/§4 docs-vs-iac); a rule makes the next author not re-handwrite a count.

### A2. §2 Values & SSOT — [AMEND] S3/Multi-backend elimination is a live rule
Amend the *"Service list → group_vars + services.md"* row to add:

> **Convention:** when a **storage/media backend decision is made in IaC** (e.g. MinIO retired, Immich originals → live Box CIFS), the **owning service + storage docs must be updated in the same change** — a data-location claim left in prose that contradicts the IaC is a review failure.

**Owner:** `docs/storage-zfs.md`, `docs/services.md`, `docs/deployment-compose.md`. This directly prevents the S3/MinIO re-drift (docs-vs-iac §1).

---

## P1. Proposed new / strengthened conventions

### B1. [NEW] §7 — Version-pin hygiene becomes an explicit rule
Current §3 has *"pinned tags"*. Strengthen:

> **Convention (version pins):**
> 1. Every `*_version` pin lives in **one** file — the proposed `group_vars/versions.yml` — **not** spread across `all.yml` (see `iac-changes.md` #7). Renovate's docker datasource + a version review are single-sheet.
> 2. A pin is **never bare `latest`** and never a *mutable alias* (`-rocm`, `main-stable`) **unless** the owning doc records an explicit MUST-pin + verified-semver precondition (Tuwunel / OpenClaw / LiteLLM fluid-tag precedents, HD-121/134).
> 3. On a fluid-tag *first* pin, show the registry-verified tag + Renovate tracking in the same change.

**Owner:** `deployment-compose.md`, `deployment-renovate.md`, `group_vars/versions.yml` (new).

### C. [NEW] §8 — "Deploy-gated" is also a Docs-Gate (two-sided gate)
The existing §4 already has the **⏳ Deploy-gated** lifecycle rule for `todo.md`. Strengthen it to cover **documentation gating**:

> **Convention (two-sided deploy gate):** a service/component whose IaC is "done but not live" is **⏳ deploy-gated in `todo.md` AND its owning doc must carry the same `⏳` marker** (what exactly is unprovisioned, which 1Password item, which live-verify step). A doc for a not-live service can say "designed" but **must say "not yet live — ⏳ deploy-gated"**, never present itself as deployed.

**Why:** the audit found several **design-spec .md files that read as if the service existed** (README "five interfaces", `services-authentik.md` SSO flows) while the repo is in planning phase — the docs must visibly say "planned, ⏳ deploy-gated", not "live".

### C. [NEW] §9 — "VPS/oldsrv split" as a cross-cutting placement convention
- Add to §1/§2 a **short placement convention**: services are split **VPS (public edge / live-data / observability backend / GitOps) vs oldsrv (GPU / LAN / storage-bound)** + nas (ZFS storage) + pi (HA primary + DNS secondary). Point to `docs/services.md` + `services-vps.md` as owner.
- **Why:** the audit's two biggest crosses (S3, observability location) both stem from this split; making it an explicit §1 naming/placement rule reduces future drift.

### D. [NEW] §10 — "validate-all as the do-not-commit gate" (formalize commit law + doc-lint)
The repo already runs `scripts/validate-all.sh` before commit; the audit recommends **extending it** with:
1. **Doc-map reconciliation** — flag every on-disk `docs/*.md` missing from `docs/index.md` map.
2. **Count-lint** — assert any doc-claimed role/template count matches (or suppress).
3. **Secrets-lint** — grep group_vars/templates for literal-looking credentials (`validate-secrets.py`, `iac-changes.md` #8).

**Rule:** `validate-all.sh` green (incl. the new lints) is the **pre-commit / pre-deploy-gate** bar; a docs-claim is not "nice to fix", it's a lint failure.

---

## P2. Amend existing rows

### E. §5 Service-onboarding — add a "storage/data-location" step
The existing 10-step checklist omits a **storage/backup** bullet that would have caught the MinIO→CIFS drift. Recommend inserting (renumbering optional) after step 6 (State & backups):

> **6.5. Storage/data location** — state where the service's big data lives (NAS ZFS dataset / VPS NVMe / live Box CIFS / WebDAV / S3) **in the owning doc**, consistent with the user the storage-SSOT (`storage-zfs.md`). If a storage decision changes, update IaC + owning doc **in the same change** (rule A2).

### F. §2 (Values & SSOT) — "no server-type secret" already documented
No change needed; reconfirm `deployment-secrets.md`'s *Config vs credential split* (no `server` type) stays authoritative — keep the convention as-is.

### G. §6 Cross-cutting — language/headers/links unchanged
Keep the "English technical / Slovenian family" + relative-links + headers rules as-is (no change). Suggest adding **one** line to headers convention:

> Every architecture/hardware doc's header `Role:` already carries ★ for design-spec — **reconfirm** the ★ marks value-carrying/reference docs and that nothing generated is hand-edited.

---

## Summary of convention proposals

| Ref | Change | Type | Owner |
|-----|--------|------|-------|
| A1 | counts live, never hand-entered | new global rule | index.md, validate-all |
| A2 | data-location drift = same-change rule | new global rule | storage-zfs/services/compose |
| B | version-pin hygiene (one file, no mutable alias) | new §7 | deployment-compose/renovate, versions.yml |
| B2 | deploy-gate is two-sided (todo + docs must say not-live) | amend §4 | todo.md, all design-spec |
| C | placement convention (VPS/oldsrv/nas/pi) | new §1 rule | services.md, services-vps.md |
| D | validate + doc/secret-lint = commit gate | new §6 provision | scripts/validate-all.sh |
| E | service-onboarding storage bullet (6.5) | amend §5 | CONVENTIONS.md §5 |
| G | header/★ reconfirm | amend §6 | index.md |