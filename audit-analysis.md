# Audit Analysis — Consolidation of the 5 Input Documents

> **Purpose:** A running, actionable work-list that drives the consolidation of the five
> input documents produced by the recent Qwen audits. Each item is an independent unit of
> work with a **difficulty** (1–5) and a **priority** (P1 = do first). Items are appended as
> the analysis progresses. For execution, select the next item **in numeric order** by the
> rule in "How to use this file" below (lowest-numbered `(pending)` whose deps are done).
>
> **Input documents (the "5"):**
> 1. `Qwen-bugs.md` — security audit (61 findings, KOPS-xxx, incremental/duplicated)
> 2. `Qwen-architecture.md` — architecture audit (6 systemic flaws, roadmap, open questions)
> 3. `low-fruits.md` — highest-ROI changes (6 concrete fixes)
> 4. `todo.md` — canonical backlog (HD-XX, the surviving single source of truth)
> 5. `deployment-tasks.md` — phase-based build-order runbook
>
> **End state this list drives toward:** the information in the two Qwen audits and
> `low-fruits.md` is fully absorbed into the canonical system (`docs/` + `todo.md` +
> `deployment-tasks.md`), the audits are deduplicated/validated/reconciled and retired as
> living documents, and the backlog is cleaned of stale/completed state.
>
> **Difficulty rubric (from `todo.md`):**
>
> | Diff | Meaning |
> |------|---------|
> | 1 | Trivial / mechanical, single file, no research, low risk |
> | 2 | Straightforward, small batch, well-specified |
> | 3 | Moderate, multi-file, some judgment, needs validation |
> | 4 | Demanding, cross-cutting, design + verification |
> | 5 | Ambiguous / high-risk / needs human gate |

---

## Recorded decisions (input — resolved 2025-08-16, already in `todo.md`)

These were settled during brainstorming **before** the audit consolidation. They resolve content
inside the audit docs, so the reconciliation items below must honor them:

- **HD-92 — oldsrv stays bare-metal Debian + Docker.** No local Proxmox / no GPU passthrough on
  the single Phase-1 box (one shared dGPU = desktop **and** AI; single host gains no HA from VMs).
  Proxmox deferred to HD-41/42 with a real 2nd node. → **AUD-03** should relabel the Proxmox
  "Final Architecture Proposal" artifact in `Qwen-architecture.md` as **REJECTED** per this
  decision (stronger than "legacy/outdated").
- **HD-93 — buy Contabo VPS before go-live; public edge on VPS from day one.** Fold HD-40A/40B
  into Phase 1; oldsrv becomes an internal/LAN box. → **AUD-06**/roadmap: do not treat VPS/edge
  as a deferred Phase-2 open question.
- **HD-51 / HD-94 — multi-axis identity model.** Persons = Authentik (4 + guest); shared bytes =
  neutral `media` system owner via `storage_uid`/`storage_gid` (not `domen`, not 1000); no human
  logins on nas; OpenCloud via Authentik OIDC (per-user isolation, not Forward-Auth); centralize
  container PUID/PGID on the shared vars (KOPS-060).

---

## How to use this file (READ FIRST — for worker/executor models)

This file is a **self-driving work-list**. If you are pointed at it with "do the next
item," follow these rules exactly:

1. **Select the next item this way:** pick the **lowest-numbered `### AUD-XX` whose
   heading still says `(pending)`** and whose `Depends on` prerequisites (if any) are all
   `(done)`. Work in numeric order within that rule — do **not** skip around arbitrarily.
2. **Respect dependencies:** AUD-01 must finish before AUD-04. AUD-05 and AUD-06 must
   wait until AUD-01 and AUD-02 are `(done)` (their source IDs are only trustworthy then).
   The `Depends on` line on each item states this explicitly.
3. **State marks:** keep the **status tag** on each AUD heading current:
   `### AUD-XX — Title (pending)` → `(in-progress)` while working → `(done)` only after the
   `Verify` line passes. Do not mark `(done)` merely because you edited files.
4. **Definition of Done (all four must hold):**
   a. the item's **`Verify`** command(s) return the stated result (exit 0 / empty grep);
   b. the matching box in the **End-state checklist** is ticked `[x]`;
   c. if it touched tracked files, the change is committed with a descriptive message;
   d. no *other* AUD item's correctness regressed (re-run its Verify if affected).
5. **If you cannot satisfy Verify:** leave the heading `(pending)`, append a one-line
   `> ⚠ reason:` note under the item explaining what blocked you, and move to the next item.
   Do not silently skip or half-finish.

---

## A. Reconcile & clean the audit documents (inputs 1–3)

### AUD-01 — Deduplicate KOPS findings by adding **only** first-free IDs (no mass renumber) (done)
- **Difficulty:** 2 · **Priority:** P1 · **Depends on:** none
- **What:** In `Qwen-bugs.md` the same KOPS ID is sometimes reused for *different* content
  (evidence of incremental appends, never consolidated), and some findings are repeated
  verbatim. **Do NOT renumber the whole file sequentially.** The IDs are opaque labels, not a
  sequence — a bug just needs its own unique ID. So:
  - **Keep** the existing ID on every finding whose content is currently unique (don't touch
    already-unique IDs, even though they are non-contiguous).
  - **Split:** where one ID carries two (or more) different findings, keep the *first*
    occurrence on the original ID and give each *additional* distinct finding the **first free
    (unused) KOPS number** (e.g. KOPS-062 onward, since KOPS-001…061 already exist).
  - **Remove:** where the same finding is repeated verbatim, keep one copy and delete the
    duplicates entirely (no new ID needed — same finding, same ID).
  - Preserve each finding's original title and content; only the ID label may change. Do **not**
    build a comprehensive `old → new` map — since one old ID can fan out to several new IDs, a
    clean 1:1 map isn't possible. AUD-04 resolves the cross-refs by reading the deduped file
    directly instead (content-based lookup), so no map is required here.
- **Known duplicate inventory (indicative — confirm with the method below):**

  | ID | # occurrences | distinct topics carried |
  |----|---------------|------------------------|
  | KOPS-043 | 3 | switch port map ×2, playbook order ×1 |
  | KOPS-044 | 4 | preseed root hash ×3, switch/AP bootstrap TLS ×1 |
  | KOPS-045 | 3 | Pi first-boot path, RMat port 80, preseed root hash |
  | KOPS-046 | 4–5 | AP ethernet ports ×3, RMat port 80 ×2 |
  | KOPS-047 | 2 | Seerr no-edge, Renovate coverage |
  | KOPS-048 | 2 | Seerr no-edge, Signal REST host port |
  | KOPS-049 | 3 | RMat port 2001 dup, playbook order, Technitium port 53 |
  | KOPS-050 | 2 | Loki schema date, playbook order |

  > ⚠ Only trust this table as a *starting checklist*; re-derive the authoritative occurrences
  > with the method below — there may be more than listed.
- **Method (do this, don't guess):** for each suspected duplicate, list every heading that
  uses it: `grep -nE 'KOPS-(043|044|045|046|047|048|049|050)' Qwen-bugs.md`. For each, read the
  following block and decide: identical content already seen ⇒ **delete** the repeat; genuinely
  different content ⇒ assign the **first free** KOPS number (`grep -oE 'KOPS-[0-9]+' Qwen-bugs.md
  | sort -V | tail -1` to see the current max, then use the next ID). Preserve original
  titles/content; add the new ID only where a distinct finding needs it.
- **Verify:** `grep -oE 'KOPS-[0-9]+' Qwen-bugs.md | sort | uniq -d` returns **nothing** (no
  duplicate IDs); `grep -oE 'KOPS-[0-9]+' Qwen-bugs.md | sort -u | wc -l` equals the number of
  distinct findings (blocks) actually present; every surviving finding retains its original
  title/content. (No `old → new` map is required — see AUD-04.)
- **Why first:** all other cross-referencing (Flaw-A table, low-fruits, roadmap, and this
  audit) is unreliable until IDs are unique. This approach reaches that state with far less
  churn than a full renumber: already-unique findings keep their IDs, only duplicated content
  gets a fresh label, and verbatim repeats are dropped.

### AUD-02 — Reconcile audit findings against current HEAD (done)
- **Difficulty:** 3 · **Priority:** P1 · **Depends on:** AUD-01 (works on the de-duplicated
  findings)
- **What:** Re-validate every KOPS finding against the **current** tree before treating it as
  actionable, and record a disposition on each. Do **not** trust the audit's claims that code
  still looks as quoted — the audit was an incremental scan run against a moving snapshot.
- **Per-finding method (do this for each KOPS block):**
  1. Read the finding's **`File:`** line and the **quoted code line(s)**.
  2. Check whether that exact code still exists: `grep -nF '<quoted string>' <cited file>`.
  3. Classify and record the disposition right after the finding block:
     - **`valid`** — code still present as quoted AND the described risk still applies.
     - **`stale`** — code no longer present / already fixed in current HEAD.
     - **`decision`** — finding's own prose says "acceptable / not a bug / expected
       behavior" (see list below) — it is a policy choice, not a defect.
- **Known-stale example (verify, don't trust):** KOPS-021 ("docker_services enables ALL
  services") looks already fixed — `roles/docker_services/tasks/main.yml` line 43 has
  `when: item.enabled | default(true)` (also mentioned in commit `f0c084b`). Confirm before
  you mark it.
- **Policy-decision findings (re-tag as `decision`, do NOT report as open bugs):**
  KOPS-033/034 (Matrix open federation), KOPS-058 (Homepage docker.sock health widget),
  KOPS-059 (Seerr SQLite accepted risk), and any KOPS-050 entry the doc concludes is "not
  actually a bug" (playbook order). AUD-13 later writes these into the decision log.
- **Verify:** every finding has an explicit `valid`/`stale`/`decision` disposition; zero
  findings are marked open while the current code already addresses them; `decision` findings
  are excluded from open-bug counts.

### AUD-03 — Remove / relabel the legacy Proxmox "Final Architecture Proposal" artifact (done)
- **Difficulty:** 1 · **Priority:** P1 · **Depends on:** none
- **What:** `Qwen-architecture.md` §1 ends with a "Final Architecture Proposal" ASCII block
  showing `oldsrv (Proxmox)` + "infra VM" + "desktop VM" + GPU passthrough. This contradicts
  the committed design (bare-metal Debian + Docker; Proxmox = Phase 2 / HD-41) and the
  README. Delete it or label it **`REJECTED / OUTDATED (superseded by bare-metal + Docker)`**.
- **Verify:** no section of `Qwen-architecture.md` (or any live doc) contradicts the
  bare-metal+Docker design.

### AUD-04 — Fix cross-references broken by the KOPS duplication (done)
- **Difficulty:** 2 · **Priority:** P1 · **Depends on:** AUD-01
- **What:** Other docs cite KOPS IDs as shorthand for a specific finding — e.g. the Flaw-A
  table in `Qwen-architecture.md` and `low-fruits.md` cite KOPS-047/048 for the *Seerr*
  finding, but after dedup those IDs belong to *Renovate* / *Signal*. Because AUD-01 now only
  keeps surviving unique IDs (no comprehensive `old → new` map; one old ID can become several
  new ones), update every cross-reference in `Qwen-architecture.md`, `low-fruits.md`, and any
  `todo.md` mention by **resolving the intended finding by content**, not by number.
- **Method (do this, don't guess):** for each cited KOPS ID outside `Qwen-bugs.md`, read the
  surrounding sentence to determine *which* finding it means (by its topic/title — e.g. "the
  Seerr finding"). Locate that finding's unique block in the now-deduplicated `Qwen-bugs.md`
  (grep on a distinctive title word) and replace the stale ID with that block's actual final
  ID. If the cross-ref meant a finding that was deleted as a verbatim duplicate, point it at
  the surviving copy's ID instead.
- **Verify:** `grep -rn 'KOPS-' *.md docs/ todo.md` returns only IDs that each resolve to
  exactly one unique finding block in `Qwen-bugs.md`, and every cross-ref corresponds to the
  intended finding by content (spot-check the Seerr/Flaw-A citations specifically).

---

## B. Absorb actionable content into the canonical system

### AUD-05 — Add the 6 low-fruits fixes as `todo.md` rows (tag ROI) (done)
- **Difficulty:** 1 · **Priority:** P1 · **Depends on:** AUD-01/02 (IDs + validation)
- **What:** Represent the six `low-fruits.md` items in `todo.md`, each as one row tagged
  `ROI`, `source: qwen`, with the difficulty/priority below. Suggested IDs **HD-60…HD-65**
  (do not reuse an ID already present in `todo.md`):

  1. **HD-60** `crowdsec-only` middleware chain → apply to self-auth'd routes
     (D2, P1) · [`docs/services-traefik.md`](docs/services-traefik.md)
  2. **HD-61** pin image tags, Traefik first (`traefik_version: latest` today)
     (D1, P1) · [`docs/deployment-compose.md`](docs/deployment-compose.md)
  3. **HD-62** remove/unbind host ports (signal `8080:8080`; prometheus; technitium;
     sunshine) (D2, P1) · [`docs/deployment-compose.md`](docs/deployment-compose.md)
  4. **HD-63** uncomment immich DB backup + opencloud tar (host default `immich-postgres`;
     the stale `db-backup` comment says `immich-db` — real service is `immich-postgres`)
     (D2, P1) · [`docs/backup.md`](docs/backup.md)
  5. **HD-64** fix loki schema `from: 2026-01-01` → `2025-01-01`/current
     (D1, P1) · [`docs/observability.md`](docs/observability.md)
  6. **HD-65** fail-loud on missing secrets — remove `default('')` (pihole `WEBPASSWORD`)
     (D2, P2) · [`docs/deployment-secrets.md`](docs/deployment-secrets.md)

  (If AUD-06 already claims any of HD-60+, coordinate so IDs do not collide.)
- **Row template — copy `todo.md`'s exact table format:**
  ```
  | HD-60 | 2 | AI | open | **crowdsec-only middleware chain** — add `crowdsec-only@file` to `middlewares.yml.j2`; apply to every self-auth'd route (ha, jellyfin, seerr, matrix, chat, ha-standby). ROI · source qwen. · [services-traefik.md](docs/services-traefik.md) |
  ```
  Insert each row under the **correct Priority section** (P1 items → `## Priority 1`), then
  **update the header tally** line `**Status: NN open · NN done** · **Total: NN**` to match
  the new row count.
- **Verify:** `grep -c '^| HD-6' todo.md` == 6 (or matches the section split); every new row
  has `| D | Exec | Status |` columns in the `todo.md` schema; each links to its owning doc;
  the header tally equals the true table count.

### AUD-06 — Migrate the architecture roadmap `NEW-*` items into `todo.md` (done)
- **Difficulty:** 2 · **Priority:** P1 · **Depends on:** AUD-01/02 (IDs + validation)
- **What:** Replace the parallel `NEW-S01…S07`, `NEW-M01…M08`, `NEW-L01…L07` namespace in
  `Qwen-architecture.md` §5 with HD-60+ rows in `todo.md` (tagged `source: qwen`). Where an
  item is **already tracked**, point to the existing row and do **not** duplicate. Keep each
  row's KOPS `Source` reference **only after** AUD-01/02 settle the true unique IDs.

  **Full mapping table (use as-is; suggested HD-70+ to stay clear of AUD-05's HD-60–65):**

  | NEW-* | suggested HD | brief | D | P | owner doc |
  |-------|-------------|-------|---|---|-----------|
  | NEW-S01 | HD-70 | crowdsec-only middleware (same net change as HD-60 — **merge**, don't duplicate) | 2 | P1 | services-traefik.md |
  | NEW-S02 | HD-71 | pin all `latest` image vars (supersedes/merges HD-61) | 1 | P1 | deployment-compose.md |
  | NEW-S03 | HD-72 | HA primary `privileged:true`+`network_mode:host` → targeted `devices:`+`cap_add:` | 3 | P1* | smart-home-failover.md |
  | NEW-S04 | HD-73 | create `group_vars/switch.yml` port map (fold into HD-03 context) | 3 | P1 | network-rack.md / network-vlans.md |
  | NEW-S05 | HD-74 | remove host port binds (merge with HD-62) | 2 | P1 | deployment-compose.md |
  | NEW-S06 | HD-75 | uncomment immich/opencloud DB backups (merge with HD-63) | 2 | P1 | backup.md |
  | NEW-S07 | HD-76 | loki schema date + fail-loud secrets (merges HD-64 + HD-65) | 2 | P1 | observability.md / deployment-secrets.md |
  | NEW-M01 | HD-77 | split `n8n_password` → `n8n_password` + `n8n-webhook_api` | 2 | P2 | deployment-secrets.md |
  | NEW-M02 | HD-78 | router INPUT-chain rules (mgmt services → VLAN 99 only) | 2 | P2 | network-vlans.md / network-ops.md |
  | NEW-M03 | HD-79 | pin Homematic USB by-id in host_vars + udev symlink | 2 | P2 | smart-home-failover.md |
  | NEW-M04 | HD-80 | unique root hash per host OR `root-login false` in preseed | 2 | P2 | deployment-preseed.md |
  | NEW-M05 | HD-81 | shrink HA `trusted_proxies` /16 → Traefik container IPs | 2 | P2 | smart-home-failover.md / security.md |
  | NEW-M06 | HD-82 | Grafana `GF_AUTH_DISABLE_LOGIN_FORM` single auth path | 2 | P2 | observability.md |
  | NEW-M07 | HD-83 | restrict router API to mgmt VLAN in bootstrap .rsc itself | 2 | P2 | network-ops.md |
  | NEW-M08 | HD-84 | Headscale: real ACL policy OR fix misleading comment | 2 | P2 | network-vpn.md |
  | NEW-L01 | HD-85 | add CrowdSec collections (home-assistant, matrix, grafana) | 1 | P3 | observability.md |
  | NEW-L02 | HD-86 | `op signin --account` instead of bashrc token | 1 | P3 | deployment-secrets.md |
  | NEW-L03 | HD-87 | pin CrowdSec bouncer plugin version | 1 | P3 | deployment-compose.md |
  | NEW-L04 | HD-88 | dedup sshd_config append in post_install.sh | 1 | P3 | deployment-preseed.md |
  | NEW-L05 | HD-89 | disable/move unused AP ethernet ports off Mgmt VLAN | 1 | P3 | network-vlans.md |
  | NEW-L06 | HD-90 | Renovate managers: ansible-galaxy + pip (not just docker) | 1 | P3 | deployment-renovate.md |
  | NEW-L07 | HD-91 | fail-closed `fail: msg=` guards on missing secrets (merge with HD-65/HD-76) | 2 | P3 | deployment-secrets.md |

  **Already tracked — point to existing row, do NOT create new:** HD-03, HD-04, HD-06,
  HD-13, HD-16, HD-17, HD-19, HD-39, HD-40, HD-41, HD-42, HD-45, HD-48, HD-51, HD-52,
  HD-53, HD-54, HD-56, HD-59. Where the roadmap lists one of these, leave the existing row
  untouched.
- **Verify:** `grep -rn 'NEW-' Qwen-architecture.md` returns nothing after removal; every
  NEW-* row above exists in `todo.md` as an HD-70+ row (or is marked *merged* into HD-60–65);
  no HD-70+ row duplicates an already-tracked HD item; roadmap rows keep a `source: qwen` tag.

### AUD-07 — Refresh the stale status in `deployment-tasks.md` (pending)
- **Difficulty:** 1 · **Priority:** P1 · **Depends on:** none
- **What:** Phase 3's warning "some compose templates are still `TODO: define service`
  placeholders (authentik→HD-16, crowdsec, forgejo, opencloud, db-backup, headscale…)" is
  **out of date** — HD-16 and HD-50 are done and all 42 templates exist. Update the header
  tally and that warning to reference live status.
- **Verify:** no "TODO: define service" / stale placeholder wording remains; the doc points at
  `group_vars/home_servers.yml` (the true source of truth) without stale per-template caveats.

### AUD-08 — Create persistent `docs/security.md` hardening posture (pending)
- **Difficulty:** 3 · **Priority:** P2 · **Depends on:** AUD-06 (so the HD rows exist to link)
- **What:** Create `docs/security.md` — a durable home for the security *postures* so they
  outlive the audits. Write it following `docs/index.md` conventions: start with
  `> **Role:** security hardening posture` + `> **Linked from:** ../README.md` headers,
  relative links, no inline secrets.
- **Required section outline (create at least these headings):**
  1. `## 1. Edge WAF (Flaw A)` — middleware map (`authentik-forward-auth` vs the new
     `crowdsec-only`); which routes skip Forward-Auth and must carry crowdsec-only. Links
     `services-traefik.md`.
  2. `## 2. Version pinning (Flaw B)` — every mutable `latest`/`-rocm` tag must have a pinned
     var in group_vars + a Renovate follow-up. Links `deployment-compose.md`,
     `deployment-renovate.md`.
  3. `## 3. Host port-binding policy (Flaw C)` — rule: no `0.0.0.0` host binds; bind loopback
     or a specific VLAN IP when a host port is required; prefer the Docker overlay network.
     Links `deployment-compose.md`.
  4. `## 4. Container minimum privilege (Flaw D)` — targeted `devices:`/`cap_add:` over
     `privileged`/`NET_ADMIN`/host-net; document the HA + Technitium + Doco-CD cases. Links
     `smart-home-failover.md`.
  5. `## 5. Backup coverage (Flaw E)` — DB list that must be covered (immich, opencloud) +
     metadata-loss rationale; logs auth. Links `backup.md`, `storage-zfs.md`.
  6. `## 6. Bootstrap hygiene (Flaw F)` — unique root hashes, router API interface binding,
     switch port map, fail-loud secrets, preseed defaults. Links `deployment-preseed.md`,
     `deployment-secrets.md`, `network-ops.md`.
  7. `## 7. Decision log` — the accepted/closed decisions from AUD-13 (one bullet each,
     rationale + date).
- **Verify:** `docs/security.md` exists with all 7 headings; `docs/index.md` document-map
  lists `security.md`; every posture section links to its owning doc; `validate-doc-templates`
  still passes.

---

## C. Backlog hygiene & final consolidation (inputs 4–5)

### AUD-09 — Reconcile `todo.md` tally and completed-state notes (pending)
- **Difficulty:** 2 · **Priority:** P2 · **Depends on:** AUD-05, AUD-06
- **What:** `todo.md` header says "50 open · 11 done". Re-tally after AUD-05/06 add rows;
  remove the resolved "dead reference" note for HD-35 (content already lives in
  `assets/Network-Devices.canvas`); refresh the "Recently-implemented IaC (not deployed)"
  block to current truth (failover primary/standby steps are now committed).
- **Verify:** header count matches row count; no note describes already-resolved work as open.

### AUD-10 — Decide disposition of each audit document (pending)
- **Difficulty:** 3 · **Priority:** P2 (needs a human decision for the final call) · **Depends on:** AUD-01, AUD-02, AUD-06
- **What:** After content is absorbed, decide for each source doc where it lives long-term.
  Recommended:
  - `Qwen-bugs.md` → keep as **evidence annex** (deduped per AUD-01) under `reports/` or
    `brainstorming/`; not a living document.
  - `Qwen-architecture.md` → **retire** after AUD-06 (keep §2 "six flaws" distilled into
    `docs/security.md`); move to `reports/` or `brainstorming/`.
  - `low-fruits.md` → **execute-then-retire** after AUD-05; move to `reports/` as historical.
  - `todo.md`, `deployment-tasks.md` → **remain canonical and live**.
- **Verify:** a committed decision exists for each file; no audit doc is still treated as a
  source of truth.

### AUD-11 — Final cross-document consistency pass (pending)
- **Difficulty:** 2 · **Priority:** P2 · **Depends on:** AUD-01…AUD-09
- **What:** Run the repo validators (`bash scripts/validate-all.sh`, `check_doc_ips.py`,
  `validate_doc_templates.py`), confirm no dangling links / dead references introduced by the
  consolidation, and confirm every HD/KOPS/NEW ID referenced resolves to one canonical home.
- **Verify:** validators exit 0; `git grep` for the old namespaces (`NEW-`, stale `KOPS-047`
  as Seerr) finds nothing; working tree is internally consistent.

---

### AUD-12 — Update `docs/index.md` document map for the consolidated state (pending)
- **Difficulty:** 1 · **Priority:** P2 · **Depends on:** AUD-08, AUD-10
- **What:** Once the audits are reconciled and retired, update `docs/index.md` so the dispatcher
  reflects reality: add `security.md` (from AUD-08) to the document map, keep the **Backlog**
  pointer on `todo.md` (now contains the qwen-absorbed rows), and drop/adjust any doc-map lines
  that still treat `Qwen-*.md` / `low-fruits.md` as live inputs.
- **Verify:** `docs/index.md` map lists only live docs; the dispatcher's "Backlog / open
  decisions" row resolves through `todo.md` only.

### AUD-13 — Record every audit policy decision in a persistent decision log (pending)
- **Difficulty:** 2 · **Priority:** P3 · **Depends on:** AUD-02
- **What:** Decisions the audits surfaced as "findings" — e.g. Matrix open federation
  (KOPS-033/034), Homepage docker.sock health widget (KOPS-058), Seerr SQLite accepted
  (KOPS-059), the accepted playbook ordering (former KOPS-050), HA privileged-mode tradeoff —
  should be written explicitly as accepted/closed decisions in `docs/security.md` (or an
  existing decision section), with a one-line rationale, so they are not re-raised as bugs on
  every future scan.
- **Verify:** every finding AUD-02 re-tagged as `decision` has a corresponding sentence in the
  decision log with rationale + date.

---

## End-state checklist (all AUD-xx done ⇒ consolidation complete)

- [ ] KOPS IDs unique and reconciled to HEAD (AUD-01, AUD-02)
- [x] Proxmox artifact removed; cross-refs fixed (AUD-03, AUD-04)
- [x] All 6 low-fruits + all architecture `NEW-*` items are HD-XX rows in `todo.md` (AUD-05, AUD-06)
- [ ] `deployment-tasks.md` reflects live status (AUD-07)
- [ ] `docs/security.md` exists and is wired into the doc map (AUD-08)
- [ ] `todo.md` tally/hygiene correct (AUD-09)
- [ ] Each audit doc has a committed long-term disposition (AUD-10)
- [ ] Validators green; no dangling references (AUD-11)
- [ ] `docs/index.md` map reflects only live docs (AUD-12)
- [ ] Policy decisions recorded in a persistent decision log (AUD-13)
