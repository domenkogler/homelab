# Next Session — Where to Start & What's Next

> Handoff written **2026-08-19** at the end of the HD-153 + OpenCloud-storage session.
> Read this first, then `todo.md` §0 (lifecycle) + §3c (deploy-gated checklist), then `deployment-tasks.md` (build order).

---

## 1. FIRST: commit the uncommitted working tree

**Nothing from the last two sessions is committed yet.** `git status` shows ~27 modified files + 7 staged deletions. All of it is coherent, validated work; do **not** re-derive it.

```
git status          # expect: 27 modified + 7 deleted (D staged)
bash scripts/validate-all.sh   # must be green before commit
git add -A
git commit          # 2 logical commits:
#  a) "docs(audit): fold audit deliverables + delete root audit files (HD-153)"
#     → CONVENTIONS.md, IaC/README.md, README.md, changelog.md, deployment-tasks.md,
#       docs/security.md (§8–9 new), docs/index.md, docs/interfaces.md, docs/observability.md,
#       docs/services*.md, docs/smart-home*.md, docs/hardware-oldsrv.md, docs/storage-zfs.md,
#       todo.md (HD-154…165 rows), + the 7 deleted audit files
#  b) "docs(storage): OpenCloud user files → live Hetzner Box, NAS dataset = archive (HD-135/151)"
#     → docs/storage-zfs.md, docs/services.md, docs/hardware-nas.md, docs/backup.md,
#       docs/ai-stack.md, docs/subscription.md, todo.md (HD-151 row)
```

Housekeeping rules (CONVENTIONS.md): `validate-all.sh` green before commit; update `todo.md` in the same change; **no hand-maintained tally/Status line** (removed — counts are derived).

> ⚠ Two stray zero-byte files exist in repo root: `**Linked` and `**Role:**` (untracked, from an earlier accidental redirect). Safe to `rm` them — they are not referenced anywhere.

---

## 2. State of the world (what the last session did)

**HD-153 (audit consolidation) — DONE, closed in changelog:**
- 7 root audit files deleted (`docs-vs-iac.md`, `docs-changes.md`, `iac-changes.md`, `conventions-proposal.md`, `lifecycle-docs-proposal.md`, `architecture.md`, `security.md`) — preserved in git `4b20b59`.
- Durable content folded into canonical docs (MinIO→CIFS, observability→VPS, index map, role-catalog owner, README interfaces, CONVENTIONS §7/§8 rules, security.md §8–9).
- **12 new backlog rows from audit actionables: HD-154 … HD-165** (VPS hardening, tunnel ACL, all.yml split, linting, etc. — see §4 below).

**OpenCloud storage correction (requested live this session):**
- OpenCloud user files now documented as **live Hetzner Box (WebDAV/CIFS)**, **not NAS** — matching Immich originals (HD-135).
- NAS `tank/data/documents` + `bulk/data/documents` = **retained archive only** (orphan, same class as `immich`), trim decision tracked in **HD-151**.
- Updated: storage-zfs.md (SSOT), services.md, hardware-nas.md, backup.md, ai-stack.md, subscription.md, deployment-tasks.md (already correct), todo HD-151.

**Open items still open (top of backlog):** see §4.

---

## 3. Where to start next (recommended order)

The repo is in **planning phase — nothing is deployed live yet** (VPS bought+provisioned, home hosts unprovisioned). The next *real* milestone is **Phase 1 (VPS public edge)** per `deployment-tasks.md`, but several **cheap, high-value, deploy-gated-prep items** can be done from the laptop *now*.

**Suggested first tasks (all laptop-doable, no hardware):**

1. **HD-156 — Split `group_vars/all.yml` version pins → `versions.yml`** (P2, AI, 3h)
   All `*_version` pins (~30) live in `all.yml` today; Renovate + version review should be single-file.
   New `IaC/ansible/group_vars/versions.yml`; keep infra in `all.yml`; update `deployment-compose.md`, `CONVENTIONS.md` §7, `IaC/README.md`, and the validator mocks (`validate-docker-services.py` BASE_CTX). **Biggest maintenance win available now.**

2. **HD-157 — Add `validate-secrets.py` + doc-map/count lint to `validate-all.sh`** (P2, AI)
   (a) literal-credential grep over group_vars/templates; (b) `docs/index.md` map vs `find docs -name '*.md'`; (c) template-count lint vs `docker_services/`. Turns docs-drift into a lint failure.

3. **HD-164 — Annotate the `kopia` role as retained stub + expiry note** (P4, 15 min) — `IaC/README.md` one-liner so a future agent doesn't "finish" it.

4. **HD-165 — Document per-gear routeros credentials (RB4011 / CRS328 / hAP)** (P4) — `deployment-secrets.md`: note that `mikrotik-admin_login` is one item; distinct devices may need distinct passwords.

5. **HD-158 — `network-addresses.md` = IP-SSOT only until `switch_port_map` verified** (P2) — gate `render_rack_connections.py` physical-port output behind `switch_port_map_verified: true`.

After those, the deploy-track work begins (needs live hosts + 1Password items — **human gate**):
- **HD-154 (VPS host hardening checklist)** + **HD-40A (run VPS playbook)** — Phase 1. Human checkpoint.
- **HD-149 (verify Authentik OIDC blueprint on 2026.5.6)** — the highest-risk live-verify; blocks HD-147.
- **HD-147 (live deploy-verify all 8 OIDC clients)** — depends on 142→148 + VPS provisioned.

---

## 4. Open backlog (from todo.md §2 — the 5 highest-priority items by module)

| ID | P | Exec | Item | Notes |
|----|---|------|------|-------|
| HD-03 | 1 | AI+gate | **Network redo: VLAN segmentation** — IaC done, NOT deployed; WG VPS peer pubkeys + tunnel bring-up live | Blocks HD-135/155 |
| HD-135 | 2 | AI+gate | **VPS/oldsrv service split** — IaC matrices applied; remaining: WG pubkeys, live-Box CIFS mount, live-verify | Phase 1 |
| HD-141 | 1 | AI+gate | **(epic) Authentik OIDC provisioning** — Blueprint + secret-egress glue (A–F subtasks 142–147) | Big epic, mostly IaC-done |
| HD-154 | 1 | AI+gate | **VPS host hardening checklist** (fail2ban, sshd knobs, container caps, deny-all inbound) | New (from audit); folds into Phase 1 |
| HD-155 | 1 | AI+gate | **VPS→home tunnel least-access ACL + fail-loud WG gate** | New (from audit); security-critical |
| HD-151 | 2 | AI | **Trim orphan datasets** (tsdb/immich/postgres/documents) — now also covers `documents` | Doc+IaC decision |
| HD-156 | 2 | AI | **all.yml → versions.yml split** | Best laptop task |

Full list: `todo.md` §2 (105 active open rows) + §3c (28 deploy-gated live-verify rows — the one-screen "what's not live yet" view).

---

## 5. Guardrails / context for the next agent

- **Nothing is deployed.** Every "✅ IaC done" row still carries a **⏳ deploy-gated** tail — do not read design docs as live state. `docs/services-vps.md`, `docs/observability.md`, `docs/smart-home.md` carry explicit "not live" banners.
- **Single deploy path = Ansible only** (HD-150): Renovate PR → Forgejo Actions button → Ansible. Doco-CD is dropped. No watchtower (HD-39).
- **SSOT chain:** `group_vars/*` → render (`render-docs.yml`) → generated docs (`network-addresses.md`, `inventory.md` — never hand-edit). `docs/services.md` = service catalog. `docs/storage-zfs.md` = storage SSOT. `docs/security.md` = security law (incl. new §8–9).
- **Conventions:** `CONVENTIONS.md` is the rule index (derived counts, data-location same-change rule, two-sided deploy gate, version-pin hygiene §7). `validate-all.sh` green before commit.
- **Secrets:** 1Password `Homelab` vault only, `lookup('community.general.onepassword', …)` at render, no literals, no `default('')` (fail-loud, HD-65).
- **New HD IDs:** next free = **HD-166**.
- **Environment:** Ansible runs in **WSL Debian** (`wsl.exe -d Debian`, `~/ansible-venv`); `op` (1Password) on the Windows host; Windows 11 host.
- **HD-151 scope note:** the `storage` role still *creates* the orphan datasets — decide trim vs repoint *before* first NAS deploy (Phase 2) to avoid creating them.

---

## 6. Quick reference

- Backlog: `todo.md` (105 active open rows · 0 decisions · 1 purchase · 10 parked — counts are derived, no hand tally)
- Build order: `deployment-tasks.md` (Phase 0 laptop → Phase 1 VPS → 1.5 network → 2 nas → 3 oldsrv → 4 pi → 5 GitOps → 6 observability → 7 smart home → 8 backup → 9 docs)
- Deploy-gated live-verify: `todo.md` §3c
- Decisions log: `changelog.md`
- Storage architecture: `docs/storage-zfs.md` (§Service↔Storage Placement = VPS-era truth)
- Secrets master list: `docs/deployment-secrets.md`
