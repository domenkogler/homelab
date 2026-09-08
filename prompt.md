> **Role:** entry point for the next session. This handoff is a **pointer index** — every item's owning doc/row holds the detail. Start with README.md §0 (intent routing), then §1 context, then §3 execution order. Read [todo.md](todo.md) for the full row bodies.

> **Linked from:** [README.md](README.md) §0/§2 · [CONVENTIONS.md](CONVENTIONS.md) §4/§6 · [scripts/guard-session.sh](scripts/guard-session.sh) · [todo.md](todo.md) · archive: [reports/changelog.md](reports/changelog.md), [reports/deployment-journal.md](reports/deployment-journal.md).

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §6 worktree discipline (**MECHANICALLY** enforced by `scripts/guard-session.sh` + validate-all hard-gate), §4 journal loop + close-out items, §2 secret-output hygiene, §5 service-onboarding checklist.
2. [docs/deployment-ansible.md](docs/deployment-ansible.md) — §Tags & surgical runs (`docker_services_scope`, `base` tier) + §Deploy Timing Runbook.
3. [docs/deployment-compose.md](docs/deployment-compose.md) + [docs/deployment-secrets.md](docs/deployment-secrets.md) — compose/secret conventions + fail-loud rule.
4. [docs/network-vpn.md](docs/network-vpn.md) — §Pattern A tailnet sidecars + current tailnet edge state + §MagicDNS (extra_records design).
5. Owning `docs/*.md` (per task) — the decision-logs + spec SSOT; read before re-deciding anything. Historical changelog/journal rows live in the frozen `reports/changelog.md` / `reports/deployment-journal.md` (archive-only).

## 1. Environment (WSL Debian primary, ext4) — as of #67, the repo runs from the WSL Debian primary on ext4 (not Windows)

Adapted to the WSL Debian primary (repo moved to ext4; the Windows-runner/9P-gate era is legacy — see "9P gate: N/A" in §4). `python3`/bash/LF/UTF-8 no-BOM. Secrets → 1Password item.field only, `>-` for YAML renders. **Self-learned (2026-08-26):** do NOT use multi-line bash heredocs with backslashes/backticks (mangled through `bash -c`) — write patch scripts to a temp file and run them. **Signed-commit gotcha (still valid):** keys in `~/.ssh/github_signing`/`github_auth`; `Couldn't find key in agent` → `ssh-add ~/.ssh/github_signing ~/.ssh/github_auth`.

## 2. Current open work (handoff state — next session starts here)

> Pointer index only: each open HD links its owning-doc status block (the SSOT) and its
> [todo.md](todo.md) row (the registry — a row is deleted when fully done, §4(a)).
> For "what to do next" also see [todo-table.md](todo-table.md) (planning view: AI-runnable vs owner-blocked).
>
> **2026-09-08 Mgmt-99 direct cleanup:** the laptop/WSL now reaches the Mgmt VLAN **directly** via the Windows
> Mgmt99 vNIC (`wsl-nat-resolv.ps1 -EnableMgmt99`) — SSH aliases `router`/`switch`/`oldsrv`/`pi99` are **direct
> (no ProxyJump `pi`)**, the hop aliases (`pi99`-via-`pi`, `router99`, `oldsrv99`, `nas99`) were removed + deduped,
> HD-33/26/303/311 closed. `ansible-network-hop.sh` is kept but **obsolete** (scripts/README). `pi`/`pi99` are the
> one dual-leg exception.

| HD | Open item (one line) | Detail SSOT |
|----|----------------------|-------------|
| HD-342 | Victoria stack deploy (VPS) LIVE; remaining tails: kopia client wiring for Victoria data, oldsrv MCP (HD-344) | [observability.md](docs/observability.md) · [todo.md HD-342](todo.md) |
| HD-344 | MCP AI-debugging servers on oldsrv (register in pi/OWUI/OpenClaw + tailnet redo) | [observability.md](docs/observability.md) §MCP · [todo.md HD-344](todo.md) |
| HD-318 | oldsrv Phase-3 provision — **kopia-agent DONE + LIVE 2026-09-08 (HD-318a):** agent Up over HTTPS+fingerprint, snapshots flowing; remaining = recyclarr @daily verify | [hardware-oldsrv.md](docs/hardware-oldsrv.md) · [todo.md HD-318](todo.md) |
| HD-03 | Inter-VLAN residual audit + Kids forced-DNS/Home-drop live-verify | [network-vlans.md](docs/network-vlans.md) · [todo.md HD-03](todo.md) |
| HD-343 | Network Clients dashboard — owner verify (wifi path, panels, stats.kogler.si) | [observability.md](docs/observability.md) §Network Clients Dashboard · [todo.md HD-343](todo.md) |
| HD-315 | Grafana dashboard render-verify with data (**data now flowing** — all 4 hosts + probes; owner visual verify) | [observability.md](docs/observability.md) §Dashboards · [todo.md HD-315](todo.md) |
| HD-345 | `ifOperStatus` SNMP series still 0 in VM (rules live, noDataState OK; SNMP now enabled — walk not yet arriving) | [observability.md](docs/observability.md) · [todo.md HD-345](todo.md) |
| HD-08 | UPS battery-pull test (owner manual; feeds HD-06/07) — **ready 2026-09-08:** all three NUT legs (nas/oldsrv/pi) healthy ("#"-in-gen_pw bug fixed; passwords rotated #-free; POWERDOWNWAIT removed) | [hardware-ups.md](docs/hardware-ups.md) · [todo.md HD-08](todo.md) |

**Recent sessions (history — see owning docs/commits):** 2026-09-08 Victoria migration authored+merged (@`4ba5ac9`), oldsrv/nas/pi converges (HD-318b/c/343/08, `d476aba`), backlog sweep + worktree/branch cleanup (`9674f65`), **observability fix+deploy session (HD-346): per-node Alloy on all 4 hosts (vps/oldsrv/nas/pi) live + Host Overview populated; MikroTik SNMP RO enabled on router+switch (HD-53) + consolidated `fixboot`; blackbox probe family fixed; nas eno2/ether9 route fix; n8n router API user provisioned (HD-312(4))** — all merged to `main`, worktrees removed. Do not re-open; the commit history + docs hold the records.

**HD-318a/kopia + platform/secrets session (2026-09-08, `94f6231` + `98d4720`):** kopia-agent auth fixed end-to-end (htpasswd user@host entries + repo-user provisioned with the repo master password + compose `$$`-escaping) — agent **LIVE + snapshotting**; HD-134 matrix pinned `v1.9.0`; HD-59 `prometheus-internal_api` retired (Victoria); HD-286 vault-escape comments; HD-218 re-sample (zero residue, orphaned loki/prom/renovate removed); HD-211 Authentik expiring=False audit passed. todo.md/todo-table.md updated at close-out.

**Storage/UPS session (2026-09-08, `20c2b1d`/`5e7043f`):** NUT — `gen_pw` excluded `#` (NUT comment char broke every upsmon MONITOR line in 2.8.1); `nut_password`/`nut-exporter_password` rotated #-free; POWERDOWNWAIT dropped; nas/oldsrv/pi `nut-monitor` all active again (`upsc powerwalker@nas.kogler.si` → OL/100%). Kopia — oldsrv agent re-rendered with per-client htpasswd identity + first snapshots landed (opt 1.3GB/5648f, dumps, immich-upload, signal-cli-data); HD-191 first-snapshot phase done (⏳ restore drill + volume-name pin remains open), HD-220 kopia-seed phase resolved (⏳ renovate token check remains owner). Battery-pull test ready for owner (HD-08/HD-06).
