# Docs Changes — Content Cleanup, Consolidation, Rewrite, Split/Merge

> **Role:** Change-proposal ledger for `docs/` (content structure, consolidation, rewrites, split/merge).
> **Linked from:** an audit deliverable; pairs with `docs-vs-iac.md` (what changed) + `iac-changes.md` (IaC side).
> **Convention:** each entry = a concrete, reviewable change; marked **merge/split/rewrite/edit** with owning docs.

---

## P0 — resolve the live contradictions first (blocking)

### 1. Rewrite stale MinIO/S3 wording → live-Box CIFS reality
- **Docs:** `services.md` (§Storage & versions), `deployment-compose.md` (§*arr), `storage-zfs.md` (§Per-Dataset + §Mount), `subscription.md` (live Box purpose).
- **Action:** replace every *"S3-backed (MinIO, HD-131 D1)"* / *"`tank/data/immich` is MinIO object store"* / *"Phase-2 Immich-originals S3"* bullet with the post-HD-135 statement: **Immich originals + encoded-video live on the live Hetzner Box (CIFS), enabled via Immich storage template at deploy; no MinIO, no S3.**
- **Why:** the IaC already removed MinIO; leaving the docs on the old backend misdirects the *authoring* specs (the very files AI reads to regenerate IaC).

### 2. Fix the observability-backend contradiction
- **Docs:** `docs/hardware-oldsrv.md` (§Observability Storage & Notes) + `docs/storage-zfs.md` (TSDB rows / ^tree).
- **Action:**
  - `hardware-oldsrv.md`: delete "TSDB on oldsrv `nvme` pool" + rewrite the SPOF para to the HD-135 reality: backend on **VPS NVMe**; oldsrv = **Alloy collector** forwarding over `wg-s2s`.
  - `storage-zfs.md`: TSDB (`nvme/tsdb`) rows → **VPS NVMe**; keep nas `tank`/`bulk` as NAS-local storage.
- **Why:** `observability.md` §Placement (HD-135) is correct; `hardware-oldsrv.md` carries the old two-box model. One physical host no longer holds the backend; the docs must not re-create a false SPOF.

### 2. Align the post-HD-135 "who runs what" framing consistently
- **Files:** `README.md` (Key Design `oldsrv` role), `hardware-oldsrv.md`, `docs/services.md`, `docs/services-vps.md`, `deployment-tasks.md` (Phase 3 note).
- **Action:** sweep for any remaining "oldsrv = full Docker stack / public edge lives on oldsrv" wording and align to the VPS-edge / oldsrv-GPU-LAN / nas storage / pi-HA split. (Most already updated; the drift is mainly the S3 + observability bullets above.)

---

## P1. Structural cleanup

### 3. Fix the role/template count drift
- **Files:** `IaC/README.md` (role table says "15", templates "41"), `deployment-tasks.md` ("42 templates"), `docs/index.md` (valid "48").
- **Action:** stop hardcoding a count in docs prose; where a number is needed, point at `docs/index.md` "currently 48" (true) or better, at the **`IaC/ansible/templates/docker_services/`** dir + `scripts/validate-docker-services.py` as the living count.
- **Why:** these numbers drift the moment a template is added; an AI author trusts the count to know scope.

### 4. Reconcile `docs/index.md` Document Map with on-disk `.md`
- **Files:** `docs/index.md` (map) + reality (48 templates, 20 roles, ~43 docs).
- **Action:** re-run a `find docs -name "*.md"` and add missing files to the map: `hd110-office-mcp-research.md`, `deployment-ai-stack-secrets.md`, `rack-connections.md`, `subscriptions-table.md`, `inventory.md`, the full `manual/*` set (README + wifi/desktop/immich/opencloud/vpn/server-restart/restore-backup/contacts/smart-home/chat), + `1password.md` if not listed.
- **Why:** the doc map **is the AI dispatcher**; omitting real files is a discoverability + freshness regression.

### 4b. Decide `docs/vs` two-catalog split
- **Proposal:** `docs/hardware*.md` are per-machine refs; `docs/services*` (traefik/authentik/matrix/finance/vps) + `docs/ai-stack.md` are per-domain. This is **already the model** — keep it. Do **not** merge; the split is healthy. Only reconcile the map (item above).

### 5. Consolidate the three observability views
- **Files:** `docs/observability.md` (SSOT), `docs/interfaces.md` (UI/alerting subset), `docs/services.md` (catalog rows), `docs/hardware-oldsrv.md`/`services-vps.md` (placement notes).
- **Action:**
  - Keep **`observability.md` the single SSOT** for architecture/alerting/retention.
  - **Trim** the duplicated alerting/notification block out of `interfaces.md` → one-line pointer to `observability.md`.
  - In `services.md`, ensure each catalog row that has an observability/alerting role points to `observability.md` (don't restate).
- **Why:** 3 files currently describe alert delivery partly in parallel; the SSOT convention says one owner.

### 6. Consolidate the subscription docs
- **Files:** `group_vars/subscriptions.yml` (SSOT data) → `docs/subscription.md` (prose) → `docs/subscriptions-table.md` (rendered).
- **Action:** keep exactly this model. Ensure `subscription.md` **prose only** and the rendered table stays marked **★ generated, never hand-edit** (already so). No structural change beyond confirming `subscriptions-table.md` exists in `index.md` map.

### 7. Split `docs/deployment.md` + `deployment-???.md` (Gittering)
- **Files:** `deployment.md` (broad) / `deployment-ansible.md` / `deployment-compose.md` / `deployment-preseed.md` / `deployment-secrets.md` / `deployment-renovate.md` is a **healthy family**. No split needed — each already one domain.
- **One improvement:** delegate the "Ansible role catalog" prose out of both `deployment-ansible.md` **and** `IaC/README.md` — currently *two* authoritative role lists that drift (§3). Pick **one** (recommend `deployment-ansible.md`) and make `IaC/README.md` link to it instead of listing all roles a second time. Same for the File Layout / Template lists.

### 8. Merge or correct the "manual/ gaps
- **Files:** `docs/manual/README.md` + the 10 Slovenian family guides exist on disk (HD-32 `status: wip`).
- **Action:** keep manual files per-guide (they're already one-page each); the gap is **`index.md` map + `manual/README.md` TOC** — add every guide to both. No merge.

### 9. `docs/inventory.md` — is it a real SSOT or stale?
- **File:** `docs/inventory.md` exists (rendered), but the `docs/index.md` map lists it only via `deployment-ansible.md`.
- **Action:** **remove hand-edited inventory scope**; the render hook + `render_docs.yml` writes it. Add to `index.md` map as a ★ generated view (like `network-addresses.md`). If no active consumer, consider excluding from Git to avoid drift.

---

## P2. Polish (non-blocking)

### 1. `README.md` interface count
- Change `"Five interfaces… TileBoard"` → the current set: **Homepage, HA Dashboard, Grafana, Forgejo, Obsidian (+ Metabase, Element)**; note TileBoard retired (HD-24). (Single paragraph; not a whole-file rewrite.)

### 2. `README.md` "Key Design Decisions"
- Add the two driving 2026-08-18 decisions so a new agent starts right: **HD-135 (VPS/oldsrv split + Hetzner Boxes + CIFS, not S3)** and **HD-150 (Ansible-only deploy)**. These are currently the two biggest post-planning facts and belong in the dispatch README.

### 3. Consider `docs/1password.md` merge
- `docs/1password.md` overlaps `docs/deployment-secrets.md` (SSH agent/setup). Recommend keeping both but making `deployment-secrets.md` the master list owner and `1password.md` → "runner + setup how-to" (pointer, not duplicate).

---

## Summary of recommended actions (docs)

| # | Change | Type | Owner file(s) |
|---|--------|------|---------------|
| P0-1 | Kill MinIO/S3 bullets | rewrite/edit | services.md, deployment-compose.md, storage-zfs.md, subscription.md |
| P0-2 | Fix observability location + SPOF | edit | hardware-oldsrv.md, storage-zfs.md |
| P0-3 | Align template/role counts + stop hand-counts | edit | IaC/README.md, deployment-tasks.md, index.md |
| P0-4 | Reconcile index map with disk | edit | index.md |
| P1-5 | De-dup alerting into observability.md | merge/edit | observability.md, interfaces.md |
| P1-6 | Subscription model: keep, link table | edit | subscription.md, index.md |
| P1-7 | Pick ONE role-catalog owner | merge/edit | IaC/README.md, deployment-ansible.md |
| P1-8 | Wire manual guides into map | edit | index.md, manual/README.md |
| P1-9 | Make inventory.md a tracked generated view | edit | index.md |
| P2-1/2 | README interface-count + decisions | edit | README.md |