# Network Redo + Cleanup — Orchestrator Plan (2026-08-24)

Worktree: `homelab-wt-20260824-0958` · Branch: `cleanup-netredo-20260824-0958`
Owner decisions: Q0=Option A · R-2 D1/D2/D3 approved · CAPsMAN=rsc modern wifi-qcom-ac ·
Renovate re-enable = file-edit only (other session runs playbooks) · headplane/headscale = SEPARATE session (do not touch).

## Roster

| # | Task | Deliverable | Diff | State |
|---|------|-------------|------|-------|
| R-1 | Reconcilation Option A + Pi-DNS | decision artifact + all.yml/host_vars/inventory/docs | 4 | ✅ committed `7a29199` |
| R-2 | Reservations from inventory + switch-map fixes | network_static_hosts + router loop + switch.yml + render | 2 | ✅ committed `3167885` |
| 1 | file.kogler.si editor round-trip verify | verify report (collab svc, WOPI, JWT both sides, CSP) | 2 | ✅ committed `f1d75b8` (owner round-trip = only remaining gate) |
| 2 | Switch completeness (switch_port_map SSOT from Rack.canvas) | filled SSOT + role de-gap + validate | 4 | ✅ committed `231c564` (VLAN 20/21 blocks + nas-eno→Home) |
| 3 | Firewall matrix verification plan | e2e test script (cross-VLAN, Kids bedtime, forced DNS) | 3 | ⬜ |
| 4 | Conflict cleanup (HD-207 dup, AP-dnevna dup, todo §1 stale, deploy-gated trim) | curated todo/changelog/inventory | 2 | ⬜ (AP-dnevna dup part done in R-1) |
| 5 | Renovate re-enable (file-edit only, no playbook) | flip flag + deployment-renovate.md refresh | 2 | ⬜ |
| 6 | Migration-inventory refresh (read-only live probes) | updated inventory + unknowns | 3 | ⬜ |
| 8 | CAPsMAN-wifi-qcom plan (rsc + retire wAP + docs + hw gate) | rsc templates + render playbook + docs | 4 | ⬜ |

## Validation convention
9P gate before any playbook (none run here). Validators/`$?` bare (pipe-masking law).
`scripts/validate*.py` + `check_*.py` green before commit. Journal+changelog in same change. No rendered/ committed. No IP literals in prose (check_doc_ips). headplane/headscale untouched.

## Checkpoints
- R-1, R-2 done (no human gate needed — D1/D2/D3 pre-approved).
- Task 8 ships hardware gate (dnevna swap + garage replacement wifi-qcom-ac-capable) — human at cutover.
- Other-session coordinates the live Renovate playbook from our file edit.