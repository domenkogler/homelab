# prompt-hd191 — oldsrv Kopia agent (S18/J5)

> **Role:** Task handoff for **HD-191** (todo.md §2.9). **Linked from:** [todo.md](todo.md);
> audit evidence: `security.md` §5 S18, `docs-vs-iac.md` §J5, `architecture.md` W12.

## Problem

`backup.md` says Kopia runs on **VPS + oldsrv** (sources: `/srv/dumps`, service state dirs,
Immich face thumbs, `/opt/*` compose configs), NAS-independent. Reality: only the VPS has
`kopia-server` + `db-backup` in `group_vars/vps.yml`; **`group_vars/home_servers.yml` has no kopia
entry** → oldsrv-local state never reaches the off-site backup Box.

## Design (per existing docs — confirm while implementing)

- The repo server (`kopia-server`) lives on the **VPS**; its repository backend is the Hetzner
  **backup Box over SFTP** (`kopia_sftp_*` in `all.yml`). Server auth = `kopia-server-internal_api`
  (htpasswd, HD-59).
- oldsrv therefore runs a **kopia agent** (client): `kopia repository connect server --url=https://…`
  or `http://kopia-server:51515` over `services-internal`/WG with the htpasswd identity, then a
  systemd timer snapshots the local sources.
- Cross-host reach: oldsrv → kopia-server (VPS) is home-initiated over WG — allowed by the S2S
  scoping (router routes `wg-vps-services`; VPS nftables forward admits docker-bound traffic).
  Verify the kopia-server port (51515) is reachable on the overlay path; it is NOT published
  (correct) — the client must target the overlay/WG address per the prometheus/loki bind pattern.

## Steps

1. New template `templates/docker_services/kopia-agent/docker-compose.yml.j2` (client mode:
   `kopia repository connect server …` + `kopia snapshot create <sources>` via a small entrypoint
   script or scheduled command) — OR a host-native systemd timer if containerizing the client adds
   friction with `/srv/dumps` + `/opt/*` reads (decide; document why).
2. Register `kopia-agent` in `group_vars/home_servers.yml`; add any needed 1Password item to
   `docs/deployment-secrets.md` master list (likely reuse `kopia-server-internal_api`; no new item
   unless the design needs one).
3. Sources per backup.md §Kopia Policy: `/srv/dumps`, service state dirs, thumbs, `/opt/*` configs;
   exclusions: TSDB, docker layers, models, `/mnt/nas/*`.
4. Align `backup.md` (agent section: host, transport, schedule) and `storage.md` push-job notes if
   wording changes.
5. `bash scripts/validate-all.sh` green (new template dir must appear in a docker_services list —
   count-lint enforces it).
6. todo HD-191 ✅ IaC with `⏳ Deploy-gated:` tail: "first snapshot from oldsrv lands in the repo;
   restore drill picks it up". changelog row.

## Constraints

- Kopia stays NAS-independent (never read `/mnt/nas/*`) — backup.md invariant.
- No new S3 anything (Box is SSH/SFTP-only; the repo already lives behind kopia-server).

**Cleanup:** delete this handoff (`prompt-hd191.md`) in the same closing change (A3 lifecycle, CONVENTIONS §4; HD-203 sweeps any leftovers).
