---
title: Deployment — Rejected / Dropped Decision Log
role: log
domain: deployment
status: active
tags: [deployment, rejected, decision-log]
---
# Deployment — Rejected / Dropped

> **Role:** Append-only decision log — deploy-toolchain / VPS-host / hypervisor options the homelab evaluated and declined. Sorted by service name. This log is the per-domain **decision-log SSOT**.
> **Links to:** `deployment.md`
> **Linked from:** `index.md`, `deployment.md`

> ⚠️ **Append-only.** Never edit or reorder an entry after it lands. A changed decision is a **new appended entry** (do not strike/replace). Each row: `| <tool> | <rejected|dropped|superseded> | <date> | <why, 1–2 lines + evidence link> |`.
> ⚠️ **Evidence = the owning doc + this decision log.** Dates are the decision dates in the owning doc / git-attribution dates (advisory).

## Decisions

| Tool | Status | Date | Why |
|------|--------|------|-----|
| Contabo VPS | superseded | 2026-08-18 | Purchase superseded by the netcup RS 2000 G12 (cheaper/better suited as the public edge + live-data tier). · [subscription.md](subscription.md), [services-vps.md](services-vps.md) |
| Doco-CD | dropped | 2026-08-19 | Removed entirely — a 2nd (Docker-socket-agent) deploy path that could not safely cover public VPS services (`docker.sock:rw` = root-equivalent). Single path = Ansible. HD-150. · [deployment.md](deployment.md) |
| Proxmox (local hypervisor, Phase 1) | rejected | 2026-08-16 | oldsrv stays bare-metal Debian + Docker on the single Phase-1 box — VM/GPU-passthrough is mutually exclusive with the shared dGPU used by desktop + AI. Deferred to Phase 2 (HD-41/42). HD-92. · [hardware-oldsrv.md](hardware-oldsrv.md) |
| Phase-2 build — AMD Ryzen 9 9900X + Radeon AI PRO R9700 + Proxmox VE (~€4,449) | superseded | 2026-09-06 | **Superseded by the Lenovo ThinkStation PGX (NVIDIA GB10 Grace Blackwell) purchase** — hardware-spark node. More local-inference compute per €, no hypervisor layer, no AMD ROCm toolchain. Old `hardware-phase2.md` archived here + git. HD-335. · [hardware-spark.md](hardware-spark.md) |
| watchtower | rejected | 2026-08-18 | Deliberate no — would bypass the Ansible/Renovate gate + break primary/standby HA version parity; HA updates stay Renovate + `stable`. Revisit only if HA runs single-node. HD-39. · [deployment-renovate.md](deployment-renovate.md) |

> **Not a deployment-domain decision:** guest-network / storage / services rejections live in their own `<domain>-rejected.md` files — see [`services-rejected.md`](services-rejected.md), [`storage-rejected.md`](storage-rejected.md), [`network-rejected.md`](network-rejected.md), [`smart-home-rejected.md`](smart-home-rejected.md).
> **SSOT note:** this log is the decision-log SSOT for the deploy/hypervisor domain.