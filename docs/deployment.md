---
title: GitOps Deployment
role: broad
domain: deployment
status: active
tags: [deployment, gitops, ansible, renovate, forgejo-actions]
---
# GitOps Deployment

> **Role:** Broad context — deployment philosophy, deploy flow, tool choices.
> **Links to:** `deployment-preseed.md`, `deployment-ansible.md`, `deployment-compose.md`, `deployment-secrets.md`, `deployment-renovate.md`, `interfaces.md`
> **Linked from:** `index.md`

---

## Architecture Philosophy

- **Direction of truth:** IaC is the source of truth for **values** (IPs, VLANs, host vars, service lists) — they render INTO docs (`network-addresses-generated.md`, `services-inventory-generated.md`). The `deployment-*` specs are **authoring guides** used to write/correct the IaC, not runtime inputs. See `deployment-ansible.md`.
- **Database-free, pure GitOps** — all config, versions, and docs are plain text in Git
- **One Git repo** — IaC code + technical docs + family guides together
- **Ansible-driven** — single deployment/upgrade path for BOTH VPS and oldsrv (idempotent, safe; no Docker-socket agent, no `docker.sock:rw` root-equivalent surface on any target).
- **Ansible for base deploys + every upgrade** (system-level one-time + app lifecycle reused).
- **Renovate proposes, Ansible applies** — Renovate opens PRs on the git surface its platform points at; an
  apply is an **Ansible run from the control node** — no deploy button (`workflow_dispatch`) exists on either
  git surface, because no runner is installed. Homepage is a dashboard/launcher (no deploy role).

---

## Deployment Tools

| Tool | Scope | When |
|------|-------|------|
| **Preseed** | OS installation (Debian) | Initial setup, disaster recovery |
| **Ansible** | Base system + ALL Docker lifecycle (single path, VPS + oldsrv) | Initial setup, DR, and every upgrade |
| **CI** | **runs on neither git surface today**: no runner is installed on any host and GitHub reports 0 workflows for the repo (the only workflow file in the tree sits in a nested path GitHub never reads) | the local `scripts/validate-all.sh`, before commit |
| **Renovate** | Upstream version tracking → PRs | Automated, continuous |

---

## Deployment Flow (Third-Party Images)

```
Upstream release → Renovate (3-day hold) → Dependency Dashboard
    → Domen checks box → Renovate PR → Domen merges
    → Ansible apply from the control node (no deploy button exists on either git surface)
        → docker compose up -d → deployed  (same path for VPS + oldsrv)
    → Post-deploy hooks: regenerate Homepage config, inventory docs
```

## Deployment Flow (Custom Apps — Fast Lane)

```
git push → merge → Ansible apply from the control node → deployed   (no CI runs on either git surface)
```

---

## Repository Layout

```
./
├── IaC/                                    # Infrastructure as Code
│   ├── ansible/                             # Ansible playbooks, roles, templates
│   │   ├── site.yml                         # Master playbook
│   │   ├── inventory.ini                    # Host groups
│   │   ├── group_vars/                      # Per-group variables
│   │   ├── host_vars/                       # Per-host variables
│   │   ├── playbooks/                       # Per-group playbooks
│   │   ├── roles/                           # role catalog — see deployment-ansible.md (count derived from the directory)
│   │   └── templates/                       # docker-compose + homepage + inventory
│   ├── host/                                # OS configs
│   │   ├── post_install.sh                  # Shared bootstrap — single copy for all hosts
│   │   └── nas/                            # preseed.cfg (sample)
│   └── router/                              # RouterOS .rsc files
│
├── docs/                                    # This documentation
└── renovate.json                            # Renovate update config
```

---

## Target Matrix

| Target | Deploy tool | Why |
|--------|-------------|-----|
| **oldsrv** (local Docker) | Ansible | single path; SSH into host, no Docker-socket agent |
| **Proxmox VM** (local Docker) | Ansible | same, portable |
| **VPS** (remote Docker) | Ansible | SSH into the host; no runner-backed deploy button exists on either git surface |
| **nas** (no Docker) | Ansible (bootstrap only) | ZFS/NFS are system-level |

---

## Document Map

| For | Read |
|-----|------|
| Preseed + post_install spec | [`deployment-preseed.md`](deployment-preseed.md) |
| Ansible role catalog & spec | [`deployment-ansible.md`](deployment-ansible.md) |
| Docker compose conventions | [`deployment-compose.md`](deployment-compose.md) |
| Authentik OIDC provisioning (Blueprint + glue) | [`deployment-oidc.md`](deployment-oidc.md) |
| 1Password secrets & philosophy | [`deployment-secrets.md`](deployment-secrets.md) |
| Renovate config | [`deployment-renovate.md`](deployment-renovate.md) |
| Security hardening posture | [`security.md`](security.md) |
| Backup & disaster recovery | [`backup.md`](backup.md) |
| ZFS storage layout & properties | [`storage.md`](storage.md) |
| Dashboard matrix | [`interfaces.md`](interfaces.md) |
| Deployment ledger (plan + progress) | [`../deployment-tasks.md`](../deployment-tasks.md) |
| Deployment as-built (frozen archive, pre-2026-09-01) | [`../reports/deployment-journal.md`](../reports/deployment-journal.md) |
| Deployment runbook (redeploy procedure, true zero → live) | [`../deployment-manual.md`](../deployment-manual.md) |

---

## Phase numbering across the ledger and the runbook

**The invariant:** the `## Phase <n>` headings of [`../deployment-tasks.md`](../deployment-tasks.md)
(the ledger) and [`../deployment-manual.md`](../deployment-manual.md) (the runbook) name the SAME
work — "Phase 4b" is one machine and one procedure, not two. Both documents state it: the ledger's
phase blocks are the plan, and the runbook's charter line says its phase numbering follows the ledger
exactly. One exception is allowed by design: the runbook orders a true-zero rebuild in the order the
steps must be pressed, so it may number a phase the ledger carries as a step inside another phase —
and that exemption is a single documented value, `Phase 0.5` (the VPS re-provisioning, which the
ledger folds into its Phase 1 steps). Rule and owning doc: [CONVENTIONS.md](../CONVENTIONS.md) §4.

**How it is enforced, and what the enforcement cannot see:**
[`../scripts/gate/check_runbook_purity.py`](../scripts/gate/check_runbook_purity.py) compares the two
documents' phase headings (`phase-alignment`, run by `scripts/validate-all.sh`). Its capture admits a
digit, an optional `.N`, and a trailing `a` or `b` — nothing else. A phase heading written with any
other suffix is therefore not compared in EITHER direction: it is not reported as an orphan, and it
is not counted in the phase total the verdict prints, so `OK: … N phases aligned with the ledger` can
be true of a runbook that numbers more phases than the sentence claims. The exemption set cannot
rescue such a heading either, because it lists `0.5` only. The checker's `--self-test` carries a
**KNOWN-LIMITATION** arm that asserts precisely this blindness, so it turns RED if the capture is
ever widened without the record — this paragraph, that checker's comment and the
[`../scripts/README.md`](../scripts/README.md) row — being updated in the same change. So a phase this
gate cannot see is a phase nobody agreed to: read both documents directly (`grep -n '^## Phase'` in
each) whenever a phase number outside that shape appears, and treat a divergence as open work.

## Related

- [Preseed & Post-Install Specification](deployment-preseed.md)
- [Ansible Specification](deployment-ansible.md)
- [Docker Compose Specification](deployment-compose.md)
- [Authentik OIDC Provisioning](deployment-oidc.md)
- [Secrets Management & Passwordless Philosophy](deployment-secrets.md)
- [Deployment Review Queue](deployment-review.md)
- [Deployment Rejected / Dropped (decision log)](deployment-rejected.md)
- [Renovate Bot — Update Lifecycle](deployment-renovate.md)
- [Security Hardening Posture](security.md)
- [Backup & Disaster Recovery](backup.md)
- [ZFS Storage Layout & Properties](storage.md)
- [Interface Matrix — Dashboards & Management](interfaces.md)
