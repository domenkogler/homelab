# pin-major-forgejo.md — `forgejo_version` 16 → 17

> **Role:** one-session brief for ONE major: the pin line, the live subject, the preconditions, the procedure,
> the acceptance read and the rollback. It carries no queue row and states no status — the fleet pin SSOT is
> `IaC/ansible/group_vars/all/versions.yml` and the rule is [CONVENTIONS.md](CONVENTIONS.md) §7.
> **Linked from:** [prompt-update.md](prompt-update.md) (the majors the pin sweep must not touch) ·
> [pin-major-postgres.md](pin-major-postgres.md) (`forgejo_db` is a separate leg on the same service)

**Verdict: safe as a solo window with a fresh backup taken in that window.** The database needs nothing, the
migration is automatic, and it is **forward-only by construction** — so the backup is the rollback, not the pin.

| field | value |
|---|---|
| pin var | `forgejo_version` → `16.0.5` |
| probe target | `17.0.0` (hold-eligible 2026-10-15) · `17.0.1` (newest) |
| template | `IaC/ansible/templates/docker_services/forgejo/docker-compose.yml.j2` |
| host | **vps** — service `forgejo`, `git.kogler.si` |
| database | `forgejo_db` → `postgres:16.15-alpine` — **untouched by this brief**; Forgejo supports PostgreSQL ≥ 14 ([database preparation](https://forgejo.org/docs/latest/admin/installation/database-preparation/)) |
| live | `forgejo` + `forgejo-db` Up/healthy; `/srv/docker/forgejo/{data,postgres}` (data is in Kopia scope) (`live-verified 2026-10-27`) |
| shape | application major: automatic migrations at first start, irreversible |

## 1. What upstream requires, and which half this fleet can skip

* **A backup before a stable-release major is stated as a requirement, not advice**, and the same page says a
  post-major problem discovered days later is "much more challenging" to fix on a live instance
  ([upgrade guide](https://forgejo.org/docs/latest/admin/upgrade/)). Forgejo's data is *multiple* stores — the
  Postgres database **and** `/srv/docker/forgejo/data` (repos, attachments, LFS, avatars) — so a dump of one is
  not a backup of the other. Shut the app down for the snapshot; upstream warns about the split otherwise.
* **Migrations run as part of the upgrade** — "upgrade straight to the latest released version by replacing the
  binary or container image (the upgrade procedure will take care of migrations)". No step-through of 16.x is
  required for a healthy instance; the page's "known problematic versions / upgrade paths" list is the one thing
  to read for a 16 → 17 note before choosing the target patch.
* **A downgrade refuses to start.** The database stores its version specifically "to prevent an accidental
  downgrade", so 16.0.5 pointed at a migrated database **will not come up**. Repinning is therefore not a
  rollback; restoring the snapshot is.
* This deployment needs none of the Gitea-migration path and none of the `app.ini` surgery the page's
  troubleshooting section describes.

## 2. Re-derive before acting (read-only)

```bash
py -3 scripts/ansible/image-pin-probe.py --file IaC/ansible/group_vars/all/versions.yml --json
ssh -n vps 'docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}" | grep -i forgejo
            docker exec forgejo-db psql -U forgejo -d forgejo -Atc "select version, (select count(*) from information_schema.tables where table_schema=\"public\") from schema_migrations limit 1" 2>/dev/null \
              || docker exec forgejo-db psql -U forgejo -d forgejo -Atc "select count(*) from information_schema.tables where table_schema=\"public\""
            docker exec forgejo-db psql -U forgejo -d forgejo -Atc "select rolname from pg_roles order by 1"'
du -sh /srv/docker/forgejo/data   # on the VPS
```

The role list matters: `forgejo-db` carries a **`metabase_ro`** role created outside the compose env
([docs/backup.md](docs/backup.md) §Four traps). A per-database `pg_dump` does not carry cluster roles, so that
role and its grants are the thing a restore silently drops — and the consumer of it is the Metabase instance on
oldsrv ([docs/services-admin.md](docs/services-admin.md) §Metabase — deployed on oldsrv).

## 3. Procedure

1. **Freeze the writers** — say it in the commit so the next reader knows why the repo push failed that hour:
   this repository itself is hosted on Forgejo (Renovate points at a test repo until HD-264 flips it, so the
   automation is quiet, but the human pushes are not).
2. **Back up, in this order, in the window:**
   ```bash
   docker compose -f /opt/forgejo/docker-compose.yml stop forgejo           # app only, db stays up
   docker exec forgejo-db pg_dumpall -U forgejo --roles-only > /root/pg18/forgejo/roles.sql
   docker exec -i forgejo-db pg_dump -Fc -U forgejo -d forgejo > /root/pg18/forgejo/data.dump
   docker exec -i forgejo-db pg_restore --list < /root/pg18/forgejo/data.dump | wc -l     # proves the dump is readable
   ```
   Then a file-level copy (or a ZFS/Kopia snapshot) of `/srv/docker/forgejo/data` taken **while the app is
   stopped** — the dump alone cannot restore a repo.
3. Move `forgejo_version` to the target, then converge the service alone:
   ```bash
   bash scripts/ansible/ansible-run.sh playbooks/vps.yml --limit vps.kogler.si \
        --tags docker_services -e docker_services_scope=forgejo
   ```
   `--check` first, apply detached; the migration runs on the container's first start, so the first healthcheck
   pass can take minutes and `RestartCount` must stay 0.
4. Let only the app come back up; do not restart anything else on that host in the same window.

## 4. Acceptance

* `forgejo doctor check --all --log-file /tmp/doctor.log` reports no problem — upstream names this as the
  verify step, and it is the only check that reads both stores.
* Web UI: login (Authentik OIDC through `sso.kogler.si`), a repo's Issues + Actions tabs, a raw file fetch.
* A real `git clone` and a `git push` from the seat — the git path is the part a database-only check never
  proves.
* A PR flow through `renovate`'s endpoint (`http://forgejo:3000`) once HD-264 flips it; until then, the
  `forgejo_api` token path is exercised by hand at most, so do not claim CI coverage that does not exist.
* `metabase_ro` still exists with its grants, and Metabase's Forgejo connection still queries.
* The nightly `db-backup` **DB02** slot still dumps `forgejo-db` (it addresses the container by name, so a
  name-preserving leg survives — but "survives" is read back, not assumed).

## 5. Rollback

Stop the app, repin `16.0.5`, restore `roles.sql` then `data.dump` into a **fresh** datadir (the pattern is
`docs/backup.md` §One leg, in order), and restore `/srv/docker/forgejo/data` from the same-minute snapshot. Keep
the running 17 datadir aside as `postgres.17-<date>` until the next backup cycle proves the restore — the same
"datadir and pin move together" rule the Postgres legs carry.

## 6. Traps

* ⛔ **Never point 16.x at a migrated database to "check".** It refuses to start, and the refused start can
  half-open a connection pool that makes the subsequent restore look corrupt.
* ⚠ The database version is a fact about the app, not the pin: after this bump, `forgejo_db_version` at 16.15 is
  still correct and legal. Do not "keep them in step" — that is how a data-format major ends up in an
  application window (see [pin-major-postgres.md](pin-major-postgres.md) for that leg).
* ⚠ `forgejo-mcp` and `rag-mcp` are disabled services on the VPS; a 17 API change there is latent, not live, and
  must not be reported as a passed test.
* ⚠ One converge in flight per host ([docs/orchestration.md](docs/orchestration.md) §4); `git.kogler.si` is
  reachable only through the VPS edge, so a Traefik restart in the same window makes the failure ambiguous.

## 7. When the line lands (repo side)

* `forgejo_version` moves in `versions.yml`; the "probe the manifest before pinning" note beside it stays, since
  a released version can still ship a broken publish.
* Anything true about the Forgejo interface after the bump belongs to `docs/services-admin.md`, not here.
* **Delete this file in the same change that lands the pin.** Git is the changelog.
