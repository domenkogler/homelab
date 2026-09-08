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

> Only items with a **real `⏳` tail in [todo.md](todo.md)** are listed. Done items are deleted from todo.md (record in owning docs + git history); anything marked done here must match todo.md's open rows.

- **HD-342 — Victoria stack deploy (VPS): ✅ LIVE CUTOVER COMPLETED 2026-09-08 (this session).** VictoriaMetrics (:8428) + VictoriaLogs (:9428) deployed; seeded `victoria-metrics_api`/`victoria-logs_api` (+ `kopia-server_fingerprint`); converged VPS (`docker_services,monitoring`); **Grafana datasources migrated to Victoria** (uid `prometheus`→VM, uid `loki`→VL via API-seed after removing the stale read-only Loki datasource; VL healthcheck bug fixed — tool-less image has no `wget`); **Alloy restarted** to load Victoria remote_write targets (it had been running the old config since Sep 3 — was the reason VM had no series); old `prometheus` + `loki` containers stopped; datasource healths OK, VM has 13 `up` series, alert rules evaluate with **0 errors**. ⏳ **Remaining tails:** kopia client wiring for `/srv/docker/victoria-*/data`, oldsrv MCP (HD-344). [observability.md](docs/observability.md) · [todo.md HD-342](todo.md)
- **HD-344 — MCP AI-debugging servers (oldsrv).** ⏳ oldsrv converge (Phase-3/HD-318) + VPS Victoria backend live (HD-342), then register MCP in pi/OWUI/OpenClaw + tailnet redo. [observability.md](docs/observability.md) §MCP
- **HD-318 — oldsrv Phase-3 provision (in progress).** ⏳ (a) kopia-agent crash-loop **VPS-gated (HD-318a)** — 1P `kopia-server_fingerprint` unseedable until VPS kopia-server leg converges; ⏳ (b) recyclarr profile-sync verify at next @daily run. [hardware-oldsrv.md](docs/hardware-oldsrv.md)
- **HD-311 — oldsrv dual-home tagged-99.** ⏳ apply the oldsrv tagged-99 sub-interface (deploy-gated on host provision). [network-vlans.md](docs/network-vlans.md)
- **HD-03 — inter-VLAN residual audit.** ⏳ final inter-VLAN matrix audit (Pkg B: HD-304/89/03 apply). [network-vlans.md](docs/network-vlans.md)
- **HD-302 — modem DNS record.** ⏳ add private split-horizon `modem.kogler.si` → `comtrend_modem.modem_mgmt_ip` to the technitium-seed loop (never Cloudflare). [network.md](docs/network.md) §Comtrend
- **HD-343 — Network Clients dashboard.** ⏳ owner verify: wifi registration-table vs legacy path, panels render after Victoria provision, `stats.kogler.si` shows it. [observability.md](docs/observability.md) §Network Clients Dashboard
- **HD-08 — UPS battery-pull test.** ⏳ owner manual test (feeds the HD-06/07 chain). [hardware-ups.md](docs/hardware-ups.md)

**Recent sessions (history — see owning docs/commits):** 2026-09-08 Victoria migration authored+merged (@`4ba5ac9`), oldsrv/nas/pi converges (HD-318b/c/343/08, `d476aba`), backlog sweep + worktree/branch cleanup (`9674f65`) — all merged to `main`, worktrees removed. Do not re-open; the commit history + docs hold the records.