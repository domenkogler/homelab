# Improvements & Next Steps

> Actionable suggestions that emerged from connecting all the ideas.  
> None of these discard anything — they refine and complement.

---

## 🟢 Suggestions for Improvement

### 1. Consolidate Duplicate Files
Three pairs of files contain nearly identical or overlapping content:

| Duplicate Pair | Recommended Action |
|---------------|-------------------|
| `Home Lab & Family Network Architecture.md` ≈ `Homelab network architecture.md` | **Keep one**, rename to `network-architecture.md`, delete the other |
| `Homeassistant rework prompt.md` → `Homeassistant rework.md` | Keep the refined one. The first is a template for AI prompting |
| `potovalni vpn prompt.md` → `potovalni.vpn.md` → `Road warrior plan.md` | Merge into one `travel-vpn-design.md` covering both WireGuard+Headscale |
| `nov strežnik.md` → `new home server...` → `Stroškovnik...` | Keep only `Stroškovnik za novi strežnik.md` as canonical. Archive the others in an `archive/` folder |

### 2. Create a Single "Source of Truth" per Domain
Having one canonical document per domain prevents drift:

```
docs/
  network-architecture.md          ← VLANs, firewall, DNS (merge from 3 files)
  home-server-hardware.md          ← Final BOM only
  vps-application-stack.md         ← družinski web sistem (rename to English)
  vps-security.md                  ← Varnostni načrt
  smart-home-voice.md              ← Slovenian voice + audio
  home-assistant-dashboards.md     ← TileBoard + Grafana strategy
  travel-vpn.md                    ← Merged VPN/road-warrior docs
  local-llm-office.md              ← Local LLM for Word/Mail/PPT
  1password-authentik.md           ← Keep as-is
  db-backup-strategy.md            ← Keep as-is
  archive/                         ← Superseded docs
```

### 3. Define an Explicit IP Address Registry
The subnets are scattered across docs. Create one authoritative table:

| Network | CIDR | Gateway | DHCP Range | DNS | Location |
|---------|------|---------|------------|-----|----------|
| Management | 10.10.99.0/24 | 10.10.99.1 | ... | ... | Home |
| Home | 10.10.1.0/24 | 10.10.1.1 | ... | ... | Home |
| IoT | 10.10.20.0/24 | 10.10.20.1 | ... | ... | Home |
| Guest | 10.10.30.0/24 | 10.10.30.1 | ... | ... | Home |
| Kids | 10.10.40.0/24 | 10.10.40.1 | ... | ... | Home |
| VPS DMZ | 10.255.10.0/24 | ... | ... | ... | VPS |
| VPS Services | 10.255.20.0/24 | ... | ... | ... | VPS |
| VPS Lab | 10.255.30.0/24 | ... | ... | ... | VPS |
| S2S Tunnel | 10.255.40.0/30 | ... | static | ... | Both |
| Road-Warrior | 10.255.200.0/24 | ... | static | ... | Home |
| Travel LAN | 192.168.123.0/24 | 192.168.123.1 | ... | ... | Travel |
| Headscale | 100.64.0.0/10 | ... | ... | ... | Overlay |

### 4. Add a "Family Documentation" Section
The prompt emphasizes that the family should be able to continue without you. Create a `docs/family/` folder with **Slovenian-language guides**:

- `Kako uporabljati WiFi.md` — Which SSID for which purpose
- `Kako dostopati do slik (Immich).md` — Photo access from phone/PC
- `Kako deliti datoteke (OpenCloud).md` — File sharing
- `Kako uporabljati VPN na potovanju.md` — Travel router + Headscale
- `Kako ponovno zagnati strežnik.md` — Physical reset procedure
- `Kontakti za pomoč.md` — Who to call if everything breaks (ISP, friends, etc.)
- `Obnovitev iz varnostne kopije.md` — Disaster recovery in Slovenian

### 5. Create a "Runbook" for Disaster Recovery
A separate `docs/runbook/` folder with step-by-step recovery procedures:

- Router factory reset → restore from Git
- Home server dead → reinstall Proxmox → Ansible reprovision
- VPS destroyed → rebuild from Docker Compose + Kopia restore
- 1Password vault lost → what's the recovery path?
- Total house loss → what's recoverable from VPS + offsite?

### 6. Proxmox-specific: Document VM/LXC Layout
When the home server is built, document:

```
Proxmox Host (deblab-prod or kogler-hv1):
├─ LXC: docker-host (privileged? unprivileged with GPU map?)
│   ├─ Ollama
│   ├─ n8n
│   ├─ Home Assistant (or separate LXC?)
│   └─ Headscale
├─ LXC: monitoring (Grafana, InfluxDB, Telegraf)
├─ VM: (future Windows/Linux lab VMs)
└─ Storage:
    ├─ NVMe Gen5 → LXC root disks, DBs, LLM models
    └─ SATA SSD/HDD → media, backups
```

### 7. Start a Changelog
Since the idea evolved over time, add a `CHANGELOG.md` to track decisions:

```markdown
# Changelog

## 2026-07-16 — Brainstorming synthesis
- Identified 7 decision conflicts across docs
- Resolved: motherboard (ASUS B850), chassis (open-frame), KVM (Comet)
- Unresolved: Immich location, VPN strategy, DNS architecture

## 2026-06-27 — Network architecture finalized
- 4-VLAN design adopted
- WireGuard chosen over IPsec

## 2026-06-24 — Application stack finalized
- OpenCloud replaces Nextcloud
- Infomaniak for email/calendar
```

### 8. Router Config: Export Current State
The audit in the architecture doc references an `rb4011_config.rsc` that isn't in the repo.

- **Export the current RB4011 config** and commit it to `Iaac/router/rb4011-current.rsc`
- **Before any changes**, the backup is the safety net

### 9. Add a `.gitignore` for Secrets
The Ansible playbook references 1Password for secrets — good. But ensure:

```
# .gitignore
*.rsc (if containing keys — or scrub before commit)
.env
**/secrets/
ansible/vault-password
```

### 10. Standardize Language
Current docs are mixed Slovenian/English:
- Technical docs: **English** (wider community, better tooling)
- Family docs: **Slovenian** (target audience)
- Code comments: **English** (convention)
- File names: **English** (avoid encoding issues with ščž)

---

## 🎯 Next Steps — Prioritized

### Immediate (This Week)
1. ✅ Synthesis complete — review `dump/01-master-synthesis.md`
2. ❓ Answer the questions in `dump/02-questions-by-theme.md`
3. 📋 Resolve the 4 unresolved conflicts (Immich location, VPN strategy, DNS, MS-A2)
4. 📁 Reorganize docs folder (move superseded to `archive/`, create canonical docs)

### Short Term (Next 1-2 Weeks)
5. Export `rb4011_config.rsc` to repo
6. Create the IP address registry
7. Write `travel-vpn-design.md` (merge 3 VPN docs)
8. Write `home-server-hardware.md` (single canonical BOM)
9. Start family documentation in Slovenian

### Medium Term (After Hardware Arrives)
10. Proxmox installation + GPU passthrough
11. Docker Compose for VPS stack (Traefik, Authentik, OpenCloud, Immich)
12. Ansible roles for `storage`, `identity`, `apps`
13. WireGuard tunnel between home and VPS
14. Travel router prototype (captive portal is highest-risk component)

### Long Term
15. Slovenian wake word + voice pipeline
16. TileBoard + Grafana dashboards (once HA entity list is available)
17. Quarterly backup restore drill
18. Family documentation printed + stored with hardware

---

## 📊 Progress Dashboard

| Domain | Design | Implemented | Documented | Tested |
|--------|--------|-------------|------------|--------|
| Network VLANs | ✅ | ❌ | ✅ | ❌ |
| Firewall Rules | ✅ | ❌ | ✅ | ❌ |
| Home Server HW | ✅ | ❌ | ✅ | ❌ |
| VPS Services | ✅ | ❌ | ✅ | ❌ |
| Authentik SSO | ✅ | ❌ | ✅ | ❌ |
| WireGuard S2S | ✅ | ❌ | ✅ | ❌ |
| Travel VPN | ⚠️ | ❌ | ⚠️ | ❌ |
| Headscale | ⚠️ | ❌ | ⚠️ | ❌ |
| DNS Architecture | ⚠️ | ❌ | ⚠️ | ❌ |
| Backup (Kopia+DB) | ✅ | ❌ | ✅ | ❌ |
| Voice Assistant | ✅ | ❌ | ✅ | ❌ |
| Dashboards | ✅ | ❌ | ⚠️ | ❌ |
| Ansible (common) | ✅ | ✅ | ✅ | ⚠️ |
| Ansible (apps) | ❌ | ❌ | ❌ | ❌ |
| Family Docs | ❌ | ❌ | ❌ | ❌ |
| Disaster Recovery | ❌ | ❌ | ❌ | ❌ |

**Legend:** ✅ = Done | ⚠️ = Partial/Needs decision | ❌ = Not started
