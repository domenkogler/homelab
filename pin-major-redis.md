# pin-major-redis.md — `tube_archivist_redis_version` 7 → 8

> **Role:** one-session brief for ONE data-format major: the pin line, the live subject, the preconditions, the
> procedure, the acceptance read and the rollback. It carries no queue row and states no status — the fleet pin
> SSOT is `IaC/ansible/group_vars/all/versions.yml` and the rule is [CONVENTIONS.md](CONVENTIONS.md) §7.
> **Linked from:** [prompt-update.md](prompt-update.md) (the majors the pin sweep must not touch) ·
> [CONVENTIONS.md](CONVENTIONS.md) §7

**Verdict: safe, and the cheapest of the majors — the only 7.x subject in the fleet belongs to a disabled,
torn-down service.** Redis 8 reads a 7.x RDB/AOF, so this is a restart, not a migration.

| field | value |
|---|---|
| pin var | `tube_archivist_redis_version` → `7.4.11-alpine` |
| probe target | `8.10.1-alpine` (3-day hold eligible) · `8.10.3-alpine` (newest published) |
| template | `IaC/ansible/templates/docker_services/tube-archivist/docker-compose.yml.j2` → `archivist-redis` |
| declaring host | `oldsrv` — `group_vars/home_servers.yml` lists `tube-archivist` with `enabled: false` |
| live subject | none — no `archivist-redis` container exists on any host (`live-verified 2026-10-27`) |
| shape | restart (RDB/AOF backward-compatible) |

## 1. The redis fleet, so no lane re-derives it

| container | host | pin var | running | consumer | data |
|---|---|---|---|---|---|
| `authentik-redis` | vps | `authentik_redis_version: 8.10.2-alpine` | 8.10.2 | Authentik cache/outpost queue — **sessions live in Postgres, not here** | bind `/srv/docker/authentik/redis`, `save` snapshots, `appendonly no` |
| `onlyoffice-redis` | vps | `onlyoffice_redis_version: 8.10.2-alpine` | 8.10.2 | ONLYOFFICE Docs transient cache/queue | named volume `onlyoffice-redis-data:/data`, `appendonly no` |
| `immich-valkey` | vps | `immich_valkey_version: 9.1.2` | Valkey 9.1.2 (reports `redis_version 7.2.4`) | Immich queue | bind `/srv/docker/immich/valkey` |
| `archivist-redis` | — | `tube_archivist_redis_version: 7.4.11-alpine` | **absent** | Tube Archivist queue (service disabled) | would be `/srv/docker/tube-archivist/redis` |

Three consequences:

1. **Redis 8 is already proven in this fleet** — both live redis instances run 8.10.2. Crossing 7 → 8 is not a
   theory here, it is state, and `versions.yml` says so beside the ONLYOFFICE sidecar pins.
2. **The "7 → 8 major" in the pin sweep has no live data behind it.** Bumping `tube_archivist_redis_version`
   changes the tag a disabled service would pull. Nothing restarts, nothing migrates.
3. **`immich-valkey` is not part of this bump.** It is Valkey, a different project whose compatibility floor is
   reported as Redis 7.2 — it moves on `immich_valkey_version`, and immich's own compose pairs it with the
   `14-vectorchord…` database image, which is immich's call, not a pin sweep's.

## 2. Re-derive before acting (read-only)

```bash
py -3 scripts/ansible/image-pin-probe.py --file IaC/ansible/group_vars/all/versions.yml --json   # on a Win11 seat add --file IaC/ansible/group_vars/all/versions.yml: DEFAULT_ROOT is off by one folder
ssh -n oldsrv 'docker ps -a --format "{{.Names}}\t{{.Image}}" | grep -i redis; ls -d /srv/docker/tube-archivist 2>/dev/null'
ssh -n vps    'docker exec authentik-redis  redis-cli INFO server | grep -i ^redis_version; \
               docker exec onlyoffice-redis redis-cli INFO server | grep -i ^redis_version'
```

A `0`-line first probe on oldsrv is the expected result and is the whole precondition.

## 3. Procedure

One line, in the pin sweep commit or on its own:

```
tube_archivist_redis_version: "8.10.3-alpine"   # exact tag, never the `7-alpine`/`8-alpine` alias (§7)
```

No converge is owed by the pin alone: the service is `enabled: false`, so no host renders it. If the owner wants
the rendered state to move anyway, it is a render-only change (`playbooks/render-docs.yml`); ⛔ do not run a
`docker_services` converge to "apply" a disabled service.

## 4. Acceptance

* `image-pin-probe.py --verify` reports the pin resolves at the registry (an `-alpine` tag that 404s is a
  phantom pin and fails at container start, not at render).
* The comment beside the var still says an exact patch tag is deliberate (mutable aliases are §7 violations).
* `ssh -n oldsrv 'docker ps --format "{{.Names}}" | grep -c archivist'` → still `0`.

## 5. If Tube Archivist is ever re-enabled (HD-362)

Order matters and it is not this brief's work: the ES `path.repo` fix in the container's own
`elasticsearch.yml` comes first (the env-var and `-E` forms both destabilise the ES bootstrap), then the ES
`elastic` bootstrap password item, then the redis sidecar. Redis 8 is not the blocker in that sequence and must
not be presented as one.

## 6. When the line lands (repo side)

* `versions.yml` line changes; nothing else carries the value (§7).
* `docs/services-media.md` keeps Tube Archivist's disabled state as a fact — do not write this bump there.
* **Delete this file in the same change that lands the pin** — a brief that outlives its act becomes a second
  copy of state nothing re-renders. Git keeps it.
