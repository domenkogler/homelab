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

| HD | Open item (one line) | Detail SSOT |
|----|----------------------|-------------|
| HD-342 | Victoria stack deploy (VPS) LIVE; remaining tails: kopia client wiring for Victoria data, oldsrv MCP (HD-344) | [observability.md](docs/observability.md) · [todo.md HD-342](todo.md) |
| HD-344 | MCP AI-debugging servers on oldsrv (register in pi/OWUI/OpenClaw + tailnet redo) | [observability.md](docs/observability.md) §MCP · [todo.md HD-344](todo.md) |
| HD-318 | oldsrv Phase-3 provision in progress (kopia-agent VPS-gated; recyclarr @daily verify) | [hardware-oldsrv.md](docs/hardware-oldsrv.md) · [todo.md HD-318](todo.md) |
| HD-311 | oldsrv dual-home tagged-99 sub-interface apply | [network-vlans.md](docs/network-vlans.md) · [todo.md HD-311](todo.md) |
| HD-03 | Inter-VLAN residual audit + Kids forced-DNS/Home-drop live-verify | [network-vlans.md](docs/network-vlans.md) · [todo.md HD-03](todo.md) |
| HD-343 | Network Clients dashboard — owner verify (wifi path, panels, stats.kogler.si) | [observability.md](docs/observability.md) §Network Clients Dashboard · [todo.md HD-343](todo.md) |
| HD-08 | UPS battery-pull test (owner manual; feeds HD-06/07) | [hardware-ups.md](docs/hardware-ups.md) · [todo.md HD-08](todo.md) |

**Recent sessions (history — see owning docs/commits):** 2026-09-08 Victoria migration authored+merged (@`4ba5ac9`), oldsrv/nas/pi converges (HD-318b/c/343/08, `d476aba`), backlog sweep + worktree/branch cleanup (`9674f65`) — all merged to `main`, worktrees removed. Do not re-open; the commit history + docs hold the records.
