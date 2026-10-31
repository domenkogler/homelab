# `prompt-media-arrs.md` — Lane brief · the media + music ladder, subtitles, downloads

> **Role:** dispatch note for **one** lane session on the media domain. **The rows are the authority** for what is missing
> and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-362 · HD-1088 · HD-1090 · HD-1091 · HD-1092 · HD-1096 · HD-353 · HD-354 · HD-230 · HD-1089 ·
> HD-1172** (row ids as of `c13e30f6` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge host + slot (O3):** **oldsrv** — the arr trio, slskd, Bazarr, Prowlarr and the NAS provisioning glue all render
from there. One converge in flight, per service directory one writer. HD-354's `music` door has a **VPS** half (the
`traefik-tailnet` edge router): that leg is a VPS converge, so sequence it and never run it while another lane holds the VPS.
⛔ **Do not share a wave with another oldsrv lane** — two lanes restarting containers on one box is the hazard O3 exists for,
and never beside a probe lane standing things up on oldsrv under the `domen` seat.

**Read first:** [docs/services-media.md](docs/services-media.md) §Music Pillar + §Subtitles →
[docs/services-downloads.md](docs/services-downloads.md) §Registering a torrent client in an app →
[docs/storage.md](docs/storage.md) §Store tiering + §Samba → [docs/backup.md](docs/backup.md).

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-362** | Verify the two Lidarr legs: submit one YouTube-sourced album through `lidarr-ydl` and read Lidarr's queue **and** the import, then exercise Aurral's recommendation → Lidarr add path once. ⛔ What Lidarr is missing is **APP state** — one indexer entry and one download-client entry, which is the seed-in-IaC question, not a UI hand-edit and not a secret | ⚠ `templates/docker_services/lidarr-ydl/docker-compose.yml.j2` reads `vault['lidarr_api'].credential` and `check-vault-items.sh` does **not** flag a missing `vault['X']` ref — a deleted vault item surfaces only as a 401 at the next music converge. Before re-enabling Tube Archivist, apply `path.repo` inside the ES container's own `elasticsearch.yml` (the env-var and `-E` forms both destabilise bootstrap). Aurral → Lidarr is a **browser** leg: the add is a click on a recommendation card and its URL+key live encrypted inside `aurral.db`, so nothing headless can drive it — park it |
| 2 | **HD-1088** | The push is **authored** (option B — `oldsrv` → Storage Box over SSH/SFTP `:23`, no new mount, the VPS-only `cifs` assert untouched; the keypair and `known_hosts` are on the box). What is owed is the **one blocked action first**: register `storage-push-music@oldsrv.kogler.si`'s public key on the live Box in the **Hetzner console** — port 23 is key-auth-only and the Box's vault item holds only a CIFS/WebDAV password, so there is no other way in — **PARKED** (O4). Only then `storage_push_music.enabled: true`, `--check` then `--tags storage --limit oldsrv.kogler.si`, then one `systemctl start push-music.service` and its far-side file-count read-back; then the ruling's end-to-end proof — one Lidarr-imported album in Navidrome with no manual copy, and a Lidarr move/rename removing the old Box path in the same run. The Kopia leg is a **separate parked act** (it restarts a running container: `--tags docker_services -e docker_services_scope=kopia-agent --limit oldsrv.kogler.si`, detached) | ⛔ Assert the mountpoint **before** copying and bound the deletion (`--max-delete` is a **CAP, not an abort**): a dead mount is an empty directory, and an empty directory is what Navidrome will then serve. The deploy script's identity assert runs **before** the mount assert, which is why the mount guard cannot be exercised live until the key exists. Retention (neither copy is in Kopia's scope) is an **owner** call — park it, do not decide it |
| 3 | **HD-1090** | One grab started in Prowlarr's own search UI must land in `/downloads/complete/prowlarr` — the idempotence and client-test halves are on record, the grab path is not | Needs a real indexer result, so it is an **owner-witnessed** leg: name the blocked action and continue. ⛔ Do not touch the arr-side clients and never add a second client of one protocol to an app — Prowlarr syncs indexers, never download clients. The directory not existing until qBittorrent first writes into it is expected |
| 4 | **HD-1091** | The bridge is **deployed** — a `docker_services` entry on the oldsrv Home leg with its own template dir + `soularr_version` pin, `soulseek-internal_api` rendered into **both** ends (`SLSKD_API_KEY` and soularr's `[Slskd] api_key`), both patience knobs at 3600. What the row owes is **one wanted album crossed end-to-end**: Lidarr wanted → slskd fetch → folder under the artist → Lidarr imports it — which needs a peer to finish one inside the poll window, so name it and continue. ⛔ `lidarr_api`, `soulseek_api`, `soulseek-internal_api` and `qbittorrent_api` are **rotated** with their holders re-taught — do not restate a rotation as owed and do not re-rotate one inside a session | Lidarr 3.1 has **no** Slskd download-client type — verify against `GET /api/v1/downloadclient/schema`, not the UI. The disk→Lidarr half is blocked by soularr's own `cancel_and_delete()` → `rmtree` on timeout, which deletes a part-delivered album's completed folder: the next act there is an **upstream/config question**, not another wait. Record the cross-bind consequence honestly: an arr cannot hardlink across the `/downloads` → `/media` binds, so it **moves** the file and seeding stops at import — an accepted cost, not a bug to re-litigate |
| 5 | **HD-1092** | Re-derive the row's premise **before** writing a step: the Authentik → NAS glue is torn down in the tree (`roles/storage/tasks/samba.yml` stops/disables the timer and removes its files), `op` on the NAS is **unwanted** rather than missing, and the family list is `storage_samba_users` in `host_vars/nas.kogler.si.yml` — a repo edit. What remains is one credential-bearing leg on a second host: re-prove a member's tree connect to their private drive from a client (`smbclient //nas/domen -A creds`, creds via stdin) — **parked** (O4). ⛔ 1005 (`media`) is a **supplementary** group by design (`groups: storage_gid, append: true`): a primary gid of 1005 would strip each member's own group and leave no ownership-based isolation, so do not accept `id <name>` on a primary gid | The `op`-on-the-NAS and the `smb.conf` include halves are **void as written** unless measurement contradicts the tree: provisioning no longer writes runtime share fragments, and `roles/storage/templates/smb.conf.j2` carries no such include (`/etc/samba/` holds only `smb.conf`, no `include` line, no `share-*.conf`). Install nothing on the NAS from this brief |
| 6 | **HD-1096** | Write `roles/docker_services/tasks/bazarr-seed.yml`, which does not exist yet: PVR keys read from each instance's own `config.xml` (the `arr-seed.yml` rule, never the vault copies), `languages-enabled`, provider creds from `opensubtitles_login`, gated like the other seeds (`not ansible_check_mode`). No Jellyfin leg: Bazarr's upstreams are the two arrs, `general.use_jellyfin` is declared false and the item that carried the leg is deleted ([docs/services-media.md](docs/services-media.md) §Credential rotation). ⛔ The seed never writes Bazarr's own `auth.apikey` — the instance issues it and no IaC file reads `bazarr_api`, so a rotation of that item propagates through nothing | **No credential rotation this round**: test the stored `opensubtitles_login` first and report whether Bazarr still reads `Login failed`; a browser rotate is owed only if it fails. The Languages-page profile-shape trap and the 1.6 API surface are in the owning doc — quote `bazarr_version`, not a number |
| 7 | **HD-354** | Open the `music` door: one `zone_kogler_si` row, a `music` router on the VPS `traefik-tailnet` edge (service-name backend to `navidrome:4533`, the `immich-backend` pattern), and the home edge's `music-backend` dialled at `wg_s2s_vps.ip:wg_internal_edge_port` (the `foto` precedent) | Prove it by dialling the **HOSTNAME**, not by reading `docker ps`. Quote `navidrome_version` from `IaC/ansible/group_vars/all/versions.yml` — the row still quotes an older tag, so read the pin, never the row. The empty-library and admin-user halves are **VOID** by owner fact: do not mint an admin for an empty library |
| 8 | **HD-353** | Owner leg only: verify the owner's own Jellyfin login at the `seerrng` route | Per-device and interactive — park it with the exact blocked action rather than staging a substitute check |
| 9 | **HD-230** | The batch's leftovers: the surgical converge + its verifies, then hand the two owner decisions (the Kopia source-wiring call and the two password items that row carries) | Both are deploy-gated / owner-owned; the repo halves are already in tree, so this line is converges + a park, nothing authored here |
| 10 | **HD-1089** | The seed is live on **oldsrv**; what is left is one read from a real tailnet client — `curl -sk https://sab.ts.kogler.si/` on a phone or laptop on the tailnet, answering anything other than `External internet access denied` | An **owner eyeball** (O4): this seat resolves no `.ts` name at all, so the seed's XFF-simulated probe is the whole automated proof. ⛔ Do not re-open the router or the LAN leg — both are proven fine |
| 11 | **HD-1172** | Land the **read-and-REPORT** leg in `arr-seed.yml`: GET the live `rootfolder` set and fail naming the path when a live root is not in `arr_seed_apps.lidarr.root_folders` — the prune-guard shape `scripts/gate/check_dns_seed_prune_guard.py` already uses for the DNS seed. ⛔ Ruled: **no root is declared and none is deleted before that report exists** — declaring both paths is a one-way door because `IaC/` carries no DELETE for `rootfolder`, and removing a live root is a human call made on the report | `/downloads/complete/music` is at the same moment slskd's completion dir and soularr's `download_dir`, and Lidarr binds `/mnt/nas/media/downloads` to `/downloads` — so an album pinned to a root inside that tree has its only copy in a directory soularr clears on timeout. Whether a second root is live is not readable from the tree; it needs `GET /api/v1/rootfolder` with `lidarr_api` |

## ⛔ Traps that cost a round

* **Quote a pin by its var, not by a line.** `navidrome_version`, `bazarr_version`, `slskd_version` in
  `IaC/ansible/group_vars/all/versions.yml` are the current truth; a row's number, and any `versions.yml:<line>` cite, are not.
* **Most of this lane's credentials are already rotated — ⛔ not again.** `lidarr_api` (moved at Lidarr's `config.xml`, in the
  row's forced order: mint → the app → restart → soularr's `config.ini` → SeerrNG, holders re-taught), `bazarr_api`,
  `soulseek_api` + `soulseek-internal_api` and `qbittorrent_api` all moved with their far ends. The two media web-auth users and
  the Seerr keys are **parked on the owner with no machine path**: this Jellyfin answers `POST /Users/<id>/Password` with 403
  and has no ApiKeys endpoint at all, this Radarr build has no user store, and `admin @radarr.kogler.si` carries the **same**
  value as `admin @media.kogler.si` — so the act is one UI change plus both vault writes, and the two Seerr keys move with it.
  The issuer/holder map is [docs/services-media.md](docs/services-media.md) §Credential rotation — point at it, do not restate
  it. ⛔ Probe slskd with `docker exec slskd /slskd/slskd --envars`, never by grepping a rendered compose, and the Soulseek
  **network** login is not rotatable from a seat: it stays a ledger debt, do not re-open it.
* **A green-looking timer is not evidence.** Read the unit's **exit status** and the artefact it claims to produce
  (`/tank/data/users`, `/etc/samba/share-*.conf`, `id <member>`), never the timer state.
* **Vault refs are invisible to the gate.** `check-vault-items.sh` does not flag a `vault['X']` reference in a compose
  template, so a renamed or deleted item is a runtime 401. When you add a service that consumes an API, register it in
  `_service_vault_items` in the same change (CONVENTIONS §2) and run the vault check.
* **Cross-bind moves, not hardlinks.** Anything importing across the `/downloads` → `/media` binds costs seeding; say so in
  the doc rather than presenting the ladder as lossless.
* **A mountpoint that is gone is an empty directory.** Every push/copy leg asserts the mount first and bounds `--delete`;
  unbounded deletion against an empty tree is how a music library disappears.
* Seeds are gated (`not ansible_check_mode`) and read app state from the **instance**, not from vault copies; an unseeded
  app looks healthy and serves an empty configuration (the Bazarr shape) — a route returning 200 is not an app being wired.
* Converge discipline: one oldsrv converge in flight, detached, guarded, one `/tmp` log per attempt; never change a scrape
  cadence or a monitoring role mid-lane, and never bundle the VPS edge half into an oldsrv run.

## Owns / never touches

**Owns:** the media/download service directories on oldsrv (`templates/docker_services/{radarr,sonarr,lidarr,lidarr-ydl,prowlarr,qbittorrent,slskd,bazarr,seerrng,navidrome,jellyfin}/**`
and their `tasks/*-seed.yml`), `roles/storage/**` for the family-account/Samba half,
`host_vars/nas.kogler.si.yml`'s `storage_samba_users`, `docs/services-media.md`, `docs/services-downloads.md`, the
`docs/storage.md` sections your rows falsify, and your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; `zone_kogler_si` itself and the DNS/answer-plane work
(the transport lane owns that list and its gates); traefik edge routers beyond the single `music` router HD-354 names;
`docs/services-authentik.md` beyond a claim this lane falsifies; `roles/router/**`; the NAS ZFS/Kopia/DR rows (the
storage-backup lane); `roles/monitoring/**`; the frozen archives and generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: the `lidarr-ydl` queue+import read and the Aurral add-path read · the Box push proven end-to-end with the
mount assert and the bounded delete in the diff, or the Hetzner-console key registration named as the park that blocks every
end-to-end proof on this row (retention parked as an owner decision, not answered) · one Prowlarr grab seen
in `/downloads/complete/prowlarr`, or that leg parked as owner-witnessed with the exact command · one album crossed end-to-end
by soularr, or that leg parked naming what it waits on · a member's private drive proven by a real tree connect from a client,
with the gid-1005 acceptance read off the row (supplementary, by design) and the HD-1092 premise re-derived against the tree ·
`bazarr-seed.yml` in tree with the seed re-run reporting `changed=0` and the
provider-auth read reported honestly · `music.kogler.si` answering by hostname on both edges · the root drift loud via the
read-and-REPORT leg, with no root declared or deleted before that report exists · the owner legs on HD-353 /
HD-230 named as parks · rows deleted or trimmed to their tails, no history in the row · `bash scripts/validate-all.sh` green
**in this worktree** → **stop**.
