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
- **Ansible-driven** — single deployment/upgrade path for BOTH VPS and oldsrv (idempotent, safe; no Docker-socket agent). Doco-CD is **dropped** (HD-150) — it was a 2nd path that couldn't safely deploy public VPS services (`docker.sock:rw` = root-equivalent).
- **Ansible for base deploys + every upgrade** (system-level one-time + app lifecycle reused).
- **Renovate proposes, Ansible applies** — Renovate opens Forgejo PRs; the **Forgejo Actions deploy button** (`workflow_dispatch`) runs Ansible to apply. Homepage is a dashboard/launcher (no deploy role).

---

## Deployment Tools

| Tool | Scope | When |
|------|-------|------|
| **Preseed** | OS installation (Debian) | Initial setup, disaster recovery |
| **Ansible** | Base system + ALL Docker lifecycle (single path, VPS + oldsrv) | Initial setup, DR, and every upgrade |
| **Forgejo Actions** | CI (tests) + the **deploy button** (`workflow_dispatch` → Ansible) | PR validation, apply merges |
| **Renovate** | Upstream version tracking → PRs | Automated, continuous |

---

## Deployment Flow (Third-Party Images)

```
Upstream release → Renovate (3-day hold) → Dependency Dashboard
    → Domen checks box → Renovate PR → Domen merges
    → Forgejo Actions deploy button (workflow_dispatch) → Ansible
        → docker compose up -d → deployed  (same path for VPS + oldsrv)
    → Post-deploy hooks: regenerate Homepage config, inventory docs
```

## Deployment Flow (Custom Apps — Fast Lane)

```
git push → (Forgejo Actions CI) → merge → deploy button → Ansible → deployed
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
│   │   ├── roles/                           # 12 roles (see deployment-ansible.md)
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
| **VPS** (remote Docker) | Forgejo Actions + Ansible | the deploy button runs Ansible; SSH is right tool |
| **nas** (no Docker) | Ansible (bootstrap only) | ZFS/NFS are system-level |

---

## Document Map

| For | Read |
|-----|------|
| Preseed + post_install spec | [`deployment-preseed.md`](deployment-preseed.md) |
| Ansible role catalog & spec | [`deployment-ansible.md`](deployment-ansible.md) |
| Docker compose conventions | [`deployment-compose.md`](deployment-compose.md) |
| 1Password secrets & philosophy | [`deployment-secrets.md`](deployment-secrets.md) |
| Renovate config | [`deployment-renovate.md`](deployment-renovate.md) |
| Security hardening posture | [`security.md`](security.md) |
| Backup & disaster recovery | [`backup.md`](backup.md) |
| ZFS storage layout & properties | [`storage.md`](storage.md) |
| Dashboard matrix | [`interfaces.md`](interfaces.md) |

## Related

- [Preseed & Post-Install Specification](deployment-preseed.md)
- [Ansible Specification](deployment-ansible.md)
- [Docker Compose Specification](deployment-compose.md)
- [Secrets Management & Passwordless Philosophy](deployment-secrets.md)
- [Deployment Review Queue](deployment-review.md)
- [Deployment Rejected / Dropped (decision log)](deployment-rejected.md)
- [Renovate Bot — Update Lifecycle](deployment-renovate.md)
- [Security Hardening Posture](security.md)
- [Backup & Disaster Recovery](backup.md)
- [ZFS Storage Layout & Properties](storage.md)
- [Interface Matrix — Dashboards & Management](interfaces.md)
