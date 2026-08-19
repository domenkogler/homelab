# Prompt: HD-151 — Trim orphan oldsrv/nas datasets post-HD-135

> Handoff written 2026-08-19. Goal: remove datasets the VPS-era architecture no longer writes.

## Task

Decide + apply the trim of orphan ZFS datasets on oldsrv/nas. The observability backend, Immich,
Postgres, and **OpenCloud user files** all moved to the VPS / live Hetzner Box (HD-135) — nothing on
oldsrv/nas writes these datasets anymore, but the `storage` role still creates them.

## The orphan datasets (in `IaC/ansible/roles/storage/defaults/main.yml` `storage_datasets:`)

**oldsrv (`nvme` pool):**
- `nvme/tsdb` (mountpoint `/srv/tsdb`) — observability moved to VPS
- `nvme/docker/immich` (mountpoint `/srv/docker/immich`) — Immich moved to VPS
- `nvme/docker/postgres` (mountpoint `/srv/docker/postgres`) — Postgres moved to VPS

**nas (`tank` + `bulk` pools):**
- `tank/data/immich`, `bulk/data/immich` — Immich originals are on the live Box (CIFS)
- `tank/data/documents`, `bulk/data/documents` — OpenCloud user files are on the live Box
  (`bulk/data/immich-thumbs` — check: it may still be needed or is also orphan)

## What to do

1. **Read `docs/storage-zfs.md`** — it's the storage SSOT. The datasets are already documented as
   "retained archive only / nothing writes to it today (orphan — trim decision: HD-151)".
2. **Decide the trim set** in `storage_datasets` (keep `services/dumps/docker-layers/models`;
   drop or repoint `tsdb/immich/postgres/documents` + `bulk/data/immich-thumbs` if orphan).
   ⚠ The `documents`/`immich` rows on nas have a **retained-archive** rationale — decide whether
   "trim" means delete the row or keep the dataset but stop auto-creating it.
3. **Align `docs/storage-zfs.md`** tree/tables with the new set (data-location same-change rule,
   CONVENTIONS §2 — IaC + docs in the SAME commit).
4. Update the **snapshot/sanoid schedule** block if it references dropped datasets (there's a
   `datasets:` map at ~line 146 referencing `tank/data/immich`, `tank/data/documents`, etc.).
5. Update the **HD-151 row in `todo.md`** (✅ done / ⏳ deploy-gated as appropriate — this is
   laptop-doable IaC, so it should close at IaC-completion with a deploy-gated tail if the
   datasets exist on live hosts).
6. Run `bash scripts/validate-all.sh` — must be green before commit.

## Guardrails
- **Do NOT break** the retained-archive intent: check `hardware-nas.md` / `backup.md` for what
  still references these datasets before removing.
- The live Box (CIFS) is the new SSOT for user files — never repoint back to NAS.
- If a dataset is still referenced by a compose template or service, that's a conflict — flag it.

## Definition of done
`storage_datasets` reflects the VPS-era set; `storage-zfs.md` matches (tree + tables + sanoid
schedule); `todo.md` HD-151 updated; `validate-all.sh` green; one clean commit.
