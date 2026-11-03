# `prompt-engine-bearer-wsl.md` — Lane brief · the WSL seat's half of the engine-bearer rotation

> **Rows it carries:** none, and it claims none. It runs the **consumer half** of a rotation the spark
> seat has already performed; the rows stay owned by the briefs [todo-table.md](todo-table.md) §B0 assigns them to
> ([`prompt-litellm-consumers.md`](prompt-litellm-consumers.md) · [`prompt-secrets.md`](prompt-secrets.md)
> · [`prompt-spark-llm.md`](prompt-spark-llm.md)). No row is minted, no ownership moves here — this file
> dies with its lane (O7).
> **Role:** the runbook for what may run only from **this** seat, after the spark seat has rotated
> `spark-llm-api` and `litellm-engine_api` and converged the engine. Every act below names its own
> proof; a box ticked without its proof is not a box.
> **Linked from:** [`prompt.md`](prompt.md) §2 (the handoff family) — not from a `todo-table.md` cell,
> because a `todo-table.md` lane-map cell would claim a row that already has an owner.
> **Seat contract:** [`prompt-laptop-wsl.md`](prompt-laptop-wsl.md) (its §0 pre-flight and its seat facts) — this is that seat, and that
> file's pre-flight runs **first**. Dies with the lane (O7).

---

## 0. What has already happened, and what that means for you

The **spark seat** has, in one window:

- rotated both engine bearers in the vault — `spark-llm_api` and `litellm-engine_api` — through
  [`scripts/secrets/rotate-engine-bearers.sh`](scripts/secrets/rotate-engine-bearers.sh),
  both re-read and hash-matched. **⛔ Never read, print, compare or paste either value.** They are in
  `Homelab-ansible` and they move only by re-running that script.
- converged `spark` (`playbooks/spark.yml`, full, detached) so the engine boots with the new
  accepted-key **list** — `--api-key` is `nargs='+'`, position 1 is `spark-llm_api` (the oom-watchdog
  parses that position) and position 2 is `litellm-engine_api`.
- helped `docker-compose-plugin` land at `5.7.0` (`group_vars/all/versions.yml`) and masked the
  vendor `nvidia-spark-run-apt-upgrade-once.service` beside the `dgx-dashboard` tombstone.

**What that means:** the engine accepts the NEW values from its next boot, and nothing else has moved.
Both LiteLLM instances still send the OLD `spark-llm_api` upstream until you re-render them, and the
laptop's `models.json` still carries the old engine key. **Do not converge oldsrv or vps until step 1
below prints the green line**, or you will re-render a consumer onto a key the engine no longer accepts.

---

## 1. Gate — read this before any converge

```bash
# the engine must accept BOTH new values, and the OLD value must be refused.
# Values are read from the vault into shell variables and never printed; only HTTP codes come out.
new="$(op read 'op://Homelab-ansible/spark-llm_api/credential' </dev/null)"
newg="$(op read 'op://Homelab-ansible/litellm-engine_api/credential' </dev/null)"
printf 'spark-llm_api     at engine :8000 -> %s\n' "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $new"  http://llm.kogler.si/v1/models)"
printf 'litellm-engine_api at engine :8000 -> %s\n' "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $newg" http://llm.kogler.si/v1/models)"
printf 'superseded value  at engine :8000 -> %s   (expect 401)\n' \
  "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(cat /tmp/hl-engine-old-*/superseded-keys-0600 2>/dev/null | head -1)" http://llm.kogler.si/v1/models)"
```

- Both **new** rows `200`; the superseded row `401`. That is the only shape that permits step 2.
- ⚠ **Gate on the engine's argv, never on `/health`.** `/health` answers `200` for the whole window
  before the container is recreated, so a health-only wait verifies the OLD key against a still-running
  engine and looks green.
- If the superseded-check file is not on this seat, skip that row and say so — it is the spark seat's
  capture, and the negative test then has to be reproduced there.

---

## 2. The two gateways — the consumer half, in this order

```bash
# vps first, then oldsrv. Both are FULL converges; a scoped leg can exit 0 having skipped the service.
bash scripts/ansible/ansible-run.sh playbooks/vps.yml --tags docker_services   # detached, log + poll
bash scripts/ansible/ansible-run.sh playbooks/home_servers.yml --limit oldsrv.kogler.si --tags docker_services
```

Detached form, one converge in flight per host (O3):

```bash
nohup bash scripts/ansible/ansible-run.sh playbooks/vps.yml --tags docker_services \
  >/tmp/converge-vps-gw-$(date +%Y%m%d-%H%M).log 2>&1 &
```

⛔ `--diff` anywhere (it renders vault values into the diff). ⛔ `--allow-change-held-packages`.
⚠ On `vps`, anything that restarts the tailnet sidecar or Traefik goes **LAST** — and read
`bash scripts/harness/seat-llm-path.sh --check` before an edge act.

**Proof per host, hashes only** — the rendered env must hash equal to the vault item, and must be
`litellm-engine_api`, not `spark-llm_api`:

```bash
h(){ printf '%s' "${1:-}" | sha256sum | cut -c1-12; }
want="$(h "$(op read 'op://Homelab-ansible/litellm-engine_api/credential' </dev/null)")"
for hc in "vps litellm" "oldsrv lan-litellm"; do set -- $hc
  got="$(ssh -o BatchMode=yes "$1" "docker inspect $2 --format '{{range .Config.Env}}{{println .}}{{end}}'" \
        | grep '^OPENAI_API_KEY=' | cut -d= -f2- | tr -d '\n')"
  printf '%-8s %-14s %s\n' "$1" "$2" "$([ "$(h "$got")" = "$want" ] && echo MATCH || echo MISMATCH)"; done
```

⚠ **Known blocker on `oldsrv`:** the status block of [`docs/hardware-spark.md`](docs/hardware-spark.md) records that the LAN LiteLLM
bootstrap-key glue aborts `rc2` on a stale `dsh` secret, so **every `lan-litellm` converge is red until
it is remediated**. If that hits, park with the exact blocked action (O4) — do not "fix" it by editing a
vault value, and do not converge oldsrv twice in a row to see if it clears.

⚠ **Do not flip both gateways to the new key in one go if you cannot prove the engine first.** The
inverted order 401s every upstream call: gateways holding a key the running engine never accepted.

---

## 3. The seats' rendered config — the half Ansible does not own

`scripts/harness/pi/models-spec.yml` renders `~/.pi/agent/models.json` on every seat, and the spark
row authenticates with the **engine** key directly (`llm.ts.kogler.si` proxies straight to spark; the
`traefik-tailnet` route says "auth is the ENGINE's `--api-key`, not a middleware"). So:

```bash
# regenerate every seat's render; a missed seat silently loses its spark lane.
bash scripts/harness/render-pi-config.py            # then read the diff, never cat the file
# prove it: a real request through the spark lane, on THIS seat
pi --provider spark -m spark/qwen3.8-flash-next -p 'reply with the single word ok'
```

⛔ A missed seat is a silent loss, not an error — the gateway path may still answer while the direct
lane 401s.

---

## 4. The window's timed legs — both refuse any other seat

These are `Rule 0` instruments: they exit 3 on a spark-served session **and** `check_bench_provenance.py`
holds `STATION = "domenp14s"`, so a leg stamped from another box reddens the gate as off-station.

```bash
# the row — the rest-floor measurement. Owner ruling: the DELTA PICKS THE FLOOR (CRIT vs WARN),
# so nothing is written to IaC before the number exists.
bash scripts/bench/spark/usable-sampler.sh

# the row — gate 6 at the ruled budget, both legs graded at the same max_tokens.
bash scripts/bench/spark/gate6-couple.sh --max-tokens 16384
```

⚠ **One at a time, and never beside a spark converge or a profile flip** — they drive load through the
engine whose numbers they record. Each takes 5–10 min wall (the sampler is capped at 900 s and ends when
its prefill returns + 15 s). ⛔ Gate 6 needs the B1 `reasoning` baseline re-run **in the same change**;
grading an arm against a baseline taken at the old budget is not a measurement.

---

## 5. `alloy` — the scheduled bump, in this same sweep

The spark seat moved `docker_compose_plugin_version` to `5.7.0`; `alloy_version` is **deliberately
still `1.21.2-1`**, because all five hosts read `1.21.2-1` and the pin rule is *the highest release
already running in the fleet, never the newest upstream*. `1.21.3-1` is published for both arches, so
raising it is a legal, scheduled act — and this session is the window for it, since every collector
restart costs one scrape cycle anyway:

```bash
# 1. raise the pin (one line), 2. converge the monitoring group, 3. read the gauge back
#    IaC/ansible/group_vars/all/versions.yml  ->  alloy_version: "1.21.3-1"
# the five hosts: vps, oldsrv, nas, pi, spark — spark's leg is monitoring-scope only
```
⚠ `nas` converges always carry `--skip-tags alloy` for a different reason (a collector being debugged);
in **this** window `alloy` is the point, so name the tag explicitly. ⛔ Do the bump **after** step 2's
gateway proof, so a 401 and a metrics gap never land in the same read.

---

## 6. Report — evidence, not prose

A report with no commit is a report of nothing. Give: the four HTTP codes from §1 · a per-host
`MATCH/MISMATCH` table from §2 with the converge log paths · the `pi` spark-lane answer from §3 ·
the sampler's `delta` line and gate 6's four numbers from §4 (with `--client` stamps) ·
`bash scripts/validate-all.sh; rc=$?` from your worktree · and the **parks**, each with the exact
blocked action.

⛔ Never paste a bearer, an env dump, or a rendered compose line into the report — hashes, codes and
verdict words only (CONVENTIONS §3, `prompt-update.md` §5a).
