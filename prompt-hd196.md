# prompt-hd196 — Stale-docs sweep (VPS era)

> **Role:** Task handoff for **HD-196** (todo.md §2.10). File-by-file checklist; details and
> rationale live in `docs-changes.md` §1/§4. **Linked from:** [todo.md](todo.md).

## Per-file fixes

1. `backup.md` — "What Gets Backed Up": DBs + TSDB locations → VPS NVMe (HD-135); Kopia sources
   → VPS paths + WG pushes; keep the dual-layer architecture text.
2. `observability.md` — Pi-SD section "Loki (14d, oldsrv NVMe)" → VPS; move the two done items
   (Alloy instance label HD-116, SNMP community HD-53) out of ⚠ TODO tables into decided notes.
3. `services-matrix.md` — placement oldsrv → VPS (matches `group_vars/vps.yml`); fix storage path
   `/srv/docker/matrix` host + the "WAN 443 to oldsrv" sentence.
4. `hardware-nas.md` — delete the "TODO (IaC): nas storage role … doc-only" box.
5. `storage.md` — delete "Proposed IaC (stub)" section incl. the "3879 mounts" typo; compress the
   struck-through legacy Immich section to ≤5 lines.
6. `security.md` §2 — traefik "currently latest" (false), "42 templates" → reference the directory;
   remove the duplicated fragment line in §9.
7. `docs/index.md` — add missing dispatch rows (storage triage, VPN detail); re-star ★ files by
   actual authoring-spec role.
8. `network-dns.md` — remove ghost subdomain `bck`; align public-record list to services.md mirror
   (or link it once HD-198 lands).
9. Legacy blocks → ≤5 lines each: Immich hybrid storage (`deployment-compose.md` + `storage.md`),
   Proxmox VM table (`hardware-oldsrv.md`) — decision + changelog link only.
10. `interfaces.md` — pipeline step 5: either drop "commit+push" or mark it control-plane-manual
    (the role does not commit) — closes audit D11.
11. Date typos: `docs/services-ai.md` (10×), `docs/security.md` (4×, minus already-fixed),
    `docs/services-vps.md`, `docs/hardware-oldsrv.md` — 2025→2026.

## Validation

- `bash scripts/validate-all.sh` green after each few files.
- No new claims without a source: every "VPS-era" statement must match group_vars/playbooks.
- todo HD-196 ✅; changelog row listing files touched.
