---
title: GitOps Deployment
role: broad
domain: deployment
status: active
tags: [deployment, gitops, doco-cd]
---
# GitOps Deployment

> **Role:** Broad context — deployment philosophy, Doco-CD flow, tool choices.
> **Links to:** `deployment-preseed.md`, `deployment-ansible.md`, `deployment-compose.md`, `deployment-secrets.md`, `deployment-renovate.md`, `interfaces.md`
> **Linked from:** `index.md`

---

## Architecture Philosophy

- **Database-free, pure GitOps** — all config, versions, and docs are plain text in Git
- **One Git repo** — IaC code + technical docs + family guides together
- **Doco-CD driven** ⚠️ WIP — Docker deployments automated via GitOps (watches repo, deploys on change). Not yet activated; Ansible handles all deployment until Doco-CD is configured.
- **Ansible for OS bootstrap only** — system-level provisioning one-time. App lifecycle is GitOps.
- **Forgejo Actions for CI + VPS fallback** — CI tests on PR, CD fallback for remote VPS

---

## Deployment Tools

| Tool | Scope | When |
|------|-------|------|
| **Preseed** | OS installation (Debian) | Initial setup, disaster recovery |
| **Ansible** | Base system (Docker, GPU, ZFS, Doco-CD install) | Initial setup, disaster recovery |
| **Doco-CD** | Docker container lifecycle (primary CD) ⚠️ WIP — not yet activated | Day-to-day: merge → deploy |
| **Forgejo Actions** | CI (tests) + VPS CD fallback | PR validation, remote deploy |
| **Renovate** | Upstream version tracking | Automated, continuous |

---

## Deployment Flow (Third-Party Images)

```
Upstream release → Renovate (3-day hold) → Dependency Dashboard
    → Domen checks box → Renovate PR → Domen merges
    → Doco-CD detects merge → docker compose up -d → deployed
    → Post-deploy hooks: regenerate Homepage config, inventory docs
```

## Deployment Flow (Custom Apps — Fast Lane)

```
git push → Doco-CD webhook → docker compose build + up → deployed <5 min
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
├── .doco-cd.yml                             # Doco-CD deployment config
└── renovate.json                            # Renovate Bot config
```

---

## Target Matrix

| Target | CD Tool | Why |
|--------|---------|-----|
| **oldsrv** (local Docker) | Doco-CD | Fast, drift-correcting, no SSH |
| **Proxmox VM** (local Docker) | Doco-CD | Same container, portable |
| **VPS** (remote Docker) | Forgejo Actions + Ansible | No socket access; SSH is right tool |
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
| Dashboard matrix | [`interfaces.md`](interfaces.md) |

## Related

- [Preseed & Post-Install Specification](deployment-preseed.md)
- [Ansible Specification](deployment-ansible.md)
- [Docker Compose Specification](deployment-compose.md)
- [Secrets Management & Passwordless Philosophy](deployment-secrets.md)
- [Renovate Bot — Update Lifecycle](deployment-renovate.md)
- [Interface Matrix — Dashboards & Management](interfaces.md)
