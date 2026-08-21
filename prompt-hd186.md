# prompt-hd186 — Close the published-port firewall bypass (S1)

> **Role:** Task handoff for **HD-186** (todo.md §2.8). **AI + gate**: firewall semantics on the
> public VPS — confirm option choice before merging. **Linked from:** [todo.md](todo.md) (HD-186);
> audit evidence: `security.md` §2 S1 + §5 verification plan.

## Problem (two halves — fix both)

1. **authentik publishes LDAP on all interfaces:** `templates/docker_services/authentik/docker-compose.yml.j2`
   → `ports: - "3389:3389"` (unconditional, 0.0.0.0) on the **public VPS**.
2. **nftables forward chain admits DNAT'd ports:** `roles/vps-hardening/templates/nftables.conf.j2`
   forward chain has `iifname/oifname "docker*" accept`. Docker-published traffic is DNAT'd in the
   nat path and hits *forward*, not *input* — so the "default-deny except :443/:51820" claim does
   not hold for published ports. The authentik template comment ("restrict src at firewall") is
   currently false.

## Fix options

- **A (preferred): remove the publish.** The LDAP outpost is consumed by Samba (nas). Over WG:
  home→VPS is allowed by scoping, so Samba targets the VPS's WG-side address instead of a published
  port. Consequence: HD-132's "firewall 3389→nas" wording must be updated (direction: nas is the
  client; nothing is published publicly).
- **B: DOCKER-USER filter chain** in `vps-hardening` (nftables): allow forwarded dport 443 from any;
  dport 3389 only from the WG peer (`wg_s2s_vps` / client = router peer); drop other forwarded
  new-connections from non-WG ifaces. Keeps the publish but adds moving parts.
- **C: bind the publish to the WG address** — same pattern as prometheus/loki templates
  (`{{ wg_s2s_vps.ip … }}:3389:3389` conditional on peer pubkey).

Recommendation: **A**, with **B** as defense-in-depth follow-up if any future service ever needs a
published port.

## Steps

1. Implement A (or chosen option) in the authentik template + comment block (fix the stale
   "oldsrv:3389" wording — authentik is on the VPS; nas reaches it over WG).
2. If B: extend `vps-hardening` nftables template + handlers; keep `flush ruleset` ordering in mind
   (docker re-adds its chains at docker.service start — DOCKER-USER rules must live in OUR file to
   survive, since docker only manages its own tables/chains).
3. Update `docs/services-vps.md` checklist table (+1 row: published-port bypass verify) and
   `docs/security.md` §8 status line; strike the false "input policy covers it" claim wherever
   present (`grep -rn "default-deny" docs/security.md docs/services-vps.md`).
4. Verification plan (from security.md §5) into the row's ⏳ tail:
   external `nc -vz <vps> 3389` must REFUSE; `ldapsearch` over WG must connect; `nft list ruleset`
   shows the expected chains.
5. `bash scripts/validate-all.sh` green; todo HD-186 ✅ IaC + ⏳ live-verify; changelog row.

## Constraints

- Do not weaken the :443/:51820 input accepts; do not touch docker's own chain management.
- Keep everything derived from group_vars (no IP literals — check_doc_ips gate).

**Cleanup:** delete this handoff (`prompt-hd186.md`) in the same closing change (A3 lifecycle, CONVENTIONS §4; HD-203 sweeps any leftovers).
