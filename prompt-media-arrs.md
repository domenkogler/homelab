# `prompt-media-arrs.md` — Lane brief · the media + music ladder, subtitles, downloads

> **Role:** dispatch note for **one** lane session on the media domain. **The rows are the authority** for what is missing
> and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-362 · HD-1088 · HD-1090 · HD-1091 · HD-1092 · HD-1096 · HD-353 · HD-354 · HD-230**
> (row ids as of `9e661845` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O9) — read it once; it overrides README §4 and
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
| 1 | **HD-362** | Verify the two Lidarr legs: submit one YouTube-sourced album through `lidarr-ydl` and read Lidarr's queue **and** the import, then exercise Aurral's recommendation → Lidarr add path once | ⚠ `templates/docker_services/lidarr-ydl/docker-compose.yml.j2` reads `vault['lidarr_api'].credential` and `check-vault-items.sh` does **not** flag a missing `vault['X']` ref — a deleted vault item surfaces only as a 401 at the next music converge. Before re-enabling Tube Archivist, apply `path.repo` inside the ES container's own `elasticsearch.yml` (the env-var and `-E` forms both destabilise bootstrap) |
| 2 | **HD-1088** | Author the **ruled** push — option B, `oldsrv` → Storage Box rsync/SFTP over `:23`, no new mount, the VPS-only `cifs` assert untouched — then prove one Lidarr-imported album appears in Navidrome with no manual copy, and a Lidarr move/rename removes the old Box path in the same run | ⛔ Assert the mountpoint **before** copying and bound the deletion (`--max-delete`): a dead mount is an empty directory, and an empty directory is what Navidrome will then serve. Retention (neither copy is in Kopia's scope) is an **owner** call — park it, do not decide it |
| 3 | **HD-1090** | One grab started in Prowlarr's own search UI must land in `/downloads/complete/prowlarr` — the idempotence and client-test halves are on record, the grab path is not | Needs a real indexer result, so it is an **owner-witnessed** leg: name the blocked action and continue. ⛔ Do not touch the arr-side clients and never add a second client of one protocol to an app — Prowlarr syncs indexers, never download clients. The directory not existing until qBittorrent first writes into it is expected |
| 4 | **HD-1091** | Wire the Soulseek → Lidarr bridge (`mrusse/soularr`): choose and justify the deployment shape (`docker_services` entry with its own template dir + pin + `enabled:` on the Home leg, or an oldsrv systemd timer), register `lidarr_api` + `soulseek_api` under the new service name in `_service_vault_items`, then live-verify one wanted album end-to-end | Lidarr 3.1 has **no** Slskd download-client type — verify against `GET /api/v1/downloadclient/schema`, not the UI. Record the HD-1086 consequence honestly: an arr cannot hardlink across the `/downloads` → `/media` binds, so it **moves** the file and seeding stops at import — an accepted cost, not a bug to re-litigate |
| 5 | **HD-1092** | Re-derive the row's premise **before** writing a step: the Authentik → NAS glue is torn down in the tree (`roles/storage/tasks/samba.yml` stops/disables the timer and removes its files), and the family list is `storage_samba_users` in `host_vars/nas.kogler.si.yml` — a repo edit. Then verify the owed outcome: a family member's `id <name>` returns a uid with primary gid **1005** and their private drive really mounts | The `op`-on-the-NAS and the `smb.conf` include halves are **void as written** unless measurement contradicts the tree: provisioning no longer writes runtime share fragments, and `roles/storage/templates/smb.conf.j2` carries no such include. Install nothing on the NAS from this brief |
| 6 | **HD-1096** | Write `roles/docker_services/tasks/bazarr-seed.yml`: PVR keys read from each instance's own `config.xml` (the `arr-seed.yml` rule, never the vault copies), the Jellyfin url+key from the vault, `languages-enabled`, provider creds from `opensubtitles_login`, gated like the other seeds (`not ansible_check_mode`) | **No credential rotation this round**: test the stored `opensubtitles_login` first and report whether Bazarr still reads `Login failed`; a browser rotate is owed only if it fails. The Languages-page profile-shape trap and the 1.6 API surface are in the owning doc — pin is `versions.yml:83` |
| 7 | **HD-354** | Open the `music` door: one `zone_kogler_si` row, a `music` router on the VPS `traefik-tailnet` edge (service-name backend to `navidrome:4533`, the `immich-backend` pattern), and the home edge's `music-backend` dialled at `wg_s2s_vps.ip:wg_internal_edge_port` (the `foto` precedent) | Prove it by dialling the **HOSTNAME**, not by reading `docker ps`. The pin is `versions.yml:102` — the row still quotes an older tag, so re-read before repeating a number. The empty-library and admin-user halves are **VOID** by owner fact: do not mint an admin for an empty library |
| 8 | **HD-353** | Owner leg only: verify the owner's own Jellyfin login at the `seerrng` route | Per-device and interactive — park it with the exact blocked action rather than staging a substitute check |
| 9 | **HD-230** | The batch's leftovers: the surgical converge + its verifies, then hand the two owner decisions (the Kopia source-wiring call, HD-211's password items) | Both are deploy-gated / owner-owned; the repo halves are already in tree, so this line is converges + a park, nothing authored here |

## ⛔ Traps that cost a round (re-grounded at this `HEAD`)

* **Quote a pin only with its `versions.yml` line beside it.** Navidrome, Bazarr and slskd all moved since the rows were
  written — `versions.yml:102`, `versions.yml:83`, `versions.yml:107` are the current truth; a row's number is not.
* **A green-looking timer is not evidence.** HD-1092's glue exited 127 on all 823 runs while the unit read enabled: read the
  unit's **exit status** and the artefact it claims to produce (`/tank/data/users`, `/etc/samba/share-*.conf`, `id <member>`),
  never the timer state.
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
mount assert and the bounded delete in the diff (retention parked as an owner decision, not answered) · one Prowlarr grab seen
in `/downloads/complete/prowlarr`, or that leg parked as owner-witnessed with the exact command · soularr deployed with both
vault items registered and one album in the Lidarr library · a family member resolving to gid 1005 with a real mount, plus the
HD-1092 premise re-derived against the tree · `bazarr-seed.yml` in tree with the seed re-run reporting `changed=0` and the
provider-auth read reported honestly · `music.kogler.si` answering by hostname on both edges · the owner legs on HD-353 /
HD-230 named as parks · rows deleted or trimmed to their tails, no history in the row · `bash scripts/validate-all.sh` green
**in this worktree** → **stop**.
