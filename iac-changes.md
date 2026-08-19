# IaC Changes — Architectural Reworks & Long-Run Maintainability

> **Role:** Change-proposal ledger for `IaC/` — architectural improvements, reworks, and the trade-offs for long-run maintenance.
> **Pairs with:** `docs-vs-iac.md` (what drifted) + `docs-changes.md` (doc side).
> **Convention:** each item = a concrete, reviewable change with the owning role/file + why it eases maintenance.

---

## P0 — deploy-correctness gaps in the current roles

### 1. `wireguard` role is gated on an empty-until-provisioned var — make the skip explicit & loud
- **Files:** `IaC/ansible/playbooks/vps.yml`, `group_vars/all.yml` (`wg_s2s_vps.*`), `group_vars/router.yml` (`wireguard_s2s_vps`).
- **Issue:** `when: wg_s2s_vps.peer_public_key | default('') | length > 0` silently skips; the docs imply the tunnel builds.
- **Change:** keep the skip (VPS edge must deploy standalone) but add a **fail-loud guard / task log** when the peer key is missing so a run never *looks* like it configured WG when it didn't. Document in `IaC/README.md` + `network-vpn.md` that WG peering is deploy-gated pending `wg_s2s_router_public_key` / VPS pubkey items.
- **Why:** prevents a "tunnel configured" false sense during the first VPS deploy; makes the deploy-gate obvious.

### 2. Router/switch API-first roles — verify how `community.routeros.api_modify` is enlisted
- **Files:** `roles/router/tasks/main.yml`, `roles/switch/tasks/main.yml`, `requirements.yml`.
- **Note (from changelog):** HD-137 rewrote both roles from nonexistent `community.routeros_*` modules onto **`community.routeros.api_modify`** (path-based), since `community.routeros` only ships `api`/`api_facts`/`api_find_and_modify`/`api_info`/`api_modify`/`command`/`facts`. This is a **good** migration (idempotent, deterministic), but it's a large 40+15-call job — 
  - **Change:** add a **read-only `api_facts` "assert current state == expected"** step before mutating calls, so a device that drifts from the SSOT is caught and reported rather than blindly re-asserted. This makes the router/switch roles genuinely **observable/repair-easier** long-run.
  - Add `routeros_api_tls` capability (currently `# routeros_api_tls: true # enable after Let's Encrypt on router`) — decide TLS on mgmt interface and wire it; keep the TODO honest.

### 3. `switch` port-map is still estimates — make it fail-not-guess
- **Files:** `group_vars/switch.yml` (`switch_port_map` with 8 `# TODO: VERIFY` entries), `render_rack_connections.py`.
- **Change:** until a live human verifies physical ports, treat `network-addresses.md` as **IP-SSOT only**, not a physical-port map. Mark `switch_port_map` as **not-yet-SSOT** in the doc, and gate any render/physical assertion on a `switch_port_map_verified: true` flag. This keeps `network-addresses.md` honest and prevents bad port assignments from being treated as truth.
- **Why:** the whole point of SSOT breaks if a WIP map is rendered as authoritative.

---

## P1 — maintainability redesigns

### 4. Kill the "two role catalogs" drift (IaC/README vs deployment-ansible)
- **Files:** `IaC/README.md`, `docs/deployment-ansible.md`.
- **Change:** make **`deployment-ansible.md` the single role-catalog owner**; `IaC/README.md` keeps the implementation-status + repo layout only and links there. Remove the duplicated role descriptions + hardcoded "15"/"41" counts (see `docs-changes.md` §3).
- **Why:** today three lists (README, deploy-ansible, index) drift independently.

### 5. Make `docker_services` role's per-service loop the ONE template-authoring contract
- **File:** `roles/docker_services/tasks/main.yml` + `deploy-service.yml`, `templates/docker_services/*`.
- **Already-good:** `_extra_templates` mapping + service `enabled`/`instance`/`subdomain` fields + `docker-compose@.service` + Authentik glue ordering.
- **Change / note:** 
  - The **`when: svc.name == 'authentik'` glue** running *inside* the per-service loop is a slightly hacky dependency (works today, but it blurs "per-service deploy" vs "edge bootstrap").
  - **Recommended:** keep it but move the glue to **one explicit pre-pass task** (not name-matched), so the loop itself stays purely per-service. Documented as a maintenance-ergonomics win, not a bug.
  - Add a **render + validate step inside the loop** (not only at the end) so one bad template aborts loudly with the service name, not after a full render.

### 6. Consolidate the "host control-plane render" scripts
- **Files:** `scripts/render_network_addresses.py`, `render_rack_connections.py`, `check_doc_ips.py`, `validate_doc_templates.py`, `validate_all.sh`, `validate-docker-services.py`.
- **Issue:** Python render logic + Ansible render (`render-docs.yml`) overlap; `check_doc_ips.py` conceptually belongs with the render.
- **Change:** keep the **Ansible `render-docs.yml` as the control-plane owner** (it's the committed path), and make the standalone `.py` scripts **thin wrappers** that call the same core, or document exactly which is authoritative. Consider one `scripts/render_all.py` orchestrator so the "which script regenerates what" is a single entry point the way `validate_all.sh` is for validation.

### 7. Split `group_vars/all.yml` — it's becoming a grab-bag
- **File:** `group_vars/all.yml` (now holds timezone/locale/NTP + GPU gids + every `*_version` pin + WG + livebox + address SSOT + cert files + UAexporter + ZFS exporter + observability target).
- **Issue:** a single "global" file mixes *infrastructure (timezone/IP/mounts/WG)* with *image-version pins* with *per-service knobs*. That's fragile for Renovate (every pin is here) and for humans who must know where a value lives.
- **Change:** split into
  - `group_vars/all.yml` → location/NTP/domain/GPU-gid/`op_vault` + IP/ranges/WG/cert + livebox + global observability targets (infra).
  - `group_vars/versions.yml` (new) → **all `*_version` image pins** (the ~30 pins) so **Renovate's docker-datasource + a version-bump review has ONE file**.
  - `group_vars/knobs.yml` (new, optional) → per-host observable knobs (exporter ports, alloy labels, secrets refs).
  - Update `deployment-ansible.md` + `IaC/README.md` + `CONVENTIONS.md` §2/§3 to point at the new split.
- **Why:** version pins change on a **different cadence** (Renovate) than infra; separating them removes the "why did all.yml change" guess and makes version audits single-sheet.

### 8. Standardize secret ref var vs literal in group_vars
- **Files:** all `group_vars/*.yml` + compose templates.
- **Goal:** already mostly `{{ lookup('community.general.onepassword'…) }}`. 
- **Change:** make a **repo-wide convention that group_vars never embed a literal itself** (host ip/salt/status allowed; secret **values** never) and enforce via `scripts/check_doc_ips.py`-style + a **new `validate-secrets.py`** that greps group_vars/templates for `lookup(` misuse and any literal-looking credential. This closes the class of HD-65/HD-91 near-misses at review time, not deploy time.

---

## P2 — long-run maintainability

### 9. Playbook list drift
- `docs/deployment-ansible.md` + `deployment.md` File Layout list only 4 playbooks, but disk has **11** (`all, dns, home_servers, raspberry_pi, render-docs, render-routeros, router, storage, switch, vps` + `site`). 
- **Reorder** the "File Layout" docs to the actual `playbooks/` set, or better: point at `playbooks/` dir as the truth.

### 10. `kopia` role/`kopia-server` container — keep as-is (decision HD-1 not a bug) but fix the container-vs-role split
- `kopia` role exists but "intentionally unused" (containerized via `docker_services`). That's a **valid** decision — just annotate in `IaC/README.md` that the dir is a **retained stub** for a possible bare-metal nas path, and give it an expiry note so a future agent doesn't "finish" it blindly.

### 11. Add a `validate` gate for role/template counts + doc-map reconciliation
- **Change:** extend `scripts/validate-all.sh` to **also** compare `docs/index.md` document map against `find docs -name '*.md'` and flag missing rows, + assert the `docker_services/` dir count matches any doc-claimed number (or auto-suppress hand-counts). This turns the "docs drift" class of the audit into a **lint failure, not a judgment call**.

### 12. `routeros_` secrets — one owner for network-gear credential
- Already centralized to `mikrotik-admin_login` (1Password) + `network-snmp_login`. Keep; just document the **per-gear** (RB4011 / CRS328 / hAP) item relationship so a single admin item isn't assumed to cover distinct devices with one password.

---

## Summary of recommended IaC changes

| # | Change | Priority | Files |
|---|---------|----------|-------|
| P0-1 | wireguard gate: make explicit-not-silent + doc | high | vps.yml, README, network-vpn.md |
| P0-2 | router/switch api_modify: add assert-before-mutate + tls decision | high | roles/router, roles/switch |
| P0-3 | switch port map: gate physical render behind verified flag | high | switch.yml, render scripts |
| P1-4 | one role-catalog owner (deployment-ansible) | med | IaC/README.md, deploy-ansible.md |
| P1-5 | docker_services: move glue to pre-pass, loop-pure | med | roles/docker_services |
| P1-6 | consolidate render scripts behind one entry | med | scripts/*.py |
| P1-7 | split all.yml into infra + versions + knobs | med | group_vars/*.yml |
| P1-8 | secrets-lint script (no literals) | med | scripts/validate-secrets.py (new) |
| P1-9 | fix playbook file-layout in docs | low | deployment-ansible.md |
| P1-10 | annotate kopia stub expiry | low | IaC/README.md |
| P1-11 | add doc-map + template-count lint to validate-all | low | scripts/validate-all.sh |
| P1-12 | per-gear routeros credential note | low | deployment-secrets.md |