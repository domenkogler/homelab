# Idea Connections Map

> How the 17 docs and 6 IaC files relate to each other — cross-references, dependencies, and conflicts.

---

## 📄 Document Cross-Reference Matrix

```
doc: "Home Lab & Family Network Architecture.md"
  ├─ IDENTICAL TO: "Homelab network architecture.md" ⚠️ DUPLICATE
  ├─ EXTENDS: "Multi-VLAN DNS Integration Architecture.md" (DNS layer detail)
  ├─ DEPENDS ON: "Road warrior plan.md" (VPN section implementation)
  ├─ REFERENCES: "družinski web sistem.md" (VPS services mentioned but not detailed)
  ├─ CONFLICT: Mentions Immich on VPS; hardware docs put it on home server
  └─ CONFLICT: Uses AdGuard-only DNS; Multi-VLAN doc uses Technitium+Pi-hole

doc: "družinski web sistem.md" (the application stack)
  ├─ DEPENDS ON: "1password authentik.md" (Authentik integration detail)
  ├─ DEPENDS ON: "chosen db backup service.md" (backup implementation)
  ├─ DEPENDS ON: "Varnostni načrt za zaščito VPS.md" (security hardening)
  ├─ REFERENCED BY: "Home Lab & Family Network Architecture.md" (VPS services)
  └─ CONFLICT: Places Immich on VPS; hardware docs place it on home server

doc: "Varnostni načrt za zaščito VPS.md" (VPS security)
  ├─ EXTENDS: "družinski web sistem.md" (secures the application stack)
  └─ REFERENCED BY: "Home Lab & Family Network Architecture.md"

doc: "1password authentik.md" (SSO integration)
  ├─ EXTENDS: "družinski web sistem.md" (Authentik detail)
  └─ ENABLES: Family-friendly SSO → all apps

doc: "chosen db backup service.md" (backup tool)
  ├─ EXTENDS: "družinski web sistem.md" (backup strategy detail)
  └─ COMPLEMENTS: Kopia (in družinski web sistem doc)

doc: "nov strežnik.md" (home server — EARLIER version)
  ├─ SUPERSEDED BY: "new home server hardware configuration summary.md"
  ├─ SUPERSEDED BY: "Stroškovnik za novi strežnik.md" (cost breakdown)
  ├─ CONFLICT: MSI motherboard → ASUS in later docs
  ├─ CONFLICT: 4U rack case → open-frame in later docs
  └─ CONFLICT: PiKVM → Comet KVM in later docs

doc: "new home server hardware configuration summary.md" (home server — LATER)
  ├─ SUPERSEDES: "nov strežnik.md"
  ├─ EXTENDED BY: "Stroškovnik za novi strežnik.md" (full BOM with costs)
  └─ CONFLICT: References open-frame but also includes B850 motherboard → RESOLVED in cost doc

doc: "Stroškovnik za novi strežnik.md" (final cost breakdown)
  ├─ SUPERSEDES: "nov strežnik.md" + "new home server hardware configuration summary.md"
  ├─ CONTAINS: Duplicated hardware summary from "new home server hardware..." ⚠️
  └─ THIS IS THE CANONICAL HARDWARE DOC

doc: "Načrt Homelab sistema_ Lokalni slovenski glasovni asistent in avdio sistem.md" (voice/audio)
  ├─ DEPENDS ON: "nov strežnik.md" (mentions Minisforum MS-A2)
  ├─ DEPENDS ON: "Local llm agent for word mail and presentations.md" (same GPU for LLM)
  ├─ DEPENDS ON: "Homeassistant rework.md" (HA is the integration hub)
  ├─ CONFLICT: References MS-A2; hardware docs settled on custom server
  └─ ENABLES: Slovenian-local voice → whole smart home

doc: "Homeassistant rework.md" / "Homeassistant rework prompt.md" (dashboard prompt)
  ├─ DUPLICATE: "rework.md" is a refined version of "rework prompt.md"
  ├─ DEPENDS ON: HA entity list (NOT YET PROVIDED — template only)
  └─ OUTPUT: TileBoard config + Grafana strategy (not yet generated — waiting for entities)

doc: "local llm agent for word mail and presentations.md" (office AI)
  ├─ RELATED TO: "nov strežnik.md" (runs on same GPU)
  ├─ RELATED TO: VRAM management strategy in hardware docs
  └─ INDEPENDENT: Can work without any other system

doc: "Multi-VLAN DNS Integration Architecture.md" (DNS layer)
  ├─ EXTENDS: "Home Lab & Family Network Architecture.md" (DNS section)
  └─ ADDS: Technitium + Pi-hole layer not in base architecture

doc: "potovalni vpn prompt.md" (travel VPN — EARLIER prompt)
  ├─ SUPERSEDED BY: "potovalni.vpn.md" (refined prompt)
  ├─ DUPLICATE: "Road warrior plan.md" (different tool, same goal)
  └─ REFERENCES: Sploax/KORP + Headscale

doc: "potovalni.vpn.md" (travel VPN — REFINED prompt)
  ├─ REFINES: "potovalni vpn prompt.md"
  ├─ ADDS: Static DNS `potovalni.vpn` → 192.168.123.1
  ├─ COMPLEMENTS: "Road warrior plan.md" (combines WireGuard + Headscale)
  └─ DEPENDS ON: RB4011 at home

doc: "Road warrior plan.md" (travel VPN — DIFFERENT approach)
  ├─ ALTERNATIVE TO: "potovalni vpn prompt.md" / "potovalni.vpn.md"
  ├─ DIFFERENT: Uses MikroTik Hotspot instead of Sploax for captive portal
  ├─ DIFFERENT: Native WireGuard only (no Headscale)
  └─ MORE DETAILED: Full CLI commands expected, three-part deliverable

IaC: "Iaac/ansible/site.yml"
  ├─ TARGETS: "Iaac/ansible/inventory.ini" → deblab (10.10.1.125)
  ├─ DEPENDS ON: "Iaac/bootstrap-ansible-client/bootstrap.sh" (management laptop setup)
  ├─ DEPENDS ON: "Iaac/host/host-wsl2.md" or "Iaac/host/host-Hyper-v.md" (host setup)
  ├─ SECRETS: 1Password lookup (Kopia, Authentik, DB passwords)
  └─ STATUS: Testing phase — only `common` role active

IaC: "Iaac/bootstrap-ansible-client/bootstrap.sh"
  ├─ DOCUMENTED BY: "Iaac/bootstrap-ansible-client/ansible.md"
  ├─ PREREQUISITE: "Iaac/host/host-wsl2.md" (WSL2 Debian setup)
  └─ OUTPUT: Ready-to-use Ansible control node on laptop
```

---

## 🔗 Dependency Graph (Build Order)

```
Phase 0: Foundation
  host-wsl2.md / host-Hyper-v.md → bootstrap.sh → Ansible ready
  rb4011 current config → VLAN redesign (€0 architecture)

Phase 1: Home Network (parallel with Phase 2 planning)
  VLAN redesign → Multi-VLAN DNS → WireGuard S2S → Road-warrior VPN
  Travel router config (relies on home WireGuard)

Phase 2: Home Server (hardware acquisition)
  Stroškovnik → purchase → physical assembly → Proxmox install
  → GPU passthrough → Ollama → LLM / Voice pipeline

Phase 3: VPS (parallel with Phase 2)
  Hetzner provision → Traefik + Authentik → OpenCloud + Immich
  → Kopia + db-backup → Security hardening (CrowdSec, Cloudflare)
  → Site-to-site VPN to home

Phase 4: Integration
  Home server ↔ VPS (via WireGuard)
  Authentik SSO for ALL services (VPS + Home Assistant)
  1Password + Passkeys for family
  Dashboard (TileBoard + Grafana)

Phase 5: Polish
  Family documentation
  Backup validation
  Travel router field test
  Voice assistant tuning
```

---

## 🟡 Conflicts & Resolution Status

| Conflict | Files Involved | Resolution |
|----------|---------------|------------|
| Motherboard: MSI vs ASUS | `nov strežnik.md` vs `Stroškovnik...` | ✅ **ASUS ProArt B850-Creator** is final |
| Chassis: 4U rack vs open-frame | `nov strežnik.md` vs `Stroškovnik...` | ✅ **Open-frame ALAMENGDA ALE01** is final |
| Remote KVM: PiKVM vs Comet KVM | `nov strežnik.md` vs `Stroškovnik...` | ✅ **GL.iNet Comet KVM** is final |
| DNS: AdGuard-only vs Technitium+Pi-hole | `Home Lab...` vs `Multi-VLAN DNS...` | ❓ **Not resolved** — need decision |
| VPN: WireGuard vs Headscale | `Road warrior plan.md` vs `potovalni.vpn.md` | ❓ **Not resolved** — need decision |
| Immich location: VPS vs Home | `družinski web...` vs hardware docs | ❓ **Not resolved** — need decision |
| Voice brain: MS-A2 vs Custom server | `Načrt Homelab...` vs hardware docs | ❓ **Not resolved** — need clarification |
| Travel VPN: Hotspot vs Sploax/KORP | `Road warrior plan.md` vs `potovalni.vpn.md` | ❓ **Not resolved** — need decision |
| VPS type: Dedicated vs CX43 | `Home Lab...` (Section 3) | ❓ **Not resolved** — budget decision |

---

## 💡 Commonalities Across All Docs

1. **Local-first philosophy** — Everything that CAN be local IS local (voice, LLM, HA). Cloud is for what MUST be external (email, public-facing apps).
2. **MikroTik everywhere** — RouterOS is the backbone. RB4011 at home, hAP ac² for travel. No UniFi, no consumer gear.
3. **Authentik as gatekeeper** — Single identity provider for everything, family-managed.
4. **1Password as secret store** — Family already uses 1Password Families; Ansible reads from it, family authenticates through it.
5. **Docker/Proxmox, not Kubernetes** — No unnecessary complexity. Compose files, LXC containers.
6. **Family UX over engineer UX** — Captive portals, passkeys, auto-VPN, printed cards. The wife/kids test is the real acceptance test.
7. **Git-versioned everything** — Router configs, Ansible playbooks, Docker Compose. Rollback is `git revert`.
8. **Slovenian-first** — Voice assistant must work in Slovenian (Whisper, local LLM). Wi-Fi SSIDs have Slovenian names.
9. **Android ecosystem** — Chromecast built-in, HA Companion, Tasker. Apple devices are secondary (iOS WireGuard app exists).
10. **Budget-conscious but quality-focused** — €4,449 for a server that will last years. €35/mo VPS that's overkill now but grows. No cheap shortcuts.

---

## 📈 Suggested Next Discussion Topics

1. **Resolve VPS vs home server service placement** (Immich, Kopia target)
2. **Decide VPN strategy** (WireGuard-only vs WireGuard+Headscale)
3. **Consolidate DNS architecture** (single doc covering Technitium+Pi-hole+AdGuard)
4. **Clarify MS-A2 role** (separate device or superseded?)
5. **Define documentation deliverable format** (Markdown, bilingual, printed?)
6. **Prioritize Ansible role development** (which service first?)
7. **Prototype the travel router captive portal** (highest technical risk)
8. **Plan the Slovenian wake word pipeline** (ESP32-S3 feasibility check)
