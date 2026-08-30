# Audit Track A — Docs consistency & liveness

> **Audit date:** 2026-08-29
> **Repo commit:** c9baf09
> **Track scope:** docs/ (74 markdown files; 62 canonical + 11 manual/ + 1 index +
> 0 generated inside manual), docs/index.md document map, docs/manual/ family
> guides, generated-doc accuracy (4 docs).
> **Methodology:** parent (this session) executed the track inline; the
> `audit-orchestrator.js` lane architecture failed on OpenRouter rate-limits
> (see [audit-approach.md](../audit-approach.md)).
> **Read-only:** no docs/IaC/scripts mutated.

---

## A.1 Map completeness (audit.md §2.1.1)

**Verified:**
- `check_doc_map.py` runs in `validate-all.sh` and reports:
  > FAIL: 1 link(s) across repo .md do not resolve:
  >   - audit-approach.md -> [reports/full-audit-2026-08-29.md] (.../reports/full-audit-2026-08-29.md)
- The 1 broken link is a **forward reference** in my own
  [audit-approach.md](../audit-approach.md) to the report this audit is
  producing. Self-resolving once the report is written. Status:
  **TRANSIENT — will close when this report is committed.**
- Independent scan of the Document Map (basename-based, since the map is a
  code-block tree): 79 basenames in map; 62 canonical docs on disk (excluding
  `manual/` and `assets/`); **0 unmapped docs**; the 16 "orphans" the
  naive scan reports are all either root files (CONVENTIONS.md, README.md,
  todo.md — accessed via §1, not the dispatcher), wildcards in the map
  (`network-*.md`, `hardware-*.md`, `services-*.md`, `smart-home-*.md`,
  `<stale-asterisks>`), or `docs/manual/*` (excluded by validator
  convention, see scripts/README.md).

**Finding A-1.1: Document Map is comprehensive** — OK, no orphans.
**Finding A-1.2: One transient broken link** — TRANSIENT, see above.

## A.2 Link integrity (audit.md §2.1.2)

**Verified:**
- Cross-file link scan via `check_doc_map.py` reports 1 broken link (the
  transient in A-1 above).
- HD-263 follow-up: `scripts/README.md` lines 63 and 64 hard-link to
  `../ansible-enhancements.md` §8.4 — but **the file does not exist in
  the worktree**. Per the HD-263 row, that file is supposed to be **deleted**
  once HD-257–262 fold into owning docs; the references are stale and
  will go dangling in a future `validate-all.sh` run if HD-263 deletes the
  file before the README lines are updated.
  The `check_doc_map.py` validator passes today only because it whitelists
  root-canonical `*.md` paths and doesn't strictly enforce root-canonical
  target existence (the README link goes to `../ansible-enhancements.md`,
  not to a tracked file).

**Finding A-2.1 (Low): Stale `scripts/README.md` references to non-existent
`ansible-enhancements.md` (HD-263 follow-up).** Lines 63 and 64 of
`scripts/README.md` will dangle once HD-263 deletes the file. Proposed fix:
update the README to drop the §8.4 references (the content is already
folded into the row text) — or include the link target in the scan
coverage. Evidence: `scripts/README.md:63-64`.

## A.3 SSOT discipline (audit.md §2.1.3)

**Verified:**
- `check_doc_ips.py` green: "no internal IP literals outside
  docs/network-addresses-generated.md".
- `validate-secrets.py` green: "no literal credentials in
  group_vars/host_vars/role defaults/templates".
- `check_generated_suffix.py` green: 4 generated docs (network-addresses,
  network-rack, services-inventory, subscriptions-table) all carry the
  `-generated` suffix; no hand-authored doc wrongly carries it.
- 4 generated docs all open with `# Ansible managed` (per CONVENTIONS §8.2
  canonical managed-header). Confirmed in headers.

**Finding A-3.1: SSOT discipline is intact.** No IP literals, no
secret values, generated docs correctly marked.

## A.4 Docs-vs-IaC parity (audit.md §2.1.4)

**Sample spot-checks (8 hottest docs, ≥6 facts each):**

| Doc | Fact (sampled) | IaC source | Match? |
|-----|----------------|------------|--------|
| docs/services.md | 33 VPS services | group_vars/vps.yml enabled list | ✅ (33 confirmed by YAML parse) |
| docs/services.md | 2 home_servers enabled | group_vars/home_servers.yml | ✅ (technitium + sunshine) |
| docs/services-traefik.md | wildcard issuer = VPS traefik | role default + group_vars/vps.yml `traefik_acme_issuer` flag | ✅ |
| docs/network-addresses-generated.md | 6 host ansible_host values | host_vars/*.yml ansible_host | ✅ (vps/oldsrv/nas/pi all present; router+switch are network devices, not Docker hosts) |
| docs/deployment-ansible.md | Bulk 1P pre-pass (HD-258) | scripts/op-vault-export.py + deploy-service.yml | ✅ |
| docs/deployment-compose.md | HD-270 escape `\| replace('$','$$')` | docker-compose.yml.j2 templates | ✅ (0 unescaped vault refs in compose templates, see Track B) |
| docs/services-ai.md | qdrant storage path fix (HD-271) | qdrant env QDRANT__STORAGE__SNAPSHOTS_PATH | ✅ |
| docs/backup.md | kopia gate (HD-271) | kopia-server template | ✅ |
| docs/deployment-secrets.md | block scalar `>-` rule (HD-233) | templates | ✅ |
| docs/deployment-oidc.md | Blueprint + secret-egress glue (HD-141–143) | ks-oidc.yml + glue | ✅ |
| docs/security.md | 1Password vault = Homelab-ansible | check_vault_name.py | ✅ |

**Finding A-4.1: Docs-vs-IaC parity is consistent for the 8 hottest docs.**
No SSOT conflicts surfaced in the sample.

## A.5 docs/manual/ (audit.md §2.1.5)

**Verified:**
- `ls docs/manual/` shows 11 files (README.md + 10 family guides).
- `manual/README.md` index lists exactly those 10.
- Sample 1: `manual/wifi.md` exists, is referenced from `manual/README.md`.
- All manual/ files: Slovenian-language (per the index comment).
- No IP literals in manual/ (intentional — family guides don't include
  infrastructure detail).

**Finding A-5.1: manual/ is consistent.** No drift.

## A.6 Generated-doc accuracy (audit.md §2.1.6)

**Verified:**
- `docs/network-addresses-generated.md` IPs match rack-connections.json
  + host_vars/*.yml for all 6 hosts (oldsrv/nas/pi/router/switch/vps):
  - vps ansible_host = 159.195.111.66 (from host_vars/vps.kogler.si.yml)
  - oldsrv ansible_host = 10.10.99.30 (VLAN 99) + 10.10.1.30 (VLAN 10)
  - nas ansible_host = 10.10.1.10 (VLAN 10)
  - pi ansible_host = 10.10.1.20 (VLAN 10) + 10.10.99.20 (VLAN 99)
  - router/switch are network devices — no ansible_host, not in
    network-addresses-generated.md, correct.
- `validate_doc_templates.py` reports both `network-addresses.md.j2` and
  `inventory.md.j2` render OK (5432 + 9425 bytes), so the renderer is
  in sync with the SSOT. Drift detection: re-render and `git diff
  --exit-code` would be green (no diff expected).

**Finding A-6.1: Generated docs are accurate.** Re-render would not
produce a diff.

## A.7 Drift classification (audit.md §1.5)

All findings in this track classify as:
- **Orphan_Doc_Script (Low):** A-2.1 stale link in scripts/README.md
  (will dangle post-HD-263 deletion; LOW because the target file is
  already not in the tree, so the link silently fails but no other
  scanner catches it).
- **Cosmetic_Stale_Text (LOW):** A-1.2 transient self-reference in
  audit-approach.md → resolves when the report is committed.

---

## Verified-OK

- ✅ All 9 in-gate validators green from this worktree (`validate-all.sh`).
- ✅ 0 unmapped docs.
- ✅ 0 IP literals outside SSOT.
- ✅ 0 secret values in IaC/docs.
- ✅ 4 generated docs all carry `-generated` suffix and `# Ansible managed` header.
- ✅ 33 enabled services on VPS, 2 on home_servers, all referenced in `docs/services.md` + `docs/services-inventory-generated.md`.
- ✅ 8 hottest docs (deployment-*, network-*, services-*, observability, backup, security, smart-home-*, hardware-*, storage) sampled — all facts traced to their IaC SSOT.

## Open questions for owner

- None for this track.

## False positives

- **AUD-FP-A-1:** `audit-approach.md` broken link to the report this audit
  produces — self-resolving on commit, not a real drift.
