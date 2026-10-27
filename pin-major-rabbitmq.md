# pin-major-rabbitmq.md — `onlyoffice_rabbitmq_version` 3.13.7 → 4.x

> **Role:** one-session brief for ONE data-format major: the pin line, the live subject, the preconditions, the
> procedure, the acceptance read and the rollback. It carries no queue row and states no status — the fleet pin
> SSOT is `IaC/ansible/group_vars/all/versions.yml` and the rule is [CONVENTIONS.md](CONVENTIONS.md) §7.
> **Linked from:** [prompt-update.md](prompt-update.md) (the majors the pin sweep must not touch) ·
> [pin-major-onlyoffice.md](pin-major-onlyoffice.md) (same service, same window)

**Verdict: safe to do, but NOT as a one-line pin to the version the probe names.** The broker holds no durable
state for this fleet, the preconditions for leaving 3.13 are already met — and `3.13 → 4.3.7` is not a supported
in-place hop.

| field | value |
|---|---|
| pin var | `onlyoffice_rabbitmq_version` → `3.13.7-alpine` |
| probe target | `4.3.7-alpine` (hold-eligible) · `4.4.0-alpine` (newest) — **both illegal as a direct hop, see §1** |
| template | `IaC/ansible/templates/docker_services/onlyoffice-docs/docker-compose.yml.j2` → `onlyoffice-rabbitmq` |
| host | **vps** |
| live | RabbitMQ 3.13.7, single node, vhost `/`, one user `onlyoffice [administrator]`, **zero queues**, all stable feature flags `enabled`, `khepri_db` `disabled` (`live-verified 2026-10-27`) |
| state | named volume `onlyoffice-docs_onlyoffice-rabbitmq-data:/var/lib/rabbitmq` |
| shape | multi-hop in-place upgrade **or** recreate-from-empty |

## 1. The upstream rules, which replace the note in `versions.yml`

`versions.yml` holds the pin because "RabbitMQ 4 cannot read a 3.13 mnesia store" was never sourced. That claim
is indeed unsupported — and the real rules are different, so the hold has to move onto them:

* **`3.13 → 4.x` is a supported in-place upgrade**, provided *all stable feature flags are enabled first*, and
  provided `khepri_db` is **not** enabled on the 3.13 node — Khepri in 3.13 was experimental and a 3.13 node
  with it enabled cannot go to 4.x at all ([upgrade guide](https://www.rabbitmq.com/docs/upgrade),
  [Khepri FAQ](https://www.rabbitmq.com/docs/metadata-store/khepri-faq)). **Both conditions already hold on this
  broker** — read them back, do not assume them (§2).
* **Skipping series is restricted.** The upgradability table on the same page: `3.13.x → 4.0.x`, `→ 4.1.x`,
  `→ 4.2.x` are legal; **`4.3.x` and `4.4.x` are reachable only from `4.2.x` / `4.3.x`**. `image-pin-probe.py`
  ranks by date and knows nothing about that table, so its `elig: 4.3.7-alpine` is not an actionable target.
* **Downgrades are not supported** (untested, "should not be relied upon"), and backing up the node's data
  directory before upgrading is strongly advised. Erlang ships inside the `-alpine` image, so the Erlang leg of
  the upstream procedure is a no-op here.

Two honest shapes, pick one in the window:

| shape | path | when |
|---|---|---|
| **A — hop** | `3.13.7 → 4.2.x`, enable stable feature flags, `→ 4.3.7` (or stop at the `4.2.x` line) | when keeping the broker's identity/definitions matters |
| **B — recreate** | stop, move the named volume aside, start the target `4.x` image empty | default for this fleet: the queues are transient, and the credentials come from the vault, not from mnesia |

Shape B is cheap **because** `RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` are applied at *first* mnesia init
from `onlyoffice-rabbitmq_login`, and ONLYOFFICE re-declares its own queues on connect. The compose comment
records that state as regenerable, with OpenCloud as the SSOT.

## 2. Re-derive before acting (read-only)

Every `rabbitmqctl` call must run as the `rabbitmq` user — the image has no `USER`, and under `cap_drop: ALL`
root cannot read the `0400` `.erlang.cookie` (the same reason the healthcheck uses `su-exec`, see the template
comment). As root the command spams `eacces` and says nothing.

```bash
ssh -n vps 'docker exec onlyoffice-rabbitmq su-exec rabbitmq rabbitmqctl status | head -5
            docker exec onlyoffice-rabbitmq su-exec rabbitmq rabbitmqctl list_queues name type durable messages
            docker exec onlyoffice-rabbitmq su-exec rabbitmq rabbitmqctl list_feature_flags
            docker volume ls | grep rabbitmq'
```

Go/no-go from that output: **every** stable flag `enabled` and `khepri_db` **`disabled`** → shape A or B is open.
Anything disabled → `rabbitmqctl enable_feature_flag all`, let it settle, re-read, only then move the pin.

## 3. Procedure (shape B, the recommended one)

1. Snapshot first — the volume is cheap and the alternative is unrecoverable:
   `docker run --rm -v onlyoffice-docs_onlyoffice-rabbitmq-data:/from:ro -v /srv/snapshots:/to alpine cp -a /from/. /to/rabbitmq-$(date +%Y%m%d)/`
2. Take ONLYOFFICE out of the rotation with its own stack, `docker compose -f /opt/onlyoffice-docs/docker-compose.yml stop onlyoffice-docs`
   first so the broker is not mid-message.
3. `docker compose ... stop onlyoffice-rabbitmq`, then `docker volume rename onlyoffice-docs_onlyoffice-rabbitmq-data onlyoffice-rabbitmq-data.3-$(date +%Y%m%d)`.
   **Rename, never `docker volume rm`** — a renamed volume is the rollback.
4. Set `onlyoffice_rabbitmq_version: "4.3.7-alpine"` (or the `4.2.x` last patch), then converge **this service
   only**: `bash scripts/ansible/ansible-run.sh playbooks/vps.yml --limit vps.kogler.si --tags docker_services
   -e docker_services_scope=onlyoffice-docs` (`docs/deployment-ansible.md` §Tags & surgical runs — ⛔ `--tags
   docker_services,onlyoffice-docs` is a union, not a scope). Run it detached; a foreground run killed
   mid-restart leaves siblings `Exited`.
5. Wait for the healthcheck (`su-exec rabbitmq rabbitmq-diagnostics -q ping`) → `Up (healthy)`, then start
   `onlyoffice-docs` and exercise the editor (§4).

Shape A is the same file edit twice, with a `rabbitmqctl enable_feature_flag all` and a healthy-read between the
hops, and the volume untouched throughout.

## 4. Acceptance

```bash
ssh -n vps 'docker exec onlyoffice-rabbitmq su-exec rabbitmq rabbitmqctl status | head -3
            docker exec onlyoffice-rabbitmq su-exec rabbitmq rabbitmqctl list_feature_flags | grep -c enabled
            docker exec onlyoffice-rabbitmq su-exec rabbitmq rabbitmqctl list_users
            docker ps --format "{{.Names}}\t{{.Status}}" | grep onlyoffice'
```

* version reads the target, and after a 4.x upgrade **all stable 4.x feature flags are enabled** — an
  un-flagged upgrade is an incomplete upgrade, not a finished one;
* `list_users` shows `onlyoffice` again (shape B: created from the vault item at init; shape A: inherited);
* `onlyoffice-docs` is `Up (healthy)` and a `.docx` opens, edits and saves, with co-editing alive —
  the broker's only job in this fleet is the editor's job queue, so the editor **is** the test
  ([docs/services-office.md](docs/services-office.md) §ONLYOFFICE Docs Server);
* `RestartCount` flat on both containers, and `homelab_pkg_pin_result{result="differ"}` empty again
  ([docs/observability.md](docs/observability.md) §Pin-lag report — container pins do not appear there; the gauge
  is the host-APT half).

## 5. Rollback

Move the renamed volume back (`docker volume rename` the other way), set the pin to the previous value, converge
the service again. Do **not** test the rollback by starting 3.13 on a 4.x store: downgrades are unsupported and
that is exactly the act that fails.

## 6. Traps

* ⛔ **The probe's version ranking is not an upgrade path.** `elig` answers "what is published and out of
  hold", never "can this node get there".
* ⛔ **Do not hand-create the user/vhost.** Both shapes carry the credentials in the compose env; a manual
  `add_user` desynchronises the vault item from the box and lands in the `NOT_AUTO_ROTATABLE` class.
* ⚠ `onlyoffice-docs` depends on `onlyoffice-rabbitmq` `service_healthy` — a broker that never turns healthy
  holds the whole stack down, so read the healthcheck, not `docker ps`.
* ⚠ This leg shares a window with [pin-major-onlyoffice.md](pin-major-onlyoffice.md) and the
  `onlyoffice_pg` leg in [pin-major-postgres.md](pin-major-postgres.md); three recreates of one compose project
  in one night is three restart windows for `office.kogler.si`. One converge, one decision.
* ⚠ The volume's history is also the residue the dangling-volume table tracks on this host — see
  [docs/services-vps.md](docs/services-vps.md) §The dangling-volume table before adding another renamed volume.

## 7. When the line lands (repo side)

* The `onlyoffice_rabbitmq_version` line moves **and its comment is rewritten to the upgradability rule** — the
  unsourced mnesia claim leaves in the same change, because an unsourced reason sits in the SSOT as a decision
  nobody can audit.
* `docs/services-office.md` keeps the broker fact if one changed; the act itself lives in the commit.
* **Delete this file in the same change that lands the pin.** Git is the changelog.
