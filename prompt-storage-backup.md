# `prompt-storage-backup.md` — Lane brief · nas ZFS policy units, Kopia, the DR story

> **Role:** dispatch note for **one** lane session on the storage + backup domain. **The rows are the authority** for what is
> missing and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-06 · HD-207 · HD-1105 · HD-1106 · HD-191 · HD-238 · HD-1129 · HD-1183 ·
> HD-1174** — the last one, in one clause: scrub the `kopia repository connect server` line in the **kopia-agent** leg,
> then rotate with the agent **re-connected**, because its `repository.config` caches the credential. `kopia-server_fingerprint`
> is a TLS **cert** fingerprint, not a credential, so its leak-ledger line stays while the cert is the value — a named debt,
> never a reason to re-open that rotation (row ids as of `c13e30f6` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge hosts + slots (O3):** **nas** is the primary slot (`playbooks/storage.yml`: sanoid/syncoid, NFS/SMB exports, the
pool), **oldsrv** carries the Kopia agent legs, the **VPS** carries `kopia-server` and the volume inventory, and the **nas +
Pi + oldsrv** `nut` legs are one logical change across three hosts. One converge in flight per host, detached, **never
`--diff`**. ⛔ **Do not share a wave with another lane on nas or oldsrv** — `--tags samba` rewrites the passdb, the sanoid
units are shared with everything that snapshots, and a converge that restarts containers on oldsrv while a sibling is
measuring there invalidates both runs. Destroying anything in a pool is never a side effect of a converge: name the dataset,
show `zfs list`, then act.

**Read first:** [docs/storage.md](docs/storage.md) → §Samba (SMB) shares on the NAS · [docs/backup.md](docs/backup.md) →
§The slot-numbering rule → §VPS-side coverage gap → §VPS-side backup client → §Runbook → §Restore drill → §Recovery Paths ·
[docs/hardware-nas.md](docs/hardware-nas.md) · [docs/hardware-ups.md](docs/hardware-ups.md) ·
[docs/storage-rejected.md](docs/storage-rejected.md) before re-proposing anything.

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-1105** | **All three units are ruled and fixed** — `zfs-share.service`, `winbind.service` and the empty-`ExecStart` `sync-authentik-users.service` stub are settled in [docs/storage.md](docs/storage.md) (§NFS Exports for `zfs-share`, §Samba for `winbind`; the stub is gone with only its stale failed-marker left) and `systemctl list-units --failed` lists 0 on nas. What the row still holds is one **PARKED** owner call (O4): the durable cure for a returning `zfs-share` red is `sharesmb=off` on the `bulk/migrate/**` migration remnants — a property change on a 2.33 TB tree nobody has ruled | Do not re-decide the three units: read `systemctl list-units --failed` first, and it answers 0. ⚠ If the `zfs-share` red ever returns, it arrived through `PartOf=nfs-server.service smb.service` (a Samba/NFS restart re-runs `zfs share -a`) — which is why the cure is the dataset property, not the unit. ⛔ Do not disable `winbind` to silence a red — with `smb` enabled it is the SMB-share story, not noise |
| 2 | **HD-1106** | **The named-volume half is done, so the owed act is the prune itself.** `onlyoffice-docs`' `/var/www/onlyoffice/Data` (the **WOPI/JWT keypair**) and `/var/log/onlyoffice` are named volumes now, and that fix was applied **before** the VPS `docker` converge — which is why the minted keypair survived the recreate. Now: one `docker volume rm <name>` per row the table marks `prune` / `prune-when-proven`, in a VPS window, re-reading `docker volume ls -q --filter dangling=true \| wc -l` after each | ⛔ A blanket `docker volume prune -f` stays refused — it takes the `keep` rows with the rest, and the standing rule that destroying live host state runs in a **window** is not lifted by the ruling (the owner approved the SET, not an overnight execution). The per-volume verdicts are [docs/services-vps.md](docs/services-vps.md) §The dangling-volume table; the six onlyoffice rows are exactly what the named-volume fix justifies. ⚠ That table's "what serves that path today" column names the two named volumes for those six rows, since the fix is live; re-read the count before quoting it — `docker volume ls -q --filter dangling=true \| wc -l` answers **44** |
| 3 | **HD-191** | The Kopia legs: (a) a **restore drill** from an oldsrv snapshot with the volume-name pin verified at restore; (b) the missing VPS backup **client** — the shape is **ruled** (a `kopia-agent` container on the VPS in oldsrv's own agent shape, [docs/backup.md](docs/backup.md) §VPS-side backup client), so the first act is to **price it**: `du -sh` over the three include roots (`/opt`, the `db-backup` dump volume, the `/srv/docker/*` state dirs) plus one snapshot of one small state dir from a throwaway client, and write those numbers into that section **before** authoring an include list — the `du` half is done and written there; the throwaway-client half is **parked behind the `kopia-server-internal_api` rotation**, because a scratch `repository connect server` carries that credential in the URL userinfo (the HD-1174 class), so the pricing act must not create the leak it is pricing; (c) **nothing is owed for the oldsrv dump leg** — `/srv/dumps` holds 14 `lan-litellm-db-*.sql.gz`, the push timer lands them on the NAS nightly and the agent snapshots that source (`files:14`); the earlier wording here ("no `db-backup` job", "an empty dir") was wrong and [docs/backup.md](docs/backup.md) §What Gets Backed Up is the SSOT | A `kopia snapshot list` is not a restore. ⚠ The VPS runs `kopia-server` — the endpoint the other agents push through — and has **no client of its own** (no binary, no client config, no `kopia-agent` container), so today no `/srv/docker/*` path and no `db-backup` dump reaches any off-site snapshot. `db-backup` stays the Postgres restore path — a file-level snapshot of a live database directory is not a dump — and a new client inherits **nothing**, so oldsrv's exclusions are re-declared, not inherited. ⛔ **the converge rides the pin window's VPS leg, LAST**: on that host an act that restarts the tailnet sidecar or Traefik costs the control channel, so it is never taken mid-lane |
| 4 | **HD-06** | ⏳ Owner-scheduled: the short battery pull re-test → poweroff + WoL wake end-to-end. Park it with the exact action and finish everything else (O4) | ⛔ Never a destructive pull in an unattended run. The drill exists because the notify/shutdown layer failed in three independent places (an ACL that stripped group-execute despite mode 0750, shell-not-Jinja SMTP vars that rendered literal `${…}`, no sudoers entry for `/sbin/shutdown`) — so prove each leg, not the happy path |
| 5 | **HD-207** | Redistribute the migration landing zone slowly per the storage SSOT (`playbooks/storage.yml`), then destroy it — personal documents to the OpenCloud/live-Box tier, interim `/tank/data/users/<name>/` park, media to `bulk/media/*` | ⛔ Never a recursive bulk move across datasets; copy + verify + delete, and show `zfs list` before destroying. The landing zone must be gone **before** the tree is declared equal to the storage-role SSOT; a rename that is really a personal-vs-media **decision** is an owner leg, not a convenience move |
| 6 | **HD-238** | ⏳ Owner-scheduled only: run the DR drill and tick it with a dated result; fill the per-service fail-over-vs-accept-loss table | Name the dependency honestly: while the HD-191 VPS-client leg is unlanded the runbook **cannot** promise the VPS's own state, so the drill result must say which restores it actually exercised. Address plane before data plane — a changed public IPv4 moves the DNS primary, the Cloudflare origin, the advertised routes and the conditional forwarder in one commit |
| 7 | **HD-1129** | The **VPS** leg: move the ~289 MB of Immich originals still on the VPS NVMe onto the live Hetzner Box mount, point the Immich storage path at it, and prove a fresh upload lands on the Box | Assert the Box mount **before** moving anything — a dead CIFS mount is an empty directory. When it lands, `docs/backup.md`'s scope statement needs no exception; the VPS volume inventory (HD-1106) is the same slot, sequence rather than bundle |
| 8 | **HD-1183** | Fix the boot catch-up in `roles/storage`: give `push-db-dumps-push.service.j2` the ordering its guard assumes (`RequiresMountsFor=/mnt/nas/data`, or `After=` on the `mnt-nas-data.automount` unit) so `findmnt` no longer loses the race with the `x-systemd.automount` trigger — **the ordering landed and is live on oldsrv** (`systemctl show -p Requires` resolves `mnt-nas-data.mount`); what is left is the owner's paging call and a boot to prove it | ⛔ **oldsrv, and run it OFF-box** — [docs/deployment-ansible.md](docs/deployment-ansible.md) §Self-converge guardrail refuses a `--tags storage` run whose controller is the target, and a `--check` of this role never reaches the assert. The guard stays: it is the ordering that is wrong, not the check. The unit is storage's; making it **page** (adding it to `monitoring_hygiene_units`) is the observability lane's HD-450 class, and the one `systemctl start` that lands the owed dump is an owner hand |

## ⛔ Traps that cost a round

* **Green converge ≠ healthy box.** A converge that reports `failed=0` can still leave systemd units in `failed` — a
  timer that is *enabled* and a unit whose `ExecStart` points at a nonexistent path look identical in Ansible output.
  Always read the systemd state directly.
* **Backups are proven by restore, never by listing.** A snapshot set, a dump file, or an "Up" agent is a state that coexists
  with an unrecoverable box. Every backup claim in this lane needs a restore command and its output.
* **A scheduled thing that fails every night is invisible** if nothing scrapes the result — `sanoid.conf` reading correct
  coexists with a second copy that no restore story can rely on. If your change lands a unit, land the proof it
  ran (`zfs list -t snapshot`, not the timer's `LastTriggerUSec`).
* **Password rotation has two halves**: the vault and the target. `pdbedit` state is the only proof, and NT-hash offline
  cracking makes a short family password a box-wide problem (one captured LAN exchange is enough).
* **Never widen a destructive command's scope by accident**: name datasets explicitly, no `rm -r`, no pool-wide destroy in a
  converge, and check `zfs list` / `docker volume ls` immediately before the act.
* Kopia's slot/identity conventions are load-bearing: an agent authenticates as its **own** `<host>-agent@<host>` identity, not
  the server admin user, and dump slot numbers are contiguous — a number reserved in prose but absent from the compose dumps
  nothing ([docs/backup.md](docs/backup.md) §The slot-numbering rule).
* **A kopia-server cert regen can come back loopback-only.** The boot command reads
  `subjectAltName=IP:${KOPIA_SERVER_ADDR_HOST:-127.0.0.1}` at container RUNTIME while the value lands in the project `.env`,
  which that compose never lists under `env_file:` — the fallback fires and the pair comes back with a **loopback-only SAN**
  while the agent dials `wg_s2s_vps.ip` (the trap is stated in [docs/backup.md](docs/backup.md) §Layer 2: Kopia). The template
  **assert** that would catch it is not in the tree and needs a converge to prove: owed on a **kopia converge leg**, never as a
  quiet author-only fix.
* Converge storage/nut legs **detached and guarded**, per host, never with `--diff`; the UPS change touches three hosts and
  each is a separate slot.

## Owns / never touches

**Owns:** `IaC/ansible/roles/storage/**` (incl. `tasks/nas.yml`, `tasks/samba.yml`, sanoid/syncoid templates),
`IaC/ansible/roles/nut/**`, `IaC/ansible/playbooks/storage.yml`, `IaC/ansible/templates/docker_services/{kopia-agent,kopia-server,db-backup}/**`,
the `storage_*` / `nut_*` / `kopia_*` regions of `group_vars` and `host_vars`, `docs/storage.md`, `docs/backup.md`,
`docs/hardware-nas.md`, `docs/hardware-ups.md`, `docs/storage-rejected.md`, and your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; the alert **rules** and the hygiene collector (the
observability lane owns the rules that read your units — HD-450 is that lane's row); the VPS identity/OIDC services and the
Authentik users your stub unit once referenced (the edge-identity lane); `roles/access` and the grant plumbing; the LiteLLM
gateway and its keys; traefik edges and the DNS answer plane; `IaC/router/**` and the global router slot; the spark engine and
its bench; the laptop legs; the frozen archives and generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: policy snapshots under `@autosnap_…_hourly` on the configured datasets — `zfs list -t snapshot | grep _hourly`,
never a `@hourly.` grep — from a unit whose rendered `ExecStart` is quoted, plus the syncoid leg either replicating or
parked with its stuck send named · nas's `systemctl list-units --failed` empty or each survivor justified in writing · the
SMB passdb read back after the forced converge plus one authenticated mount, with the vault rotate named as the half that was
already done · `docker volume ls --filter dangling=true` reduced to the table's justified rows, each removal named and
re-read after the act, with the WOPI keypair digest proven identical across the recreate · the Kopia restore drill executed with
the restored paths listed, the VPS client landed **with its include list priced by the sizes written back to the doc** or the
exact blocker written, and the oldsrv dump gap closed or parked · the battery drill `PARKED` with its exact owner action and no
destructive pull run unattended · the landing-zone redistribution either done with the dataset list or parked at the owner
decision it waits on, the destroy deferred to the same change as the proof · the DR drill `PARKED` with the owner-scheduling
action and the loss table either filled or named as missing · rows trimmed to their tails or deleted, no history in the row ·
`bash scripts/validate-all.sh` green **in this worktree** → **stop**.
