# IaC Folder — Change Proposals (Audit Round 2)

> **Role:** Audit deliverable — architectural and maintainability proposals for `IaC/` (Ansible core,
> templates, router, host bootstrap). Produced 2026-08-21 per `prompt.md`.
> **Linked from:** `prompt.md`; siblings: `docs-vs-iac.md`, `docs-changes.md`, `conventions-sugestions.md`,
> `tracking-sugestions.md`, `architecture.md`, `security.md`.
> **Premise:** the IaC is in good shape (fail-loud guards, SSOT vars, per-service tags, validators).
> Proposals below are ranked by maintenance payoff; nothing requires a rewrite.

---

## 1. `IaC/README.md` — make it generated or minimal (highest doc-ROI item)

The implementation spec duplicates four classes of derived data and is stale on all of them
(service lists, role counts, vault name, VPS phase status — evidence in `docs-vs-iac.md` §A/E/F).

Options (pick one):
- **A (recommended): shrink to pointers.** Keep only: layout tree (structural, stable), the two
  execution modes, idempotency table, DNS/TLS model. Delete: inline service samples ("illustrative,
  may drift" has proven false), the 1Password item table (deployment-secrets owns it), role-by-role
  detail that restates `docs/deployment-ansible.md` (declared "owner" anyway), implementation-status
  counts. Every number → replaced by a path or a link.
- **B: render it.** Add an `iac-readme-generated.md` rendered from group_vars (role list, template
  count, service lists per host) and keep hand-written prose separate. More machinery than the file
  is worth today; revisit if the repo grows.

Also fix now regardless: duplicated lines (network note ×2, router tree ×2), vault name, `router_login`,
RouterOS script count/paths.

## 2. Kill the triple VLAN map

`network_vlans` (all.yml), `vlans` (router.yml), `switch_vlans` (switch.yml) encode the same seven
VLANs three times, synced by comments. One rename and three files drift.

Proposal: keep `all.yml network_vlans` as the only literal list; derive the router/switch views in
the roles (`network_vlans | selectattr(...)` / rejectattr('id','==',1)), or at minimum replace the
duplicates with `vlans: "{{ network_vlans }}"` + role-local filters. Same pattern already used for
IPs (`network_static_hosts` lookups) — this just finishes it.

## 3. Version-pin completion (mechanical, high value)

21 compose templates still reference bare `:latest` and three use mutable aliases (`ollama:rocm`,
HA `stable`, immich `release`) while CONVENTIONS §7 forbids both and HD-134 is marked done.

Proposal:
1. Add the missing `*_version` vars to `group_vars/all/versions.yml` (one Renovate-reviewable sheet),
   registry-verify each tag once at pin time (the Tuwunel/LiteLLM MUST-pin precedent).
2. Replace `| default('latest')` fallbacks in templates with fail-loud references — a missing pin
   should abort the render like a missing secret does (HD-65 philosophy applied to versions).
3. `ollama`: pin a specific ROCm build tag; `home-assistant_version: stable` → semver (Renovate tracks
   the docker tag; `stable` defeats primary/standby parity the failover design depends on).
4. Extend `validate-docker-services.py`: currently fails on bare `latest` only via `ALLOWED_LATEST`
   allowlist — invert it to a denylist of zero entries after step 1 lands.

## 4. Template boilerplate — one shared fragment instead of 49 copies

Every compose template repeats: restart policy block, logging block (on Pi), network blocks,
Traefik label scaffolding, secret-header comment. Drift has already happened (some templates cap
logs, some don't; healthchecks are inconsistent).

Proposal (low-risk, incremental):
- Introduce `roles/docker_services/templates/_fragments/` with `restart.yml.j2`, `labels.j2`
  (given router/middlewares/service vars), `logging-pi.yml.j2`; include via Jinja `{% include %}`.
- Do NOT attempt a full abstraction layer — per-service readability is a feature of this repo.
  Target only the blocks that have already drifted (logging, restart).
- Alternatively, if fragments feel un-Ansible-y: enforce the invariants in
  `validate-docker-services.py` (e.g. "every traefik-public service must set explicit log options")
  so drift fails the gate instead.

## 5. Playbook/site ergonomics

- **site.yml pre-flight scope:** add `vps` to the guard play (it is provisioned and public; the
  comment saying "Phase 2" predates HD-40A). The common-role assert backstops it, but the master
  playbook should not be the one place without the check.
- **Phase entry points:** deployment-tasks defines phases 0–10 but operators must know which
  playbook(s) + tags map to each phase. Add a tiny `playbooks/phaseN-*.yml` wrapper or (cheaper) a
  comment block in `site.yml` mapping phases → playbook/tag sets, kept in sync with
  `deployment-tasks.md` Host→Playbook table (which is currently wrong — see `docs-vs-iac.md` §A7).
- **`render-docs.yml` host pattern** `hosts: localhost:docker_hosts:raspberry_pi` works but is
  non-obvious; a one-line comment on why storage/router are excluded would prevent future "fixes".

## 6. Router bootstrap hardening (small, deploy-time)

Findings from the template audit (details in `security.md` §5): `crs328_initial.rsc.j2` enables
api/www-ssl/ssh without interface binding; `ap_initial.rsc.j2` leaves ssh unbound over a flat bridge
including WLAN; rb4011 DHCP hands out a hardcoded public resolver.

Proposal: mirror the rb4011 pattern (`interface=vlan99-mgmt` / bridge) in crs328 + ap templates;
parameterize the bootstrap DNS resolver from group_vars. All three changes are bootstrap-window-only
risk reductions and cost ~10 lines total.

## 7. Preseed placeholder discipline

Preseeds ship placeholder disk identifiers (Slovenian placeholder strings for serials) and the Pi
first-boot script ships placeholder pubkey strings. oldsrv's ZFS pool create has a fail-loud guard;
the preseeds themselves do not.

Proposal: add a post-install assertion step (in `post_install.sh`) that refuses to continue when a
known placeholder pattern (`VNESI_MODEL`, `<SERIAL>`, `PERSONAL_PUBKEY_FROM_1PASSWORD`) is still
present in the produced config — converts silent misfires into loud failures. Also consider a
repo-side grep gate (`scripts/`) that flags committed placeholders outside the designated files.

## 8. Role-level nits

| Item | Proposal |
|------|----------|
| `monitoring` role size | It provisions Alloy + Prometheus + Loki + Grafana (+dashboards/rules/contactpoints) in one role. Works, but rule/dashboard changes redeploy everything. Split tasks into `tasks/{alloy,prometheus,loki,grafana}.yml` includes (entry-point pattern already convention) and tag them (`--tags grafana`). No structural move needed. |
| `docker_services` pre-pass naming | `prepass-authentik.yml` is authentik-specific inside the generic deployer. Fine today; if a second pre-pass ever appears, promote a generic `tasks/prepass.d/*.yml` include pattern. Note it in the role header so the next contributor doesn't inline another special case into `deploy-service.yml`. |
| `wg AllowedIPs` duplication | The scoped AllowedIPs list exists verbatim in `all.yml wg_s2s_vps.allowed_ips` and `router.yml wireguard_s2s_vps.allowed_ips`. Intentional (different consumers) but add a cross-comment "keep in sync with <other file>" both sides, or derive one from the other via hostvars. |
| `host_vars/oldsrv` `home_ip` | Duplicates the `network_static_hosts` lookup (`oldsrv_home_ip` in all.yml). Keep one; the lookup version can't drift. |
| `ansible.cfg` | `host_key_checking = False` globally — acceptable for bootstrap, but consider `True` with a known_hosts provisioning step once hosts are stable (ties into the SSH-fingerprint table already recorded in `deployment-ansible.md`). |
| `requirements.yml` | Collections are pinned (Renovate-managed ✓) — no change; just noting the ansible-galaxy manager covers it. |

## 9. Testing gap worth closing

Validators cover compose rendering, blueprint shape, doc maps, IPs, secrets — but nothing executes
Ansible logic. Cheapest meaningful step: run `ansible-playbook --syntax-check` across all playbooks
inside `validate-all.sh` (WSL/CI only; skip gracefully on native Windows like the renderers do).
This catches the class of bug HD-137 fixed (nonexistent modules) before commit rather than at deploy.

## 10. Suggested order

1. §5 site.yml vps guard + §6 router template bindings (tiny, security-relevant).
2. §3 version pins (mechanical sweep; biggest supply-chain win).
3. §1 IaC/README shrink (biggest doc-drift win).
4. §2 VLAN map dedup + §8 nits opportunistically.
5. §4 fragments / validator invariants and §9 syntax-check gate as capacity allows.

---

## 11. Deep-dive addendum (round 2) — template/role defects found line-by-line

Full line-by-line pass over the 49 compose templates + router/switch/docker_services/home_assistant
roles. Deploy-blocking and functional bugs first (evidence in `docs-vs-iac.md` §J, security framing
in `security.md` §5):

| # | Sev | File | Defect | Fix |
|---|-----|------|--------|-----|
| D1 | **H** | `templates/docker_services/immich-app/…` | `IMMICH_MACHINE_LEARNING_URL: "http://immich-ml:3003"` — container name, but immich-ml runs on oldsrv; unresolvable from the VPS. ML dead on first deploy. | Derive the oldsrv target from the SSOT like `alloy_backend_host` does (e.g. `http://{{ (network_static_hosts \| selectattr('name','equalto','oldsrv') …).ip }}:3003` over `wg-vps-services`), and confirm immich-ml's port binds are reachable cross-host. |
| D2 | **H** | `playbooks/raspberry_pi.yml` + `roles/home_assistant` | Order conflict (KOPS-063 moved docker_services before home_assistant; the role still assumes the reverse). First `compose up` auto-creates `config/`, `secrets.yaml`, `keepalived.conf` as directories; the role's `copy … keepalived.conf` then fails and HA runs on default config. | Pre-create the bind sources in the docker_services template dir (rendered by the HA role before `up`), or render HA files inside docker_services' pre-pass, or add `create_host_path: false` long-syntax mounts so `up` fails loudly instead of mkdir-ing. Also fix the stale role-header comment. |
| D3 | **H** | `templates/docker_services/traefik/…` on VPS | Same template = ACME issuer on two hosts (oldsrv + VPS): dual DNS-01 clients for one wildcard, dual certs-dumper outputs; the Pi cert-sync contract silently depends on which host wins. | Parameterize: `acme_issuer: true/false` per host (VPS or oldsrv — one decision), disable ACME+certs-dumper on the consumer, and have the issuer host be the single `certs` source. Cross-ref `docs-vs-iac.md` J3. |
| D4 | **M** | `templates/docker_services/pihole/…` | `CONDITIONAL_FORWARDING_IP: "{{ ha_vip }}"` — the VIP is not a DNS server; Pi-hole local-name resolution broken. | Use `dns_primary_ip` (Technitium primary). |
| D5 | **M** | `templates/docker_services/homepage/…` | `HOMEPAGE_ALLOWED_HOSTS: "{{ domain_local }}"` — rejects the `home.kogler.si` alias the router rule explicitly serves (Host-header mismatch). | `"{{ domain_local }},home.{{ domain_local }}"` (plus `www.` if ever added). |
| D6 | **M** | `roles/cockpit/templates/cockpit-routes.yml.j2` | Hardcoded Home-IP literals for both backends (convention: derive from `network_static_hosts`) and no middleware on the routes (add `crowdsec-only@file`). | Derive IPs via the SSOT lookup pattern used everywhere else; add the middleware. |
| D7 | **M** | `roles/router/tasks/main.yml` | Kids VLAN controls are a `debug:` placeholder; DNS forward rule covers primary only (secondary on pi unreachable cross-VLAN); doc's tertiary router resolver not configured. | Implement Kids rules or mark ⏳ in docs; add a DNS accept rule for `dns_secondary_ip` alongside the primary (and consider the router-resolver tertiary). |
| D8 | **M** | `roles/docker_services/defaults/main.yml` vs `scripts/validate-docker-services.py` | The extra-templates list exists in TWO hand-synced copies and has already diverged: role renders `headscale/policy.hujson.j2` but the validator doesn't require it; validator requires `home-assistant-standby/keepalived.conf.j2` but the role never renders it (the HA role owns that file — the template-dir copy is a raw `.j2` leftover). | Single source: move the list to one place (role defaults) and have the validator read it; drop `keepalived.conf.j2` from the standby template dir (dead file that also confuses the mount story). |
| D9 | **L** | `templates/docker_services/signal-cli-rest-api/…` | `SIGNAL_CLI_CAPTCHA … \| default('', true)` — the only fail-open secret lookup in the tree (HD-65 law exception, undocumented). | Document the exception in the template header or split registration-time captcha from runtime secrets. |
| D10 | **L** | `templates/docker_services/technitium/…`, `prometheus/…` | Technitium primary state lives in `/opt/technitium/config` (oldsrv convention is `/srv/docker/<svc>` per volume strategy; Kopia covers `/opt/*` so coverage is intact but the layout is inconsistent); Prometheus TSDB uses a named volume (convention: bind mounts for stateful, named only for ephemeral — 30d of metrics is borderline). | Align paths at first deploy or document the exceptions in deployment-compose.md §Volume Strategy. |
| D11 | **L** | `roles/docker_services/tasks/main.yml` | Post-deploy renders `services-inventory-generated.md` into the repo checkout but never commits/pushes (interfaces.md pipeline step 5 claims it does). | Either add the commit/push (on the control plane only) or correct the pipeline doc. |

**Also verified clean in this pass (no action needed):** router role HD-161 assert-before-mutate + identity guard, fail-closed WG pubkey assert, ordered forward/input chains with `ensure_order` + `handle_absent_entries: remove`; switch role identity guard + trunk/access port map; storage role full parity with storage.md (datasets, properties, sanoid cadences, push jobs); db-backup DB01–04; Blueprint provider set; middleware law on all labelled routes; prometheus/loki WG-conditional loopback binding pattern (good pattern worth reusing for the immich-ml fix, D1).
