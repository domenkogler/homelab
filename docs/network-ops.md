---
title: Network Operations — Router Config Storage
role: detail
domain: network
status: active
tags: [network, routeros, ops]
---
# Network Operations — Router Config Storage

> **Role:** Detail — where RouterOS configuration lives, versioning, change workflow.
> **Links to:** `network.md`, `network-vlans.md`
> **Linked from:** `network.md`, `index.md`

---

## Router Config Lifecycle

1. **Factory reset** → import `IaC/router/rb4011_initial.rsc` via WinBox (baseline)
2. **Ansible `router` role** takes over — all subsequent changes via REST API
3. **Optional:** after manual WinBox changes, export a snapshot as
   `IaC/router/rb4011_live.rsc` for documentation (not yet created)

Source of truth: `rb4011_initial.rsc` + the `router` Ansible role. The live export is documentation-only and not required for operations.
