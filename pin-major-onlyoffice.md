# pin-major-onlyoffice.md — `onlyoffice_version` 9 → 10

> **Role:** one-session brief for ONE major: the pin line, the live subject, the preconditions, the procedure,
> the acceptance read and the rollback. It carries no queue row and states no status — the fleet pin SSOT is
> `IaC/ansible/group_vars/all/versions.yml` and the rule is [CONVENTIONS.md](CONVENTIONS.md) §7.
> **Linked from:** [prompt-update.md](prompt-update.md) (the majors the pin sweep must not touch) ·
> [pin-major-rabbitmq.md](pin-major-rabbitmq.md) and [pin-major-postgres.md](pin-major-postgres.md) (same
> compose project, same VPS window)

**Verdict: not a pin edit — a window.** Requirements-wise the new major needs nothing from the sidecars, so the
risk is not compatibility, it is three irreversible-to-reverse things landing in one container recreate: the
app's own forward-only DB migration, the WOPI/JWT key material sitting on an anonymous volume, and an integration
contract written entirely in environment-variable names.

| field | value |
|---|---|
| pin var | `onlyoffice_version` → `9.4.0.1` |
| probe target | the `10` line — take the exact tag from `image-pin-probe.py --json` (`onlyoffice_version` → `best`; first published 2026-10-12, so out of the 3-day hold) |
| template | `IaC/ansible/templates/docker_services/onlyoffice-docs/docker-compose.yml.j2` |
| host | **vps** — `group_vars/vps.yml` service `onlyoffice-docs`, `office.kogler.si`, no Forward-Auth |
| sidecars | `onlyoffice-postgres` 16.15 · `onlyoffice-redis` 8.10.2 · `onlyoffice-rabbitmq` 3.13.7 |
| upstream floor | PostgreSQL ≥ 12.9, Redis ≥ 4/5, a current RabbitMQ ([install requirements](https://helpcenter.onlyoffice.com/docs/installation/docs-enterprise-sys-reqs-linux.aspx)) — **all three sidecars already clear a 10.x** |
| shape | application major: recreate + in-app DB migration at first start |

## 1. What a 9 → 10 recreate actually moves

1. **The app migrates its own database at first start.** The `onlyoffice` schema in `onlyoffice-postgres` is
   owned by DocumentServer's upgrade machinery, not by IaC, and it is forward-only: after 10.x has run against
   it, the 9.x image is not a safe place to return to. A fresh dump before the recreate is the whole insurance
   policy.
2. **`/var/www/onlyoffice/Data` is an anonymous volume.** `docker inspect onlyoffice-docs` (read-only,
   `live-verified 2026-10-27`) shows `/var/log/onlyoffice`, `/var/www/onlyoffice/Data` (holding
   `wopi_private.key` / `wopi_public.key`) and the custom-fonts path on hash-named volumes, because the compose
   declares named volumes only for the three sidecars. Every recreate therefore mints a fresh set and re-mints
   the keypair — survivable by design (the shared WOPI/JWT secret is the vault item
   `opencloud-collab_password`, rendered into both sides), but each major adds another dangling volume to the
   VPS table. HD-1106 is the row that gives those two paths a named volume or a bind; **it is open, and doing it
   before a major is cheaper than after.**
3. **The integration contract is env names + one Traefik middleware.** The template documents the exact set the
   image reads — `DB_TYPE/DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PWD` (⛔ not `DB_PASS`), `AMQP_URI` (the
   `RABBITMQ_SERVER_URL` / `AMQP_SERVER_URL` forms are deprecated), `REDIS_SERVER_HOST` / `REDIS_SERVER_PORT`
   (the `REDIS_HOST` / `REDIS_PORT` forms do not exist), plus `WOPI_ENABLED=true`, `EXAMPLE_ENABLED=true`,
   `JWT_ENABLED`/`JWT_SECRET`/`JWT_HEADER`. An env rename in a major is invisible at render and fatal at
   runtime. The `onlyoffice-csp` middleware (`upgrade-insecure-requests`) stays attached to the
   `office` router: it is the compensation for the mixed-content bug
   ([docs/services-office.md](docs/services-office.md) §ONLYOFFICE Docs Server).

Docs 10's own breaking list, read against this deployment: the removed deprecated Docs-API customisation
parameters (`reviewDisplay`, `showReviewChanges`, `trackChanges`) — this deployment sets none of them, the
editor config is minted by OpenCloud's `collaboration` service; and the command / conversion / doc-builder
services no longer taking the token from the editor configuration, replaced by an `operation` field gated by a
new `services.CoAuthoring` option — which is precisely the path `/command` and the conversion calls that
OpenCloud drives, so it is the item to re-read in the [10.0 changelog](https://api.onlyoffice.com/changelog/2026/10/15/version-10-0-0)
before the window, not after. The open-source build also drops built-in AI; nothing here uses it.

## 2. Re-derive before acting (read-only)

```bash
py -3 scripts/ansible/image-pin-probe.py --file IaC/ansible/group_vars/all/versions.yml --json
ssh -n vps 'docker inspect -f "{{.Config.Image}} {{range .Mounts}}{{.Source}}->{{.Destination}} {{end}}" onlyoffice-docs
            docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" onlyoffice-docs | grep -E "^(DB_|AMQP_URI|REDIS_|WOPI_|JWT_|EXAMPLE)" | sed "s/=.*//"'
ssh -n vps 'docker exec onlyoffice-postgres psql -U onlyoffice -d onlyoffice -Atc "select count(*) from information_schema.tables where table_schema=\"public\""'
curl -sf https://office.kogler.si/hosting/discovery -o /dev/null -w "%{http_code}\n"
```

The second probe is the one that pays: it prints **which env names the running container actually has**. Diff
that list against the 10.x image's documented names before the recreate — that diff is the real review, and the
`sed "s/=.*//"` keeps values out of the transcript (lengths and names only, never a value).

## 3. Procedure

1. **Land HD-1106's first half if it is still open**: name `/var/www/onlyoffice/Data` and `/var/log/onlyoffice`
   in the template. Prune or recreate after, never before.
2. **Dump DB06 now**, not "tonight's scheduled run":
   `ssh -n vps 'docker exec db-backup dbbackup run'` or a direct
   `docker exec -i onlyoffice-postgres pg_dump -Fc -U onlyoffice -d onlyoffice > /root/pg18/onlyoffice/data.dump`
   — over **STDIN**, because `read_only: true` rejects `docker cp` and that failure lands *after* the swap
   ([docs/backup.md](docs/backup.md) §What PG 18 actually requires). Record a pre-count of tables for the diff.
3. Decide the sidecars in the same sitting and say so: a 10.x runs on **PG 16** and on the broker's current
   series, so nothing forces [pin-major-postgres.md](pin-major-postgres.md) or
   [pin-major-rabbitmq.md](pin-major-rabbitmq.md) into this window. If either does ride along, do the **DS
   major first**, verify the editor, then the data-format leg — one irreversible act at a time.
4. Move the pin, then converge the one service, detached:
   ```bash
   bash scripts/ansible/ansible-run.sh playbooks/vps.yml --limit vps.kogler.si \
        --tags docker_services -e docker_services_scope=onlyoffice-docs
   ```
   (`--check` first in the foreground; the apply detached — `docs/deployment-ansible.md` §Tags & surgical runs
   for why `--tags docker_services,onlyoffice-docs` is a union and not a scope.)
5. Watch first boot: the DS init is slow, `RestartCount` must stay 0, and the DB migration runs in that window.

## 4. Acceptance — the editor is the test, not `docker ps`

* `/hosting/discovery` answers 200 and OpenCloud still registers the editor (a 404 here means
  `WOPI_ENABLED`/`EXAMPLE_ENABLED` silently fell back to image defaults).
* A `.docx` opens, edits, saves; **two browsers co-edit** simultaneously; an `.xlsx` converts. This is the
  functional proof, and the only one that proves the DB migrated.
* No mixed-content block in the browser console (the CSP `upgrade-insecure-requests` leg still holds).
* `docker inspect` mount list: the two paths that HD-1106 named are named volumes; no **new** anonymous volume
  beyond the justified ones ([docs/services-vps.md](docs/services-vps.md) §The dangling-volume table).
* Table count post-migration matches the pre-dump count plus whatever the migration legitimately adds — write
  the difference down in the owning doc only if it is a fact about the schema, not about this session.

## 5. Rollback

Repin `9.4.0.1` and converge the service — and expect the app to refuse the older schema if 10.x migrated it.
The rollback of record is therefore **the dump**: restore into the `onlyoffice` database and start 9.x. That
asymmetry is the reason this file asks for a fresh dump instead of trusting the nightly `db-backup` slot.

## 6. Traps

* ⛔ No `cap_drop: ALL` on this container — supervisord's per-child setuid fails under it (documented in the
  template). Re-adding it in a "harden while we're here" edit turns a version bump into an outage.
* ⛔ Do not hand-edit `/etc/onlyoffice/documentserver/local.json` — it is on the container rootfs and is
  regenerated; persistent DS config in this fleet is env + the rendered compose.
* ⚠ The route is `traefik-public` + `db-internal` only; OpenCloud talks to DS **over the edge**, so a failure
  after the bump shows up at `file.kogler.si` as a collaboration error, not at `office.kogler.si`.
* ⚠ `opencloud-collab_password` must stay one value across FOUR envs on both sides; a rotation in the same
  window as the major makes an editor failure impossible to attribute.
* ⚠ One converge in flight per host — the spark and VPS slot rules apply here too
  ([docs/orchestration.md](docs/orchestration.md) §4).

## 7. When the line lands (repo side)

* `onlyoffice_version` moves in `versions.yml`; if an env name changed, the template changes in the **same**
  commit, with the template's env-name comment rewritten to the names the 10.x image actually reads.
* `docs/services-office.md` keeps whatever is now true about the WOPI/DS interface.
* **Delete this file in the same change that lands the pin.** Git is the changelog.
