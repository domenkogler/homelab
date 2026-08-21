# prompt-hd195 — deployment-tasks phase sweep

> **Role:** Task handoff for **HD-195** (todo.md §2.10). Mechanical text sweep — the checklist is
> the spec. **Linked from:** [todo.md](todo.md); evidence: `tracking-sugestions.md` §2,
> `docs-vs-iac.md` §A/§I.

## Checklist (fix each; keep phase structure intact)

1. Header: `2025-08-16` decision dates → 2026.
2. Phase 2 step 2 chain: insert the `storage` role (actual: common→ai_diag→network→storage→nut→cockpit).
3. Phase 3 step 3: replace the stale service list with the real oldsrv subset from
   `group_vars/home_servers.yml` (ollama, immich-ml, technitium, pihole, homepage*, dozzle,
   signal-cli, sunshine, jellyfin+*arr, HA-standby) — *homepage moves to VPS per HD-180/183*;
   delete "remove/downgrade per HD-135" (already applied). Phase 3 verify: drop Grafana/Forgejo
   local-reachability wording (VPS edge serves them).
4. Phase 4 steps 2–3: Pi docker_services = home-assistant-primary, technitium-secondary,
   traefik-ha (no pihole/raspberrymatic); order = docker_services BEFORE home_assistant (KOPS-063);
   mark Homematic step ⏳ parked (HD-13/179 context).
5. Phase 6: HD-14 row "TileBoard" → "HA Dashboard lovelace".
6. Phase 7 item 7: AnythingLLM + LocPilot → Office MCP path (HD-108/111).
7. Phase 9: delete resolved rows HD-35 (link fixed) and HD-39 (watchtower decided).
8. Host→Playbook table: vps chain += vps-hardening/cifs/wireguard(cond); nas chain += storage;
   pi chain order fixed. Must match the playbook files exactly.
9. Sweep any remaining "2025" year typos (2 known).

## Validation

- `bash scripts/validate-all.sh` green (doc-map links).
- Cross-check every changed claim against the playbook/group_vars file it names.
- todo HD-195 ✅; changelog row.

**Cleanup:** delete this handoff (`prompt-hd195.md`) in the same closing change (A3 lifecycle, CONVENTIONS §4; HD-203 sweeps any leftovers).
