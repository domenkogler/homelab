# prompt-hd184 — Fix immich-app→immich-ml URL (cross-host)

> **Role:** Task handoff for **HD-184** (todo.md §2.4). Execute per CONVENTIONS.md; run
> `bash scripts/validate-all.sh` green before finishing; update todo/changelog in the same change.
> **Linked from:** [todo.md](todo.md) (HD-184); audit evidence: `docs-vs-iac.md` §J1, `iac-changes.md` §11 D1.

## Problem

`IaC/ansible/templates/docker_services/immich-app/docker-compose.yml.j2` sets:

    IMMICH_MACHINE_LEARNING_URL: "http://immich-ml:3003"

immich-app deploys on the **VPS**; immich-ml on **oldsrv**. Docker DNS cannot resolve across hosts →
ML is dead on first VPS deploy. The comment above the line already says "ML on oldsrv GPU (WG tunnel)"
— the value was never updated for the HD-135 split.

## Second half of the bug (do not miss)

`immich-ml/docker-compose.yml.j2` publishes **no ports** — it listens on the `services-internal`
overlay only, so even a correct IP would not be reachable cross-host. The fix has two parts:

1. **Publish 3003 on oldsrv, bound to oldsrv's Home-VLAN IP** (not `0.0.0.0`):
   `- "{{ <oldsrv home ip>: }}3003:3003"` derived via the SSOT lookup pattern (never a literal).
2. Point immich-app at that address.

## How to derive the address (repo pattern)

Copy the established idiom — see `alloy_backend_host` / `nut_exporter_host` in
`group_vars/all.yml`:

    {{ (network_static_hosts | selectattr('name', 'equalto', 'oldsrv') | selectattr('vlan', 'equalto', 10) | first).ip }}

Add a derived var (e.g. `immich_ml_url: "http://{{ … }}:3003"`) in `group_vars/all.yml`
(infra var → all.yml, NOT versions.yml), or inline it in the template — prefer the group_var so the
VPS compose and future docs share one definition.

## Reachability (already satisfied — verify, don't rebuild)

- WG AllowedIPs include oldsrv /32 both sides (`wg_s2s_vps.allowed_ips`, HD-155).
- RouterOS forward ACL accepts `vps_s2s_peer → vps_scoped_home` (any port) — oldsrv is in the list.
- ML key auth already wired both sides (`IMMICH_MACHINE_LEARNING_KEY` ↔ `IMMICH_API_KEY`, HD-160).
- Confirm immich-ml binds `0.0.0.0:3003` inside the container (`IMMICH_HOST` env) so the published
  port actually forwards.

## Steps

1. Add the derived URL var; update the immich-app template env + its comment block.
2. Add the bound port publish to the immich-ml template (+ comment: cross-host ML for immich-app,
   firewall-scoped by WG AllowedIPs + RouterOS ACL).
3. `python scripts/render_all.py` not needed (no generated doc changes); run
   `bash scripts/validate-all.sh` — must stay green.
4. Update `docs/services-ai.md`/`deployment-compose.md` sibling-auth map row if it names the URL
   shape (it says "VPS → oldsrv (WG)" — already correct; just confirm no stale `immich-ml:3003`
   anywhere: `grep -rn "immich-ml:3003" docs/ IaC/`).
5. todo.md: mark HD-184 ✅ IaC done with a `⏳ Deploy-gated:` tail: "live-verify ML round-trip from
   the VPS over WG (Immich smart-search job completes)". changelog: move the row.

## Constraints

- No literal IPs anywhere (SSOT rule; check_doc_ips will fail the gate otherwise).
- Do not touch the immich-ml auth env names — their live verification belongs to HD-160.
