> **Role:** entry point for the next session — a **lean handoff**. It is a pointer index: every item's owning doc ([`docs/index.md`](docs/index.md) map) / [todo.md](todo.md) row holds the detail. Start with [README.md](README.md) §0 (intent routing) → §1 mandatory context → §2 below. History is not kept here: session accounts live in the owning-doc status blocks + git history (archive-only: `reports/changelog.md`, `reports/deployment-journal.md`).
> **Linked from:** [README.md](README.md) §0/§2 · [CONVENTIONS.md](CONVENTIONS.md) §4/§6 · [todo.md](todo.md) · [todo-table.md](todo-table.md) (planning view).

---

## 1. Environment

WSL Debian primary, ext4 (repo runs from the WSL Debian primary, not Windows). `python3`/bash/LF/UTF-8 no-BOM. Secrets → 1Password `Homelab-ansible` item.field only, `>-` for YAML renders. Multi-line bash heredocs with backslashes/backticks get mangled through `bash -c` — write script bodies to a temp file and run them (self-learned 2026-08-26). **Signed-commit gotcha:** keys in `~/.ssh/github_signing`/`github_auth`; `Couldn't find key in agent` → `ssh-add ~/.ssh/github_signing ~/.ssh/github_auth`.

Laptop/WSL reaches the **Mgmt VLAN directly** (Windows `Mgmt99` vNIC, `wsl-nat-resolv.ps1 -EnableMgmt99`) — SSH aliases `router`/`switch`/`oldsrv`/`pi99` are direct, no ProxyJump. `ansible-network-hop.sh` is obsolete. `pi`/`pi99` remain the one dual-leg exception.

---

## 2. Open work (read the HD rows; this is only the index)

For "what to do next" see [todo-table.md](todo-table.md) (Table AI / Table Human). Each HD line links its owning doc + todo row; the ⏳ = exact next step. Deploy-gated verifies live in [`deployment-tasks.md`](deployment-tasks.md) (per-phase chapters).

**AI-actionable now (no owner prerequisite):**
- **HD-352** — ⏳ DNS re-point tail: Pi tertiary seed converge (raspberry_pi.yml) → `dig @<home> media.kogler.si` verify; oldsrv secondary seed converged 2026-09-14. · [network-dns.md](docs/network-dns.md)
- **HD-365** — ⏳ `spark.kogler.si` split-horizon DNS record (home instances only): deploy-gated seed converge on oldsrv/Pi → `dig` verify; VPS primary must NOT answer. · [network-dns.md](docs/network-dns.md)
- **HD-344** — ⏳ register MCP victoria endpoints in pi / Open WebUI / OpenClaw (servers deployed :8080/:8081); tailnet redo = owner. · [observability.md](docs/observability.md) §MCP
- **HD-318(b)** — ⏳ recyclarr @daily quality-profile sync verify (stacks up 2026-09-08). · [hardware-oldsrv.md](docs/hardware-oldsrv.md) · [todo.md HD-318](todo.md)

**Deploy-gated (AI does the deploy/verify on gate-clear):**
- **HD-356** — ⏳ LAN LiteLLM split: stays `enabled: false` — spark bench certify → add `bootstrap_keys` + `config.yaml.j2` → flip; dsh/pi-dev already re-pointed to it. · [services-ai.md](docs/services-ai.md) · [todo.md HD-356](todo.md)
- **HD-354** — ⏳ Navidrome on VPS + Storage Box: re-converge VPS to completion (2026-09-14 converge aborted before navidrome — traefik-tailnet restart fail) + Storage Box music dir + Subsonic/ExtAuth verify. · [services-media.md](docs/services-media.md)
- **HD-360** — ⏳ Samba Authentik-as-LDAP (VPS-side): LDAP provider + svc_samba + fresh `authentik-ldap_bind` token → redeploy → flip `storage_samba_passdb: ldapsam` on nas → family-drive verify. **Do NOT flip before provider/outpost/token are up** (smbd fails hard). · [deployment-compose.md](docs/deployment-compose.md) §Samba↔Authentik-as-LDAP

**Owner-step tails on live work:**
- **HD-350** — ⏳ tail: authorize oldsrv `/root/.ssh/traefik-cert-sync.pub` on the VPS → verify wildcard pair + LAN routes (`traefik-internal` home edge deployed 2026-09-14). · [services-traefik.md](docs/services-traefik.md) §Edge model
- **HD-353** — ⏳ owner: verify own Jellyfin login at seerrng (SeerrNG up, internal :5055). · [services-media.md](docs/services-media.md)
- **HD-362** — ⏳ Music pillar tails (pillar deployed 2026-09-14): 1P placeholders → real service values; lidarr-ydl `/home/appuser/.profile` + aurral `/app/downloads` EACCES; wire Lidarr clients; Navidrome Box refresh. · [services-media.md](docs/services-media.md) §Music Pillar
- **HD-358** — ⏳ Seerr↔*arr wiring runbook step (bug #7): record API-key + URL wiring once home edge is up. · [services-media.md](docs/services-media.md)
- **HD-357** — ⏳ Homepage tiles fix (bug #6): Jellyfin/Seerr tiles dead, Immich stuck "Soon"; wire layout/widgets to the verified endpoints. · [services.md](docs/services.md) accessibility SSOT
- **HD-343 / HD-315** — ⏳ dashboards render-verify (owner): Network Clients + host-overview panels with data (data flowing on all 4 hosts); wifi-path verify. · [observability.md](docs/observability.md) §Dashboards
- **HD-345** — ⏳ `ifOperStatus` SNMP series still 0 in VM (rules on; SNMP enabled, walk not arriving). · [observability.md](docs/observability.md)
- **HD-368** — ⏳ vLLM inference dashboards live-verify: `vllm:*` series in VM + panels populate on `stats.kogler.si` (3 dashboards authored + merged `a582acb`; engine flipped `enabled: true` `9445d35`; data path = spark-ai loopback `:8000` → spark Alloy `vllm` scrape → VPS VM). · [observability.md](docs/observability.md) §Dashboards
- **HD-08 / HD-06** — ⏳ UPS wake re-test (owner): short pull → poweroff + WoL wake end-to-end (full fix set merged + deployed nas/oldsrv/pi 2026-09-09). · [hardware-ups.md](docs/hardware-ups.md)

**spark (DGX GB10) — the other active lane:**
- **HD-367** — ⏳ S1 bench live-verify on the box: **flip + 4 blocker fixes are MERGED on main** (`9445d35`…`91d6049`; validates green — no pending branch to merge); the remaining gate is **the engine actually booting + benching on spark**: converge spark (live compose must match SSOT) → :8000 health → warmup → accuracy gate → C1/C2/C3 sanity → record [BENCHMARK-PLAN.md](spark/BENCHMARK-PLAN.md) §9 → full ladder S1–S5 later. Status: mgmt-leg dual-home (VLAN-99 tagged) + llm-d removal done; **first boot done** — blockers fixed in SSOT: swap-space/quantization/spec-overrides dropped, `gpu_memory_utilization` 0.95→0.93, WHOLE-`/root/.cache` mount (torchinductor), plain `python3 -m vllm` start; PLE offload table was ~33% (2/6 shards) at close. ⚠ box tails cleared 2026-09-15: `dgx-dashboard-socat` removed, `traefik-spark` healthy, dashboard :11000 verified 200. · [hardware-spark.md](docs/hardware-spark.md) §B1 engine boot · [todo.md HD-367](todo.md)
- **HD-359** — ⏳ spark bench S1–S5 → flip `spark-ai.enabled` (node provisioned 2026-09-14: DGX OS wizard, bootstrap, p3 XFS carve 503.4G, `spark.yml` failed=0; artifact store staged — weights 169G + overlays + INT4 tables 30G). Subsumed by the HD-367 lane. · [hardware-spark.md](docs/hardware-spark.md) §Benchmark
- **HD-366** — ⏳ DGX Dashboard JupyterLab LAN edge (:11002): entrypoint + route already exist; spawn a lab from the dashboard → curl `http://spark.kogler.si:11002` from a LAN client. **Deliberately untouched 2026-09-15** (owner instruction).

**Backlog (rest of todo.md — stays open; parking lot / late-phase / not the current focus).** HD-301 router bootstrap hardening · HD-312 kids per-MAC (observation tail only) · HD-207 landing-zone redistribution · HD-219/220/230 Phase-1 wave-2 + renovate/kopia owner tails · HD-247/248/249/250/251 LiteLLM cutover + OWUI split + n8n + DSH · HD-335/337 spark bring-up plan (folded into the HD-367/359 lane) · HD-100/101/103/104/111 AI-stack deploy tails · HD-147 OIDC live-verify (matrix/claw/foto/immich) · HD-47 Matrix federation records · HD-112 Zipline · HD-288 sunshine · HD-361 cockpit break-glass · HD-49/34/238/191 backup matrix + restore drill · HD-57/133 finance · HD-32 family guides. **Parked:** HD-45 (Homelable — parallel lane), HD-264 (renovate sandbox), HD-336b (CrewAI pilot = owner decision). See [todo.md](todo.md) + [todo-table.md](todo-table.md).

---

## 3. Working contract (non-negotiable)

1. **Step-0 ritual:** `git status` sanity + fresh session worktree (`git worktree add ../homelab-wt-<date>-<HHMM>`, CONVENTIONS §6) — enforced by `scripts/guard-session.sh`.
2. **Prior-art sweep** before new HD rows: todo.md + owning docs + `<domain>-rejected.md` + `git log -S 'HD-…'` (re-decide ban).
3. **Validate before finishing:** `bash scripts/validate-all.sh` must end green (checks prompt↔todo consistency, SSOT doc map, IP literals, placeholders, done-row deletion).
4. **SSOT direction:** values in IaC (`group_vars/*.yml`, `host_vars/*.yml`) · generated `*-generated.md` never hand-edited · secrets 1Password `Homelab-ansible` only, fail-loud (no `default('')`).
5. **Lifecycle:** fully-done HD row → **deleted** from todo.md (record in owning doc + git). IaC-done-but-deploy-gated row stays with a ⏳ tail. Decisions written once to the owning doc + `<domain>-rejected.md`.
6. **Close-out:** record the outcome + runbook in the owning doc; commit signed; merge/push per the session branch policy (unmerged `session/*` branches are the norm until the deploy-gate flips).
7. **Orchestrator discipline (2026-09-08 lesson):** for multi-step/multi-host/live-deploy changes, one parent co-ordinates bounded single-deliverable subagent lanes (pi-subagents); the parent holds final acceptance + runs validate-all. Timebox reviews (~10 min); a child exceeding that with no verdict is steered to wrap up.

**Ask-if-unsure:** planned/multi-host/deploy-gated/irreversible → orchestrator pattern; re-deciding → check owning doc + rejected log first; unsure of the owning doc → `docs/index.md` map.