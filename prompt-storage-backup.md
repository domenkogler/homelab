# `prompt-storage-backup.md` — Lane brief · nas ZFS policy units, Kopia, the DR story

> **Role:** dispatch note for **one** lane session on the storage + backup domain. **The rows are the authority** for what is
> missing and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-06 · HD-207 · HD-1105 · HD-1106 · HD-1107 · HD-191 · HD-238 · HD-1093**
> (row ids as of `16177f19` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O9) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge hosts + slots (O3):** **nas** is the primary slot (`playbooks/storage.yml`: sanoid/syncoid, NFS/SMB exports, the
pool), **oldsrv** carries the Kopia agent legs, the **VPS** carries `kopia-server` and the volume inventory, and the **nas +
Pi + oldsrv** `nut` legs are one logical change across three hosts. One converge in flight per host, detached, **never
`--diff`**. ⛔ **Do not share a wave with another lane on nas or oldsrv** — `--tags samba` rewrites the passdb, the sanoid
units are shared with everything that snapshots, and a converge that restarts containers on oldsrv while a sibling is
measuring there invalidates both runs. Destroying anything in a pool is never a side effect of a converge: name the dataset,
show `zfs list`, then act.

**Read first:** [docs/storage.md](docs/storage.md) → §Samba (SMB) shares on the NAS · [docs/backup.md](docs/backup.md) →
§The slot-numbering rule → §VPS-side coverage gap → §Runbook → §Restore drill → §Recovery Paths ·
[docs/hardware-nas.md](docs/hardware-nas.md) · [docs/hardware-ups.md](docs/hardware-ups.md) ·
[docs/storage-rejected.md](docs/storage-rejected.md) before re-proposing anything.

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-1107** | Run the repaired `sanoid` unit once by hand and prove `hourly.*` / `daily.*` snapshots appear and stay inside the config window; then decide `/etc/cron.d/sanoid` | The fix is `ExecStart=/usr/sbin/sanoid --cron` (`IaC/ansible/roles/storage/tasks/nas.yml:53`) — the unit **we generate** pointed at `/usr/local/bin/sanoid`, which the Debian package never installs. Quote `systemctl cat sanoid` **on the box**, not the repo. ⚠ The package also ships its own scheduling: two schedulers firing is one scheduler with double the retention math, and `hourly=24 daily=7` read from `sanoid.conf` says nothing about what ran |
| 2 | **HD-1105** | Decide per unit on nas whether it is wanted: configure or **disable** — `zfs-share.service` (`zfs share -a` exits 1), `winbind.service` (enabled, exits 1 while `smb` is enabled), and the `sync-authentik-users.service` stub whose `ExecStart` is empty (127) | `ok=159 failed=0` proves nothing here: a systemd-level failure is invisible to Ansible idempotency. Acceptance is `systemctl list-units --failed` empty, or a written justification per surviving failure. ⛔ Do not disable `winbind` to silence the red — with `smb` enabled it is the SMB-share story, not noise |
| 3 | **HD-1093** | Land the rotated family SMB passwords on the NAS with the row's exact command (`… playbooks/storage.yml --no-pull --limit nas.kogler.si --tags samba -e '{"storage_samba_password_force":["domen","shared"]}'`), then read the passdb back | A vault rotate alone changes NOTHING on the box — the passdb write is a target-side act gated by `storage_samba_password_force` (`IaC/ansible/roles/storage/tasks/samba.yml:215`, `defaults/main.yml:75`). Prove with `pdbedit -L` + one authenticated mount, not with the vault timestamp |
| 4 | **HD-1106** | Inventory the dangling VPS volumes **with provenance** — creating compose project, first mtime, whether a bind mount replaced them — then prune only what is proven empty | ⛔ Do not delete unattributed state to reclaim space: the two 47 MB volumes are the whole risk and 644 MB is not a reason. A snapshot list is not a provenance read. Anonymous volumes created by a session's own experiment are that session's residue — attribute them in the table, never "pruned as empty" |
| 5 | **HD-191** | The Kopia legs: (a) a **restore drill** from an oldsrv snapshot with the volume-name pin verified at restore; (b) the missing VPS backup **client** — an agent container + include list (`/opt`, the dump volume, the `/srv/docker/*` state dirs), not two paths added to an include list; (c) oldsrv has no `db-backup` job, so `/srv/dumps` snapshots an empty dir and `lan-litellm-db` has no dump anywhere | A `kopia snapshot list` is not a restore. ⚠ The VPS runs `kopia-server` — the endpoint the other agents push through — and has **no client of its own** (no binary, no client config, no `kopia-agent` container), so today no `/srv/docker/*` path and no `db-backup` dump reaches any off-site snapshot |
| 6 | **HD-06** | ⏳ Owner-scheduled: the short battery pull re-test → poweroff + WoL wake end-to-end. Park it with the exact action and finish everything else (O4) | ⛔ Never a destructive pull in an unattended run. The drill exists because the notify/shutdown layer failed in three independent places (an ACL that stripped group-execute despite mode 0750, shell-not-Jinja SMTP vars that rendered literal `${…}`, no sudoers entry for `/sbin/shutdown`) — so prove each leg, not the happy path |
| 7 | **HD-207** | Redistribute the migration landing zone slowly per the storage SSOT (`playbooks/storage.yml`), then destroy it — personal documents to the OpenCloud/live-Box tier, interim `/tank/data/users/<name>/` park, media to `bulk/media/*` | ⛔ Never a recursive bulk move across datasets; copy + verify + delete, and show `zfs list` before destroying. The landing zone must be gone **before** the tree is declared equal to the storage-role SSOT; a rename that is really a personal-vs-media **decision** is an owner leg, not a convenience move |
| 8 | **HD-238** | ⏳ Owner-scheduled only: run the DR drill and tick it with a dated result; fill the per-service fail-over-vs-accept-loss table | Name the dependency honestly: while the HD-191 VPS-client leg is unlanded the runbook **cannot** promise the VPS's own state, so the drill result must say which restores it actually exercised. Address plane before data plane — a changed public IPv4 moves the DNS primary, the Cloudflare origin, the advertised routes and the conditional forwarder in one commit |

## ⛔ Traps that cost a round (re-grounded at this `HEAD`)

* **Green converge ≠ healthy box.** Three nas units fail on a converge that reports `failed=0`; a timer that is *enabled* and a
  unit whose `ExecStart` points at a nonexistent path look identical in Ansible output. Always read the systemd state directly.
* **Backups are proven by restore, never by listing.** A snapshot set, a dump file, or an "Up" agent is a state that coexists
  with an unrecoverable box. Every backup claim in this lane needs a restore command and its output.
* **A scheduled thing that fails every night is invisible** if nothing scrapes the result — the ZFS second copy that every
  restore story assumes was absent for weeks while `sanoid.conf` looked correct. If your change lands a unit, land the proof it
  ran (`zfs list -t snapshot`, not the timer's `LastTriggerUSec`).
* **Password rotation has two halves**: the vault and the target. `pdbedit` state is the only proof, and NT-hash offline
  cracking makes a short family password a box-wide problem (one captured LAN exchange is enough).
* **Never widen a destructive command's scope by accident**: name datasets explicitly, no `rm -r`, no pool-wide destroy in a
  converge, and check `zfs list` / `docker volume ls` immediately before the act.
* Kopia's slot/identity conventions are load-bearing: an agent authenticates as its **own** `<host>-agent@<host>` identity, not
  the server admin user, and dump slot numbers are contiguous — a number reserved in prose but absent from the compose dumps
  nothing ([docs/backup.md](docs/backup.md) §The slot-numbering rule).
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
not run. Concretely: fresh `hourly.*` snapshots in `zfs list -t snapshot` from a unit whose rendered `ExecStart` is quoted, with
the dual-scheduler question decided · nas's `systemctl list-units --failed` empty or each survivor justified in writing · the
SMB passdb read back after the forced converge plus one authenticated mount, with the vault rotate named as the half that was
already done · a per-volume provenance table with a verdict each and `docker volume ls --filter dangling=true` reduced to the
justified ones · the Kopia restore drill executed with the restored paths listed, the VPS client landed or the exact blocker
written, and the oldsrv dump gap closed or parked · the battery drill `PARKED` with its exact owner action and no destructive
pull run unattended · the landing-zone redistribution either done with the dataset list or parked at the owner decision it
waits on, the destroy deferred to the same change as the proof · the DR drill `PARKED` with the owner-scheduling action and
the loss table either filled or named as missing · rows trimmed to their tails or deleted, no history in the row ·
`bash scripts/validate-all.sh` green **in this worktree** → **stop**.
