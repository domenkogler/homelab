---
title: Observability
domain: observability
role: ssot
status: active
tags: [observability, grafana, prometheus, monitoring]
---
# Observability

> **Role:** Single source of truth — the complete observability stack as a domain (VictoriaMetrics/VictoriaLogs/Grafana + Alloy/exporters + alerting).
> **Links to:** `interfaces.md`, `deployment-ansible.md`, `smart-home.md`, `backup.md`, `services.md`, `observability-rejected.md`
> **Linked from:** `index.md`, `interfaces.md`, `services.md`

> **Status: 🟢 live.** The backend is the **Victoria stack on the VPS** — **VictoriaMetrics** (metrics,
> 365 d) + **VictoriaLogs** (logs, 90 d) + **Grafana** + blackbox-exporter, all on the tailnet-only edge.
> Collectors: **Alloy** per host (VPS loopback, oldsrv, spark, nas, Pi), oldsrv's SNMP + network-clients exporters, RouterOS syslog over RFC5424, `nut_exporter` on nas,
> `zfs_exporter`, blackbox probes. Alerting: **Grafana → n8n (`homelab-alerts` webhook) → Signal + Matrix**,
> with Grafana-native SMTP in parallel as the fail-safe. The ruled delivery surface is the Matrix
> `#homelab-alerts` room, live but not yet read by a human — see §Alerting.
>
> ⏳ **Open:**
> the last two steps of the Matrix `#homelab-alerts` leg (the operator joining the room, then demoting
> Signal), contact-point/datasource password rotation,
> device-side SNMP enablement, and the Kopia wiring for `/srv/docker/victoria-*/data`.
>
> ✅ All five `monitoring` hosts run the pinned Alloy and ship their own `node_*` — the read that proves it is
> in §The Alloy pin.

---

## Architecture

```
Alloy (host agent: metrics + logs + SNMP, has docker.sock)  ← the SINGLE scrape tier (topology B)
   ├─ remote_write ──▶ VictoriaMetrics (THE metrics store, 365d)
   └─ push ──────────▶ VictoriaLogs   (logs, 90d)
Dozzle viewers (read-only docker.sock) ──▶ live per-container log tail (ops, no storage)
   ├─ VPS viewer (logs.kogler.si, tailnet) — VPS containers
   └─ OLDSRV HUB (llogs.kogler.si, :8081, LAN/internal edge) ──agents──▶ pi + spark containers
Home Assistant (SWO-B + ComfoAir) ──HA exporter──▶ Alloy scrape ──▶ VictoriaMetrics
MikroTik (SNMP, 5–15s poll) ─────────────────────────────▶ Alloy scrape ──▶ VictoriaMetrics
blackbox_exporter (external reachability) ───────────────▶ Alloy scrape ──▶ VictoriaMetrics  (probe_success)
nut_exporter (UPS, on nas) ──────────────────────────────▶ Alloy scrape ──▶ VictoriaMetrics  (battery/runtime/voltage)

                        VictoriaMetrics ──▶ Grafana (stats.kogler.si, internal, Authentik admin-only)
                                                  │  webhook
                                                  ▼
                                                n8n (alert router: dedup / tier / format)
                                                  ├──▶ signal-cli → Signal "Homelab Alerts" group
                                                  └──▶ SMTP → email
                               Grafana-native SMTP = fail-safe, parallel
```

- **Single source of truth** for every type of data; no redundant backends.
- **Display:** Grafana (admin analytics) + Homepage (status widget — reachability eyeball view).
- **Acquisition files live where the collector reads them.** CrowdSec's RouterOS acquisition file belongs
  in the CrowdSec **config mount's** `acquis.d/` (`/srv/docker/crowdsec/config` → `/etc/crowdsec`
  in-container, so `/etc/crowdsec/acquis.d/`); an extra-template copy in the compose dir (`/opt/crowdsec/`)
  is never read — the file is on disk and the pipeline stays silently blind. The `monitoring` group spans
  BOTH the oldsrv collector and the VPS backend, while the CrowdSec container and its config mount are
  **VPS-only**: the acquisition task is gated to the `vps` group, because on oldsrv `/opt/crowdsec` does
  not exist and the container restart fails there.

### The Victoria stack — the shape and why

**One** metrics store (**VictoriaMetrics**, `victoria-metrics:8428`) + **one** log store
(**VictoriaLogs**, `victoria-logs:9428`), both on the **VPS**, with **many writers** (Alloy
collectors on VPS/oldsrv/nas/Pi/spark, blackbox/nut/zfs exporters, MikroTik syslog) remote-writing into them.
**Grafana stays** in front of both. **MCP AI-debugging servers run on oldsrv** (much more RAM there) and
point at the VPS endpoints over wg-s2s — **storage stays on the VPS, tooling stays at home.**
Research + rationale: [`brainstorming/recent/Prometheus-Vs-victoriastack.md`](../brainstorming/recent/Prometheus-Vs-victoriastack.md).

```
Alloy (host agent: metrics + logs + SNMP) ──remote_write──▶ VictoriaMetrics (VPS, metrics)
Alloy (logs) ───────────────────────────────push─────────▶ VictoriaLogs   (VPS, logs)
MikroTik (SNMP / syslog) ────────────────────────────────▶ VictoriaMetrics / VictoriaLogs
blackbox / nut / zfs exporters ─────────────scrape/remote─▶ VictoriaMetrics

VictoriaMetrics ──▶ Grafana (stats.kogler.si)  ──webhook──▶ n8n → Signal + email
VictoriaLogs    ──▶ Grafana (logs datasource)

mcp-victoriametrics / mcp-victorialogs (on OLDSRV, RAM) ──wg-s2s/tailnet──▶ VPS Victoria endpoints
```

- **Writers stay on home infra** (oldsrv/nas/Pi/spark Alloy + exporters), buffering over wg-s2s; the **single backend is on the VPS** (reliability).
- **MCP AI servers on oldsrv** (≈600–700 MB RAM each) — not on the VPS, not on the Pi.
- **Dozzle is kept alongside VictoriaLogs.** They are different tools: Dozzle is a live per-container tail
  with no storage, VictoriaLogs is the searchable 90-day store. Replacing one with the other loses an
  operator reflex, so both stay — but Dozzle must never become a second log backend.

### MCP AI-debugging servers on oldsrv

> **Status: ✅ live** — two `docker_services` on **oldsrv**, `mcp-victoriametrics` (`:8083`) and
> `mcp-victorialogs` (`:8084`), fronting the VPS Victoria backend for AI tools (pi, Open WebUI, OpenClaw).
> They require the VPS backend to be reachable.

- **Endpoint reachability — wg-s2s now, tailnet later.** The MCP servers point at the VPS
  backend via `victoria_backend_host` (group_vars/all/main.yml), which **defaults to
  `wg_s2s_vps.ip`** — the same guaranteed-reachable tunnel the Alloy collector uses. The planned
  s2s-wg→tailnet redo re-plumbs **this one var** to the VPS tailnet address and the compose needs no
  other change. **No VPS tailnet IP
  exists in the SSOT yet — do not invent one** (see network-vpn.md before the redo).
- **Exposure — LAN/tailnet-only, never public/WAN.** Ports publish on oldsrv's Home-VLAN
  address (`oldsrv_home_ip`, actual-budget :5006 / immich-ml :3003 precedent); the future
  tailnet redo adds a Pattern-A sidecar. **No traefik-public labels, no `public: true`.**
- **Auth — Basic to the backend, network gate to the client.** The MCP server (`http` mode)
  has **no native auth**; each container sends `Authorization: Basic <b64(user:pass)>` to
  the VPS backend from the `victoria-metrics_api` / `victoria-logs_api` 1P items
  (`VM_INSTANCE_HEADERS` / `VL_INSTANCE_HEADERS`). The client-facing gate is the
  Home-VLAN-only bind + (future) tailnet ACL — **do not expose on the WAN edge**.
- **Images (pinned, CONVENTIONS §7):** `mcp_victoriametrics:v1.18.0` + `mcp_victorialogs:v1.8.0`,
  Renovate-tracked.
- **Registry:** oldsrv `docker_services` rows with `enabled: true`.

#### Wiring AI tools (pi, Open WebUI, OpenClaw)

Each AI client registers the MCP server as a **Streamable HTTP** MCP endpoint pointing at
the oldsrv MCP listen address (`http://oldsrv:8083` metrics / `:8084` logs). The MCP
servers carry the backend auth themselves, so the client config carries **no secrets**.
All endpoints are **LAN/tailnet-only** (served on the oldsrv hosts above).

- **pi (pi.dev)** — add an MCP server entry in the pi agent config pointing at
  `http://oldsrv:8083` (metrics) / `http://oldsrv:8084` (logs), transport `http` (SSE
  alias for Streamable HTTP). No such entry is authored in `pi-agent/` yet — its `prompts/` holds
  `start.md` only.
- **Open WebUI** — register both as **Tools** (Admin → Tools → MCP) with `url:
  http://oldsrv:8083` / `http://oldsrv:8084` (Streamable HTTP), tagged for the internal
  `ai.kogler.si` instance so agent-role users can query metrics/logs.
- **OpenClaw** — add both MCP servers to the OpenClaw MCP config (`http://oldsrv:8083` /
  `:8084`), gated to the same tailnet/LAN path.
- ⏳ **Concrete client config files are not authored here yet** — the URLs above are the **SSOT
  contract**; the client-side config is environment-specific and lives with each tool
  ([services-ai.md](services-ai.md)).

---

## Component Table

| Layer | Service | Role | Network | Retention |
|-------|---------|------|---------|-----------|
| Agent | **Alloy** (per-node: vps/oldsrv/nas/pi/spark) | Host metrics + logs + SNMP (oldsrv only for SNMP/network-clients) | host (`docker.sock`) → `services-internal` | — |
| Backend | **VictoriaMetrics** | Sole metrics store (pure storage/query — Alloy does ALL scraping, topology B) | `db-internal` | 365d (Kopia-backed) |
| Backend | **VictoriaLogs** | Log aggregation, single-node/SSD | `db-internal` | 90d (Kopia-backed) |
| Exporter | **blackbox** | External reachability (`probe_success`) | `services-internal` | in VictoriaMetrics |
| Exporter | **HA exporter** | HA entities → VictoriaMetrics (Alloy scrape, gated `alloy_ha_exporter`) | `services-internal` | in VictoriaMetrics |
| Exporter | **nut_exporter** | UPS status (battery/runtime/voltage/load) → VictoriaMetrics · single instance on **nas** (NUT master) | `services-internal` | in VictoriaMetrics |
| UI | **Grafana** | Dashboards, `stats.kogler.si` (**internal**) | `traefik-public` **+** `db-internal` | — |
| Router | **n8n** | Alert routing/dedup → Signal/email | `services-internal` | — |
| Notify | **signal-cli** | Signal delivery (linked device) | `services-internal` (needs internet) | — |
| Viewer | **Dozzle** | Live per-container log streaming (read-only `docker.sock`); **two instances** — VPS (`logs.kogler.si`, tailnet via `traefik-tailnet`) + home LAN hub on oldsrv (`llogs.kogler.si`, :8081, via `traefik-internal`, pi/spark remote agents :7007); **viewer only — nothing stored** | `traefik-public` | — |

### The Alloy pin — what actually proves a host is on it

Alloy is the observability tier's only **host package** (APT from `apt.grafana.com`, the deliberate exception
to the Docker rule), so its version comes from **one** place — `alloy_version` in
`IaC/ansible/group_vars/all/versions.yml` — and `roles/monitoring/tasks/main.yml` installs it as
`alloy={{ alloy_version }}` on every host in the `monitoring` group. A `host_vars` override is drift, not a
second shape, and the fleet pin is what the five collectors must agree with
([CONVENTIONS.md](../CONVENTIONS.md) §7).

**Reads, and what each one actually answers.** What the package manager recorded is not what is running,
and neither is what the backend can see:

| Question | The read | Where |
| --- | --- | --- |
| What version does the **running** collector report about itself? | `alloy_build_info{version=…}` — the collector's own build info, served by its HTTP server (`server.http.listen-addr`, `127.0.0.1:12345`) | `curl -s 127.0.0.1:12345/metrics \| grep ^alloy_build_info` on the host |
| …and the same, for the whole fleet at once, out of the store | `alloy_build_info` — every monitoring host remote-writes its own, so `instance` and `version` arrive together | `GET /api/v1/query` on VictoriaMetrics |
| Is that collector **answering scrapes**? | `up{job="alloy"}` — the `prometheus.scrape "alloy_self"` read of the same `/metrics`, tagged `job="alloy"` + `instance=<host>`, i.e. the pipeline's own liveness view | VictoriaMetrics |
| What is installed, for context | `dpkg-query -W -f='${Version}' alloy` | on the host — **never the verdict on its own** |

⚠ A `dpkg` read cannot close a version question by itself: a host can carry the pinned package while the
live process predates the last restart, and every restart drops one scrape cycle — `up` is what says whether
that cycle came back.

⛔ **A pin that lags the box is a failed converge, never a downgrade.** `Install Alloy` asking for a version
below what the host already runs dies with `E: Packages were downgraded and -y was used without
--allow-downgrades` and takes the rest of the monitoring role with it. `--allow-downgrades` is not the fix —
it would silently pull down every other package whose pin lags its box. The fix is one line in
`versions.yml`: raise the pin to the highest release **already running** somewhere in the fleet, then
converge (which costs one Alloy restart per host).

✅ **Live-verified 2026-10-19, every collector that reaches the store**: `alloy_build_info` reports
`version` == the pin on the four `monitoring` hosts the backend can see (`oldsrv`, `vps`, `pi`, `spark`),
with `up{job="alloy"}` = **1** on each. A fifth host in the group is on the pin and reports **nothing at
all** — `dpkg` will happily confirm the pinned deb while the process ships no series, which is the gap
between "installed", "running" and "scraping"; see §Silent-failure hygiene for the class and the
instrument that names it.

The standing, automated version of the same comparison — per package, read on the box, no ssh in the way —
is §Pin-lag report (`homelab_pkg_pin_result`). The table above is the manual read that stands behind it, and
it is the one to take when a host is suspected of running something other than what it was told to.

## Access & login path (stats.kogler.si)

**Tailnet-only:** the observability dashboards (`stats`/`traefik`/`logs`/`csui`/`auto`
and by extension the underlying victoria-metrics/victoria-logs/blackbox) have **no public DNS record** and are **not
WAN-reachable**. They are reached over the **headscale tailnet** from admin devices via the
**`traefik-tailnet` edge** (node `vps-obs`) — a consumer-mode Traefik (+ userspace tailscale sidecar
sharing its netns) that serves the dashboards with **clean subdomain URLs** and no port numbers
(see [`network-vpn.md`](network-vpn.md) §Tailnet-exposed services and the `docker_services/traefik-tailnet`
compose). The one exception is the home log hub **`llogs`**: **LAN-only**, served by the oldsrv
`traefik-internal` edge for WAN-out survival — no tailnet route, no public record (§Dozzle multi-host).

| App | URL (tailnet) |
|-----|---------------|
| Grafana (`stats`) | `https://stats.kogler.si` / `https://stats.ts.kogler.si` |
| Dozzle (`logs`) | `https://logs.kogler.si` / `https://logs.ts.kogler.si` |
| Dozzle home hub (`llogs`) | `https://llogs.kogler.si` (**LAN-only** — oldsrv `traefik-internal` edge, WAN-out survival; shows oldsrv + pi + spark containers) |
| CrowdSec Web UI (`csui`) | `https://csui.kogler.si` / `https://csui.ts.kogler.si` |
| Traefik dashboard (`traefik`) | `https://traefik.kogler.si` / `https://traefik.ts.kogler.si` |
| n8n (`auto`, **internal-only**) | `https://auto.kogler.si` / `https://auto.ts.kogler.si` |

The plain `*.kogler.si` names resolve via headscale MagicDNS (`dns.search_domains: [kogler.si]`, and **`dns.nameservers` must put the MagicDNS loop `100.100.100.100` FIRST**) and carry
**Authentik Forward-Auth** (same chain as the public edge). The `*.ts.kogler.si` MagicDNS twins are
**ACL-gated** (no forward-auth — the headscale ACL `tag:sidecar:443` is the gate; tailnet-only by
construction). The public CNAMEs are removed from the IaC SSOT and deleted from Cloudflare at deploy
time (owner action).

> **Why the loop must come first.** With only the Technitium VPS primary in `dns.nameservers`, a tailnet
> device on a foreign network (mobile hotspot) sends `stats.kogler.si` to the system resolver → NXDOMAIN →
> `ERR_NAME_NOT_RESOLVED`, while `stats.ts.kogler.si` still resolves — a device whose client-side MagicDNS
> `extra_records` are populated answers regardless. Ordering the MagicDNS loop first resolves **both**
> namespaces locally on any network. Symptom shape: "one suffix works, the other does not, and it depends
> on the network you are on" is a **resolver order** bug, not a routing bug.

Forward-Auth (Traefik chain) still gates the route; Grafana then auto-logs-in via `[auth.proxy]`,
trusting the `X-authentik-email` header ONLY from the pinned Traefik edge IP (`traefik_edge_ip_pin`
via compose `ipv4_address`, whitelisted through `GF_AUTH_PROXY_WHITELIST` = `traefik_edge_ips`).
The native login form is disabled (`GF_AUTH_DISABLE_LOGIN_FORM`), so a **logo-only bare `/login`
page means Grafana rejected proxy auth** — either a whitelist/edge-IP mismatch or no matching user:
`AUTO_SIGN_UP` is off by design, so every user must be mapped explicitly via the
break-glass admin API before SSO works for them. Two operational caveats:
Docker's dynamic bridge assignment can silently drift the edge IP off the whitelist (pin prevents
it), and Grafana provisioning does NOT overwrite `secureJsonData` of an EXISTING datasource — a
rotated datasource password must be re-applied via delete+recreate with the same uid or an API
update, or queries keep 401-ing despite correct rendered files.

**"The dashboard opens but has no data" is a reachability fault, not a query fault.** Grafana's
VictoriaMetrics datasource is queried **server-side** by name (`http://victoria-metrics:8428`), so every
panel — and every alert rule — fails together with `dial tcp: lookup victoria-metrics on 127.0.0.11:53:
no such host` while the UI itself loads fine behind SSO. Docker's embedded DNS answers only for
containers that are **members of the network**, so a metrics container that is `Up (healthy)` yet
attached to nothing removes the name and silently removes the whole observability plane. Separating
read: `docker inspect -f '{{len .NetworkSettings.Networks}}' victoria-metrics` → `0` means detached
(`docker restart` does not repair it; recreate does). The same class and its guard:
[deployment-compose.md](deployment-compose.md) §Boot auto-start (docker-compose@).

---

## Single Source of Truth Matrix

| Data | Owner | Where it lives |
|------|-------|----------------|
| Host + SNMP metrics | per-node Alloy (vps/oldsrv/nas/pi/spark host exporters) + oldsrv SNMP → VictoriaMetrics | VictoriaMetrics (365d, Kopia) |
| Service scrape (Traefik, CrowdSec) | Alloy (VPS loopback) → VictoriaMetrics | VictoriaMetrics (365d) |
| HA entity metrics (weather, ComfoAir) | HA exporter → Alloy → VictoriaMetrics | VictoriaMetrics (365d) |
| External reachability | blackbox → Alloy → VictoriaMetrics | VictoriaMetrics (365d) |
| UPS status (battery, runtime, voltage, load, online/on-batt) | nut_exporter (on nas) → Alloy → VictoriaMetrics | VictoriaMetrics (365d) |
| Logs | Alloy → VictoriaLogs | VictoriaLogs (90d, Kopia) |
| RouterOS logs (RB4011/switch/AP) | RFC5424 syslog → VPS rsyslog → CrowdSec/VictoriaLogs | VictoriaLogs (90d) |
| Live logs (ops day-to-day tail) | Dozzle viewers — VPS `logs.kogler.si` (tailnet) + home hub `llogs.kogler.si` (LAN, oldsrv, pi/spark agents) | ephemeral — nothing persisted |
| Alerts | Grafana Alerting → n8n → Matrix + Signal, plus Grafana-native SMTP in parallel | alert delivery — **Matrix/Element is the ruled delivery surface; the room exists and the bot can write it, but no human has joined it, so Signal + email are what a human actually reads today** |
| Display | Grafana + Homepage | — |

---

## Alerting

- **Engine:** Grafana Unified Alerting (rules live with the data; no separate Alertmanager).
- **Router:** alerts → n8n webhook → normalize / dedup / tier / format → Signal + Matrix. n8n also serves office automation ([`services-office.md`](services-office.md)).
- **Delivery is two paths, not one chain.** Path 1 is the n8n workflow: the Signal send, with the Matrix
  send chained behind it. Path 2 is the **Grafana-native SMTP receiver on the same contact point**, which
  never touches n8n — that is what survives n8n, Matrix and signal-cli all being down. Both receivers hang
  off one contact point wired to the default policy, so an alert reaches both and neither depends on the
  other.
- **Webhook:** Grafana's contact point posts to `grafana_alert_webhook_url` (group_var, default `http://n8n:5678/webhook/homelab-alerts`, traefik-public). ⚠ The n8n workflow **`homelab-alerts`** on that route must exist before the first alert fires (created at n8n setup; payload = Grafana alert-notification webhook, see the monitoring role `grafana-contactpoints.yml.j2`).
- **Fail-safe:** Grafana-native SMTP contact point runs in parallel — alerts still go out if n8n/signal-cli is down.
- **SMTP relay:** SMTP2Go (`mail-eu.smtp2go.com:2525`, STARTTLS). Dedicated transactional relay, free-tier 1000/mo, deliberately independent of the Infomaniak kSuite mailbox so the alert fail-safe isn't coupled to personal email. Grafana + NUT share it; creds = `smtp_login` / `smtp_login` (Login items in 1Password). Rotating `smtp_login` means re-converging **every** consumer and verifying the rendered value: VPS
  Grafana (compose env), Pi + oldsrv HA (`secrets.yaml`), and **NUT `upssched-cmd` on nas**, which embeds it
  **inline** (see [hardware-ups.md](hardware-ups.md)).
  - **Connecting (SMTP2Go, EU datacenter — as provided by the account):** server `mail-eu.smtp2go.com`; SMTP port `2525` (default), alternates `8025`, `587`, `80`, `25` — **TLS available on the same ports** (STARTTLS). SSL: `465`, `8465`, `443`. The repo uses `mail-eu.smtp2go.com:2525` + STARTTLS (**587 is blocked from the VPS egress**, so **2525 is the SSOT port**, not 587).
- **Signal:** `signal-cli-rest-api` container, **linked** to Domen's personal number (no second SIM), sends to a dedicated **"Homelab Alerts"** group. Persist the Signal identity volume so it doesn't need re-linking. Delivery is **✅ live**. **Recipient: the WHOLE group** — `signal_alert_recipients` takes the **group ID** that signal-cli reports, read off
`GET http://127.0.0.1:8080/v1/groups/$SIGNAL_CLI_PHONE_NUMBER` **inside the container** (that raw upstream
API has no auth and NO host port — hence `docker exec`, exactly as the `group_vars/all/main.yml` comment
shows) → `.id` on the linked oldsrv daemon, stored in `group_vars/all/main.yml` (`group.NVZ6Y21…`) — **not** the group's invite link, which is an encrypted join blob and not a recipient the API accepts, and **not** the group's *name*. The ID is only readable from the linked daemon; never reconstruct it from a message-store backup, which would mean reading private messages.
- **Matrix is the ruled delivery channel, and it is the leg that is not finished.** Two facts made it a
  decision rather than a preference: the `signal-cli-rest-api` daemon is **linked to the operator's
  personal number** and the "Homelab Alerts" group's **only human member is the operator** — so nothing in
  this fleet pages anyone else — and the operator reads **Element**, not Signal, so a Signal-only alert is
  an alert with no reader. What exists now: the **`#homelab-alerts` room** and its dedicated bot
  `@homelab-alerts:kogler.si` on the live Tuwunel, the token in the `Homelab-ansible` vault item
  `matrix-alerts_api` (never a literal), the recipient state on the n8n registry entry in
  `group_vars/vps.yml`, and the two `Send Matrix` nodes chained **behind** the untouched Signal sends in
  `homelab-alerts.workflow.json`. The room id, the MXID, the registration recipe (Tuwunel's own `mac`
  formula, not Synapse's) and the **`PUT`-not-`POST`** shape of the send are
  [services-matrix.md](services-matrix.md) §Alert room.
  - ⚠ **A public room with only the bot in it pages nobody.** The room is `join_rule: public` precisely so
    the operator can join it by alias from Element without an invite; until that human act happens the
    Matrix leg delivers into an unread room and Signal + email remain the only channel anyone reads.
  - **Signal is not deleted by this.** `signal-cli-rest-api` stays live and its nodes stay byte-identical
    until the Matrix leg proves itself; demoting it to a documented fallback or removing it is the last
    step, not a side effect of this one. The chain is temporary in shape: a Matrix failure cannot suppress
    a Signal send, but a Signal failure stops the workflow before the Matrix node — which is exactly why
    the demotion has to be an act and not a drift.

### Operational gotchas

**Grafana**

- **`read_only: true` breaks Grafana 13's bundled-plugin installer.** Grafana 13 keeps bundled plugins —
  **including `prometheus`, the datasource that talks to VictoriaMetrics** — in the image layer at
  `/usr/share/grafana/data/plugins-bundled` and re-installs them on every start; the installer must
  `unlinkat` that directory, which fails under the hardening flag, leaving the plugin **unregistered**:
  empty panels, `/api/datasources/uid/prometheus/health` → 404 `Plugin not registered`, and every rule
  erroring `plugin.notRegistered` (~2.5 k failed evals). **Fix = one env line,
  `GF_PLUGINS_PREINSTALL_DISABLED: "true"`** (the setting the image ships), so plugins load in place and
  `read_only: true` stays. **Diagnosis shortcut:** a datasource plugin installed into the **writable**
  `/var/lib/grafana/plugins` (like `victoriametrics-logs-datasource`) stays healthy — that contrast is the
  whole diagnosis. On any `grafana_version` bump: re-check preinstall **before** widening `read_only`.
- **Provisioning does NOT overwrite `secureJsonData` of an existing datasource.** A rotated datasource
  password must be re-applied by delete+recreate **with the same uid** (or an API update) — otherwise
  queries keep 401-ing while the rendered files look perfect.
- **Pin the edge IP.** Docker's dynamic bridge assignment silently drifts the Traefik edge address off
  `GF_AUTH_PROXY_WHITELIST`, which reads as "SSO stopped working after an unrelated redeploy".
- **`noDataState` is the loudest footgun in the stack.** A rule whose PromQL matches **no series** fires a
  synthetic `DatasourceNoData` alert on every evaluation. That is a **collection gap, never a condition**:
  real-condition rules take `noDataState: OK` (or `NoData`) + `execErrState: Error`; only self-monitoring
  rules (`victoria-*-down`, `wg-s2s-down`) keep `Alerting`. Anything whose series may legitimately be
  absent (UPS metrics while healthy, `probe_ssl_earliest_cert_expiry` — blackbox does not emit SSL expiry,
  SNMP interfaces before SNMP ships) must be set explicitly, not left at the default.
- **⚠ A filtered-empty result is the SAME `NoData` state as no-series.** Grafana
  cannot tell "the query matched nothing because the condition is false" from "the series does not exist",
  so `expr: <something> > 900` **under `noDataState: Alerting` fires while everything is healthy**: the
  comparison deletes every series on a good evaluation. Two rules follow from the shape, and both are
  required for a staleness alert:
  1. **Keep the comparison in the threshold expression, not in the PromQL.** A must return a value on a
     healthy evaluation; the `gt`/`lt` lives in `data` B (`eval_type` / `eval_params` in
     `roles/monitoring/vars/main.yml`). That is what `spark-host-mem-oom-critical` does — same tier, same
     `noDataState: Alerting`, reads `Normal`.
  2. **A plain selector cannot age.** The 5-min staleness horizon drops the last sample *before* a
     900-second threshold becomes reachable, so a dead exporter can only reach the rule as NoData — it
     pages without naming a host, and goes blind entirely once the host leaves the database. Wrap the
     metric in a range window (`max_over_time(<metric>[6h])`) so a silent series keeps evaluating.
  The read that shows the state in one line:
  `GET /api/prometheus/grafana/api/v1/alerts` — every entry prints its reason, `Alerting (NoData)` versus
  `Normal (NoData)` versus a real `Normal`.
- **Alert rules must match the live backend.** After a backend migration, orphan rules survive in the live
  Grafana DB (provenance = file, but absent from the rendered rules file). Delete orphans after any
  backend change — a stale `prometheus-down` rule alerts about a component that no longer exists.

**Rules + exporters**

- **The evaluator has to match the expression.** Rules templated with a hardcoded `gt 0` can never fire for
  `expr: X == 0` (`*-down`, `host-unreachable`, `wg-s2s-down`) — the rule is silently dead, which is worse
  than a missing rule. The template carries `eval_type` per rule; `== 0` rules use `lt` with `[1]`.
- **Self-scrape needs the backend's auth.** Without `victoria-metrics_api` / `victoria-logs_api` basic auth
  on the self-scrape jobs, `up{job="victoria-metrics"}=0` permanently — which reads as "monitoring is down"
  and trains everyone to ignore it. Same class: a blackbox self-target pointed at `/probe` instead of
  `/metrics` is dead, not degraded.
- **SNMP interface names need two things at once.** The `ifName` OID must be in the module's `walk` list
  **and** the lookup must declare `type: DisplayString`; otherwise labels are missing (`interface [no value]`)
  and values render as hex (`0x65746865…`). Give each device its own `instance` label or two devices
  collapse into one flat series.
- **A probe job needs a per-target label, or every probe of that job collapses into one series.** The
  blackbox target shape is `__address__` = the exporter and `__param_target` = the thing probed, and
  `__param_*` is a QUERY PARAMETER — it never becomes a label. So `instance` on a probe series is the
  exporter's own address (`127.0.0.1:9115`) for every target of the job, the store keeps ONE series per
  job no matter how many hosts it probes, and `count by (instance) (probe_success{job=…})` returns the
  exporter, not the fleet. Two consequences follow: a rule over the bare job (`host-unreachable`,
  `public-service-down`) pages without naming anything, and a rule that filters on a probed URL
  (`instance="https://…"`) selects NO series at all — with the only sane `noDataState` for it, `OK`, it
  is green forever. The fix is the SNMP rule above applied to the probe jobs: name the target inside the
  target map, or relabel `__param_target` into a label. The read that shows it in one line is
  `count by (job, instance) (probe_success)` — a probe job whose count is 1 is a job whose targets cannot
  be told apart.
- **Do not alert on intentionally-empty state.** Unprovisioned is not incident-worthy: a link rule that
  matches every switch port pages on the ports that carry nothing (ten simultaneous instances on ports with
  no cable). Alert on the loss of a link that carries something.

**Alert delivery**

- **The n8n workflow must exist and be ACTIVE before the first alert** — otherwise the Grafana contact point
  hits `POST /webhook/homelab-alerts` → 404 and nothing is routed. It is versioned at
  `roles/monitoring/files/n8n/homelab-alerts.workflow.json` and created/activated through the n8n public API
  (`n8n_api`, `POST /api/v1/workflows` + `/activate`). Verify with a POST expecting
  `200 "Workflow was started"`.
- **⚠ That 200 proves the run STARTED, never that anything was delivered.** The
  webhook can answer 200 for executions that send **nothing**. The delivery evidence is downstream and
  specific — n8n's **execution status** for the Signal node, the gateway's `POST /v2/send` → **201**, and
  the **delivery receipt** signal-cli logs. For the Matrix leg the evidence is **the room's own event**:
  read it back with the bot token (`GET /_matrix/client/v3/rooms/{urlencoded id}/messages?dir=b&limit=5`)
  and quote the `event_id` — the send's own `200 {"event_id":…}` is the receipt, and the `PUT` form that
  returns it is [services-matrix.md](services-matrix.md) §Alert room. Ask for those three; a green webhook
  is not one of them. ⚠ **Any post to this webhook sends on the Signal leg too**, so proving a new node
  must not be a reason to page a phone: prove the expressions on a **throwaway workflow with its own
  webhook path**, read the room event, then delete the throwaway and read back that it is gone.
- **n8n 2.x blocks `$env` in workflow expressions BY DEFAULT, which silently kills the Signal leg.**
  Read inside the pin (`n8n-workflow/dist/esm/workflow-data-proxy-env-provider.js`):
  `isEnvAccessBlocked = process.env.N8N_BLOCK_ENV_ACCESS_IN_NODE !== 'false'` — **unset means blocked**,
  every `{{ $env.* }}` throws `access to env vars denied`, and the render's `SIGNAL_*` values (the whole
  SSOT→runtime handoff: token, URL, recipients, phone) never reach the node. The compose therefore sets
  `N8N_BLOCK_ENV_ACCESS_IN_NODE: "false"` explicitly; typing the four values into the workflow instead
  would fork the SSOT, which is what the row's design refuses. Consequence: **env access is
  now ON for every workflow this instance can run** — bounded by n8n being admin-only over the tailnet
  (`auto.ts.kogler.si`, no public route).
- **`onError` on a delivery node is a mute, so it must be `stopWorkflow`.** `continueRegularOutput` turns
  "no recipient configured", "wrong-shaped recipient" and "access to env vars denied" into
  `status=success`. An alerting path that swallows its own send failure cannot ever be trusted, so a failed
  send must be a **RED execution**.
- **⚠ The versioned workflow JSON is NOT deployed by anything** — no role task imports it. The live copy
  lives in n8n's SQLite, created and activated by hand through the public API
  (`n8n_api`), so `roles/monitoring/files/n8n/homelab-alerts.workflow.json` drifts
  silently from it. Two consequences: editing the repo file changes
  nothing until it is PUT to the API, and a re-provision from the repo copy would re-break delivery
  **after** a green converge. Any change therefore lands in **both** places in one act, and the act has a
  shape: `GET /api/v1/workflows/{id}` → **save the export as the rollback file** → `PUT` the repo JSON →
  `POST …/activate` → read the node list back. ⛔ Never `n8n import:workflow` to update it — import
  **creates** a workflow, and two active workflows on one webhook path is a duplicate-send fault that
  announces itself as two pages per alert.
- **A missing Signal device is silent by design — for the LINK, not for the send.** An unlinked
  `signal-cli` must not be able to break email delivery, so email is a separate parallel Grafana contact
  point (§above) rather than a node downstream of the Signal node. Linking the "Homelab Alerts" device is
  an owner action.
- **`signal-cli-rest-api` is published on `{{ oldsrv_home_ip }}:8082`** because the alert brain (n8n) runs on
  the VPS and cannot resolve an oldsrv-only overlay name — the cross-host API-leg pattern (precedents:
  actual-budget `:5006`, immich-ml `:3003`). **`:8080` belongs to something else** — never reuse it here.
  **⚠ The gateway takes the token ONLY as `Authorization: Bearer <token>`**: against `:8082`,
  `X-Api-Key` → **401** and `Bearer` → **200** on `/v1/about`.
- **Three converge-time traps that are repo rules:** every vault item a template reads must be declared in
  `_template_vault_items`, or the render dies with `dict has no attribute …`; Jinja `default()` fallbacks in
  YAML need single quotes, or the fallback renders nested quotes and `docker compose config` fails; and a
  pinned image tag must be **verified to exist** in the registry before it lands (`1.9.0` vs `v1.9.0` is a
  failed pull on docker.io).

### spark host-memory (OOM) alert rules

The container memory cage cannot protect a GB10 host (GPU pages are not cgroup-charged) and Docker reports
`OOMKilled: false` on a host-side kill, so **host memory is the only early warning** there. Rules
`spark-host-mem-oom-warning` / `spark-host-mem-oom-critical`; the on-box enforcer is
`spark-oom-watchdog` (`roles/spark`: CRIT < 8 GiB → planned engine restart, max 2 per 2 h, arm-off file;
the idle-recycle term is **OFF** — `spark_oom_watchdog_recycle: false` — and hardware-spark.md
§Unified-memory budget proves it live).

- **Gauge: `usable = MemAvailable − CmaFree`** (`node_memory_MemAvailable_bytes -
  node_memory_CmaFree_bytes`, `job="alloy"`, `instance=~"spark.*"`). On GB10 the GPU carve is CMA and CMA
  counts as available, so raw `MemAvailable` **inflates as pressure rises** (by up to ~9.5 GiB here) — a
  threshold on it can never warn before the cliff. `MemFree − CmaFree` is the inverted alternative.
  Rationale + the incident series: [hardware-spark.md](hardware-spark.md) §Unified-memory budget and
  [spark-incidents.md](spark-incidents.md) #7/#8.
- **Thresholds are measured, not designed:** `WARN < 12 GiB for 2m` (`noDataState: OK`) /
  `CRIT < 8 GiB for 1m` (`noDataState: Alerting`). Both observed kills were at **1.62 / 1.64 GiB**, but the
  lowest value a 60 s scrape ever recorded inside those windows was **5.01** — a rule set at the kill point
  could not have fired. The sampling gap behind that sentence is its own section: **§Scrape cadence and
  metric resolution**.
- **Preflight before touching these rules:** confirm `node_memory_CmaFree_bytes` exists in VictoriaMetrics.
  It is **not** in node_exporter's default meminfo whitelist, and on a CRIT rule with
  `noDataState: Alerting` a missing series is a false-positive machine.
- **Operating point:** at the certified 16 GiB KV pool, idle `usable` is **18.5 GiB** (6.5 GiB of WARN
  margin) and the certified worst case bottoms at **17.78 GiB**. The thresholds still clear — but there is
  **no room for another KV raise in bf16**, because that would put WARN inside routine-transient range.
- Both rules load in the ruler (`vps.yml --tags monitoring`) with CRIT `noDataState: Alerting`.

### Silent-failure hygiene: unit results and consumer cert age as series

Two signal classes a plain metric scrape does not produce: a systemd unit's *result*, and the cert pair a
**consumer** holds. A timer that fails on every run changes **no series anywhere**, so no rule can see it;
and the rule `ssl-cert-expiring` reads `probe_ssl_earliest_cert_expiry`, which is structurally dead
because blackbox emits no SSL expiry and that metric has **zero series**.

`roles/monitoring` ships `homelab-hygiene.py` on every monitoring host (loopback `:9098`, scraped by
that host's Alloy into the same remote_write path as everything else). The exporter's rendered docstring
carries no ticket-id token and no ISO date: the deployed copy on oldsrv
(`/usr/local/sbin/homelab-hygiene.py`) returns zero hits for both patterns, and `check_iac_identifiers.py`
holds the `IaC/` template half clean:

| Series | Meaning |
| --- | --- |
| `homelab_unit_last_success{unit=}` | 1 when the unit exists AND its last run succeeded — the only signal that separates a healthy oneshot from a failing one, because `is-active` answers `inactive` for both |
| `homelab_unit_result{unit=,result="success\|failed\|missing"}` | the reason, for the dashboard and the alert text |
| `homelab_unit_last_success_timestamp_seconds{unit=}` | unix time of this unit's last SUCCESSFUL run — the age the two result series cannot express, because a timer that stops firing produces no attempt and therefore no result, leaving `last_success` holding the value of some earlier success indefinitely. Emitted ONLY for a unit a `.timer` triggers (`TriggeredBy`) and only when the last run succeeded, so a long-running daemon — the NUT units on the same list — and a unit that has not run since a boot both emit nothing rather than an age that would page a healthy host |
| `homelab_cert_pair_present{consumer=}` | 1 when the pair this edge actually loads exists |
| `homelab_cert_days_left{consumer=}` | days to expiry of the pair this edge loads |
| `homelab_nut_master_reachable{master=}` | 1 when this host's NUT **client** can read its master — a unit result never implies this claim |
| `homelab_nut_master_result{master=,result="ok\|unreachable\|unknown"}` | why the leg reads what it reads: `unreachable` = `upsc` answered with a failure, `unknown` = no `upsc` binary or the call outlived its 5 s bound |
| `homelab_gpu_present{gpu=}` | 1 while EVERY declared sysfs counter of that GPU reads — a renamed/re-probed card reports `0` and emits no value, because a zero-filled "used" would read as an idle card |
| `homelab_gpu_vram_used_bytes{gpu=}` · `homelab_gpu_vram_total_bytes{gpu=}` · `homelab_gpu_busy_percent{gpu=}` | the `amdgpu` sysfs counters (`mem_info_vram_used` / `mem_info_vram_total` / `gpu_busy_percent`) — the only GPU telemetry the oldsrv RX 7600 can produce, because that host ships no `rocm-smi`/`amd_smi` (§LLM token accounting rule 6). Declared per host in `host_vars/oldsrv.kogler.si.yml`, addressed by **render node** so a card re-numbering cannot silently orphan the leg |
| `homelab_hygiene_scrape_ok` | the collector's own heartbeat — the collector is a systemd service, i.e. the same failure class |

⚠ **What the cert legs cover**, at the metric-name level (VM
`/api/v1/label/__name__/values`, cross-checked per host against `curl -s 127.0.0.1:9098/metrics`): the
`homelab_cert_*` family carries one entry per consumer edge that loads a **PEM file** on disk —
`consumer="traefik-internal"` on oldsrv, `consumer="traefik-ha"` on the Pi, and the VPS pair-dumper's two
outputs as `"traefik-tailnet"` / `"traefik-tailnet-ts"` — **all four are in the backend today**, read on
2026-10-17 as `homelab_cert_pair_present` = 1 for each (`traefik-internal` 34.85 d, `traefik-ha` 34.85 d,
`traefik-tailnet` 34.85 d, `traefik-tailnet-ts` 40.74 d). The other cert-bearing series are blackbox
`probe_ssl_earliest_cert_expiry` (**zero series** — blackbox emits no SSL expiry, which is what makes the
`ssl-cert-expiring` rule structurally dead) and Traefik's own `traefik_tls_certs_not_after`, which the
VPS-only `job="traefik"` scrape takes from the **issuer's** in-memory cert view.

**The VPS box cert has no acme.sh behind it** — no `acme.sh` binary, no `/etc/letsencrypt`, no
`/var/log/acme.sh.log`. The VPS Traefik *is* the fleet's single ACME issuer (Cloudflare DNS-01), so its own
material lives in `/opt/traefik/acme/acme.json`, a JSON store `openssl x509` cannot open; the part this box
loads as a pair is the dump in `/opt/traefik/certs/`, bind-mounted into `traefik-tailnet` and written by the
certs-dumper's rename step. That dump is therefore the cert leg this host was missing, and the issuer's age
is already a series through Traefik's own metrics. A rule written against a plausible-sounding name like
`cert_age_days{name="vps-cert"}` would sit green forever on a series that has never existed, which is the
failure mode this whole section exists to prevent.

*Fail-loud by construction*, because a monitor that says "healthy" about what it cannot see is the worst
failure here: a listed unit that is not installed → `0`/`missing` (so a wrong list
costs a visible alert, never silence); a unit whose `systemctl show` gives no output at all → `0`/`unknown`;
an absent cert file → `pair_present = 0`, **not** a NaN days-left value, because `NaN < 14` is false and a
vanished pair would have read as "not expiring". All four branches are canaried, including a real failed
transient unit (`systemd-run --wait --unit=… /bin/false` → `0`/`failed`).

**Thresholds are measured, not copied.** The live pair is a **90-day cert** (`notAfter 2026-11-20`) and the
issuer renews late in that window, so a healthy consumer's `days_left` bottoms out near three weeks — a
30-day warning would fire for days before every scheduled renewal, which is how an alert class gets muted.
Shipped: **WARN 14 d / CRIT 7 d** + a critical on
`pair_present == 0`. Re-derive them if the pair lifetime or the renewal threshold changes.

**Fleet coverage:** the exporter runs on `oldsrv · pi · nas · vps · spark`. Count them from the store,
never from this sentence: `count by (instance) (homelab_hygiene_scrape_ok)` answers which collectors are
reaching the backend, and the two numbers are not the same claim — the exporter runs on every host,
while a host reaches the store only if its **own Alloy** ships what it scraped. `nas` publishes no unit
and no cert series because it declares neither a watched unit nor a cert pair, and that absence is
topology; the absence that matters is when a host publishes **nothing at all**, which the next
paragraph is about. The rules are in
Grafana: of 32 rules loaded, **8 reference `homelab_*`** — `cert-pair-missing` (CRIT, 5 m),
`cert-age-critical` (`< 7 d`, CRIT, 10 m), `hygiene-collector-stale` (CRIT, 5 m), `unit-last-result-failed`
(WARN, 5 m), `cert-age-warning` (`< 14 d`, WARN, 30 m), `nut-master-unreachable` (WARN, 5 m), `pkg-pin-drift`
(WARN, 30 m, §Pin-lag report) and `unit-last-success-stale` (WARN, 30 m, the age half below) — read back from the ruler API. Count them from the ruler API, never
from this sentence — the read is in the table below.

**A unit's RESULT is not its AGE, and only the age sees a dead timer.** `unit-last-result-failed` reads
`homelab_unit_last_success`, which answers "how did the last attempt go" — so a timer that stops firing (masked,
unset, a `.timer` whose install never landed) leaves the gauge at **1** for as long as the host is up, and a run
that never returns leaves it wherever the last good run left it. `homelab_unit_last_success_timestamp_seconds`
above, with the `unit-last-success-stale` warning rule (90 min, `for: 30 m`), is the age half. **It is loaded and
evaluating, and it has never been watched red**: 32 rules load on the backend and this one lists two live
instances (`traefik-cert-pull.service`, `ha-cert-sync.service`), both `Normal` at ~4 min of age. Reaching it needs
90 min of a watched timer not succeeding, and both shortcuts are refused below — fail a real cert puller, or park
a fabricated sample in the metric store, which is a page that lies. The series is the proof to look at first: on the Pi it read
`last_success = 0` / `result = "failed"` on every scrape of a tick that failed, which is the result half working
exactly as designed while nobody was looking at it.

**A host that emits NO series is invisible to every rule, so the expected set has to come from the
inventory.** The shape, measured on the storage collector host: `alloy` and `homelab-hygiene` both
`active`, `:9098` answering its `homelab_*` lines, the unit `active (running)` for 19 h with **one**
runtime thread burning 100 % of a core and `curl 127.0.0.1:12345/metrics` hanging to its timeout (TCP
accepted by the kernel, never answered by the process) — and in the store **zero** series carrying that
host's `instance`, no `up{job="alloy"}`, no `node_uname_info`, no heartbeat. Before it wedged the unit
had restarted 4,847 times in one boot, each exit `status=2/INVALIDARGUMENT` — which is how a **Go
runtime fatal** leaves a process, not how a bad config leaves one: the rendered file answers
`alloy validate` with rc 0, so nothing in the role was wrong about the box. Its `nut_exporter` and
`zfs_exporter` stayed green the whole time, because OLDSRV scrapes those under
`instance="<ip>:919x"`, not under the host's name. Nothing paged:
`hygiene-collector-stale` is correct as written — unfiltered A + a threshold — and a threshold needs a
value, which a dark host never produces. Three instruments close it, and each proves a different half:
| Instrument | What it holds | What it cannot do |
| --- | --- | --- |
| the probe + restart leg in `roles/monitoring` | the SERVING claim at converge time: `curl -sf -m 10 127.0.0.1:12345/metrics`, and one `systemd state: restarted` on the host whose own listener refused | act between converges; `state: started` alone asks systemd whether a process exists, so a converge on a wedged host reported `ok` and changed nothing |
| `scripts/gate/check_host_reporting.py --check` | the **expected set**: every host in the inventory's `[monitoring]` group must carry `up{job="alloy",instance=<host>}` **and** the heartbeat. Four verdicts — `BLIND`, `SCRAPE LEG DEAD`, `COLLECTOR STALE`, `UNDECLARED` | say which of the four shapes a page means, and answer between converges only when run — the rule-shaped form below pages, but it cannot name the shape |
| the metric rules | every shape where a value exists and goes stale | see a host that never produced a value |

**The paging half is one generated `absent_over_time` rule per `[monitoring]` host, and that form was chosen
against the anti-join on purpose.** `roles/monitoring/vars/main.yml` builds `grafana_alert_rules_blind_host`
from `groups['monitoring']` — never from a list typed into a file, because an expected set with two owners
drifts exactly when a host is added — and `grafana-rules.yml.j2` appends it to `critical`, so ONE rule body
renders both halves. The rendered rule is
`absent_over_time(up{job="alloy",instance="<inventory hostname>"}[10m])`, `for: 5m`, evaluator `gt 0`, severity
critical (a host nobody can see hides every other fault, so it is not a warning).

| Knob | Value here | Why, and what the alternative cost |
| --- | --- | --- |
| rule shape | one rule per host, the expectation carried in the expression | The anti-join needs a publisher for a static `homelab_expected_host{instance=…} 1`. Nothing publishes it: `count(homelab_expected_host)` answers **empty** on the live store, so the anti-join is NoData and — with the only sane `noDataState` for an absent-style rule, `OK` — **it is green on a tree where the expected set never loaded at all**. Its failure direction is silence. `absent_over_time` is evaluated inside VictoriaMetrics and its failure direction is a page: no matching series in the window ⇒ `1`, carrying the selector's labels, so the page names the host. Measured: `…instance="nas.kogler.si"` → `1`, `…instance="vps.kogler.si"` → empty. |
| the probed metric | `up{job="alloy",instance=<host>}` | The same selector the offline check uses, so the two instruments cannot disagree about what "reporting" means. Deliberately NOT `homelab_hygiene_scrape_ok`, which is absent on a host that declares no watched units and no cert pair — topology, not an outage, and it would page on a newly-added collector host. |
| `noDataState` | **`OK`** | For an absent-style rule the healthy state IS NoData: a reporting host makes the expression return nothing. `Alerting` here pages on a healthy fleet, which is how an alert class gets muted inside a week. |
| `execErrState` | **`Alerting`** | The half that closes the green-out trap `noDataState: OK` opens. "Every host reports" and "nobody could be queried" must not be the same state. A store that cannot answer at all (connection refused, a broken datasource, an expression the backend rejects) lands in Error, and Error is a state nothing pages on; `Alerting` makes "I could not look" cost a page — the right trade for the one rule whose whole job is to notice that nobody is looking. |
| `keep_firing_for` | **not set** | It shipped once at `5m` and was removed on measurement: the provisioned file said `keep_firing_for: 5m` while the loaded record read `keep_firing_for: 0s` (`GET /api/v1/provisioning/alert-rules/<uid>`) — this Grafana's **file** provisioning applies `for`, `noDataState` and `execErrState` and drops that key. A knob whose value the backend discards is worse than no knob: it reads as a protection the rule does not have. The anti-strobe property therefore comes from the 10 m window + the 5 m hold, which is what actually governs. |

**Watched red, live, with nothing fabricated.** The set loaded at 16:24:54 and `No telemetry from
nas.kogler.si` went **`firing`** at 16:30:00 — `value=1`, `labels{instance="nas.kogler.si", job="alloy",
severity="critical"}` — the `for: 5m` hold after the load, on the box that has published nothing since its
collector began crash-looping. The four hosts that DO report read `Normal (NoData)`, which is the designed
healthy state. The reads that answer are `/api/prometheus/grafana/api/v1/rules` (per-rule `state`, and
`alerts[].state` / `activeAt` / `value` per instance) and `/api/v1/provisioning/alert-rules` (what is LOADED,
32 rules, `provenance: file`). ⚠ Both endpoints can mislead: the ruler API and the provisioning folder
endpoint key a file-provisioned rule by its **TITLE**, so grepping either for a `uid` finds nothing while every
rule is loaded.

What is NOT retired is the offline tool: it still answers **which of the four shapes** a page means, which no
rule can, and its teeth are still measured by `--self-test` — remove one instance's series from a fixture store
and it must redden, and re-run that same healthy store against an inventory declaring one host more, which must
also redden because the set comes from the inventory and not from what happens to report.

**What the restart leg bought, measured.** Probing and restarting the host whose listener refused is the
right repair for a wedged collector and the wrong expectation for this box: the probe returned rc 28
against a socket in `LISTEN`, one `systemd state: restarted` ran, the listener answered `200` and
`up{job="alloy"}` came back — for about two minutes. After that the process died every ~5 s with
`fatal error: traceback did not unwind completely` on Go 1.26.7, preceded by `runtime: gN: frame.sp=…
top=…` (a frame pointer ABOVE the stack top, which no application-level panic produces), and the restart
counter ran 99 → 107 in 41 s at load 2.07. The unit was then **stopped** to end the CPU churn — not
masked, no drop-in, still `enabled`, so a boot brings it back; the restore line is `systemctl start alloy`
on that host. So the class this section names is now closed by the instruments, while the cause on that
one host is a hardware/firmware question owned by [hardware-nas.md](hardware-nas.md), not by this section:
the repo is excluded (the rendered file validates rc 0, the converge found the template unchanged, the
same pin runs on two other hosts of the same arch and OS without dying) and so is memory corruption
(`edac` `ce_count`/`ue_count` are 0, no `mce` lines, and the `DMAR: ERROR: DMA PTE … already set` traces
— which carry `Comm: alloy` and look like the smoking gun — are that box's documented benign VT-d quirk).
Until it publishes again, the expected-set check reads **red for that host and that is the correct
signal**: it is naming a real hole in what the fleet can see, and the fix is not to soften the set.

⚠ **`active` is not `serving`, on any collector host.** The reads that answer are the collector's own`/metrics` on the box and `up{job="alloy"}` in the store; `systemctl is-active` answers a different
question and, in the case above, answered it wrongly for 19 hours.

**`hygiene-collector-stale` must be written as unfiltered A + a threshold expression**, the shape
§Alerting demands: `time() - max_over_time(homelab_hygiene_scrape_ok[6h])` in A, `gt [900]` in B, `for: 5m`,
`noDataState: Alerting`. Read back it yields **five series, one per host, each carrying `instance=`** and
`Normal` when fresh. A filtered expression (`time() - homelab_hygiene_scrape_ok > 900`) instead deletes
every series on a healthy evaluation, so the rule fires on a healthy fleet as ONE valueless
`Alerting (NoData)` series — a filtered result has no labels to enumerate — and a genuinely dead collector
reaches the rule as NoData (no `instance=`, so no host name) rather than as a value, because the 5-min
staleness horizon drops the heartbeat long before 900 s is reachable. Wrapping the metric in
`max_over_time(…[6h])` fixes the second half: **Normal when fresh, a per-host `instance=` page at ~20 min of
silence, NoData only if no host has collected in 6 h**. A page lands **20–21 min after the last collection**
and clears **~1.5 min after the cause is fixed** (next scrape + the 1 m rule interval).

**Three reads answer, and two confidently lie**:

| Question | The read that answers | The read that misleads |
|---|---|---|
| Are the rules in Grafana? | `GET http://<grafana-container-ip>:3000/api/ruler/grafana/api/v1/rules` with `admin` + the password from `docker exec grafana printenv GF_SECURITY_ADMIN_PASSWORD` (the role's own source — never a vault guess). Match on the **metric in the expression**: a file-provisioned rule lists under its TITLE, not its `uid`. | `GET /api/v1/rules` → **404** on this Grafana; a name-match on `uid` finds **zero** of the five while all five are loaded. |
| Did the series reach the backend? | Query **through the datasource proxy**: `…/api/datasources/proxy/uid/prometheus/api/v1/query?query=…`. | A direct `curl` to `victoria-metrics:8428` answers **400** even with correct basic auth (this VM build wants a request shape curl's `-G` does not produce) — a 400 there is NOT "no data", and a 401 is often just the absent `OP_SERVICE_ACCOUNT_TOKEN`, because the vault lookup then yields nothing. |
| Is the exporter up on a host? | `curl -s 127.0.0.1:9098/metrics \| grep -c '^homelab_'` on that host (oldsrv: 9). | The unit being `active` — the collector can be up and its `systemctl show` loop empty. |

End-to-end delivery is **✅ live** — Signal + email both confirmed received. Once the Matrix
delivery leg lands the read moves from the Signal group to the `#homelab-alerts` room; the trigger does not
change.

⚠ **A canary must be a unit the collector actually reports.** `homelab-hygiene.py` reports **only** the
units in `monitoring_hygiene_units` for that host (oldsrv: three series, `traefik-cert-pull` +
`nut-monitor` + `nut-client`), so `systemd-run --wait --unit=<name> /bin/false` outside that list emits no
series and a rule with nothing to compare is silent. Listing a canary would fire it as `result="missing"`
(the fail-loud branch doing its job), but that costs a `host_vars` edit + a converge, and failing a real
watched unit to test a notification means breaking the cert puller or the NUT clients. **What tests the
exact class the rule exists for without breaking anything:**

```bash
ssh <host> 'sudo systemctl stop homelab-hygiene'    # one monitoring host; nothing else reads :9098
# …wait ~20 min for the rule, read the alert channel, then:
ssh <host> 'sudo systemctl start homelab-hygiene'
```

No other rule keys on `up{job="homelab-hygiene"}` (all 24 checked), so exactly one rule can fire, and only
that host is blind for the length of the test. The other hosts stay `Normal`.

⚠ **`textfile` is unusable on this Alloy build.** `prometheus.exporter.unix` here accepts a
`textfile {}` block but rejects every attribute name that would point it at a directory — probed against
v1.20.1 on the box: `collectors_dir`, `directories`, `paths`, `files`, `syntax_version` each return
`unrecognized attribute name`, while `textfile {}` with an empty body parses. Collector-side data therefore
follows the shape the same role already proves live (the network-clients exporter), never a textfile
directory; that is also why `set_collectors` does NOT list `textfile`.

**Coverage today**, from the read rather than from this sentence
(`curl -s 127.0.0.1:9098/metrics | grep -c '^homelab_'` on each host): all five monitoring hosts publish the
heartbeat and the pin-lag legs (§Pin-lag report); oldsrv (`traefik-cert-pull` + the two NUT units) and the
Pi (`ha-cert-sync` + the two NUT units) also publish one cert pair and the NUT client leg each, all
`last_success = 1`; `nas` and `spark` publish no unit or cert series, because neither declares a watched
unit or a pair — that absence is topology, and it is why the cert rules read four consumers, not five.

**The NUT client→master leg is the claim the unit legs cannot carry.** `nut-monitor.service` and
`nut-client.service` stay `active` while the master stops answering — `upsmon` retries forever and never
fails its unit — so a window in which a client reads nothing is invisible until a converge happens to run
its own client-leg assert. `homelab_nut_master_reachable` runs the client's own
`upsc <ups>@<master> ups.status` on every scrape, on the client host, against the master `nut_host` names;
UPS *values* stay single-sourced on the master (see §UPS / Power-Loss Monitoring (NUT)), so this leg adds a
reachability verdict and never a second copy of the battery numbers. A client that declares no master emits
no series — the leg is declared per client host, and absence of the declaration is the one case the rule
cannot see.

**Deploy state: ✅ LIVE on all five monitoring hosts (read 2026-10-17).** Both legs shipped inside
`homelab-hygiene.py` plus the host lists and landed with the `--tags monitoring` converges; what closed
them is the read, not the run log:

| Leg | The read that closed it | Verdict |
| --- | --- | --- |
| NUT client → master | `curl -s 127.0.0.1:9098/metrics \| grep '^homelab_nut_'` on oldsrv and on the Pi | `homelab_nut_master_reachable{master="nas.kogler.si"} 1` + `homelab_nut_master_result{master="nas.kogler.si", result="ok"} 1` on **both** clients |
| …in the store | `GET /api/v1/query?query=homelab_nut_master_reachable` through the datasource proxy | two series, `instance=oldsrv.kogler.si` and `instance=pi.kogler.si`, both 1 |
| VPS consumer cert pairs | `curl -s 127.0.0.1:9098/metrics \| grep '^homelab_cert'` on the VPS | `homelab_cert_pair_present{consumer="traefik-tailnet"} 1` and `{consumer="traefik-tailnet-ts"} 1` |
| …in the store | the same query for `homelab_cert_pair_present` | four consumers across three hosts — the VPS pair arrived with the other two |
| The rule | `GET /api/ruler/grafana/api/v1/rules` | loaded in `Homelab · Warning` as "NUT client cannot reach its master", `expr: homelab_nut_master_reachable == 0`, `for: 5m`, `no_data_state: OK`, `exec_err_state: Error`, condition B `lt 1` |

`nas` and `spark` emit no `homelab_nut_*` series and that is correct: neither declares
`monitoring_hygiene_nut_masters`, so they run no NUT client — absence is topology here, and the rule's
`noDataState: OK` is what keeps it silent rather than falsely green. A host that DOES declare a master and
stops producing the series is the `hygiene-collector-stale` rule's page, not this one's.

⛔ The converges that landed this are not repeatable casually: `--diff` on this role prints vault values
into the run log (→ [deployment-secrets.md](deployment-secrets.md)), and on the VPS the monitoring role
restarts the scrape tier.

⚠ **Never dump `/etc/alloy/config.alloy` to inspect the
remote_write block**: it prints the VictoriaMetrics **and** VictoriaLogs basic-auth passwords. The file is 0600
root but it is not a safe thing to `grep -A40`. Take credentials through the vault lookup the role already
uses, or read them into a shell variable and never echo them — this is why the monitoring tasks template
them from `victoria-metrics_api` / `victoria-logs_api` instead of reading back rendered files.

#### Pin-lag report: running version vs the pin, with no updater anywhere

The visibility half of a version policy that deliberately has no automated upgrade phase
([CONVENTIONS.md](../CONVENTIONS.md) §7; the hold leg that keeps the pins frozen is
`roles/common/tasks/apt-holds.yml`): an updater would make the pin advisory, and `group_vars/all/versions.yml`
is the version truth. So the fleet **reports** the lag instead of closing it — what a host runs, what the
repo says it should run, and whether a reboot is still owed. Same collector, same loopback port, no second
timer and no second service:

| Series | Meaning |
| --- | --- |
| `homelab_pkg_pin_ok{package=}` | 1 when the installed version MATCHES the pin — exactly for a pin that carries a dpkg revision, on the dpkg upstream version for a family pin — the shape that keeps "in sync" distinct from "not installed here" |
| `homelab_pkg_pin_result{package=, pin=, result=, running=}` | the comparison itself. `result` is `match` / `differ` / `missing` (this host does not carry the package) / `unknown` (dpkg gave nothing readable), and both version strings travel as labels |
| `homelab_upgrade_plan_ok` | 1 once a simulated plan has been read — `0` means "no readable plan yet" (seconds after a restart, or an apt wedged on its lock), never "nothing pending" |
| `homelab_upgrade_plan_count` | how many packages this box's own solver would upgrade |
| `homelab_reboot_required` | 1 while Debian's own `/run/reboot-required` marker exists |

**Where the pin comes from.** `monitoring_hygiene_pins` (`roles/monitoring/defaults/main.yml`) IS the fleet's
pin map, `host_apt_pin_vars` (`group_vars/all/versions.yml`) — the same mapping that drives `apt-mark hold`
(`roles/common`) and the `package=version` install (`roles/docker`), so the report cannot fall behind the
pin set and a package cannot be held with no pin. Each entry pairs a package with the NAME of the
`versions.yml` var that pins it, and the template resolves that var at render — no version literal exists
in the collector, in a rule, or in panel text, and an undefined pin var aborts the render instead of
reporting "no pin" about a healthy box. The consequence is worth stating plainly: the pin the report
compares against is the pin **as of the last monitoring converge**, so a `versions.yml` bump that never
converged reads as "in sync" with the older value.

One pin shape needs one comparison rule. A pin that carries a dpkg revision (`alloy_version` =
`1.20.1-1`) compares EXACTLY; a pin that carries none is a FAMILY pin and compares on the running
version's dpkg upstream part — everything before the last hyphen — because download.docker.com stamps
the same release as `5:29.8.2-1~debian.13~trixie` on Debian 13 and `5:29.8.2-1~ubuntu.24.04~noble` on
Ubuntu 24.04, and a fleet-wide value can only name the part both share. `roles/docker` asserts the same
rule after installing the suite, so a box the converge never moved reddens instead of reporting green.

**It cannot change anything — and that is a property of the reads, not a promise.** `dpkg-query -W` reads
the status file without ever taking the dpkg lock; the solver runs as `apt-get -s` (simulate), which
prints a plan and executes nothing; `apt-mark` is not called; the reboot leg is one `stat`. Two details
make the read HONEST rather than merely harmless:

* `LC_ALL=C` on both apt reads. The plan summary line and dpkg's absent-package message are TRANSLATED —
  on a Slovene locale a parse that assumed English finds no count and reports a healthy-looking "0
  pending", which is the fail-open half of the exact class this collector exists for.
* `apt::get::show-upgraded=false` keeps the summary line and drops the per-package list, so the plan read
  costs ~1 s instead of dragging thousands of package names through a pipe. It is therefore the ONE leg
  not collected per scrape: the read runs on its own thread at most every 15 min (60 s after a failed one)
  and the scrape serves the cache — never inline, because apt waits for the dpkg lock and a stalled render
  freezes `homelab_hygiene_scrape_ok`, which is the CRIT heartbeat rule: it would page about a dead
  collector in the middle of someone's unrelated converge. Measured scrape cost, cold and warm alike:
  **59 ms**. The pin and reboot legs stay collected per scrape, single-digit ms each.

| Question | The read that answers it |
| --- | --- |
| Is a host off its pin? | `homelab_pkg_pin_result{result="differ"}` — the two labels ARE the proof (`pin=`, `running=`). Measured 2026-10-18 after the vps `--tags docker` apply (which moved vps to the pin): oldsrv and vps all their pins match (`alloy` `1.20.1-1`, `tailscale` `1.102.5` — `missing` on vps, which carries no Tailscale — and the docker family at `5:29.8.2`/`2.3.6`/`0.37.1`/`5.5.1`); on pi/spark the docker-family entries still read `differ` (6 on pi, 5 on spark plus one `unknown`) — see the fleet table below |
| How far from current is the box? | `homelab_upgrade_plan_count` — measured 2026-10-17: oldsrv **56**, vps 74, pi 93, nas 95, spark 230. None of those are the pinned packages, because a HELD package is kept back rather than listed (the ⚠ below): the count is the whole unpinned OS tail. It is the staleness signal, never a pin signal |
| Does this host even carry the package? | `result="missing"` — what a fleet-wide list reads on a host that legitimately does not carry it, and the reason a first rule keys on `result="differ"` rather than on the ok gauge. Measured 2026-10-17: `nas` reports `missing` for the whole docker family (no Docker there) and for `tailscale` |
| …and if dpkg answers nothing at all? | `result="unknown"` — measured on spark for `docker-ce-rootless-extras`: an empty version with rc 0, because the dpkg state is `hold ok not-installed`. A held package the box never installed is NOT the same fact as `missing`, and neither one is drift |
| Is a reboot still owed? | `homelab_reboot_required` |

⚠ **A HELD package does not appear in the plan count** — the solver keeps held packages back instead of
listing them, so the pin legs, never the plan, are what reports a held package's version.

**The rule is `pkg-pin-drift`, and it was written AFTER the series were read out of the store, not with
them.** The shape needs no threshold — `count by (instance) (homelab_pkg_pin_result{result="differ"})` —
but a rule written against a series the backend has never held sits green forever, which is the failure
mode this whole section documents. Its two non-obvious settings are reasoned in
[`../IaC/ansible/roles/monitoring/vars/main.yml`](../IaC/ansible/roles/monitoring/vars/main.yml) and are
not copies of the neighbours: it keys on `result="differ"` and **never** on `homelab_pkg_pin_ok` (the ok
gauge is 0 for "off its pin" AND for "this host does not carry the package", so a fleet-wide rule on it
pages `nas` forever), and it takes `noDataState: OK` because a filtered-empty result IS NoData
(§Operational gotchas) — `Alerting` here would page every evaluation on a fleet that is entirely in sync.

**What the fleet reads today** (2026-10-17, `count by (instance, result) (homelab_pkg_pin_result)` out of
VictoriaMetrics, cross-checked against each host's own `:9098`):

| Host | `match` | `differ` | `missing` | `unknown` |
| --- | --- | --- | --- | --- |
| oldsrv | 8 | — | — | — |
| nas | 1 (`alloy`) | — | 7 (the docker family + `tailscale` — nas runs no Docker and no Tailscale) | — |
| pi | 2 (`alloy`, `tailscale`) | 6 (the docker family) | — | — |
| spark | 1 (`alloy`) | 5 (the docker family) | 1 (`tailscale`) | 1 (`docker-ce-rootless-extras`) |
| vps | 7 (`alloy` + the docker family) | — | 1 (`tailscale`) | — |

⚠ **So `pkg-pin-drift` fires the day it loads, first on `pi`, `spark` and `vps`, and that is true, not a false
positive**: `docker_ce_version` is `5:29.8.2` and those three boxes ran `5:29.7.2` (`containerd.io`
`2.3.6` vs `2.3.4`, buildx `0.37.1` vs `0.37.0`, compose `5.5.1` vs `5.5.0`). The drift is the pending
`--tags docker` applies on the pinned docker-family suite `roles/docker` installs — each restarts the
daemon, so they are owner-windowed, one host at a time, not a converge a lane may run. Now that the
family is HELD, `apt upgrade` will not close the gap on its own: the rule stays red until those applies
run. vps was established on the pin 2026-10-18 (`--tags docker` apply + `sudo docker restart traefik
dozzle crowdsec` recovery — the daemon restart stale-sockets the docker.sock mounts of the live-restore
survivors, see deployment-manual §1.10), so the rule now reads red on `pi` and `spark` only. Do not mute it to make the landing quiet.

⚠ **`docker-ce-rootless-extras` is named in the suite, so nothing keeps this rule red except the
applies themselves.** It is in the pin map and in the held set, and `roles/docker` installs it there:
the suite list is `docker_ce_suite_packages`, which drives the apt call, the pre-install hold decision
and the read-back assert alike, and the family the pin map names is asserted to BE that list — a pinned
docker package that no task installs now reddens the converge instead of waiting for someone to notice.
What that means host by host: on `vps` the 2026-10-18 `--tags docker` apply moved it to
`5:29.8.2` with the rest of the family (their `differ` entries cleared and the collector re-reads
`match` on vps — measured on the host itself); on `pi` the same pending apply moves it; on `spark`
the same apply INSTALLS it — its dpkg state today is `hold ok not-installed`, `dpkg-query` answers empty
with rc 0, and the simulate there reads `5 upgraded, 1 newly installed` with this package as the new one
and `dbus-user-session` + `libc6` as its only dependencies, both already present; on `nas` nothing
changes, because `playbooks/storage.yml` carries no docker role at all, so the `missing` reading there
is structural and stays. ⚠ And the apply has to lift the hold to work, which is now the role's job and
not the operator's: a held package is NOT movable by an apt-module install
(`apt-get -s -y install 'docker-ce=5:29.8.2-*' …` answers `E: Held packages were changed and -y was used
without --allow-change-held-packages`, rc 100, where the same command without `-y` resolves), so
`roles/docker` unholds the names it moves, installs, and re-holds them in the same play — see
[deployment-ansible.md](deployment-ansible.md) §common. Until those applies run the rule stays red on
`pi` and `spark` (vps is in sync since 2026-10-18), and that is the honest reading, not noise.

⚠ **`unknown` is a fourth reading, and the hold leg explains it.** On spark `dpkg-query -W
-f='${Version}' docker-ce-rootless-extras` answers **empty with rc 0** — the dpkg status is
`Status: hold ok not-installed`, a package the database knows and holds but has never installed — so the
absent-package branch (`"no packages found" in stderr`) does not fire and the collector reports `unknown`
rather than `missing`. That is the fail-loud branch working: "no version" never collapses into "match". It
is also a standing correction to the idea that a host holds only what it runs — the hold leg's "which
packages does this host carry" probe is `dpkg-query -W -f='${Package}'`, which answers for a deinstalled
package too, so a held-but-not-installed package is a real state in this fleet (read `apt-mark showhold`
against `dpkg-query -s <pkg>`, never against each other).

**Deploy state: 🟢 LIVE — the collector on all five hosts and the rule loaded in the ruler; the rule reads 🔴 red on
`pi` and `spark` only — vps is ON the pin since the 2026-10-18 `--tags docker` apply, and its collector
re-reads `match` for the whole docker family (measured on the host); the remaining red is the pi/spark
docker-family lag being reported rather than work left on this leg.** The
collector half landed with the `--tags monitoring` converges and was verified per host with
`curl -s 127.0.0.1:9098/metrics | grep -E '^homelab_(pkg|upgrade|reboot)'` — 8 pin pairs +
`homelab_upgrade_plan_ok`/`_count` + `homelab_reboot_required` on each of `oldsrv · vps · nas · pi ·
the five). `pkg-pin-drift` ships in `roles/monitoring/vars/main.yml` and reaches Grafana only through the
rules task, and **which filter selects that task is a property of the tree, not of the host**: the role entry in
`playbooks/vps.yml` carries `tags: [monitoring]`, Ansible inherits a role's tags onto every task in it, so
`bash scripts/ansible/ansible-run.sh playbooks/vps.yml --tags monitoring` **does** select `Provision Grafana alert
rules` and a run under it cannot skip rule provisioning while printing green. The filter that silently dropped it
was **`--tags grafana`**, while the task was untagged and so inherited only the role's tag: that run re-provisioned
the contact points, the policy and the dashboards, reported `failed=0`, and never re-rendered `rules.yml` — the
silent-drop half of the tag class (→ [deployment-ansible.md](deployment-ansible.md) §Tags & surgical runs; the same class
as an untagged dynamic include, which is what `scripts/gate/check_tag_coverage.py` now holds). The task carries
`tags: [monitoring, grafana]` since, so **either** filter selects it and a surgical grafana run re-renders the rules.
⛔ That converge is a deliberate window, never an unattended one: on the VPS
the monitoring role restarts the scrape tier, and `--diff` on this role prints vault values into the run
log (→ [deployment-secrets.md](deployment-secrets.md); use `--check`). Read it back from the ruler API
afterwards — a rule that is authored is not a rule that is loaded. **That read has been done** (2026-10-17):
`pkg-pin-drift` is loaded in the `Homelab · Warning` namespace with `expr: count by (instance)
(homelab_pkg_pin_result{result="differ"})`, `for: 30m`, `no_data_state: OK`, `provenance: file` —
the seventh of the `homelab_*` rules listed at §Alerting. What keeps it red is nothing in this
repository: `roles/docker` names every package the pin map pins, and the pending `--tags docker`
applies — each one a daemon restart, therefore an owner window — are what moves `pi`/`spark`
onto the pin (vps already made it, 2026-10-18), `roles/common/tasks/apt-holds.yml` holding the
family in place between them. Until
those applies run, the red is the report working.

### Tiers

| Severity | What alerts | Channel | Notes |
|----------|-------------|---------|-------|
| **Critical** | oldsrv disk ≥90%, **nas ZFS pool usage ≥80% (`tank` & `bulk`)**, host down, ZFS pool degraded, service down >2min, `probe_success==0` · **UPS battery <20% or runtime <5 min (impending shutdown)** | Signal + email | page-worthy |
| **Warning** | high CPU/load (`host-load-high`), HA unreachable (`ha-unreachable`), **nas pool ≥70%** (`zfs-pool-warn`) · **UPS on-battery / mains lost (`ups-on-battery`, auto-clears on return)** · a systemd unit whose last run failed (`unit-last-result-failed`) · a consumer cert under 14 d (`cert-age-warning`) · spark usable memory < 12 GiB (`spark-host-mem-oom-warning`) · a NUT client that cannot read its master (`nut-master-unreachable`) · a host off its version pin (`pkg-pin-drift`, §Pin-lag report) | Signal (deduped) | first send once; re-sent only by the 24 h poke below. There is **no `mikrotik-link-down` rule** (an unpatched port is not incident-worthy, §Operational gotchas) and **no container-restart rule**; adding either class needs a rule in `roles/monitoring/vars/main.yml`, not a doc edit |
| **Info** | transient / everything else · **UPS online ↔ on-battery transitions / restored** | logged only | no push |

- **Poke/throttle:** a still-firing alert re-sends at most every **24 h** (`repeat_interval` in the notification policy the monitoring role renders). The first send is not throttled by it — `group_wait: 2m`, then `group_interval: 10m` between different alerts in one group. The value is deliberately a day: a fault that is parked for days by design (a host awaiting an owner hardware window, a host off its pin) is one finding, and re-paging it every half hour costs the reader the ability to hear the ones that are new.
- **Self-monitoring:** the observability stack itself (VictoriaMetrics/VictoriaLogs/n8n down) must alert — otherwise the alert channel dies silently.

---

## UPS / Power-Loss Monitoring (NUT)

- **Metrics (single source):** one **nut_exporter** on **nas** (the NUT master) reads local `upsd` → VictoriaMetrics (via Alloy scrape). Other hosts do **not** re-export identical UPS data (avoids redundancy).
- **Reachability is a separate claim, and a separate series:** `homelab_nut_master_reachable{master=}` is published by the hygiene collector on each **client** host from that client's own `upsc …@<master>` read — `nut-monitor`/`nut-client` staying `active` is not evidence that the master is reachable (→ §Silent-failure hygiene).
- **Shutdown:** **NUT owns local shutdown** on `nas`, `oldsrv`, and `ha` (Raspberry Pi). Grafana/n8n are **alert-only** — there is **no shutdown action from Grafana** (the observability **backend is on the VPS**, so it must never be the thing that halts the NAS during a power cut; only the host NUT agents power their own box).
- **Notification ordering & delay:** on mains loss the **Warning "on-battery" alerts at t=0** (WAN still up via router/ONT on UPS → Signal + email deliver). At **Critical**, `oldsrv` is **delayed ~60 s** before powerdown (via NUT `upssched`) so its own Grafana→n8n→Signal/email pipeline flushes the Critical alert, then it powers off. `nas` + `ha` power down immediately.
- **Guaranteed fallback:** a **NUT-side `notifycmd`/`upssched-cmd` script on nas** emails + sends Signal directly on `ONBATT` and `LOWBATT`, independent of Grafana/n8n — so a pre-shutdown notification is sent even if the observability stack is already degraded.
- Registered/configured via the `nut` Ansible role — see [`deployment-ansible.md`](deployment-ansible.md).

---

## Microservice Notes

- **MikroTik SNMP:** poll at **5–15 s**; the "1s" in dashboards is a *refresh* interval, not a poll.
- **Retention is deliberate:** 365d metrics / 90d logs, Kopia-backed (see [backup.md](backup.md)); long-term metric history beyond the retention window is a deferred option (remote-write/downsampling).
- **Placement:** the observability **backend** (VictoriaMetrics/VictoriaLogs/Grafana/blackbox + the VPS
  Dozzle viewer) runs on the **VPS** — the reliable tier. **The VPS is self-sufficient for its own
  observability**: it runs its own Alloy with `alloy_backend_host` defaulting to `127.0.0.1`, so VPS
  metrics/logs land locally with no tunnel, and its own Dozzle viewer (`logs.kogler.si`).
  **oldsrv/nas/Pi/spark run thin Alloy collectors** forwarding *home* telemetry over the `wg-s2s` tunnel
  (nas's Alloy is host-exporter only — it has no Docker — and nas is still scraped for its `nut`/`zfs`
  exporters by oldsrv). **Dashboards are tailnet-only**: no public exposure, reached over the headscale
  mesh via the `traefik-tailnet` edge with clean subdomain URLs. **n8n (`auto`) is internal-only** (no
  public route). The alert brain is on the VPS and delivers over the public net, independent of the tunnel.
  **SPOF, accepted and narrowed:** if the home↔VPS tunnel or the VPS is down, *home* metrics/logs are
  unavailable in Grafana — gracefully (writers buffer and replay on reconnect) — while the VPS's own
  telemetry stays visible locally. NUT-side `notifycmd`/`upssched-cmd` on nas is the power-loss alert path
  that never depends on this stack.

- **Dozzle is not a second log backend** — it streams live logs straight from the Docker API (read-only socket) and persists nothing. VictoriaLogs stays the single stored-log source (90d) and Grafana the search/alert surface.

### Dozzle multi-host — VPS viewer + LAN hub

The design: the VPS keeps the VPS-only viewer (`logs.kogler.si`), and **oldsrv runs a LAN log HUB**
(`llogs.kogler.si`, :8081) that shows oldsrv + pi + spark containers via **remote agents**
(`DOZZLE_REMOTE_AGENT` over the Home VLAN). LAN logs stay **LAN-only by design** — never reach
VPS / public / tailnet. `nas` has no Docker (Alloy host-exporter only), so no agent.

```
VPS Dozzle (logs.kogler.si, tailnet)  ─── VPS containers only
OLDSRV Dozzle HUB (llogs.kogler.si, :8081, traefik-internal edge — WAN-out survival)
   ├─ own docker.sock  → oldsrv containers
   ├─ agent pi    (pi_home_ip:7007) → pi containers (HA primary, Technitium)
   └─ agent spark (spark_home_ip:7007) → spark containers (vLLM, dashboard)
```

- **Templates:** `dozzle` (dual-mode: VPS viewer vs oldsrv hub, `svc.dozzle_agent_connect` /
  `svc.dozzle_listen_ip` per-service vars) + `dozzle-agent` (one per docker host: pi, spark,
  oldsrv). Registry rows in `group_vars/{home_servers,raspberry_pi,spark}.yml`.
- **Security posture (Dozzle docs):** agents publish **only on the Home-VLAN IP** (`:7007`, never
  WAN/0.0.0.0). Dozzle's universal built-in cert encrypts the agent channel; the LAN bind is the
  access gate. No UI auth on the hub by owner decision (LAN-only internal edge — matches the
  **no Forward-Auth** doctrine on traefik-internal for WAN-out survival). Upgrade path: generate a
  custom cert pair (`dozzle generate-certs`) + `DOZZLE_CERT`/`DOZZLE_KEY` on hub + agents if an
  agent port is ever exposed beyond the Home VLAN.
- **DNS:** `llogs.kogler.si` → `{{ oldsrv_home_ip }}` is seeded by the technitium-seed loop on the
  **home instances only** (oldsrv secondary + Pi tertiary) — never the VPS primary (same LAN-only
  rule as `modem`/`spark`). LAN clients resolve it directly; WAN clients must NOT resolve it.
- **Route:** `llogs` router + `llogs-backend` → `http://{{ oldsrv_home_ip }}:8081` in the
  traefik-internal `routes.yml.j2` (file provider, hot-reload).

- **State: ✅ live** — hub on `:8081` answering through `traefik-internal`, agents on all three home hosts
  (`:7007`, LAN-only, healthy), VPS viewer unaffected. `llogs.kogler.si` resolves to `oldsrv_home_ip` on the
  two home Technitium instances and **not at all on the VPS primary** (verified with `dig`), which is the
  LAN-only design working. The per-host `dns-seed.timer` self-heal is active on VPS + oldsrv + Pi; a
  one-command re-seed of all three instances is `playbooks/dns-seed.yml`
  ([`network-dns.md`](network-dns.md) §Convergence & Drift) — note that a **scoped** host converge (e.g.
  `--tags dozzle-agent`) skips the seed tail, so DNS can lag a deploy on purpose.
- ⚠️ **Open, owner-side (two, both misdiagnosed easily):**
  1. **`traefik-internal` serves `TRAEFIK DEFAULT CERT`** (self-signed fallback) → "Not Secure" on
     `media.kogler.si` / `llogs`. Cause chain: the wildcard pair is not in `traefik-internal/certs` because
     the **`traefik-cert-pull` 401s** — `/root/.ssh/traefik-cert-sync` is not yet authorized on the VPS
     (manual step, [services-traefik.md](services-traefik.md) §Edge model). Fix: authorize the pubkey on the
     VPS `ansible-admin` → `systemctl start traefik-cert-pull.service` → restart `traefik-internal` →
     verify `CN=*.kogler.si`. **A default-cert response means the cert-pull is broken, not the edge.**
  2. **A phone that 404s on `llogs` is resolving it to the VPS public edge** (LE cert + 404 = the tailnet /
     Pi edge, which has no `llogs` route — correct). The client is bypassing RouterOS DHCP DNS (Android
     Private DNS / VPN / DoH). Fix it client-side or with a router DNS force — **do not** add `llogs` to the
     VPS primary to make the symptom go away.

- **Log/metric store access control:** VictoriaLogs and VictoriaMetrics authenticate with **real
  Basic Auth** (`-httpAuth.username/-httpAuth.password`) from the `victoria-logs_api` /
  `victoria-metrics_api` items — consumed by Alloy (push/remote_write) and the Grafana datasources, and by
  the oldsrv MCP servers via `*_INSTANCE_HEADERS`. **This is a credential gate, not tenant isolation.**
  Exposure: **loopback + the `wg-s2s` address only**, never a WAN or LAN-facing
  bind. Fail-loud lookups (no `default()`); the `$` in rendered values must be escaped for compose.
- ⚠ **The Victoria images are tool-less** (`/victoria-*-prod` only — no `sh`, `wget`, `curl`, `nc`), so a
  `CMD` healthcheck **cannot work** and Docker would mark the container unhealthy forever. Cover them with an
  external probe (Alloy scrape / blackbox), not a container healthcheck.
- **Pi keeps only a tiny bounded local log buffer.** The Raspberry Pi primary holds **no durable log store** — Docker uses log driver `local` (`max-size: 10m, max-file: 2`) as RAM/disk resilience when oldsrv/VictoriaLogs is down; the durable, searchable copy lives in VictoriaLogs. Host OS logs run on tmpfs (`journald Storage=volatile` + `/var/log` tmpfs). See [Pi SD-card wear strategy](#pi-sd-card-wear-strategy).
- **HA exporter** on the HA instance (Raspberry Pi 4 primary; cold-standby container on oldsrv — see [`smart-home-failover.md`](smart-home-failover.md)). Only the live instance is scraped (via the VIP); on failover the same URL resumes with no replay.
- **Conventions that are settled:** the Alloy `instance` label is `{{ inventory_hostname }}` per host, so
  series do not collide across hosts; the MikroTik SNMP community is a dedicated **read-only**
  `network-snmp_api` item (fail-loud lookup in `snmp.yml.j2`) behind a Mgmt-VLAN-only INPUT ACL —
  the **device-side** `/snmp enable` + community setting is still an owner deploy step.

---

## Pi SD-card wear strategy

The Raspberry Pi 4 primary runs HA from a **microSD** (`storage.md`), so the dominant continuous SD-wear
source is **HA's recorder DB**, plus rolling Docker/OS logs. Strategy (applies to the Pi; the standby on
oldsrv is on NVMe and mostly unaffected):

1. **HA recorder → trim, NOT disable.** Grafana (central VictoriaMetrics, 365d) replaces HA for *long-term analytics*,
   so raw state history can be short: `recorder: { purge_keep_days: 1–2, commit_interval: 2–5, … }` plus
   `exclude:` for noisy domains you only need in Grafana. Keeping the recorder **enabled** is deliberate — it still
   powers the **Logbook**, the **Energy Dashboard (long-term-statistics tables)** (e.g. KNX appliance-current
   sensors → kWh), **`history_stats` / `history()` templates**, and per-entity short-term UI sparklines, none of
   which Grafana covers. LTS writes are hourly min/max/mean per entity — negligible SD cost. **Do NOT disable** the
   recorder, and do NOT move HA to Postgres (worse microSD wear + failover coupling — see `smart-home.md`).
2. **Docker container logs → stream + bounded local buffer.** Docker log driver `local`, `max-size: 10m, max-file: 2`
   on the Pi (and standby): small RAM/disk buffer survives an oldsrv/VictoriaLogs outage, while **Alloy ships logs → VictoriaLogs
   (90d, VPS NVMe)** and Dozzle streams live — no durable on-Pi log store.
3. **OS logs off the SD.** `journald Storage=volatile` + `/var/log` mounted as tmpfs (fstab) — host OS logs live in
   RAM, lost on reboot (acceptable; VictoriaLogs retains the useful logs). Cheap, well-tested Pi-SD saver.
4. *(Optional)* **Docker *log* directory on tmpfs** to guarantee zero *transient* SD writes — must stay hard-capped
   (`max-size`/`max-file`); **never** tmpfs the Docker data-root (`/var/lib/docker`/overlay2, that holds images &
   containers), only the log portion. Only if the 4 GB RAM budget (shared with HA/Technitium) allows.

> Not addressed via ramdisk: the HA recorder DB and Technitium state stay on the microSD but are
> kept small (trimmed recorder, reduced log verbosity). tmpfs-ing the recorder would throw away state/history on
> every reboot — see the energy/logbook caveats above.

⚠ **A tmpfs carries its own mode, and `mode=` is a MOUNT-TIME option (HD-1103, 2026-10-19).** A tmpfs mounted
without `mode=` arrives `1777 root:root`, and logrotate then refuses **every** stanza with `error: skipping "…"
because parent directory has insecure permissions` — the journal keeps working, so the box looks healthy while
nothing rotates and only `systemctl --failed` says otherwise. The value to converge is what the hosts that mount
`/var/log` from the root fs measure: `755 root:adm`. On a tmpfs there are two owners of that fact, and both are
needed: `mode=0755,uid=0,gid=0` in the fstab options (owned by `roles/home_assistant/tasks/pi.yml`, and therefore
owning every mount made afterwards, including the next boot's), **and** a `file:` leg for the mount that is already
up — measured on a scratch tmpfs, `mount -o remount,mode=0755` returns 0 and leaves the directory `1777`, so a
remount cannot move a tmpfs's mode and an fstab edit alone leaves logrotate skipping files until someone reboots
(a reboot is an owner act, not how this repo fixes a mode). **Verify with the mount, never with the fstab line:**
`findmnt --target /var/log` plus `stat -c '%a %U:%G' /var/log`. `ansible.builtin.mount` rewrites fstab and issues a
bare `mount -o remount <mnt>`, which for tmpfs silently keeps the options the mount already had — a truthful fstab
line is evidence about the NEXT mount, not this one. The acceptance read is `logrotate -d /etc/logrotate.conf`
(read-only): no `error: skipping … bad file mode`/`insecure permissions` line, and note that `logrotate -d` prints
`does not exist -- skipping` for files a host simply lacks, which is not the defect.

⚠ **Rotation moves bytes, it does not remove them, and on a tmpfs the bytes have nowhere else to go.**
`logrotate` renames `/var/log/x` to `/var/log/x.1` on the SAME filesystem, so a `weekly` + `rotate 4`
policy with **no `compress`** on a 100 MB tmpfs cannot hold four periods of a ~75 MB/period `syslog` —
one real rotation of exactly that configuration leaves 77 M of that 100 M in use, which is the
full-`/var/log` failure deferred into RAM rather than avoided. A retention policy for a tmpfs `/var/log`
is therefore a sizing decision against `size=100m` (`compress` + `delaycompress`, or `rotate 1` +
`maxsize`), and it is an owner's: how much log history an SD-card box should carry. The repo ships the
mount and the mode here, not the policy.

---

## Dashboards

> Provisioned via the monitoring role (`files/dashboards/*.json` →
> `/etc/grafana/provisioning/dashboards`, hot-reloaded by the file provider in ~30 s). The metrics datasource
> uid is **`prometheus`** (kept even though the backend is VictoriaMetrics — it is a Prometheus-compatible
> datasource, and renaming it would churn every provisioned panel).
>
> ✅ **SNMP series carry `job="alloy-snmp"` + `instance="<dev>"` only because a relabel says so.**
> Alloy's `prometheus.exporter.snmp` stamps its own component path onto the emitted target and OVERWRITES
> the `job` the scrape target asks for, so the raw series arrive as
> `job="integrations/snmp/<dev>"` + `instance="prometheus.exporter.snmp.<dev>"` and a consumer asking for
> `match[]={job="alloy-snmp"}` sees nothing. The fix is a post-scrape `prometheus.relabel` that re-asserts
> `job="alloy-snmp"` + `instance="<dev>"` (`up` included), in `templates/alloy.river.j2`.
> Live on the backend:
> **`up{job="alloy-snmp",instance="router"}=1` and `up{…,instance="switch"}=1`**, and
> `count by (instance) (ifOperStatus)` = **23 router + 31 switch** (54 series total); `ifAdminStatus`
> carries the same labels.
> ⚠ **An empty SNMP panel is not evidence that SNMP is off** — the data can be arriving under labels no
> consumer queries. Check the labels before believing a `No data` panel.
> The SNMP wiring that has to be correct: `exporter.snmp` needs a valid `forward_to`, every SNMP
> target needs a `name`, and the auth block's `timeout`/`retries` must be valid for the module — an invalid
> one fails the whole Alloy reload, not just that target.

> **The vLLM dashboards — how they are derived, so nobody hand-edits a JSON.**
>
> Three grafana.com exports (25502 / 24756 / 25043) were adapted into this folder. The adaptation is a
> **script, not a hand edit**: [`scripts/ansible/adapt-vllm-dashboards.py`](../scripts/ansible/adapt-vllm-dashboards.py)
> carries every rewrite in `EXPR_REWRITES` / `PANEL_OVERRIDES` / `VAR_OVERRIDES` / `TEXT_TRANSLATE` /
> `STALE_METRICS`; re-download the exports and re-run it to re-derive the same files. It is byte-idempotent,
> **fails loud** on an unapplied rewrite, a surviving stale metric or an unmapped non-English string, and
> English-ises operator-visible strings (the exports shipped Chinese and Korean titles) per the repo language
> rule. Scaffolding (`__inputs`/`__requires`/`id`/`gnetId`) is stripped, `${DS_PROMETHEUS}` becomes the
> literal `prometheus` uid, uids are reissued as `homelab-*`.
>
> **Data path:** the spark-ai compose publishes vLLM's `:8000` **loopback-only** (`spark_metrics_publish`, the
> `127.0.0.1:8082` traefik precedent) → **spark's own Alloy** scrapes `vllm:/metrics`
> (`prometheus.scrape "vllm"`, `instance=spark.kogler.si`) → remote_write to the VPS VictoriaMetrics. vLLM
> serves `/metrics` on the API-server port via `PrometheusStatLogger` (`vllm:*` family, native `model_name`
> label; `instance` comes from the scrape config).
>
> **What upstream dashboards assume that this deployment does not have** — the audit result, which is what
> makes an exported dashboard render "No data" here (each is fixed in the adapter, not in the JSON):
> - metrics **removed in vLLM V1** (`vllm:num_requests_swapped` → `vllm:num_requests_waiting_by_reason`);
> - metrics **renamed in V1** (`vllm:gpu_prefix_cache_{hits,queries}_total` → `vllm:prefix_cache_*`, and the
>   K8s `endpoint="service-port"` label disappears);
> - **Kubernetes production-stack-only** series (`vllm:healthy_pods_total`, `router_{cpu,memory,disk}_usage_percent`,
>   `current_qps`) — no router, no pods here: use `sum(up{job="vllm"})`, a rate over
>   `vllm:request_success_total`, and the **spark host** via Alloy's node exporter for host CPU/mem/disk;
> - metrics **this build does not emit** (e.g. `vllm:kv_block_idle_before_evict_seconds_bucket`) — substitute
>   the signal you wanted (`vllm:num_preemptions_total` rate for KV pressure);
> - **unscoped** process metrics (`process_resident_memory_bytes` exists for every job in the DB, so the panel
>   plots the whole homelab) — always scope `job="vllm"`;
> - **stale upstream template variables** — one export shipped `model_name = /models/DeepSeek-V4-Flash`,
>   which silently No-datas every panel behind it; reset so the live value auto-selects.

| Dashboard | uid | View | Panels back on |
|-----------|-----|------|----------------|
| **Overview** | `homelab-overview` | top-level entry point — down-counts (public/hosts/tunnel/stack), VPS CPU+mem, links to all dashboards | `probe_success{job=blackbox_*}` · `up{job=…}` · `node_*{job="alloy"}` |
| **Host Overview** | `homelab-host-overview` | per-instance node resources: CPU, mem, load, uptime, network + **disk capacity AND disk work** — throughput B/s, IOPS, device busy %, avg wait ms — and **hwmon/thermal-zone temperatures**; multi-host (instance template var) | `node_cpu_seconds_total` · `node_memory_*` · `node_load*` · `node_filesystem_*` · `node_network_*` · `node_boot_time_seconds` · **`node_disk_read_bytes_total`/`written_bytes_total`/`reads_completed_total`/`writes_completed_total`/`io_time_seconds_total`/`read_time_seconds_total`/`write_time_seconds_total`** · ⚙ `node_hwmon_temp_celsius` (+ `_max_celsius`/`_crit_celsius`/`sensor_label`) · `node_thermal_zone_temp` — all `job="alloy"`; ⚙ the hwmon/thermal_zone series need the Alloy `set_collectors` converge, the disk ones are live already |
| **Service Reachability** | `homelab-service-reachability` | blackbox probe tables (HTTP + ICMP) + latency + TLS cert expiry | `probe_success` · `probe_duration_seconds` · `probe_ssl_earliest_cert_expiry` (`job=blackbox_*`) |
| **WAN & Tunnel** | `homelab-wan-tunnel` | wg-s2s liveness, Traefik requests, CrowdSec decisions, stack up | `probe_success{job=wg_icmp}` · `traefik_entrypoint_requests_total` · **`cs_active_decisions`** (NOT `crowdsec_decisions` — real CrowdSec metric, labels `origin`/`action`/`reason`) · `up{job=…}` |
| **Stack Health** | `homelab-selfmonitoring` | observability self-monitoring: up() per component | `up{job=victoria-metrics\|victoria-logs\|n8n\|blackbox-exporter\|crowdsec\|traefik}` (Alloy self-scrapes VM/VL /metrics; topology B) — **no alloy panel on this board**: Alloy ships its own series by remote-write instead of being scraped over the network. That is NOT the same claim as the series not existing — `up{job="alloy"}` carries one series per monitoring host (the `alloy_self` scrape), which is the collector-liveness read in §The Alloy pin |
| **UPS** | `homelab-ups` | (pre-existing) NUT battery/load/voltages + status flags panel + **over-time: Output voltage, Load, Runtime, Battery charge** | `network_ups_tools_*` (DRuggeri/nut_exporter v3) |
| **LLM Inference (vLLM/SGLang)** | `homelab-llm-inference` | unified vLLM+SGLang inference view (grafana.com gnet 25502): request volume, token throughput, latency quantiles, queue/KV-cache, engine/TP-rank | **vLLM half live** (`vllm:*` `{job="vllm"}`, spark). 36 of 74 queries stay empty **by design**: they are the `sglang:*` mirrors — they light up when the SGLang throughput lane lands |
| **vLLM Monitoring V2** | `homelab-vllm-monitoring-v2` | vLLM server monitoring (gnet 24756): scheduler state by reason, KV-cache %, token rates, latency p50/p95/p99, prefix-cache, preemption, engine RSS/GC | **all 29 queries live** — `vllm:num_requests_{running,waiting,waiting_by_reason}` · `vllm:kv_cache_usage_perc` · `vllm:generation_tokens_total` · `vllm:time_to_first_token_seconds_bucket` · `vllm:num_preemptions_total` … (`vllm:num_requests_swapped` is a V0 name → `vllm:num_requests_waiting_by_reason`) |
| **vLLM Dashboard** | `homelab-vllm-dashboard` | vLLM overview (gnet 25043, the production-stack template): engine count, QPS, latency e2e/TTFT/ITL, prefix-cache hit rate + spark host CPU/mem/disk | **all 14 queries live** — `up{job="vllm"}` · `rate(vllm:request_success_total)` · `vllm:e2e_request_latency_seconds_{sum,count}` · `vllm:prefix_cache_*` · `node_*{job="alloy",instance="spark.kogler.si"}` (production-stack `current_qps`/`healthy_pods_total`/`router_*` do not exist here) |
| **★ LLM** *(✅ provisioned, live `version` 3; ⏳ owner sign-off pending)* | `homelab-llm` | **the unified inference dashboard — the merge of the three rows above into one board** (owner: "instead of many dashboards, I want 1"): readiness → spark node (CPU/RAM/GPU + **disk capacity and disk I/O**) → scheduling → engine internals & cache → latency → throughput → request shape → per-engine detail → forward-look. Generated by [`scripts/ansible/build-llm-dashboard.py`](../scripts/ansible/build-llm-dashboard.py); see **§LLM Dashboard** below. The three vLLM boards above stay provisioned until the owner signs off — two of them are the **reference layout** the owner asked to be reproduced. | 53 panels / 9 rows; the only blanks are the `sglang:*` siblings and two stats that read "not deployed" / "probe not wired". Verification is the query replay in **§LLM Dashboard**, not the metric-name inventory. The three `DCGM_FI_PROF_*` panels are **deleted** — they can never load on GB10 — and the six real GB10 signals are wired in their place: utilisation, die temperature, power draw **with the energy-counter rate beside it**, SM clock, PCIe replays, and `DCGM_FI_DEV_XID_ERRORS` as a readiness stat. The 7 whitelisted `job="dcgm"` series are live (`match[]={job="dcgm"}` → exactly 7 names) and are in the build script's `LIVE_DCGM_METRICS` allowlist, so the empty-panel guard proves them (see §LLM Dashboard → GPU) · `vllm:*` + `node_*{job="alloy",instance="spark.kogler.si"}` + `process_*{job=~"vllm\|sglang"}` · every query joined `by (job, instance)` + scoped to `$instance` |

---

### Datasource provisioning — secret-bearing datasources are API-seeded

Both live datasources carry basic-auth secrets, so the monitoring role creates them **over the Grafana
HTTP API, create-only** — never file-provisioned. Grafana 13.x file provisioning stores a
`secureJsonData` blob it cannot resolve at query time, so a file-provisioned credentialed datasource
looks saved in the UI and answers `Authentication to data source failed` on every query.

| uid | type | backend |
|-----|------|---------|
| `prometheus` | `prometheus` | VictoriaMetrics (`victoria-metrics:8428`) — every provisioned panel and alert rule references this uid, so it is a contract, not a label |
| `loki` | `victoriametrics-logs-datasource` | VictoriaLogs (`victoria-logs:9428`) |

`provisioning/datasources/datasources.yml` renders as an **empty anchor** (`datasources: []`): its
emptiness is the design — the directory exists and the file-provisioning path stays available for a
future secret-free datasource.

**Rotation of `victoria-metrics_api` / `victoria-logs_api` = delete the datasource (API or UI), then
converge.** Seeding is create-only and provisioning never rewrites the `secureJsonData` of an existing
uid, so a re-render alone leaves queries 401-ing (§Operational gotchas → Grafana).

---

### LLM Dashboard

> **Role:** design SSOT for the **single** LLM/inference Grafana board (`homelab-llm`,
> `stats.kogler.si`) — the merge of the three vLLM dashboards above plus the spark node
> + readiness panels the owner asked for.
> **✅ provisioned** — the file provider hot-reloads the JSON in ~30 s; live as `version` 3.
> ⛔ **Owner sign-off is pending**, so the three vLLM boards stay provisioned — two of them are the
> **reference layout** the owner asked to be reproduced, and deleting them early would delete the answer.

**The three ways a merged board renders blank.** The owner's required views are "Engine Internal &
Cache" (`vLLM Monitoring V2`) and "Token Throughput (Prefill / Decode)" + "Decode Throughput"
(`LLM Inference (vLLM/SGLang)`); this board reproduces them as rows. Every blank panel on a merged board
comes from one of these classes:

| Class | Mechanism | Measured proof | Now enforced by |
|---|---|---|---|
| **1. A picker behind exact `=`** | `$model_name` carries `includeAll` + `allValue: ".*"`. With All selected Grafana substitutes the literal `.*`, and PromQL `=` is **equality**, so `model_name=".*"` matches nothing. The SAME query renders on a donor board whose picker has no All and always resolves to a concrete value | `count(vllm:num_requests_running{model_name=".*"})` → **0 series**; `{model_name=~".*"}` → **1** (and 39.6 tok/s of real traffic through the regex form). `sum by (engine) (rate(vllm:generation_tokens_total{model_name=".*"}[5m]))` → 0 | `normalize_picker_operators()` rewrites every emitted picker match to `=~`, and `guard_picker_operators()` fails the build if an exact one survives (removing the rewrite turns the build RED — checked) |
| **2. A joined selector carrying a family-only label** | `{__name__=~"vllm:x\|sglang:y"}` applies its label matchers to **both** names. `cache_source="device"` and `stage="decode"` exist only on SGLang, so vLLM — the engine that is actually running — is filtered out by its own panel | "Prefix cache hit rate (both engines)" → **0 series** while `vllm:prefix_cache_hits_total` is live and the picker is resolved; the decode leg of "Inference Stage Breakdown" likewise empty | `guard_joined_selectors()` refuses any two-family alternation carrying a label outside `instance`/`job`. Both panels query per engine (`v2:202` is deliberately vLLM-only, said in its description) |
| **3. Empty-by-design rendered as an outage** | A stat with no series shows `No data`, which is indistinguishable from "the engine is broken" on a board whose first row is readiness | "SGLang engine — ready" and "Engine /health probe" return 0 series *correctly* | both carry `fieldConfig.defaults.noValue` (`not deployed`, `probe not wired`) — an honest empty, generated not hand-painted |

⚠ **The method matters more than the fix.** A metric-name inventory, a byte-identical file
comparison, a datasource health check and the API `version` read all pass while panels are blank, because
**none of them exercises the code path that fails: template-variable interpolation.** The check that does
is cheap and
reproducible: take every `targets[].expr` out of the JSON, substitute the picker's own values
(the All value `.*`, `$__rate_interval` → 5 m, `$__range` → 1 h), POST all ~100 queries at
VictoriaMetrics and count `data.result`. Run that way, the rebuilt board returns series for
every panel **except** the two that now say so in words, and the only remaining empty targets
are the 23 `sglang:*` siblings, which are unverifiable by definition (0 `sglang:` names exist
in the DB). Do not call a dashboard verified until that replay has been run on it.

**What the engine actually exposes** (24 h window). 106 `vllm:*` names
/ 61 families for `job="vllm", instance="spark.kogler.si"`, labels `engine`, `finished_reason`,
`instance`, `job`, `model_name` — so `engine` is a **real label** (`engine="0"`) and the
per-engine panels are honest, while **`tp_rank` does not exist** (SGLang's) and `sglang:*` has
**zero** series. `model_name` is `spark/qwen3.8-flash-next`.

**Layout** (live as `version` 3, 56 panels / 9 rows). The two
groupings the owner named are reproduced rather than re-invented: a row **"Engine internals &
cache"** carries the v2 row's six panels (KV usage, prefix hit rate, scheduler state, Python
GC/memory, finish-reason distribution, throughput-vs-success) plus cached-token stats, and
**"Decode Throughput" / "Prefill Throughput"** sit in **"Throughput & Workload"**
instead of in a row titled for TP-ranks; the `Cache` and `Reliability` groupings are folded into
those rows. The last row is the RX 7600 tier, named below.

**Generation chain (SSOT direction).**`grafana.com exports (25502/24756/25043)` → [`adapt-vllm-dashboards.py`](../scripts/ansible/adapt-vllm-dashboards.py)
→ the three repo JSONs → [`build-llm-dashboard.py`](../scripts/ansible/build-llm-dashboard.py) →
`files/dashboards/homelab-llm.json`. The merged file is a **derived artefact — never
hand-edit it**; a query fix belongs in the adapter (vLLM-side) or in the merge script's
`EXPR_REWRITES` / `NEW_PANELS` (merge-side). `--check` is the CI form (fails on drift);
`--report` prints the full carry/cut map.

**Why the merge is not a concatenation.** The three exports overlap heavily — three TTFT
panels, three KV-cache panels, two E2E latency, two prefix-cache hit rate, three
running/queued. The script's `DROPPED` map carries every cut **with its reason**, and
`guard_layout_consistency()` fails the build if the map and the layout ever disagree.
gnet 25043 is
cut 100 % — every one of its 14 queries is covered by a better-scoped panel elsewhere.

**The join rule (the part that matters for the RX 7600 later).** Every carried query is
rewritten to group `by (job, instance)` and to honour `$instance`, because a `sum()`
across two engines is not a metric. Adding an engine must add a *series*, not a dashboard
— so SGLang lands in these same rows with only a scrape job, and the RX 7600's llama.cpp
legs (oldsrv, Vulkan) have been scraping since 2026-10-19 (`ai_tier_metrics_publish=true`,
HD-1122). They do **not** fill the `vllm:*`/`sglang:*` panels: llama.cpp publishes its own
`llamacpp:*` names — read off the live endpoint, NOT the `llama_*` this file used to claim, so a
`{__name__=~"llama_.*"}` query answers zero series here — and a join there would be a claim about a
metric that does not exist. `guard_instance()` refuses any query that ignores the picker. Joins are
applied **only** where both engines expose the same metric name; where they do not
(vLLM `prompt_tokens_total` vs SGLang `realtime_tokens_total` — different quantities,
the latter carries a `mode` dimension) the two upstream panels are kept side by side
rather than summed into a number that means neither. The board states this in-panel.

**The RX 7600 row is host telemetry, not a fourth engine.** The card's counters
(`homelab_gpu_present`, `_vram_used_bytes`, `_vram_total_bytes`, `_busy_percent`, labelled `gpu=`) are
published by that host's hygiene collector over loopback, because the box ships no `rocm-smi`/`amd_smi`
and this Alloy build cannot use a `textfile` collector — see §Rules for these three rows, rule 6. Three
panels carry them: used-vs-total VRAM (this card DOES expose VRAM, unlike the GB10), busy % and a
present/absent stat whose worst state is **no data**, because a host that emits nothing is invisible to
every rule that asks whether a number is old (§Silent-failure hygiene). What the row does NOT claim is
that the tier is vLLM: it is **llama.cpp over Vulkan**, and since 2026-10-19
(`ai_tier_metrics_publish=true`, HD-1122) its `llamacpp:*` counters ARE in the store — `job="llama-cpp"`,
`leg="embed"`/`leg="reranker"`, both legs `up=1` — joined to nothing on this board, because llama.cpp's
names are not vLLM's names. Reading those counters is a Metrics query, not a panel.
The queries name the host instead of filtering on `$instance` for the same reason the spark node row
does — the pickers enumerate ENGINE instances, and this box runs no engine.

**Readiness = three signals, not one.** `up{job="vllm"}` (scrape leg), `up{job="sglang"}`
(the SGLang lane) and a blackbox `http_2xx` on the engine's own `/health`. They fail
differently: `/metrics` can serve while `/health` is 503 (initialised, not ready), and
`/health` can be 200 while the scrape leg is dead — which is a config problem, not an
inference outage. A readiness panel derived from `up{}` would be a duplicate of the first
panel and would hide exactly that. ⏳ The `/health` probe is **authored empty**: the
target is spark loopback, and the VPS blackbox-exporter has no path to `127.0.0.1:8000`
on spark — wiring it needs a blackbox exporter reachable from spark's Alloy (a
sidecar on spark, or scrape the probe from spark's Alloy the way the `vllm` job is
scraped). Not built; specified here so the panel is not mistaken for a bug.

**GPU on a GB10 — what is and is NOT obtainable.**
```
spark# nvidia-smi -q -d MEMORY   → FB/BAR1 Total/Used/Free: N/A
spark# nvidia-smi dmon -s um     → fb / bar1 columns: '-'
spark# dpkg -l | grep dcgm       → (none)      dcgmi: not found
spark# docker images | grep dcgm → nvidia/dcgm-exporter:3.3.5-3.4.1-ubuntu22.04  (on disk)
```
**NVIDIA has confirmed the memory reading is by design, not a gap:** `nvidia-smi` reports
"Not Supported" for memory because "the DGX Spark has a unified memory architecture" and
reports memory utilisation only when there is dedicated VRAM — for memory usage they point
to `top`/`htop`/`free` or the DGX Dashboard. So the honest GPU picture is unified-pool RAM
(where the allocation actually is), engine RSS (the process's share of it, vs the 105 GiB engine
cage) and the engine's own per-GPU work estimates
(`vllm:estimated_flops_per_gpu_total`, `estimated_read_bytes_per_gpu_total` — live today,
plotted in "GPU work — engine reported").

**What DCGM actually delivers here** (measured by running the on-disk image):
The exporter starts and initialises, then refuses the profiling module outright:
`Not collecting DCP metrics: This request is serviced by a module of DCGM that is not
currently loaded`; forcing `dcp-metrics-included.csv` yields
`Skipping line 21..25 ('DCGM_FI_PROF_GR_ENGINE_ACTIVE' / 'PIPE_TENSOR_ACTIVE' /
'DRAM_ACTIVE' / 'PCIE_TX_BYTES' / 'PCIE_RX_BYTES'): metric not enabled` — NVIDIA has
stated there are **no plans to support DCGM profiling on Spark** (not a datacenter device).
13 series emit, with live values (`modelName="NVIDIA GB10"`,
`DCGM_FI_DRIVER_VERSION="580.178.04"`):

| Emits (live value) | Worth wiring? |
|---|---|
| `DCGM_FI_DEV_GPU_UTIL` (88–90 % under load) | **yes** — the only true GPU-busy signal; nothing else carries it |
| `DCGM_FI_DEV_GPU_TEMP` (50–58 °C) | **yes** — no nvidia hwmon chip, so `node_hwmon_*` does NOT include the GPU die |
| `DCGM_FI_DEV_POWER_USAGE` (12.3–38.9 W) | **yes** — GPU-rail power, absent from every other source |
| `DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION` (458 MJ, counter) | yes — accurate averaging (instantaneous power oscillates) |
| `DCGM_FI_DEV_SM_CLOCK` (2509 MHz) | yes — throttle/idle visibility |
| `DCGM_FI_DEV_XID_ERRORS`, `PCIE_REPLAY_COUNTER` | yes as silent-zero tripwires |
| `MEM_COPY_UTIL` (0), `MEMORY_TEMP` (**0 = bogus**), `ENC_UTIL`/`DEC_UTIL` (0), `NVLINK_BANDWIDTH_TOTAL` (0), `VGPU_LICENSE_STATUS` (0) | **no** — constant or wrong on GB10; do not chart |
| `FB_USED`/`FB_FREE`/`FB_RESERVED`, `MEM_CLOCK`, all `DCGM_FI_PROF_*` | **impossible** — not emitted |

**Corollary — the three `DCGM_FI_PROF_*` panels are DELETED, not
wired.** Wiring DCGM cannot fill them (NVIDIA statement + exporter log + live probe). The `DCGM_FI_DEV_*`
row above is what to wire instead: `nvidia/dcgm-exporter` loopback-published on `:9400` +
a `prometheus.scrape "dcgm"` block in `alloy.river.j2` under
`{% if inventory_hostname == 'spark.kogler.si' %}`, `job="dcgm"` +
`instance="spark.kogler.si"` set by relabel (the container's own `Hostname` label is the
container id, not the host — never legend on it).

**The DGX Dashboard (`db-spark.kogler.si`, `dgx-dashboard.service` on spark) is not a
data source.** `POST /api/login` → JWT, then `GET /api/v1/gpu_telemetry/stream` (SSE, one
record/s): `{percentage_utilization, memory_available_in_kib, memory_total_in_kib,
temperature_in_c, power_draw_in_w, gpu_memory_in_use_in_mb, cpu_memory_in_use_in_mb,
power_limit_in_w}`. `memory_total_in_kib` = 127532360 KiB = **the whole 121.6 GiB host
pool** — its "GPU Memory" tile is system RAM under a GPU label, and
`gpu_memory_in_use_in_mb` / `power_limit_in_w` are hard `0`. Its three real fields are the
same util/temp/power DCGM gives, it has no `/metrics` endpoint and no history, so it
informs nothing here beyond corroborating the unified-memory finding. (Its temps, 57–62 °C,
sit between DCGM's 50–58 °C and the acpitz zones' 65–73 °C — three different sensors; never
plot them as one series.)

**DCGM is wired — the signals that are real on GB10.**

| Layer | What ships |
|---|---|
| Compose service | **`spark-dcgm`** (`templates/docker_services/spark-dcgm/`) — `dcgm-exporter` on **loopback only** `127.0.0.1:9400`, the same publish discipline as `spark_metrics_publish`: no Traefik route, no Home VLAN, no auth on `/metrics`. `cap_drop ALL` + `cap_add SYS_ADMIN`, `read_only`, `pid: host`, GPU device reservation, **`mem_limit: 256m`** (≈1.8× the measured peak, so a read-only observer can never eat into the engine memory cage). Registered in `group_vars/spark.yml` (`enabled: true`). |
| Image pin | `spark_dcgm_exporter_image` in `group_vars/all/versions.yml` — **digest**-pinned (`nvidia/dcgm-exporter:3.3.5-3.4.1-ubuntu22.04@sha256:ec962b…f8870`, arm64 manifest, digest taken from spark's own image store where it was run live). Port comes from `spark_dcgm_exporter_port` (9400) — declared in group_vars, **not** `\| default()`'d: §1 fail-loud, and `validate-docker-services.py`'s mock `default` would silently render an empty port. |
| Scrape | `prometheus.scrape "dcgm"` + `prometheus.relabel "dcgm"` in `alloy.river.j2`, spark-gated, `job="dcgm"` + `instance="spark.kogler.si"` (the exporter's own `Hostname` label is the **container id** → `labeldrop`, it churns on every recreate). |
| **Metric policy** | Lives in the Alloy relabel as a **whitelist**, not in a counter CSV inside the image: `keep DCGM_FI_DEV_(GPU_UTIL\|GPU_TEMP\|POWER_USAGE\|TOTAL_ENERGY_CONSUMPTION\|SM_CLOCK\|XID_ERRORS\|PCIE_REPLAY_COUNTER)`. Dropped on evidence: `MEMORY_TEMP` (bogus **0** while the NVMe beside it reads 46 °C), `MEM_COPY_UTIL`/`ENC_UTIL`/`DEC_UTIL` (always 0), `NVLINK_BANDWIDTH_TOTAL` (no NVLink), `VGPU_LICENSE_STATUS` (no vGPU). |

⚠ **Do not add to that whitelist:** the DCP/profiling family (`GR_ENGINE_ACTIVE`, `SM_ACTIVE`,
`PIPE_TENSOR_ACTIVE`, `DRAM_ACTIVE`, `PCIE_TX/RX_BYTES`) and `FB_*`. They are not a scrape gap —
the exporter refuses them (`metric not enabled`) and NVIDIA states profiling will not be supported
on Spark. A new driver making them appear should be an explicit, reviewed IaC edit, not a silent
cardinality change.

**Live in the backend:** `VM {job="dcgm"}` returns **exactly the 7 whitelisted
series** (`GPU_UTIL`, `GPU_TEMP` 46 °C, `POWER_USAGE` 10.25 W, `TOTAL_ENERGY_CONSUMPTION`,
`SM_CLOCK` 2411 MHz, `XID_ERRORS`, `PCIE_REPLAY_COUNTER`), and the host temperatures are there too
(`node_hwmon_temp_celsius` per instance: spark 12, oldsrv 17, nas 9, pi 2 sensors).

**⚠ Operational gotcha:** a service's own
deploy tasks carry `tags: "{{ svc.name }}"` (`docker_services/tasks/deploy-service.yml`), so
`--tags monitoring,docker_services` on a **NEW** service renders the loop but **skips every inner
task** — `rc=0` while deploying nothing. **A first deploy needs the
service's own tag**: `--tags monitoring,docker_services,spark-dcgm`. rc=0 is not proof of deploy;
proof is `docker ps` + `VM {job="dcgm"}`.

**Memory (answering "can we trim the exporter's RAM via the counters CSV?") — measured, A/B on
the box.** Image default `default-counters.csv` (18 fields) = **143.2 MiB anon**; a 7-field CSV
via `DCGM_EXPORTER_COLLECTORS` = **138.8 MiB anon** (≈ **−3 %**); the same trimmed run with
`GOMEMLIMIT=64MiB GOGC=20` = 145 MiB (no effect). Conclusions:
  * The **profiling fields are not the cost here** — on GB10 the DCP module never loads
    (`Not collecting DCP metrics…`, so `dcp-metrics-included.csv` is not even read: the exporter
    logs `Falling back to metric file '/etc/dcgm-exporter/default-counters.csv'`), so there is no
    profiling buffer to reclaim. On a datacenter GPU with DCP enabled the CSV *is* a real lever;
    on Spark it is worth ~4 MiB.
  * The floor is **DCGM/NVML's device context**, not the Go heap — which is why the Go env knobs
    do nothing. `docker stats` readings drift 130–155 MiB with page cache; `memory.stat` `anon`
    is the number to trust.
  * So the lever that actually matters on this box is a **hard cap**, not trimming: the compose
    sets `mem_limit: 256m` (~1.8× the measured peak, so the cap can never OOM it in normal
    operation) — an unbounded leak in a sidecar must not be able to eat into the 105 GiB engine
    cage on a host that has already OOM-killed. Revisit the CSV only if a future
    driver starts emitting profiling fields.

**spark RAM reading — read the floor, not the ceiling.** On this box the useful signal is
`node_memory_MemAvailable_bytes` (live: 9.5 GiB of 121.6 GiB with the engine loaded),
not utilisation %: every global OOM in `spark-incidents.md` came from replace-by-percent
GPU-reserve arithmetic against this pool. The RAM panel and the host-memory alert rules read the **same**
gauge — `usable = MemAvailable − CmaFree`, warn **< 12 GiB**, crit **< 8 GiB** — never raw
`MemAvailable` and never utilisation %, both of which hide the reserve on this box.

**Known limits, recorded rather than hidden.**
- Every `sglang:*` sibling comes from SGLang's documented metric names + the gnet 25502
  author's pairing — **never from a live scrape** (no SGLang engine has run here). Expect
  the same class of metric-name corrections seen on the donor boards; the fix goes in this script, not in the JSON.
- SGLang has no prefix-cache *queries* counter, so the SGLang hit-rate leg divides by
  total prompt tokens → an **upper bound**, flagged in the panel tooltip.
- SGLang has no `finished_reason` label, so "Success rate" and "Preemptions" are vLLM-only
  by necessity (SGLang's equivalent event is its eviction counters, already plotted by the
  carried gnet 25502 panel — deliberately not summed in).

**Retiring the three old boards (owner step, after sign-off).** Delete
`llm-inference-sglang-vllm.json`, `vllm-master-v2.json`, `vllm-dashboard.json` from
`files/dashboards/` and re-converge `--tags monitoring` — the file provider follows the
directory. Until then all four are provisioned; the `homelab-llm` board is the one to
open.

---

## LLM token accounting — the three instruments

> **Role:** what the fleet can actually prove about LLM usage, and where the blind spots are — so nobody
> reports a per-client token number that no instrument produced.
> **Linked from:** §LLM Dashboard · [services-ai.md](services-ai.md) §9 decision #26

Three instruments touch LLM traffic. **One reports fully; the second reports only its GPU half; the third
is dark for a reason that is now measured rather than assumed.**

| Instrument | Where it sits | In VM? | What it can prove |
|---|---|---|---|
| **Engine counters** `vllm:*` | spark's own `/metrics` on the API port, scraped by `vllm` + `vllm_hot` (`IaC/ansible/roles/monitoring/templates/alloy.river.j2:557`, `:586`) | ✅ live | **tokens** — prompt / generation / cached / by-source, for **every caller**, because the counter is on the engine and does not care who sent the request. Labels: `model_name` + `instance` + `job` — no client, key or user dimension exists. |
| **LiteLLM gateways** (`litellm` on the VPS, `lan-litellm` on oldsrv) | the proxy's own process — and in this pin, from a **separate metrics process/port** | ❌ nothing, and now for a measured reason | per-key / per-user spend and `rpm` — the attribution the fleet could get for *free*. Those numbers live only in each gateway's Postgres + Admin UI. See **Why the LiteLLM surface is dark** below: the endpoint is not mounted in the running process, so there is deliberately **no `job="litellm"`** anywhere. |
| **oldsrv serving tier** (`embed`, `reranker`, `whisper` on the RX 7600) | llama.cpp / whisper.cpp containers + the host's `amdgpu` sysfs | ✅ **both halves live** | The card reports `homelab_gpu_vram_used_bytes` / `_vram_total_bytes` / `_busy_percent` (`gpu="rx7600"`), published by the host hygiene collector. The request/token counters came live on 2026-10-19 when `ai_tier_metrics_publish` went `true` (HD-1122): `llama-server --metrics` runs on both GGUF legs and the `llamacpp:*` family (`prompt_tokens_total`, `prompt_tokens_cached_total`, `tokens_predicted_total`, `*_seconds_total`) lands under `job="llama-cpp"` with a `leg="embed"`/`leg="reranker"` label. They join no `vllm:*`/`sglang:*` panel — different names, so read them by job. whisper.cpp (STT) still has no metrics surface. |

The honest sentence this section exists to force: **totals are known, attribution is not.**
`sum(increase(vllm:generation_tokens_total[1d]))` is a measurement; "this machine / this harness used N
tokens" is available nowhere today, and an average-tokens-per-request × request-count product is an
estimate, not a series.

**The ruling: metering is observed at the edge, not bought with a proxy hop.** Routing
the coding harnesses through LiteLLM for accounting is declined — decision #26 puts a
generation harness **direct** on the engine name edge precisely so there is no extra hop, and a metering
proxy re-buys the hop, the key management and the failure surface that decision removed. The engine stays
the token SSOT (it needs no change); attribution comes from the edge access log. Wanting per-key
spend *as measurement* later means re-opening #26 — that is an owner call, never an implementation detail.
The rejection itself is logged in [observability-rejected.md](observability-rejected.md).

### Why the LiteLLM surface is dark — measured on both gateways, same pin

The probe was the first step, and it does **not** end in "no Prometheus surface": the endpoint exists in
`docker.litellm.ai/berriai/litellm:v1.104.0` but is **not mounted in the running process**. Measured on
`lan-litellm` (oldsrv, `:4000`) and on `litellm` (VPS, container `:4000`):

| Read | Answer |
|---|---|
| `GET /metrics` unauthenticated | `401` — "…To allow unauthenticated access, set `litellm_settings.require_auth_for_metrics_endpoint: false`" |
| `GET /metrics` **with a valid admin bearer** | `404 {"detail":"Not Found"}` — the route is not there |
| rendered `config.yaml` on both | no `callbacks:` key at all (only `litellm_settings: drop_params` + `general_settings`) |

The reason is in the pin's own source: `PrometheusLogger._mount_metrics_endpoint()` — the call that does
`app.mount("/metrics", …)` — is invoked from the **callback loader**, only when `"prometheus"` is one of
the configured callbacks. No callback is configured, so nothing mounts, and the auth middleware 401s on a
route that would 404 anyway. `litellm/proxy/prometheus_metrics_server.py` additionally documents that a
worker-separated deployment serves `/metrics` from **its own process** via the CLI flag
`--prometheus_metrics_port` (which must differ from `--port` and auto-creates `PROMETHEUS_MULTIPROC_DIR`).

So enabling the surface is a **gateway change**, not a monitoring one, and until it lands a scrape job
here would scrape nothing — which is why there is no `job="litellm"` in
[`alloy.river.j2`](../IaC/ansible/roles/monitoring/templates/alloy.river.j2). Two independent halves must
land, in this order:

1. **Mount it** (both gateways): add the `prometheus` callback to the rendered `config.yaml` — and name
   the auth story with it, because the endpoint answers `401` to a scraper by default. Either keep auth
   and give Alloy a bearer (`bearer_token_file`, the `/etc/prometheus/ha_token` precedent in
   `roles/monitoring/tasks/main.yml`), or set `require_auth_for_metrics_endpoint: false` and accept that
   per-key spend becomes readable by anything that can reach the port. ⚠ `lan-litellm` publishes
   `oldsrv_home_ip:4000` — a LAN bind, so the unauthenticated form is a LAN-wide read of the spend ledger.
2. **Reach it** (VPS only): the VPS `litellm` publishes **no host port at all**, and `discovery.docker`
   finds 0 targets for a container with no port mapping, so the VPS instance additionally needs a
   loopback publish of the metrics port (the `spark_metrics_publish` shape) before any job can address it
   — an ephemeral `172.22.x.x` target is the dangling-static-IP failure class, not a fix.

When both land, one `prometheus.scrape` per instance with an **explicit `job` and `instance`** (the two
instances must never merge) at the **60 s cold** cadence, and a keep-list built from the names quoted by
the live render at that moment — never from this document.

### The trap that makes per-client accounting silently wrong: which address is the client?

`llm.kogler.si` is served on two paths and they do not present the same peer to the spark edge:

```
Home-VLAN client ─────────────────────────────▶ spark :443 (traefik-spark) ─▶ engine
Tailnet client ─▶ traefik-tailnet (VPS) ─▶ WG S2S ─▶ spark_home_ip:443 ─▶ engine
```

(`IaC/ansible/templates/docker_services/traefik-tailnet/dynamic/routes.yml.j2:563` proxies to `https://{{ spark_home_ip }}:443`.) So unless
`X-Forwarded-For` is preserved **and** trusted at the spark edge, every tailnet request is logged there
with the tunnel hop as its client and the per-client table collapses into one healthy-looking row. Same
class as HA's exact-match `ha_trusted_proxies` rule ([network-vpn.md](network-vpn.md) §Reaching LAN nodes
when away): a header the upstream edge adds is worthless if the reader does not trust the sender. **Read
the peer address off one live request on each path before choosing the shape**, then name the choice —
per-client where the path allows it, per-plane (Home vs tailnet) where it does not.

### Rules for these three rows

1. **Tokens are not in the access log.** Traefik logs the request (`ClientHost`, `RouterName`,
   `ServiceName`, `DownstreamStatus`, `RequestSizeBytes`), never the completion — so a per-client token
   figure is derived and must be labelled as derived. Never graph it as a counter.
2. **Per-client comes from logs, not metrics.** The Traefik series (`traefik_entrypoint_requests_total`,
   the v3 name — see the metric-name list above) carry no source-IP label; that cardinality is unbounded
   by design.
3. **The log plumbing already exists.** `loki.source.file "container_logs"` (`IaC/ansible/roles/monitoring/templates/alloy.river.j2:183`) ships
   every container's JSON log to VictoriaLogs, so `--accesslog=true` on the edge is the whole change.
   The host-file bind for Traefik exists because **fail2ban cannot read the Docker JSON log** — copying it here
   adds a host bind for nothing. `traefik-spark` carries neither `--accesslog.*` nor
   `--metrics.prometheus=true` today (`IaC/ansible/templates/docker_services/spark-dashboard/docker-compose.yml.j2:47`).
4. **Probe the pin before writing a scrape job** — and report what the probe answered, even when the
   answer is "not tonight". Both halves are now read rather than guessed:
   * **LiteLLM** (`docker.litellm.ai/berriai/litellm:v1.104.0`, API port 4000 per
     `IaC/ansible/templates/docker_services/traefik-tailnet/dynamic/routes.yml.j2:570`): the endpoint is
     **not mounted** — `401` unauthenticated, `404` with a valid admin bearer, on both gateways. The
     enable shape is in **Why the LiteLLM surface is dark** above. No scrape job until it lands.
   * **llama.cpp** (`llama_cpp_vulkan_image`): `--metrics` **exists** — read read-only off the running
     containers, `docker exec {embed,reranker} /app/llama-server --help` →
     `--metrics  enable prometheus compatible metrics endpoint (default: disabled)`
     (`LLAMA_ARG_ENDPOINT_METRICS`). It serves on the leg's own `--host`/`--port`; there is no separate
     metrics port, which is why the flag and a loopback publish are one gated change.
   Quote names from a live render; the metric-name list above is the graveyard of guesses.
5. **New jobs land at 60 s cold**, hot only by named family (§What resolution costs: ≈0.33 B/sample,
   ≈51 MB/day for all of spark today). A gateway job is tens of series — it does not start in the hot set.
6. **GPU numbers on oldsrv come from sysfs, not `rocm-smi`** — the host ships neither `rocm-smi` nor
   `amd_smi` ([services-ai-bench.md](services-ai-bench.md) read VRAM from the `amdgpu` sysfs counter for
   that reason). The publish path IS shipped: the hygiene collector's **direct-publish** leg
   (§Silent-failure hygiene) reads `mem_info_vram_used` / `mem_info_vram_total` / `gpu_busy_percent` and
   publishes `homelab_gpu_*{gpu="rx7600"}` on the loopback exporter — ⛔ not a `textfile` directory
   (unusable on this Alloy build) and not a new daemon. Declare the device by **render node**
   (`/sys/class/drm/{{ gpu_vulkan_render_node | basename }}/device` in `host_vars/oldsrv.kogler.si.yml`),
   never by `cardN`: the index is probe order and renames. All four names are on the LLM board
   (§LLM Dashboard — the RX 7600 row), generated by the board's generator, not hand-placed, and they
   are host telemetry: they join none of the engine panels.
7. **The RX 7600 is the only host that can show VRAM** — GB10 exposes none (§LLM Dashboard → GPU). The
   board says so itself, and its engine-count readiness panel is `count(up{job=~"vllm|sglang|llama-cpp"})`.
   It read **1** while only spark scraped; since the 2026-10-19 flip it reads **3** — spark vLLM plus the
   two llama.cpp legs, each one `up` target. The panel's own text says this now
   — it is generated by `scripts/ansible/build-llm-dashboard.py`, so the text is fixed in the generator.

### The per-day token report

[`scripts/bench/spark/vm-tokens.sh`](../scripts/bench/spark/vm-tokens.sh) answers "how many tokens did
spark produce, per day", and with `--price input,output,cached` what that same traffic would cost at
external per-token prices. It reads the engine counters named above, so everything this section says
about attribution applies to its output: **totals, never a per-client number** — and a $ column is
arithmetic on a measurement, not a series.

**The identities that make the price lines legal** (read off the live series, not assumed):

```text
vllm:prompt_tokens_total        == vllm:prefix_cache_queries_total == sum(vllm:prompt_tokens_by_source_total)
vllm:prompt_tokens_cached_total == vllm:prefix_cache_hits_total            ⊂ prompt_tokens_total
```

so `uncached input = prompt − cached` and the input / cached / output price lines never double-count.
The request-level histograms (`vllm:request_{prompt,generation}_tokens_sum`) are the cross-check: they
agree with the counters to under 1 %, the residue being requests still in flight at a window edge.

**A row is a calendar day, not a rolling 24 h** — `increase(…[1d])` evaluated at local midnight. Ask
series presence as `count(max_over_time(<metric>[1d]))`: a boundary-instant `count()` answers nothing
when the engine happened to be down at the evaluation instant, and the day that served traffic then
drops out of the period total while the table still looks complete and green. A day with no series is
excluded and said so, never zero-filled — zero-filling understates the whole window and moves the
average.

**Reaching the endpoint.** The store is IaC `victoria_backend_host` + `victoria_metrics_port`, resolved
from `group_vars/all/main.yml` when the script runs rather than typed into it, and it answers only over
wg-s2s — so from a laptop the query executes on a hop host over ssh, with the credential piped through
stdin into a `0600` curl config that is unlinked on the far side (lengths printed, never the value).
`--dry-run` prints the PromQL and touches nothing; `--self-test` proves the day bucketing, the uncached
split and the price arithmetic offline against a hand-valued fixture.

---

## Scrape cadence and metric resolution

Every job scrapes at Alloy's default **60 s** except spark's three named hot jobs — on spark the rendered
`/etc/alloy/config.alloy` carries `scrape_interval = "5s"` exactly three times (`host_metrics_hot`,
`vllm_hot`, `dcgm` in `roles/monitoring/templates/alloy.river.j2`); the three latency histogram families
ride `vllm_hot`. Everywhere else the 60 s default stands, so
fine history exists nowhere else downstream, and no Grafana setting invents it.
This is the other half of the OOM blind spot above, and the reason the spark GPU/engine panels read as a step
chart next to the DGX System Monitor, which samples **1 Hz**.

### Where the cadence is actually capped

| Source | New data exists at | Measured |
|---|---|---|
| `node_*` (Alloy host job) | kernel counters, 100 Hz jiffies | sub-second |
| `vllm:*` on `:8000/metrics` | **≈ 1 Hz under load** | `vllm:generation_tokens_total` advanced on **every one** of 17 consecutive 1 s scrapes taken during a live request (178,079 → 178,249). `VLLM_LOG_STATS_INTERVAL: "10"` is the engine's **log** heartbeat, not a publication cap — log-only lines (`running/waiting/… req/s`, `p: … reqs`) are capped at 10 s, cumulative counters are not ⇒ **no engine restart is needed** for one-second engine data |
| `DCGM_FI_DEV_*` on `:9400/metrics` | **once per `DCGM_EXPORTER_INTERVAL`** (5 s today) | `DCGM_EXPORTER_INTERVAL: "5000"` in `templates/docker_services/spark-dcgm/docker-compose.yml.j2`; `DCGM_FI_DEV_GPU_UTIL` holds one value across twelve consecutive 1 Hz reads. Scraping faster than the exporter's own interval stores copies of one sample |
| DGX System Monitor (the 1 s picture) | 1 Hz | authenticated `POST /api/login` (the JSON field is `token`) then `GET /api/v1/gpu_telemetry/stream` yields `percentage_utilization`, `memory_available_in_kib` / `memory_total_in_kib` (25,676,736 / 127,533,336 KiB = 19.7 % of the **host** pool — not a VRAM counter, see §LLM Dashboard → GPU), `temperature_in_c`, `power_draw_in_w`. It polls the **same** `spark-dcgm` exporter: the difference is cadence, plus a host-memory stat Alloy already scrapes directly |

### What resolution costs (measured on the VPS VictoriaMetrics — re-measure before quoting these numbers; the pin is `victoria_metrics_version: v1.153.0`)

| Quantity | Value |
|---|---|
| Live write rate · active series · data dir | 227.8 rows/s · 2,756 series · **92 MB** — disk is not the constraint (`/` has 418 GB free) |
| Storage per sample | ≈ **0.33 B** (92 MB ÷ ≈ 286 M samples over 30 d) |
| spark → VPS wire | ≈ 590 B/s ≈ **51 MB/day**; 1,774 samples per scrape — host 669 (**160 of them `node_cpu_seconds_total`**), engine 476 (**309 request-completion-driven `_bucket{}`**), dcgm 18 → **7 kept** after relabel |
| Engine render | 4.8–6.1 ms per scrape (64 kB, 471 lines) → at 5 s = **0.10 % of one of 20 cores** |
| **50 hot series @ 5 s** | **+9.2 rows/s · ≈ +95 MB/yr · ≈ +2 MB/day wire** |
| every spark series (1,745) @ 5 s | +125 rows/s · ≈ +3.4 GB, and it **plateaus** at the 365 d retention |
| 50 hot series @ 1 s | +49 rows/s · ≈ +0.5 GB/yr |

**Age-tiering is not available in this stack.** `-downsampling.period` and `-retentionFilter` are both **absent
from the VictoriaMetrics community binary** (absent from `--help` on the deployed build — the pin is
`victoria_metrics_version: v1.153.0` in `group_vars/all/versions.yml`, so re-run `--help` before trusting
the absence; the docs state
community supports a single retention and one storage tier), and OpenObserve's downsampling is an enterprise rule
set as well. Resolution is therefore bought **at write time** — scrape only what needs it faster — not by
collapsing old buckets afterwards. Memory, not disk, is the VPS ceiling (4.3 GiB available, no swap) and it tracks
*active series*, which cadence does not change.

### The hot set — 50 series, which is the whole fine-resolution ask

Owner scope: fine data for these panels only, **everything else stays at 60 s** — the one exception is the
three latency histogram families below.
50 of spark's ~1,893 series — the 9 panels do not need 1,745 series, and the 365-day cost of blanket 5 s is what
the exclusions avoid:

| Panel | Series kept at fine cadence |
|---|---|
| spark memory (the OOM gauge + the Monitor's memory bar) | `node_memory_MemAvailable_bytes`, `node_memory_CmaFree_bytes`, `MemTotal`, `MemFree`, `Buffers`, `Cached`, `SwapCached`, `Shmem` |
| GPU utilization · temperature · power · SM clock · energy · XID · PCIe replays | all 7 whitelisted `DCGM_FI_DEV_*` — a scrape without them is empty, so they must ride the hot job |
| CPU utilization | `node_cpu_seconds_total{mode="idle"}` **only** — 20 series, not the 160 the panel's formula never reads |
| Token throughput · decode throughput | `vllm:generation_tokens_total`, `vllm:kv_cache_usage_perc`, `vllm:num_requests_running` |
| Prompt / generation token stats | `vllm:prompt_tokens_total`, `vllm:prompt_tokens_by_source_total{source=…}` ×3 |
| Prefix Cache Hit Rate | `vllm:prefix_cache_hits_total`, `vllm:prefix_cache_queries_total` |
| Cached Token Stats | `vllm:prompt_tokens_cached_total` (plotted as a raw counter today — see 4 below) |
| Scheduler / preemption | `vllm:num_requests_waiting`, `vllm:num_requests_waiting_by_reason{reason=…}` ×2, `vllm:num_preemptions_total` |
| load (the Monitor's other two numbers) | `node_load1`, `node_load5` |

**Three latency histogram families join the hot set.** This is the
one thing the owner scope above excludes ("everything else (latency, histograms) stays
at 60 s"), and the reason is that the scope was drawn for *panels*: the bench funnel measures
per-arm TTFT / ITL / TPOT, and a 20 s decode leg moves each `_bucket{}` line at most once, so a
window rate has no second point to differentiate.
`rate(vllm:time_to_first_token_seconds_bucket[1m])` evaluated over a real window returns **EMPTY**
for TTFT p50/p95 while every 5 s counter resolves; with the padded leg window it returns
`p50 4.58 s / p95 29.0 s`, and TPOT p50 `0.0375 s` agrees with `rate(vllm:generation_tokens_total[1m])`
= 26.3 tok/s from the other side — two independent paths, one number, which is the point of having
both.

Cost, **DERIVED** from the measured cost table (not measured again): the three `_bucket` families
are 63 series on this engine (read off `/metrics`: TTFT 23 + ITL 20 + TPOT 20), so 60 s → 5 s is
12× sampling on 63 series ≈ **+11.6 rows/s ≈ +120 MB/yr ≈ +2.5 MB/day wire** — the small side of
the same curve the table already prices (50 series ≈ +95 MB/yr), and nowhere near the blanket
1,745-series case that plateaus at retention. `_sum`/`_count` of those families stay at 60 s.
Revert = delete the three names from `hot_vllm` in `roles/monitoring/templates/alloy.river.j2`;
both jobs emit the one string, so hot/cold stay disjoint and no query or alert changes.

**Implementation shape:**

1. **Split spark's scrapes into hot + cold jobs** in `roles/monitoring/templates/alloy.river.j2`, gated on the
   inventory host so only spark pays: `scrape_interval = "5s"` + `scrape_timeout = "3s"` on the hot jobs, and
   **disjoint metric sets** — `prometheus.relabel` `keep` in the hot job, the same `match_re` with
   `action = "drop"` in the cold job. Overlapping sets yield duplicate series at two cadences, which forces
   `-dedup.minScrapeInterval=5s` on the VPS: a shared-flag change that silently re-tunes dedup for every other
   host. Disjoint jobs also mean **no dashboard query changes** — the series names are identical.
2. **`DCGM_EXPORTER_INTERVAL: "30000"` → `"5000"`** in
   `templates/docker_services/spark-dcgm/docker-compose.yml.j2`, otherwise 5 s scraping records six copies of one
   GPU sample. Sidecar restart only — never the engine. ⛔ Pre-flight first: that sidecar carries
   `mem_limit: 256M` + `workers: 1` — A/B its CPU and `memory.stat`
   anon against that cap at 5 s before converging.
3. **Fix the Grafana interval floor.** The Prometheus datasource carries **no `jsonData.timeInterval`**, so
   `$__interval` / `$__rate_interval` are floored at Grafana's default **15 s**, not 5 s. Set
   `jsonData: {timeInterval: "5s"}` on the `prometheus` datasource uid. ⚠ the provisioning seed in
   `roles/monitoring/tasks/main.yml` only fires `when: … status == 404`, so it needs an API PUT on the existing
   datasource (or delete-and-re-seed) — editing the seed alone does nothing.
4. **Panel representation** — "the same as the picture" is half cadence, half representation. "Prefix Cache Hit
   Rate" is a **gauge with a hard-coded `[5m]`** window: no 5 s data shows a spike through a 5-minute window, so
   it becomes a time series over `[1m]`/`$__rate_interval`. "Cached Token Stats" plots the raw counter with no
   `rate()`.
5. **Alert rules are not a driver here.** Every alert group evaluates at `interval: 1m` with `for: 1m`/`2m`, so
   5 s data changes what a rule *sees*, not how often it runs; raising the alert interval is a separate,
   deliberate decision (it multiplies ruler load and shortens `for:` windows into noise).

**State: LIVE** — the VPS half (datasource `timeInterval` floor + the `rate()` fix) **and** the spark half (hot/cold Alloy jobs + `DCGM_EXPORTER_INTERVAL: "5000"`) are converged.

- **VPS:** the datasource read-back is `jsonData {"timeInterval": "5s"}` with `basicAuthPassword`
  still set (the PUT re-sends the vault secret because PUT replaces the record), health OK, and the
  provisioning task reports `skipping` — the floor is not a changed-on-every-run task.
- **spark cadence read:** `count_over_time(node_load1{instance=~"spark.*"}[1m])` = **12**,
  `count_over_time(vllm:generation_tokens_total[…][1m])` = **12**,
  `count_over_time(DCGM_FI_DEV_GPU_UTIL[…][1m])` = **12**, while cold-only names
  (`node_cpu_seconds_total{mode="user"}`, `vllm:e2e_request_latency_seconds_bucket`) read **1/1m**
  — the hot `keep` / cold `drop` are disjoint and matching, so no `-dedup` change is owed.
- **Sidecar cap:** `dcgm-exporter-spark` at
  `DCGM_EXPORTER_INTERVAL=5000` sits at cgroup `memory.stat` **anon 56–59 MiB**, `memory.current` 66–69 MiB,
  `docker stats` 63–66 MiB of the 256 MiB limit ⇒ ≥ 4× headroom, so `spark_dcgm_exporter_memory_limit` stays
  at 256 MiB. ⚠ **Do not read a single anon number as the floor:** the same sidecar reads
  **138.8–143.2 MiB anon** once it is aged. Both are `memory.stat` anon, so the difference is instance age /
  DCGM context state, not cadence or the counters CSV (the image default here — no
  `DCGM_EXPORTER_COLLECTORS` is set). Treat the ~200 MiB raise-threshold as a check on an **aged**
  sidecar, not a one-time verdict.
- **The two spark halves are one coupled pair** — `alloy.river.j2` (hot/cold) and the `spark-dcgm`
  `DCGM_EXPORTER_INTERVAL` converge together, because a 5 s scrape of a 30 s collector writes six copies
  of one sample; the acceptance read is
  `count_over_time(node_load1{instance=~"spark.*"}[1m])` = **12**.
- **The hard-coded `[5m]` gauge is a retired-board artefact, not a panel bug.** It lives only on
  `vllm-master-v2.json` (id 402), one of the three donor vLLM boards whose deletion waits on the owner's
  `homelab-llm` sign-off; the board of record already carries that ratio as a
  `rate(…[$__rate_interval])` time series. Deleting the retired board is the fix — rebuilding a
  panel on a board scheduled for deletion is not.
- ⚠ **`--diff` on the `monitoring` role is the same secret-dump class as on `docker_services`:**
  `alloy.river.j2` renders the Victoria* `basic_auth` credentials straight out of the vault, so a
  diff prints them. `--check` is fine; `--diff` is not.

**Re-measure instead of trusting this section** (everything below is read-only; the VM query credentials come
from the `basic_auth` block of `/etc/alloy/config.alloy` on the VPS — parse them into shell variables, never
print them):

```bash
ssh spark 'grep -c scrape_interval /etc/alloy/config.alloy'        # 3 on spark (the hot jobs); 0 elsewhere
ssh spark 'curl -s -o /dev/null -w "%{size_download} %{time_total}\n" localhost:8000/metrics'
ssh spark 'curl -s localhost:9400/metrics | grep GPU_UTIL'          # repeat at 1 Hz: the value holds for 5 s
# per-minute samples per job: Alloy's own prometheus_forwarded_samples_total over a 60 s window
# VM write rate + active series: vm_rows_inserted_total, vm_active_time_series
```

---

## Host sensors and disk I/O

The board must cover **CPU, GPU, RAM and DISK io/throughput**
from spark — and temperatures belong on **Host Overview**, not on the LLM board.

**Disk I/O needs no new telemetry.** `prometheus.exporter.unix "host"` enables the
`diskstats` collector, so the I/O families are in VM — present per
family for `instance="spark.kogler.si", device="nvme0n1"`:
`node_disk_read_bytes_total`, `node_disk_written_bytes_total`,
`node_disk_reads_completed_total`, `node_disk_writes_completed_total`,
`node_disk_io_time_seconds_total`, `node_disk_io_time_weighted_seconds_total`,
`node_disk_read_time_seconds_total`, `node_disk_write_time_seconds_total`,
`node_disk_io_now`, `node_disk_info` (+ merged/flush families). The gap is in the panels, not
the data: every dashboard has capacity (`node_filesystem_*`, "how full") and none has work
("how hard"). **Host Overview** carries a 4-panel row — throughput (B/s), IOPS (ops/s),
busy % (saturation) and avg wait per op (latency: io-time / completions, `clamp_min`'d so
idle windows stay finite) — plus two top-row stats (**Busiest disk** = peak device busy %,
**Hottest sensor**), and the **LLM board** carries throughput / IOPS / saturation panels for
spark. USE-method set: saturation and latency are the two that actually flag a
contended data device; capacity alone never does.

**spark's block layout limits the granularity:** one device (`nvme0n1`) serves BOTH the EXT4
root and the 503 GiB XFS weights/KV mount (`/mnt/spark_nvme`), so block-layer I/O cannot be
attributed per mount. Capacity stays per-mount, work stays per-device — said in-panel so
nobody reads a device series as "the XFS mount".

**Temperatures: `hwmon` and `thermal_zone` have to be enabled in `set_collectors`.** A minimal
collector list that omits them yields **no** `node_hwmon_*`/`node_thermal_zone_temp` series **for any host**,
even though the sensors are live in `/sys`. Both are valid Alloy `prometheus.exporter.unix` collectors
(Alloy fleet pin 1.20.1-1, spark's converge to it ⏳).
The series and label shape below is measured on spark, not guessed:

| Chip / sensor (measured on spark) | Reading | Note |
|---|---|---|
| `chip="nvme_nvme0", sensor="temp1"` | 45.9 °C | the **Composite** NVMe sensor (`node_hwmon_sensor_label` gives the name); `_max_celsius` 85.85, `_crit_celsius` 86.85 |
| `chip="nvme_nvme0", sensor="temp2"/"temp3"` | 56.9 / 45.9 °C | raw sensors (`_max_celsius` on temp2 reads 65261 °C — a firmware joke; use temp1) |
| `chip="thermal_thermal_zone0", sensor="temp0"…"temp7"` | 55.6–58.4 °C | the `acpitz` SoC/CPU zones |
| `chip="ieee80211_phy0", sensor="temp1"` | 54 °C | mt7925 WiFi PHY |
| `node_thermal_zone_temp{type="acpitz",zone="N"}` | same values | **duplicate** of the thermal_zone0 hwmon chip — read one or the other, not both in a sum |

⚠ **The acpitz zones are NOT the GPU.** They run 5–15 °C above `nvidia-smi`/DCGM GPU temp;
there is **no nvidia hwmon chip on this box**, so GPU die temp comes from DCGM only
(`DCGM_FI_DEV_GPU_TEMP`). That is why the two dashboards carry different temperature
sources: Host Overview = host silicon from hwmon, LLM board = GPU from DCGM.

**⚠ BIOS question, answered: the `hwmon` collector needs NO BIOS update, no kernel module,
no new daemon and no reboot.** It reads `/sys/class/hwmon`, which exists on the stock DGX
OS image today. The BIOS/firmware prerequisite belongs to a *different* thing — the
out-of-tree `antheas/spark_hwmon` SPBM driver, which is what would expose the per-rail
power split (CPU-P/CPU-E/SoC/DRAM/system). That is **not** wired here: it is a DKMS kernel
module (self-described as experimental, upstream states "vibe coded", and older firmware
genuinely misreports its CPU channels until `fwupdmgr update`), and loading it on the box
with an OOM history is an owner risk decision, not a monitoring decision. Its
reward is also thin — the SPBM `gpu` channel "matches nvidia-smi", which DCGM already
delivers; the unique part is the CPU-rail split, which NVIDIA says has no supported
interface at all. If it is ever wanted, the wiring is already prepared: it lands in
`/sys/class/hwmon`, and the `hwmon` collector enabled here picks it up with **no further
change**. Same for the community `dgx-spark-exporter` (Go, `:9876/metrics`) — its ~50
`dgx_spark_*` metrics are a 1:1 duplicate of the Alloy unix collector already running
(CPU/mem/disk-IO/filesystem/network/load/fd), its GPU trio is nvidia-smi again, and it
carries no VRAM and no profiling either; not adopted.

**In the backend:** `node_hwmon_temp_celsius` exists per
instance (spark 12, oldsrv 17, nas 9, pi 2 sensors). The disk panels need no converge — the
families are already in VM. **If a temperature panel renders
empty for one host, that host's Alloy has not picked up `set_collectors` yet** (check the
`alloy.service` restart) — it is not a dashboard bug.

⚠ **Converge trap:** a new/changed Alloy config converges under `--tags monitoring`, but the
**first deploy of a compose service needs that service's own tag**
(`--tags monitoring,docker_services,<name>`) or the deploy tasks are silently skipped while the run
still reports `failed=0`. Proof = a backend query or `docker ps`, never the recap.


> **Metric names that are not what you would guess** — each has a plausible wrong name that renders an
> empty panel:
> - Traefik: **`traefik_entrypoint_requests_total`** (v3). `traefik_requests_total` is the v2 name and is
>   a phantom here. The metrics endpoint is enabled on the main edge (`--metrics.prometheus=true`,
>   `--entryPoints.metrics.address=:8082`) with a `db-internal` join so the collector can resolve
>   `traefik:8082` at all.
> - UPS: **`network_ups_tools_*`** (DRuggeri/nut_exporter v3, path `/ups_metrics?ups=<name>`), **not**
>   `nut_*`. The exporter is **version-pinned** (`nut_exporter_release`) — `@latest` tracks `(devel)` and
>   its metric names move.
> - CrowdSec: **`cs_active_decisions`** (labels `reason`/`origin`/`action`), not `crowdsec_decisions`.
> - Host metrics: the Alloy `unix` exporter is node_exporter-compatible (`node_cpu_seconds_total`,
>   `node_uname_info`, …) in the `job="alloy"` namespace — **and an Alloy component that is declared but
>   not consumed is silently dead** (`prometheus.exporter.unix` emits zero `node_*` series unless a
>   `discovery.relabel` + `prometheus.scrape` pair consumes it). Lazy evaluation is the usual cause of
>   "the exporter is running but the metric does not exist".

---

## SNMP coverage — what the gear actually answers, against what we collect

> **Role:** measurement state for network monitoring over SNMP: which OID families **actually answer** on which device
> on this firmware, and how that compares with the one module the collector walks
> ([`snmp.yml.j2`](../IaC/ansible/roles/monitoring/templates/snmp.yml.j2) → `prometheus.exporter.snmp` above).
> A MIB name is not a capability — an answered OID is, so per-device monitoring decisions go against this table.
> **Status: ✅ measured read-only on the live gear (2026-10-13, RouterOS 7.24.4). Nothing here changed a device:**
> `snmpget`/`snmpwalk` only, never `snmpset`, never a device config.

**Method, because it is load-bearing.** Probes ran from the oldsrv seat with the distro `snmpwalk`/`snmpget`
(net-snmp 5.9.4, already installed — nothing installed for this), SNMPv2c, against the addresses the inventory models
(`network_static_hosts`). The read-only community resolves from the vault item `network-snmp_api` and is proved
present by **length only**; it is fed through a `0600` `snmp.conf` (`defCommunity`) so it never reaches `argv`, `ps`,
or a log. **The seat carries no IETF MIB files** (`/usr/share/snmp/mibs` holds only net-snmp's own), so every probe is
a **numeric OID walk** (`-On`) and the names below describe the returned payload, not a symbol resolved on the seat.
The four outcomes are kept apart: **answered** / **`noSuchObject`** (the family is not in the agent's tree) /
**timeout** (the agent never replied — says nothing about which families it would have) / **refused**.

### Per-device verdict

Addresses are the Mgmt-plane ones the SSOT models — see
[`network-addresses-generated.md`](network-addresses-generated.md); hostnames are the inventory names, which is how
the rows below identify a box.

| Device | Reachability proof | SNMP verdict |
|---|---|---|
| **router** RB4011iGS+ | ICMP up; `sysDescr` = `RouterOS RB4011iGS+ 7.24.4 (stable)`, `sysObjectID` `.1.3.6.1.4.1.14988.1` | **answers** (rows below) |
| **switch** CRS328-24P-4S+ | ICMP up; `sysDescr` = `RouterOS CRS328-24P-4S+ 7.24.4 (stable)` | **answers** (rows below) |
| **ap-spalnica** hAP ac² | ICMP up from the Mgmt plane, ARP `REACHABLE` with the inventory MAC, **and its RouterOS API port accepts a Mgmt-plane TCP connection** | **timeout on every family** — the agent is not answering. Not a Mgmt-plane input-filter problem: another management service on the same box answers from the same source. No IaC on the APs enables SNMP (no `capsman`/router template carries an `/snmp` block), so the likeliest reading is `/snmp enabled=no` on the default config. Family presence stays **unknown**, not absent |
| **ap-dnevna** hAP ac² | ICMP up, ARP `REACHABLE`, inventory MAC, API port open from Mgmt | **timeout on every family** — same state |
| **ap-spare** | no ICMP, ARP `INCOMPLETE` | **not on the wire** |
| **ilo** (nas BMC) | no ICMP, ARP `INCOMPLETE` | **not on the wire** (BMC down/off) — nothing to conclude |
| **nas** (Mgmt-plane address) | no ICMP, ARP `INCOMPLETE` on Mgmt — the box lives on Home | **timeout**; no SNMP agent is modelled for nas |
| **ups** PowerWalker (IoT-plane address) | ICMP up (routed) | **timeout** — no SNMP answer; the live truth path is NUT over USB (§UPS / Power-Loss Monitoring), so this is a non-gap |
| **homematic-hap** | no ICMP, no neighbour entry | **timeout** — HA owns this device, no SNMP path |
| **TP-Link TL-SG108E** | **no address exists** in `network_static_hosts` or the rack model (`network-rack-generated.md` records it as wiring-unknown) | **not probed** — nothing to reach; the inventory cannot currently say whether it has an agent at all |
| *MAIPU / UDM / Radlan* | **no such device** in the inventory, the rack model, or any `docs/` inventory; `RADLAN` (`.1.3.6.1.4.1.12837`) answers nowhere | nothing to walk — a device list naming them is wrong, not this network |

The two MikroTiks are the **only** SNMP surfaces in this rack, both on RouterOS 7.24.4 — one module covers 100 % of
what SNMP can see here.

### Family by family, on the two MikroTiks

`RB4011 / CRS328` = instances a numeric walk returned.

| Family | OID root | Verdict | Rows |
|---|---|---|---|
| system (`sysDescr`/`sysObjectID`/`sysUpTime`/`sysContact`/`sysName`/`sysServices`) | `.1.3.6.1.2.1.1` | answered | 6 scalars each |
| **`ifAdminStatus` / `ifOperStatus`** — *what the collector walks today* | `.1.3.6.1.2.1.2.2.1.7` / `.8` | answered | 23 / 31 |
| **`ifName`** — *walked today for the label lookup* | `.1.3.6.1.2.1.31.1.1.1.1` | answered | 23 / 31 |
| ifTable rest (`ifDescr`/`ifType`/`ifSpeed`/`ifMTU`/`ifLastChange`) | `.1.3.6.1.2.1.2.2.1` | answered | 23 / 31 |
| **throughput + error counters** (`ifInOctets`/`ifOutOctets`/`ifInErrors`/`ifOutErrors`, and the 64-bit `ifHCInOctets`/`ifHCOutOctets`) | `.1.3.6.1.2.1.2.2.1.10/.14/.16/.20`, `.1.3.6.1.2.1.31.1.1.1.6/.10` | answered | 23 / 31 each |
| `ifAlias` (port description) / `ifHighSpeed` | `.1.3.6.1.2.1.31.1.1.1.18` / `.15` | answered | 23 / 31 — but `ifAlias` is the **empty string** on 22 of 23 and 26 of 31 ports, and `ifHighSpeed` reports `0` for every LAG/virtual interface: present ≠ populated |
| bridge base + base-port map | `.1.3.6.1.2.1.17.1` | answered | 5 / 28 base ports |
| **FDB** `dot1dTpFdbPort` | `.1.3.6.1.2.1.17.4.3.1.2` | answered | 14 / 15 entries |
| **VLAN-aware FDB** `dot1qTpFdbPort` | `.1.3.6.1.2.1.17.7.1.2.2.1.2` | answered | 63 / 76 entries |
| STP `dot1dStp` | `.1.3.6.1.2.1.17.2` | answered, **walk-hostile on the RB4011** | CRS328 walks (289 rows); the RB4011 walk aborts mid-table with `Error: OID not increasing` at `.17.2.15.1.2` — scrape it column-scoped, never as a subtree walk |
| ARP `ipNetToMediaTable` | `.1.3.6.1.2.1.4.22.1` | answered | 42 / 3 entries |
| IPv6 `ipAddressTable` | `.1.3.6.1.2.1.4.34` | **absent** | `noSuchObject` at the group, the table and its columns — IPv6 addresses are not readable over SNMP here
| ENTITY-MIB `entPhysicalTable` | `.1.3.6.1.2.1.47.1.1.1.1` | **partly** | 9 / 2 entities; `entPhysicalDescr` = `"RouterOS 7.24.4 (stable) on <MODEL>"`, `entPhysicalClass` integer, but **`entPhysicalName` returns `INTEGER: -1`** and serial/model are empty strings — ENTITY says *which box*, never per-port names. `entLogicalTable` absent |
| sensors / optics DOM (`entSensorTable`) | `.1.3.6.1.2.1.99` | **absent** | no temperature / voltage / `rxPower` via the standard sensor MIB |
| **PoE** (`pethMainPse`/`pethPortPse`) | `.1.3.6.1.2.1.105` | **absent** | including on the CRS328-**24P** — PoE budget and per-port PoE state are not readable over SNMP on this firmware |
| Ethernet-like link stats (`dot3StatsTable`, `dot3OperTable`, `etherLikeOETSTable`) | `.1.3.6.1.2.1.10.7.2` / `.10.24` / `.10.20` | **absent** | CRC/alignment error counters have no `dot3` home here — use `ifTable`'s `ifInErrors`/`ifOutErrors`, which do answer |
| RMON | `.1.3.6.1.2.1.16` | **absent** | no RMON channel counters |
| LAG (`dot1dLagPort*`) / 802.3ah `aMaMux` | `.1.3.6.1.2.1.17.1.3.1.1` / `.1.2.840.11425.1.2.1` | **absent** | no LAG-member state over SNMP (`.17.1.3.0` answers as a scalar; the table does not exist) |
| CPU `hrProcessorLoad` | `.1.3.6.1.2.1.25.3.3.1.2` | answered | 4 cores / 1 core |
| Memory + disk `hrStorageTable` | `.1.3.6.1.2.1.25.2.3.1` | answered | 2 rows each: `"main memory"`, `"system disk"`, 1024-byte units |
| **MikroTik vendor subtree** | `.1.3.6.1.4.1.14988.1.1.*` | answered | groups `.1 .3 .4 .5 .6 .7 .8 .11 .12 .13 .14 .15 .16 .17 .19 .20 .21 .22`. `.11` is an ARP-shaped table (42 rows), `.14` the large per-interface counter table (1587 / 2139 rows), `.17` flash partitions + the RouterOS build string, `.19` a per-interface table naming the SFP+ ports (`sfp-sfpplus1…4`, 68 rows on the switch) — the only per-SFP SNMP surface on this box; whether any of its integer columns is a DOM value is **not resolvable from a numeric walk**, because no vendor MIB is installed on the seat |
| Other enterprise stubs | `.1.3.6.1.4.1.9.9.150.1`, `.2021.11.10.0`, `.3495.*` | answered | a handful of scalars, all zero — agent artifacts, not a vendor tree of any device in this rack. **`RADLAN` (`.1.3.6.1.4.1.12837`) answers nowhere** |

**Community behaviour, measured.** A deliberately wrong community **times out** on both boxes (the agent does check),
SNMPv3 answers `Unknown user name` (v3 present, no users), and **the RouterOS default community `public` also answers
on both boxes** alongside the vault community — so the dedicated read-only item is currently *additional*, not
*exclusive*. The switch converge template adds the vault community and never removes the factory one
(`IaC/router/templates/crs328_converge.rsc.j2`), which is exactly what the walk then confirms on the box. Which
communities a device accepts, and the `read-access`/`write-access` flags on them, live in device config and are not
readable over SNMP — this lane changed none of it and ran no SET.

### What `snmp.yml.j2` collects now — every metric proved on a live series

The `mikrotik` module walks 15 column-scoped OIDs and emits 12 metrics; Alloy scrapes it for the same two targets,
`router` and `switch`, from oldsrv only. **Measured cadence is one scrape every 60 s** (`count_over_time(up{job="alloy-snmp"}[5m])`
= 5 per box), because the two `prometheus.scrape "snmp_*"` blocks in `templates/alloy.river.j2` set no
`scrape_interval` and take Alloy's default — the 5–15 s MikroTik poll in §Microservice Notes is the stated intent, not
the state on the box. Landed and
verified live 2026-10-13 with the narrowest scoped change available — `--tags alloy --start-at-task "Template Alloy
SNMP config (MikroTik module)"` against oldsrv, which renders one file and restarts one collector, touches no device
and runs no full converge.

**The table is a proof, not a claim.** Each row's last column is the value read back out of VictoriaMetrics
(`job="alloy-snmp"`) after the deploy, with the number of ports/rows the boxes really return. Presence is enforced
rather than asserted: [`scripts/ansible/probe-snmp-presence.sh`](../scripts/ansible/probe-snmp-presence.sh) parses
the metric list **out of the module file** and fails when one stops landing on either box — widening `walk:` widens
the test for free, and an OID the firmware drops fails a script instead of emptying a panel. Run it after giving a
just-restarted collector a scrape cycle, or with a wider `--window`.

| Metric | What it proves | Rows returned (RB4011 / CRS328) | First value seen on the series |
|---|---|---|---|
| `sysUpTime` | a reboot of gear that runs no node_exporter | 1 / 1 | 2 217 661 s and 2 217 367 s → both boxes booted 2026-09-17, 15:36:44 and 15:40:38 CEST |
| `ifAdminStatus` / `ifOperStatus` | a port disabled by hand / a link that dropped | 23 / 31 each | 17 router rows and 12 switch rows at `1` (up) |
| `ifHCInOctets` / `ifHCOutOctets` | link throughput, 64-bit | 23 / 31 each | `rate[5m]`: router `ether2` 24 851 B/s, `pppoe-telekom` 7 800 B/s, switch `sfp-sfpplus1` 1 259 B/s; lifetime max 1 005 466 227 171 B on router `ether1` |
| `ifInErrors` / `ifOutErrors` | link quality — the only error counters this firmware answers | 23 / 31 each | every `ifInErrors` reads 0 on all 54 rows; exactly one non-zero error counter exists: router `wg-s2s` `ifOutErrors` 148 459 |
| `ifHighSpeed` | negotiated link speed in Mbps | 23 / 31 rows, **9 / 9 of them non-zero** | 10 000 on both `sfp-sfpplus1`, 1000 / 100 on copper, 50 on `cap-wifi1` |
| `hrProcessorLoad` | device CPU | 4 rows / 1 row | router 0 / 0 / 0 / 0 % (four cores), switch 2 % (one row) |
| `hrStorageSize` + `hrStorageUsed` + `hrStorageAllocationUnits` | device RAM and system disk | 2 rows each (`"main memory"`, `"system disk"`), units 1024 B | router RAM 1 073 741 824 B total / 210 100 224 used, disk 536 870 912 / 101 982 208; switch RAM 536 870 912 / 70 348 800, disk 16 777 216 / 13 877 248 |
| `if_alias` (a **label** on the per-interface metrics, not a metric) | the RouterOS interface comment — the port name an operator reads | 1 of 23 / 5 of 31 rows carry one | switch `ether12` → `PoE for AP: ap-dnevna`, `ether11` → `PoE for AP: ap-spalnica`, `ether3` → `PoE for AP: reolink-camera` |

**A reboot of either box now shows up in a series.** `sysUpTime` counts 1/100 s since the agent started, so a boot
resets it toward 0: the alertable forms are `resets(sysUpTime{job="alloy-snmp"}[10m]) > 0` and, for "did this box come
up since I asked", `timestamp() - sysUpTime{job="alloy-snmp"}/100` = the boot timestamp (the two values above are
what that query returned). `up{job="alloy-snmp"}` is not the reboot signal — it only says the scrape failed, and a box
that reboots between two scrapes can keep `up = 1` the whole way through. At the measured 60 s cadence a boot costs at
most one missed minute of interface series, which is what `sysUpTime` is for.

**The zero rows are a measured state, not a missing instance.** 7 of 23 router rows and 19 of 31 switch rows report
`ifHCInOctets = 0`. Every one of them is a real `Counter64: 0` value, not a `noSuchInstance` — the walk returns a
64-bit instance for **every** row the ifTable lists (23 / 23 and 31 / 31, in and out, no gap in the index sets), and
the zero rows are the idle ones by name: `ether4`/`ether5`/`ether6`, `vlan30-guest`, `vlan40-kids`, `cap-wifi1`,
`cap-wifi1-virtual1` on the router, and 19 unconnected switch ports. So "throughput is collected" is honest for all
54 rows. `ifHighSpeed` reads 0 on the other 14 / 22 rows, and 0 there means *not a physical link* (bridge, VLAN,
loopback, virtual) — it is not a down port, `ifOperStatus` is what says that.

**Why there is no 32-bit octet twin, and what that buys.** `ifInOctets`/`ifOutOctets` answer too, and they are
*exactly* the 64-bit counters modulo 2³² on every row of both boxes (23 / 23 and 31 / 31, in and out; every row whose
64-bit counter is 0 is 0 on the 32-bit one as well). They are therefore a lossy projection of a series already
stored, at double the per-interface cardinality. The arithmetic also says they would be **wrong**, not merely
redundant: 2³² octets is 4 294 967 296 B, which a saturated 10 Gb/s row rewrites in **3.4 s** and a 1 Gb/s row in
**34 s** — inside a 60 s scrape interval that is a wrap *many times over* on `sfp-sfpplus1`, so `rate()` on a Counter32
under-counts there while the same query on the Counter64 is exact. Any future `rate()` on this module's octets
should use a window of at least two scrapes (two of the measured 60 s ones = 2m); do not re-add the 32-bit pair to "help" the
10 Gb/s links.

**Which side owns "which port does this MAC sit on": the RouterOS API, not SNMP.** `dot1qTpFdbPort` does answer
(63 / 76 entries), but
[`network-clients-exporter.py.j2`](../IaC/ansible/roles/monitoring/templates/network-clients-exporter.py.j2)
already reads `/interface/bridge/host` from the router API and joins it with DHCP leases, ARP and the wifi
registration table into one de-duplicated-per-MAC `mikrotik_client` series. The SNMP FDB table would add ~140
series of raw MAC→port that churn every time a client roams, to answer a question that is already answered and
joined. Chosen side: **the API**. Corollary — a client-location question is a `network-clients` question; SNMP owns
the *interface* side of the network story (status, throughput, errors, speed, CPU, memory, uptime).

**Still not collected, on purpose.** ARP (the API exports it, joined with the rest), STP state (see the trap below),
and the vendor subtree `.14988.1.1.14`, which is 1587 / 2139 rows of per-interface counters nobody has asked a
question about yet. And the families this firmware does not answer — PoE, `entSensor` DOM/optics, `dot3` errors,
RMON, LAG-member state, ENTITY per-port names — stay out of the walk: a dashboard or rule that expects any of them
over SNMP is green-by-absence, so each needs its own path (API, Redfish, NUT, HA), not a longer `walk:` list.

**Three traps for whoever extends the module.** (1) The RB4011's `dot1dStp` subtree cannot be walked as a tree —
the agent emits a non-increasing OID and the walk dies mid-table, so a `walk:` entry there collects a partial table
with no error; STP stays out of the shared module for exactly that reason, and if it is ever wanted it needs its own
per-device module with column-scoped walks, not a line in this one. (2) `entPhysicalName` answers `INTEGER: -1`
rather than a name: an `entity`-module walk yields entities without names. (3) An absent family returns
`noSuchObject` **silently at scrape time** — a module asking for PoE or `entSensor` produces no series and no
failure, which is how a panel goes green-by-absence. The answer is the probe above, never a `default()` in the
collector: a metric is only listed here once a series carrying a real value is quoted.

---

## Network Clients Dashboard

> **Role:** design SSOT for the "all network clients, grouped per VLAN" Grafana dashboard
> (`homelab-network-clients`) at `stats.kogler.si`.
> **Status: ✅ exporter live on oldsrv, ⏳ owner render-verification owed.**
> Deployment shape (all of it load-bearing): host binary + venv under `/opt/network-clients-exporter`
> (`routeros-api==0.21.0` pinned — Debian has no `python3-routeros-api` package and the exporter imports
> the PyPI module name `routeros_api`), running as `networkclients` with the install dir `0750
> root:networkclients` so a low-privilege service user holds the RouterOS credentials, and `/metrics`
> serving the `mikrotik_client` union (DHCP + ARP + FDB + wifi) from the RB4011 `logpipe` read-only user.
> ⏳ Open: verify the wifi path against `/interface/wifi/registration-table` (vs the legacy API) and the
> owner render-check of the dashboard.

**Goal.** One dashboard showing *every* client on the homelab, grouped by VLAN
(10 Home / 20 IoT / 30 Guest / 40 Kids / 50 Media / 99 Management).

**Why 5 data sources — no single one covers “all clients”.** DHCP leases alone miss the
~static-IP hosts (router/switch/APs, nas/oldsrv/pi, shelly/KNX/printers — all static per
`network_static_hosts`, SSOT `group_vars/all/main.yml`). The dashboard is a **join**:

| RouterOS source (live API) | Path | Covers | VLAN classifier |
|---------------------------|------|--------|-----------------|
| DHCP leases | `/ip/dhcp-server/lease` | DHCP-issued clients (hostname, mac, address, status) | lease `server` → pool → subnet → VLAN |
| ARP table | `/ip/arp` | any host that has talked (IP+MAC) | ARP row's interface name (`vlan10-home` → 10) |
| Bridge host table (FDB) | `/interface/bridge/host` | L2-attached MACs, wired + wireless | bridge/vlan attribute |
| WiFi registration | `/interface/wifi/registration-table` (modern wifi-qcom-ac) | active wireless clients (mac, ssid, iface, signal) | SSID/interface → VLAN |
| SSOT static hosts (not scraped) | `network_static_hosts` | every static host + its true VLAN | `vlan` attr — naming/VLAN ground truth |

**Data path.** A small **RouterOS-API collector on `oldsrv`** is the primary pipe:
oldsrv sits on the Mgmt plane + the tunnel legs, so the RouterOS API is INPUT-legal — the router INPUT
firewall accepts mgmt services (`22,8728,8729,8291,80,443`) and SNMP/161 **only from the Mgmt VLAN +
`trusted-admin`** (`roles/router/tasks/main.yml`), then drops everything else, including the wg-s2s side.
The collector reuses the existing read-only API pattern: `skills/mikrotik/scripts/mikrotik-read.py` on
RouterOS API `:8728` with a scoped `read`-group user (the `logpipe` precedent,
`roles/router/tasks/main.yml` L1429). Exposes Prometheus-format metrics; the existing oldsrv
Alloy `remote_write`s them over `wg-s2s` → VPS VictoriaMetrics (same channel as SNMP). **No
new firewall open, no VPS reachability change.**

**SNMP stays a backstop only.** The `prometheus.exporter.snmp` block already runs on oldsrv
(`alloy.river.j2` L287) and can walk ARP `1.3.6.1.2.1.4.22` + FDB `1.3.6.1.2.1.17.4.3` + the MikroTik DHCP
MIB in `snmp.yml.j2`, but it gives no lease hostname/status richness and **no wifi-qcom-ac client data at
all** (registration lives in the API path only). Device-side SNMP enablement is still an owner deploy step.

**Metric shape.** One gauge series, info-card style, enriched at authoring time from the
rendered SSOT (`network_static_hosts` is available to the Ansible-rendered exporter):

```
mikrotik_client{dhcp_status="bound", vlan="10", hostname="phone-domen", mac="AA:BB:…", ip="<ip from SSOT row>", source="dhcp|arp|fdb|wifi|static"} 1
```

- Union leases + ARP + FDB + wifi-reg, de-duped by MAC; `source` records which view found it.
- Static SSOT rows are emitted once as `mikrotik_static_host{vlan,hostname,ip}` (or matched
  at query time) — they never change and need no scrape; they are the naming/VLAN ground truth.
- Scrape interval ~30–60 s; exporter placed alongside the SNMP block, scoped
  `{% if inventory_hostname == 'oldsrv.kogler.si' %}`.

**Dashboard.** New `homelab-network-clients` in the monitoring role (folder `Homelab`, uid
convention `homelab-*`, datasource uid `prometheus` — same as the other dashboards):

| Panel | View | Query basis |
|-------|------|-------------|
| All clients table | one row per MAC: VLAN badge, hostname (SSOT name else lease hostname), IP, MAC, source | `mikrotik_client` + `mikrotik_static_host` |
| Per-VLAN breakdown | grouped by `vlan` — template variable `vlan` (`label_values`) + sort | `count by (vlan)` |
| VLAN distribution stat | 6 stacked counts (10/20/30/40/50/99) | `count by (vlan)` |
| WiFi vs wired | optional breakdown | `source=wifi` vs others |

**Open before this is called done.**
- Exporter + dashboard are authored and deployed (`roles/monitoring/`: `network-clients-exporter.py.j2` host binary +
  systemd unit + Alloy `prometheus.scrape "network_clients"` + `homelab-network-clients.json`).
- ⏳ Confirm live wifi path: modern `wifi-qcom-ac` registers under `/interface/wifi/registration-table`
  (legacy `/interface/wireless/registration-table` in `skills/mikrotik` is the old path).
- ⏳ Router API reachable from oldsrv (Mgmt) — already the case for the SNMP exporter; re-verify with
  a read-only `mikrotik-read.py` call at deploy time.
- ⏳ Device-side SNMP enable (“if used as backstop”) is still an owner deploy step; the API collector
  needs only the API service (`/ip/service set api disabled=no`), already INPUT-scoped to Mgmt.

---

## Deferred / TODOs

| Item | When | Notes |
|------|------|-------|
| Homematic full-local (HmIP-RFUSB + RaspberryMatic on Pi) | **parked** — HmIP-HAP stays in cloud mode until an HmIP-RFUSB is bought | see `smart-home.md` — affects HAP/HA integration, not metrics flow |
| Container memory working-set metrics (Docker API → VictoriaMetrics) | with the *arr stack | validates the `services.md` RAM budget with real numbers, not estimates |
| **Homelable** (interactive topology/rack visualizer) | **Authored, deploy-gated** — oldsrv, internal-only dashboard. Live health-check map + rack canvas w/ port patching + nmap scan + MCP server. **Not** a metrics/logs/alert backend — it complements Grafana and the network-clients dashboard (see §Network Clients Dashboard). Owns the "who's on my network + where" visual that Grafana's per-VLAN tables don't. Deployment spec + onboarding: [`services-admin.md`](services-admin.md) §Homelable. |
| Route alerts to a **Matrix room** (`#homelab-alerts`) | operator joins the room, then Signal demotes | the room, the bot, the vault token and the n8n leg exist (§Alerting); what is missing is a human member in the room, and only then the Signal teardown. · [`services-matrix.md`](services-matrix.md) §Alert room |
| **Home-side tunnel check** | after Phase 1.5 cutover | blackbox `wg_icmp` probes run FROM the VPS; add a router-side netwatch → SNMP trap (or equivalent) so a home↔VPS outage is also observable from home when the VPS path is the broken side |
| **Monitoring role split** | only when dashboard/rule iteration gets slow | Alloy+VictoriaMetrics+VictoriaLogs+Grafana live in one `monitoring` role — any rule tweak redeploys the chain; split into `tasks/{alloy,victoria-metrics,victoria-logs,grafana}.yml` includes + tags (no structural move needed until it hurts) |
| **Grafana alert-rule provisioning schema** (monitoring role `grafana-rules.yml.j2`) | first deploy of the monitoring role | ⚠ **needs live check:** query+threshold data-model + folder auto-creation unverified against a running Grafana — confirm rules load (Grafana logs) and fire once before trusting alerting |
