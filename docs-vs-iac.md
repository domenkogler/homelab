# Docs vs IaC — Contradictions & Drift Audit

> **Role:** Audit — the delta between what the docs *claim* and what the IaC *actually does*.
> **Confidence:** read-only review of `docs/` + `IaC/` as of 2026-08-19 planning phase.
> **Convention:** every entry names the doc(s) and the concrete IaC evidence for the contradiction.
> Linked from: this is a deliverable ledger — file it next to `docs/` and resolve via the `docs-changes.md` / `iac-changes.md` action lists.

## Legend

- severity: 🔴 blocking (misleads a deploy/author today) · 🟡 drift (cosmetic or stale but not deploy-blocking) · 🟢 note

---

## 1. 🔴 Immich / OpenCloud *still directed at MinIO S3* — but MinIO is removed (HD-135)

The single most serious lived-consistency break. The **IaC removed MinIO** (HD-135: Immich originals → live Hetzner Box **CIFS**, not S3), and `group_vars/*`, the compose templates, the secrets master list, and `observability.md` all reflect that. But **three docs still describe Immich/OpenCloud as S3/MinIO-backed**:

| File | Claimed | Reality (IaC / decision) |
|------|---------|--------------------------|
| `docs/services.md` (§Storage & versions) | *"Immich originals are S3-backed (MinIO → Storage Box later, HD-131 D1/D3)"*; *"`tank/data/immich` is MinIO's object store"* | MinIO removed; originals → **live Box CIFS** (`//u653411…/backup`) + Immich **storage template** (DB setting, not compose env). IaC: `IaC/ansible/templates/docker_services/immich-app/docker-compose.yml.j2` header + `IaC/ansible/roles/cifs/*`. |
| `docs/deployment-compose.md` (§*arr conventions) | *"Immich originals are S3-backed (MinIO, HD-131 D1)"* | stale — see above. |
| `docs/storage-zfs.md` (§Per-Dataset + §Mount layout) | dataset row + `tank/data` description still say *"originals moved to S3 (MinIO, HD-131 D1); this holds MinIO's object blocks"* | MinIO gone; `tank/data` = user documents/dumps/service-state + (older wording). |
| `docs/subscription.md` (live Box §Purpose) | *"Phase-2 live Immich-originals S3"* | live box is CIFS/SMB/WebDAV, **not S3**. |

🟡 **Also:** `docs/services.md` *immich* catalog row still says *"originals on live Box (CIFS), thumbs/DB local"* — that part **is correct** (only the S3 minio italicized sub-bullets in §Storage are stale). `docs/observer` `observability.md` correctly marks minio_exporter retired. The drift is in `services.md`, `deployment-compose.md`, `storage-zfs.md`, `subscription.md`.

**Recommendation:** delete/rewrite the S3–MinIO bullets in those four docs to the CIFS/live-Box + storage-template reality (details in `docs-changes.md`).

---

## 2. 🔴 Observability backend placement — docs contradict each other

| File | Claimed |
|------|---------|
| `docs/hardware-oldsrv.md` (§Observability Storage & Notes) | *"Prometheus/Loki on the oldsrv `nvme` ZFS pool (`nvme/tsdb`)" + "SPOF (accepted): **all observability lives here** — if oldsrv dies, you cannot see nas/others"* |
| `docs/storage-zfs.md` (nvme layout + tsdb rows) | TSDB still drawn under oldsrv's `nvme` pool |
| `docs/endpoint.md` / `docs/observability.md` (HD-135) | observability **backend** (Prometheus/Loki/Grafana) moved to the **VPS**; oldsrv runs only a thin **Alloy collector** forwarding over `wg-s2s` |

**Reality (IaC):** `inventory.ini` §[monitoring] = `oldsrv` (collector) + `vps` (backend); `IaC/ansible/playbooks/vps.yml` runs `monitoring` on the VPS; `group_vars/all.yml` `alloy_backend_host` = VPS peer IP. The old `nvme/tsdb`-on-oldsrv + "SPOF everything on oldsrv" wording is **flatly wrong** post-HD-135.

**Also internally inconsistent:** `observability.md` §Placement correctly describes the VPS backend + acknowledges the new SPOF (tunnel/VPS down → no Grafana), but `hardware-oldsrv.md` still carries the *old* SPOF wording.

**Recommendation:** update `hardware-oldsrv.md` + `storage-zfs.md` TSDB references to the VPS NVMe backend; align the SPOF paragraph with `observability.md` (§Placement HD-135). See `docs-changes.md` §2.

---

## 3. 🟡 Template-count claims drift (48 real)

| File | Claimed count |
|------|---------------|
| `IaC/README.md` | **41** templates implemented (HD-01) |
| `deployment-tasks.md` (§Phase 3 note) | **42** compose templates |
| `docs/index.md` (Validation) | *"currently 48"* — **this is the true count** (48 dirs under `IaC/ansible/templates/docker_services/`) |

The three authoritative-ish references disagree. `docs/index.md`'s "48" matches the validator's rendered set (docs/`scripts/validate-docker-services.py` — `currently 48`). `IaC/README.md` and `deployment-tasks.md` are stale (41/42 predates several additions).

**Recommendation:** make the count **computed, not hand-maintained** (the honest fix is to stop quoting a bare number and point at `docker_services/` dir list + validator), and at minimum update `IaC/README.md` + `deployment-tasks.md` to "48".

---

## 4. 🟡 Ansible role catalog count drift

`IaC/README.md` says *"roles … (15) … `proxmox` (1, TODO) — kopia intentionally unused*", and lists a handful. The **actual** `IaC/ansible/roles/` has **20** directories: `ai_diag`, `amd_rocm`, **`cifs`**, **`cloudflare_dns`**, `cockpit`, `common`, `desktop`, `docker`, `docker_services`, `home_assistant`, `kopia`, `monitoring`, `network`, `nut`, `office`, `proxmox`, `router`, `storage`, `switch`, **`wireguard`**.

> The `cifs`, `cloudflare_dns`, and `wireguard` roles are **missing** from the IaC/README role table/count.

Also `IaC/README.md` flat layout + `docs/deployment-ansible.md` File Layout both diverge from the real `playbooks/*` list (e.g. `deployment-ansible.md` old inventory still has `raspberry_pi` grouped under `home_servers` and lists only 4 playbooks; the `switch` + `render-docs` + `dns` playbooks aren't in its File Layout).

**Recommendation:** regenerate/repair `IaC/README.md` role catalog + `deployment-ansible.md` role/file-layout so these match the 2026-08-18 `roles/` + `playbooks/` on disk.

---

## 5. 🟡 `hardware-oldsrv.md` says "NUT client on oldsrv" — correct, but the *shutdown_delay* / failover phrasing drift

`host_vars/oldsrv.kogler.si.yml` sets `shutdown_delay_seconds: 60`, `nut_mode: client`, `nut_host: nas`. That part is **consistent** with `docs/hardware-oldsrv.md`. (No bug here — lincluded for completeness; the real deltas are #1/#2.)

---

## 6. 🟡 `storage-zfs.md` table still says "no ZFS on VPS" but the tree in §old§ of the same file + §NB cols mention VPS NVMe DBs/thumbs — mixed generations

- `docs/storage-zfs.md` §Per-Dataset table (mainly nas `tank`/`bulk`) is **nas-specific** and fine.
- The **"mount/tree"** list adds `VPS NVMe` paths (`/srv/…`) that don't appear in earlier HD-131 tables. This is the split generation: a later revision added VPS-side data (good) but the **older S3/MinIO bullets still present** (see §1). Net: the doc mixes two generations in one file.

**Recommendation:** regenerate/restructure `storage-zfs.md` into "NAS ZFS" + "VPS NVMe / live-Box CIFS / Kopia" sections so it reads as one coherent post-HD-135 layout (see `docs-changes.md`).

---

## 7. 🟡 `playbooks/vps.yml` — wireguard role is `when:`-gated on a **fail-closed variable** that is empty until provisioned

```yaml
- role: wireguard
  when: wg_s2s_vps.peer_public_key | default('') | length > 0
```

GoWhat the `docs` claims:
- `IaC/README.md` "WireGuard S2S role complete both sides" + `network-vpn.md` describes the tunnel as an operating component.
- `group_vars/all.yml` `wg_s2s_vps.peer_public_key` derives from `wg_s2s_router_public_key` (a var that **does not exist yet** in host_vars / no 1Password binding was found) ⇒ the `when:` is false on a fresh build, so the **VPS wireguard role will silently not run** even though docs/README list wireguard as part of the stack. This is actually the *intended* fail-open-for-now behavior (VPS edge deploys standalone; tunnel is follow-on), but **the docs don't say "not yet provisioned"** — they imply it builds.

**Recommendation:** add to `IaC/README.md` + `network-vpn.md` an explicit footnote that the `wireguard` role + `wg_s2s_*` peering is **deploy-gated until `wg_s2s_router_public_key` / VPS peer-pubkey items exist in /vars+1Password**, and that `vps.yml` skips it under an empty pubkey (matching the `network-vlan` description of WG as Phase 1.5 apply).

---

## 8. 🟡 `inventory.md` + `network-addresses.md` are generated — but they live `docs/` and are tracked in Git with hand-edited content (`physical` from `switch.yml` but switch has TODO ports)

- `docs/network-addresses.md` + `docs/inventory.md` are *generated* (render-docs plays `render-docs.yml`) and `CONVENTIONS.md`/`index.md` say "never hand-edit". 
- But `docs/switch.yml`'s `switch_port_map` is full of `# TODO: VERIFY - estimate from canvas` and `group_vars/switch.yml` is a partially-filled WIP — yet `render_rack_connections.py` may reference ports. This isn't a doc-contradiction *per se*; it's a **"docs are generated, but the source data (switch port map) is still estimates"** gap. Worth a note: the switch `port_map` is **not** SSOT-complete enough to treat `network-addresses.md` as a reliable physical-port source until the TODO are resolved (HD-03).

---

## 9. 🟢 Index `docs/index.md` document map VS reality list

`docs/index.md` Document Map lists ~novare docs but **misses** several real files: `docs/index.md` lists `manual/README.md` but the `docs/manual/` set (wifi, desktop, immich, opencloud, vpn, server-restart, restore-backup, contacts, smart-home, chat) are **present on disk** yet map shows only `README.md` + a few. Also `docs/hd110-office-mcp-research.md` + `docs/deployment-ai-stack-secrets.md` + `docs/subscriptions-table.md` + `docs/rack-connections.md` are on disk **not reconciled** in the map. (Minor / cosmetic — but an AI dispatcher doc that omits real files is a discoverability regression.)

**Recommendation:** reconcile `index.md` map with `find docs -name "*.md"` (see `docs-changes.md` §4).

---

## 10. 🟢 Homelab "5 interfaces" in README vs interfaces.md "6-tier"

- `README.md` (§Key Design) says "Five interfaces, no overlap: Homepage/TileBoard/Grafana/Forgejo/Obsidian".
- `docs/interfaces.md` says **6-tier / 7-row** incl. native **HA Dashboard** (replaced TileBoard HD-24), **Element Web**, **Metabase/CrowdSec**, Traefik dashboard.

README's "five" is stale: TileBoard was retired (HD-24) and HA Dashboard + Element + Metabase are real interfaces. Minor, but a dispatcher README that counts the wrong set is a "start-here" hazard.

---

## Top cross-cutting findings

1. The **SSOT-vs-doc model is real** (IaC → render → docs), but **several docs carry legacy hand-written drift** (S3/MinIO, observability-locale, template/role counts, interface set) that defeats the SSOT promise. The docs are only as reliable as the last render.
2. **Count-based claims** (roles, templates) are inherently drift-prone; prefer pointing to the directory/validator.
3. The **vps/an ouble/TileBoard/obs** doc sets still encode the pre-HD-135 two-box model; the live post-HD-135 model now puts edge/AI/observability on VPS.

> **Owner:** this file is a snapshot; resolution actions live in `docs-changes.md` + `iac-changes.md`.