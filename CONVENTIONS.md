# Homelab Conventions (Consolidated)

> **Purpose:** one place to *find* every cross-cutting convention in the repo. Each row names the rule and
> points to its authoritative owner — domain-specific detail stays in the owning doc, **this file does not
> duplicate it** (single-SSOT principle). If a rule lives both here and in its owning doc, the owning doc wins;
> update the owning doc and keep this entry to the one-line summary.
>
> **Status:** draft consolidation (2026-08-17) — linked from `README.md` / `docs/index.md` once approved.

---

## 1. Naming

| Convention | Rule | Owning doc |
|-----------|------|-----------|
| DNS namespace | single `kogler.si`, flat subdomains, split-horizon; internal-only hosts unpublished in public DNS | `docs/index.md` (Conventions) |
| Hostnames | canonical list `oldsrv / nas / pi / router / switch / vps` — SSOT table | `docs/index.md` (Conventions, Hosts) |
| Backlog IDs | `HD-<number>` (next free = `HD-114`), 1 row = 1 outcome, link the owning `docs/*.md` | `todo.md` (§0) |
| 1Password items | `<service>_<type>`; `_` only delimiter; `-` allowed inside service; never a field in the name; `field=` mandatory in lookups | [docs/deployment-secrets.md](docs/deployment-secrets.md) (Secret Naming Convention) |
| Vault | one vault `Homelab`, referenced via `op_vault` var, never a literal | [docs/deployment-secrets.md](docs/deployment-secrets.md) |
| Service domains | service → `https://<name>.kogler.si` unless stated (service catalog SSOT) | [docs/services.md](docs/services.md) |
| Service placement | post-HD-135 plane split is a cross-cutting fact: **VPS** = public edge / live-data apps / AI stack / observability backend / GitOps · **oldsrv** = GPU / LAN / storage-bound core · **nas** = ZFS storage (no Docker) · **pi** = HA primary + DNS secondary. A service's plane + exposure is stated in its catalog row, never implied | [docs/services.md](docs/services.md), [docs/services-vps.md](docs/services-vps.md) |

## 2. Values & SSOT (never hardcode)

| Convention | Rule | Owning doc |
|-----------|------|-----------|
| IPs / CIDRs | never hardcode — `network_static_hosts` / `network_ranges` from `group_vars/*` | [docs/deployment-ansible.md](docs/deployment-ansible.md) (Variables & IPs) |
| IP doc | `docs/network-addresses.md` is the SSOT, generated, **never hand-edit** | [scripts/check_doc_ips.py](scripts/check_doc_ips.py), [docs/deployment-ansible.md](docs/deployment-ansible.md) |
| Service list | `group_vars/<host>.yml` is the deploy loop SSOT; catalog row in `docs/services.md` | [docs/services.md](docs/services.md) |
| Compose path | `/opt/<service>/docker-compose.yml` — architectural constant | [docs/deployment-compose.md](docs/deployment-compose.md) |
| Generated docs | never hand-edit ★-marked/generated docs (`inventory.md`, `network-addresses.md`) | [docs/index.md](docs/index.md) |
| Counts | doc-stated **counts** (templates, roles, files, services) are **derived, never hand-entered** — quote the validator/dir as the source (`scripts/validate-docker-services.py`, `roles/`, `docker_services/`); a stale number in prose is a defect, not a cosmetic | [docs/index.md](docs/index.md) (Validation), [scripts/validate-all.sh](scripts/validate-all.sh) |
| Data location | a storage/media **data-location change** (e.g. MinIO retired → live Box CIFS) must update IaC **and** the owning service/storage docs **in the same change** — a data-location claim in prose that contradicts the IaC is a review failure | [docs/services.md](docs/services.md), [docs/storage-zfs.md](docs/storage-zfs.md), [docs/deployment-compose.md](docs/deployment-compose.md) |

---

## 3. Code / IaC conventions

| Area | Rules | Owning doc |
|------|-------|-----------|
| Ansible roles | 1 entry point (`tasks/main.yml` → `include_tasks:`); assert admin user top; idempotent by default; tag every loop item | [docs/deployment-ansible.md](docs/deployment-ansible.md) (IaC Authoring Conventions) |
| Ansible vars | service/arch values → `group_vars/`, not role defaults | [docs/deployment-ansible.md](docs/deployment-ansible.md) |
| Ansible secrets | `lookup('community.general.onepassword', …, field=…)` only, `op_vault`, no literals | [docs/deployment-ansible.md](docs/deployment-ansible.md), [docs/deployment-secrets.md](docs/deployment-secrets.md) |
| Compose location | one dir per service under `templates/docker_services/<service>/` | [docs/deployment-compose.md](docs/deployment-compose.md) (File Location) |
| Compose networks | `external: true` (traefik-public, services-internal, db-internal) created by the role | [docs/deployment-compose.md](docs/deployment-compose.md) (Network Assignment) |
| Compose security | `cap_drop: ALL` + minimal `cap_add`, `read_only`, `tmpfs`; no host ports unless justified; internal services need auth tokens (`<service>-internal_api`) | [docs/deployment-compose.md](docs/deployment-compose.md) (Container Security), [docs/security.md](docs/security.md) (Flaw C/D) |
| Compose versioning | pinned tags (never bare `latest`) + Renovate trail | [docs/deployment-compose.md](docs/deployment-compose.md), [renovate.json](renovate.json) |
| RouterOS | management services bound to Management VLAN; bootstrap `.rsc` + Ansible role both enforce | [docs/network-ops.md](docs/network-ops.md) |
| Two-sided deploy gate | a service/component whose IaC is done **but not live** is ⏳ deploy-gated in `todo.md` **and** its owning doc must carry the same visible status block (**🔴 planned / 🟢 IaC done ⏳ / ✅ live**) — a design-spec doc for a not-live service must say "not yet live — ⏳ deploy-gated", never read as deployed | [todo.md](todo.md) (§0/§3c), [docs/security.md](docs/security.md) (Deploy-gated rows), each owning service doc |

---

## 4. Lifecycle conventions

| Phase | Rule | Owning doc |
|-------|------|-----------|
| Backlog | new work = new `HD-XX` row in `todo.md`; decisions written to owning doc; done → `changelog.md` | [todo.md](todo.md), [docs/index.md](docs/index.md) |
| Post-task housekeeping | **after each completed task, update `todo.md` in the same change** — move the done `HD-XX` row to `changelog.md`; never leave completed work marked open. **No hand-maintained tally/Status line** — the backlog count is derived from the rows themselves (counts are derived, never hand-entered, §2) | [todo.md](todo.md) (§0 lifecycle), [changelog.md](changelog.md) |
| Decisions | decisions log, date-stamped, closed once per decision (mirror `docs/security.md §7` style); **a resolved decision is written ONCE to `changelog.md` (decision-log SSOT) — do NOT leave a struck duplicate row with the full rationale in `todo.md` §1** | [docs/security.md](docs/security.md) (§7 Decision log), [changelog.md](changelog.md) |
| Onboarding a service | see the 10-step checklist below | — |
| Validation gate | `bash scripts/validate-all.sh` before commit (compose, templates, IPs, docs). **Planned extension (HD-157):** also lint the `docs/index.md` doc-map vs `find docs -name "*.md"` and any doc-claimed role/template count — a docs-claim that drifts is a lint failure, not a cosmetic | [scripts/](scripts/), [docs/index.md](docs/index.md) (Validation) |
| Deploy | first apply human-gated (dry-run → single host); single path = Ansible (Renovate PR → Forgejo Actions deploy button → Ansible) | [docs/deployment.md](docs/deployment.md) |
| Deploy-gated rows | an `HD-XX` row whose IaC is done **but not yet live** stays **open** with a **`⏳ Deploy-gated:`** tail listing the exact pending live steps (provider creation, secret seeding, firewall open, live-verify). It closes only after a live deploy/verify pass — **not** at IaC-completion. A task's ⏳ is a *phase*, never moved to a separate file | [todo.md](todo.md) (§0 lifecycle, §⏳ checklist), [changelog.md](changelog.md) |

> **Decision log format** (`security.md §7`): a dated bullet per decision: `- **Decision statement** — accepted/expected, Date: YYYY-MM-DD, *(evidence: KOPS-xx)*`.

---

## 5. Service-onboarding checklist (10 steps)

A new service must clear this path (each step's owning doc is the anchor; violations are review failures):

1. **Exposure & auth decision** — public / internal / Headscale-only; Forward-Auth vs native OIDC. Write it in the owning service doc.
   - **Native OIDC → Authentik:** declare the provider/application in the **Blueprint** (`ks-oidc.yml`),
     and let the **secret-egress glue** seed its `…_api` item. **Do not** hand-create OIDC providers in
     the Authentik UI. (Forward-Auth services need no provider at all.) [services-authentik.md](docs/services-authentik.md)
2. **Secrets** — create 1Password item(s) `<service>_<type>`; add a catalog row in `docs/deployment-secrets.md` (master list).
3. **Compose template** — `docker_services/<service>/` per `docs/deployment-compose.md` (external networks, pinned tags, no host ports unless justified, `cap_drop: ALL`).
4. **Registry** — add to `group_vars/home_servers.yml` + catalog row in `docs/services.md`.
5. **Edge (if exposed)** — Traefik route + middleware chain (`crowdsec-only`, Forward-Auth) per `docs/services-traefik.md`.
6. **State & backups** — map volumes/data into `db-backup` / Kopia scope.
6.5. **Storage / data location** — state where the service's big data lives (NAS ZFS dataset / VPS NVMe / live Box CIFS / WebDAV / S3) **in the owning doc**, consistent with the storage SSOT (`storage-zfs.md`). If a storage decision changes, update IaC + owning doc **in the same change** (data-location rule §2).
7. **Observability** — exporter / scrape target + Grafana dashboard if it's on a watchlist.
8. **Validation** — `bash scripts/validate-all.sh` green (template + group_vars both).
9. **Deploy gate** — first apply is human-gated (dry-run → single host) — no blind `docker compose up -d`.
10. **Docs** — `docs/index.md` map row + family guide (`docs/manual/`) if family-facing.

**Stage tracking:** service-onboarding rows in `todo.md` carry **`Stage: N/10`** in the bold title = current checklist step above. `10/10` = deployed + verified — a row only closes at step 10 (never at step 8 validation / step 9 deploy-gate). The checklist is the ledger in the owning service doc; `Stage: N/10` is a summary pointer, not a second ledger. Non-service tasks (network / IaC fixes / decisions) are not checklist candidates and carry no stage marker.

---

## 6. Cross-cutting rules (short list)

- Language: English (technical), Slovenian (family/manual).
- Headers: every doc starts with `> **Role:**` and `> **Linked from:**` — enforced by convention.
- Relative links only — markdown relatives to `docs/*.md`.
- Secrets never in docs — 1Password `Homelab` vault only.
- Generation targets marked with ★; value-carrying views are rendered, never hand-edited.
- **Don't chase cosmetic tweaks** during planning phase (ASCII alignment, spacing); substantive, consistent edits only.

---

## 7. Version-pin hygiene

| Rule | Owning doc |
|------|-----------|
| a `*_version` pin lives in **one** file — the proposed `group_vars/versions.yml` (HD-156) — **not** spread across `all.yml`; Renovate docker datasource + version review are single-sheet | [docs/deployment-compose.md](docs/deployment-compose.md), [docs/deployment-renovate.md](docs/deployment-renovate.md) |
| a pin is **never bare `latest`** and never a *mutable alias* (`-rocm`, `main-stable`) **unless** the owning doc records an explicit MUST-pin + verified-semver precondition (Tuwunel / OpenClaw / LiteLLM fluid-tag precedents, HD-121/134) | [docs/deployment-compose.md](docs/deployment-compose.md) |
| on a fluid-tag *first* pin, show the registry-verified tag + Renovate tracking **in the same change** | [docs/deployment-compose.md](docs/deployment-compose.md), [docs/deployment-renovate.md](docs/deployment-renovate.md) |

> Strengthens the §3 "Compose versioning" row (pinned tags, never bare `latest` + Renovate trail) — same owner, more explicit.

---

*Last review: 2026-08-19 (added: derived-counts, data-location same-change, two-sided deploy gate; placement §1, onboarding storage bullet §5, version-pin hygiene §7, validation-gate extension §4). Owning docs above remain authoritative.*