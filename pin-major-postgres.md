# pin-major-postgres.md — `*_db_version` / `*_pg_version` 16.15 → 18.6, the four legs still owed

> **Role:** one-session brief for the Postgres **data-format** major on the clusters still at 16: the pin lines,
> the live state, the preconditions, the procedure, the acceptance read and the rollback. It carries no queue row
> and states no status — the fleet pin SSOT is `IaC/ansible/group_vars/all/versions.yml`, the procedure SSOT is
> [docs/backup.md](docs/backup.md) §Postgres major upgrades, the rule is [CONVENTIONS.md](CONVENTIONS.md) §7.
> **Linked from:** [prompt-update.md](prompt-update.md) (the majors the pin sweep must not touch) ·
> [pin-major-onlyoffice.md](pin-major-onlyoffice.md) · [pin-major-forgejo.md](pin-major-forgejo.md)

**Verdict: four legs remain, and they are held by pacing, not by a blocker.** An existing PGDATA does not start
on the next major — the container exits `database files are incompatible with server` — so a 16 → 18 bump is a
**dump-and-restore**, one cluster per window, with rollback = pin **and** datadir moved back together. Owner
pacing is the standing rule: **one cluster per window**, each proved by its own `pg_control` read and by the next
`db-backup` run that dumps it.

## 1. The fleet's Postgres map

| cluster | host | pin var | live | dump target | this brief |
|---|---|---|---|---|---|
| `authentik-postgres` | vps | `authentik_db_version: 18.6-alpine` | **18** (`pg_control 1800`) | DB01 | done — fleet SSO, rollback datadir `postgres.16-20261008` kept |
| `litellm-db` | vps | `litellm_db_version: 18.6-alpine` | **18** (`pg_control 1800`) | DB04 | done — the leg that taught the three requirements in §3 |
| `forgejo-db` | vps | `forgejo_db_version: 16.15-alpine` | 16 (`1300`) | DB02 | **owed** — extra duty: cluster roles (§4a) |
| `zipline-db` | vps | `zipline_db_version: 16.15-alpine` | 16 (`1300`) | DB05 | **owed** — the app pin is separately held (§4b) |
| `onlyoffice-postgres` | vps | `onlyoffice_pg_version: 16.15-alpine` | 16 (`1300`) | DB06 | **owed** — datadir is a **named volume** (§4c) |
| `lan-litellm-db` | oldsrv | `lan_litellm_db_version: 16.15-alpine` | 16 (`1300`) | **none** | **owed** — needs a hand dump (§4d) |
| `immich-postgres` | vps | *(no var — composite image tag)* | 14.19 | DB03 | **out of scope**, permanently: see §5 |

(`live-verified 2026-10-27`; re-derive with §2 — a status line in a brief is a hint, the box is the truth.)

⚠ **`lan_litellm_db_version` has no `SOURCES` entry in `scripts/ansible/image-pin-probe.py`** — the probe prints
`skipped: NOT IN THE SOURCE TABLE` for it, so every "how many majors are outstanding" census built from the
probe undercounts by exactly this cluster. Fixing the probe's table is part of landing this leg.

## 2. Re-derive before acting (read-only)

```bash
ssh -n vps 'for c in authentik-postgres litellm-db forgejo-db zipline-db onlyoffice-postgres immich-postgres; do
              printf "%-20s " $c; docker exec $c cat /var/lib/postgresql/data/PG_VERSION; done
            for c in forgejo-db zipline-db onlyoffice-postgres; do printf "%-20s " $c;
              docker exec $c pg_controldata /var/lib/postgresql/data | grep -i "pg_control version"; done
            ls -d /srv/docker/*/postgres* ; docker volume ls | grep pgdata'
ssh -n oldsrv 'docker exec lan-litellm-db cat /var/lib/postgresql/data/PG_VERSION
               docker exec lan-litellm-db printenv PGDATA POSTGRES_INITDB_ARGS'
```

Two reads decide whether the window is open at all: every candidate must already carry
`PGDATA=/var/lib/postgresql/data` and `POSTGRES_INITDB_ARGS=--locale=en_US.utf8 --locale-provider=libc`
(`live-verified 2026-10-27`: both are in place on the 16 sidecars — the templates are PG-18-ready, only the pin
and a restore are missing).

## 3. The three things PG 18 requires (why the obvious leg fails twice)

Carried here so the session does not have to guess; the measurement trail is
[docs/backup.md](docs/backup.md) §What PG 18 actually requires.

1. **`PGDATA` pinned to the flat path.** The 18 images default to the version-specific
   `/var/lib/postgresql/18/docker` and their entrypoint refuses to start when the cluster sits elsewhere. A pin
   bump alone therefore fails at first boot and attaches an anonymous volume at `/var/lib/postgresql` while
   failing.
2. **Never the upstream "parent mount" shape.** It needs the entrypoint to create `/var/lib/postgresql/18` as
   root inside the container; these DB services run `cap_drop: ALL` with `CHOWN/DAC_READ_SEARCH/FOWNER/SETUID/
   SETGID` only — **no `CAP_DAC_OVERRIDE`** — so the mkdir is refused, and pinning `PGDATA` while the image still
   declares a volume at the parent path yields two mounts over one source and `initdb` aborts with *"exists but
   is not empty"*. One bind, one path, both majors.
3. **Dumps over STDIN.** The DB containers are `read_only: true`, so `docker cp` fails with *container rootfs is
   marked read-only* — and that failure lands **after** the datadir swap. `docker exec -i … pg_restore … <
   dump` is the only shape that works; `/tmp` is a writable tmpfs if a real file is needed.

Plus the three that break legs at the other end (`docs/backup.md` §Four traps): **18's `initdb` defaults to ICU**
while every cluster here is libc `en_US.utf8` — wrong sort order, no error; there is **no `postgres` role
anywhere** (the superuser is the service name); and a per-database dump **silently drops cluster roles**.
Expected, not drift: `pg_roles` count 15 → 17 (`pg_checkpoint`, `pg_maintain`), and one anonymous volume at
`/var/lib/postgresql` because the image declares it.

## 4. Leg notes (one cluster per window)

Run `docs/backup.md` §One leg, in order — it is the procedure of record, and app data fleet-wide is 362 MB, so
each window is dominated by procedure overhead, not by data size.

**a. `forgejo-db`** — dump `pg_dumpall --roles-only` **first** and re-apply it into the new cluster before the
data restore: a `metabase_ro` role exists outside the compose env and a data-only restore loses it, which shows
up later as a Metabase auth failure, not as a migration error. Consume the app-stop rule literally: Forgejo
migrates an empty cluster the moment it is allowed to start while the DB is up.

**b. `zipline-db`** — the data-format leg is independent of the app, but note the interaction: `zipline_version`
is held at 4.6.5 because 4.8.0 crash-loops on an unapplied Prisma migration ledger. Do the PG leg, verify Zipline
still serves, and leave the app pin decision to its own row (HD-264's neighbourhood, not this brief).

**c. `onlyoffice-postgres`** — the datadir is the **named volume** `onlyoffice-docs_onlyoffice-pgdata`, not a
path under `/srv/docker`, so a target list derived from `/srv/docker` walks past it. `docker volume rename` it
aside (never `rm`) and let a fresh empty volume init. Compose marks the state REGENERABLE — that is a reason to
move fast in the window, not a reason to run without a fresh DB06 dump. If
[pin-major-onlyoffice.md](pin-major-onlyoffice.md) or [pin-major-rabbitmq.md](pin-major-rabbitmq.md) ride the
same window, sequence them **app first, data-format second**, one irreversible act at a time.

**d. `lan-litellm-db` (oldsrv)** — the only leg off the VPS, and the only one with **no dump target**: the
`db-backup` DB01–06 slots are a VPS container and cannot reach this cluster, and Kopia's file-level snapshot of a
live PGDATA is not a dump. So the dump is a hand act in the window, owned by the storage lane's brief
[prompt-storage-backup.md](prompt-storage-backup.md), taken while `lan-litellm` is stopped.
⚠ `--tags` on oldsrv is a different animal from the VPS: this host is the controller, so any lockout-class role
is refused in-band by the self-converge guard (`docs/deployment-ansible.md` §Runner placement); a
`docker_services`-scoped apply is fine off-box, run detached.

## 5. Out of scope, permanently

`immich-postgres` is **14.19** on an immich-owned composite (`14-vectorchord0.4.3-pgvectors0.2.0`) that ships PG
14 only, with `vchord/0.4.3` and `vector/0.8.1` live in the schema (`face_index`, `clip_index` use `USING
vchordrq`) and `data_checksums=on`, which rules out `pg_upgrade --link` even as an idea. Those are the only
out-of-tree extensions in the fleet and their PG 18 availability is unverified. Immich's database moves when
upstream ships a composite — a pin sweep that "fixes" it breaks the photo library.

## 6. Acceptance, per leg (the row's own bar)

* `pg_controldata -D /var/lib/postgresql/data` → **`pg_control version number: 1800`**. Grep case-insensitively
  for `pg_control`: the neighbour line is `Catalog version number`, so a grep on "catalog version" matches
  nothing and a healthy cluster reads as a failure.
* `datcollate=en_US.utf8` from `psql -Atc "select datcollate, datlocprovider from pg_database where datname=current_database()"`.
* Pre/post counts identical for the tables + row counts of the three largest tables; the `pg_restore --list` TOC
  count of the post dump matches the pre-migration dump's.
* One **real functional test** of the owning app, not a healthcheck.
* The next `db-backup` run dumps the cluster (DB02 / DB05 / DB06 by container name; `lan-litellm-db` by the hand
  act being re-run), and Kopia/`vps-state-push` carry the new dumps.
* Keep `postgres.16-<date>` (or the renamed volume) until a snapshot cycle proves the new cluster — the two
  already-migrated clusters are the precedent for what "rollback available" means here.

## 7. Rollback, per leg

`versions.yml` line back to `16.15-alpine` **and** the datadir/volume moved back, in the same act, then converge
that service alone. One without the other is the failure that cost the first two attempts: the 18 image refuses a
16 datadir and a 16 image refuses an 18 datadir, and the symptom looks like corruption.

## 8. Traps

* ⛔ One cluster per window. Two clusters restored in one converge means two candidate causes and one
  indistinguishable `db-backup` result.
* ⛔ Never `-e docker_services_scope=all` to "save a run" — the scope var exists precisely so a pin bump
  touches one service (`docs/deployment-ansible.md` §Tags & surgical runs).
* ⚠ Stop the **app**, not the DB-only half, before restoring: an app that can reach a fresh empty cluster will
  migrate it before the restore finishes, and the migration is forward-only.
* ⚠ `*_db` items whose service carries `db_role_sync: true` compare a `COMMENT ON ROLE` marker against
  `pgsync:<sha256>` and ALTER on drift — a hand-run `ALTER ROLE` inside a migration is out of band and desyncs
  the marker, so roles come from `pg_dumpall --roles-only` and the converge, never from a psql one-liner.
* ⚠ A leg's first red after the bump may be the **pin-lag gauge**, not the cluster:
  `homelab_pkg_pin_result` is the host-APT half and never reads container pins
  ([docs/observability.md](docs/observability.md) §Pin-lag report).

## 9. When a leg lands (repo side)

* That leg's pin line moves in `versions.yml`; its comment keeps the data-format rule, which is a permanent fact.
* `docs/backup.md`'s status read-back line is the fleet truth and **must** be rewritten in the same commit — a
  status line that goes stale in an owning doc is worse than none.
* HD-1100's row shrinks to the legs still held; when the last one lands, the row closes and its id leaves every
  doc in that same change.
* **Delete this file when the last leg lands** — until then it stays, one window at a time, and gets the
  `owed`/`done` column updated rather than annotated.
