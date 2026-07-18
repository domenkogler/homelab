# Family Documentation Plan

> **Goal:** The family can operate and recover the homelab without Domen.  
> Based on answers from Theme G.

---

## Format

- **Language:** Slovenian for family guides, English for technical deep-dives
- **Storage:** Markdown in the homelab Git repo (self-hosted Forgejo + GitHub mirror)
- **Starting point:** `README.md` at repo root

---

## Documentation Structure

```
docs/family/
  README.md                          # "Kje začeti?" — entry point (SI)
  01-kako-uporabljati-wifi.md        # Which SSID, which VLAN, password reset (SI)
  02-kako-dostopati-do-slik-immich.md # Immich from phone and PC (SI)
  03-kako-deliti-datoteke-opencloud.md# OpenCloud usage (SI)
  04-kako-uporabljati-vpn.md         # Tailscale app on phone (SI)
  05-kako-uporabljati-potovalni-usmerjevalnik.md # Travel router + hotel Wi-Fi (SI)
  06-kako-znova-zagnati-streznik.md  # Physical reset procedure (SI)
  07-kako-obnoviti-iz-varnostne-kopije.md # Disaster recovery (SI, high-level)
  08-kontakti-za-pomoc.md            # ISP, friends, service contacts (SI)
  09-kako-upravljati-pametno-hiso.md # HA dashboard, voice commands (SI)

docs/technical/                      # Engineering docs (EN)
  01-network-architecture.md
  02-home-server-hardware.md
  03-vps-infrastructure.md
  04-vpn-and-remote-access.md
  05-smart-home-and-voice.md
  06-backup-and-disaster-recovery.md
  07-iaac-and-automation.md
  08-local-llm-office.md

Iaac/                                # Ansible, scripts, router configs
dump/                                # Brainstorming synthesis (this batch)
```

---

## Family Safe Contents

Physical paper stored in family safe:

1. **1Password master password + recovery codes**
2. **Link to GitHub repo** (Forgejo URL + public GitHub mirror URL)
3. **Brief instructions in Slovenian:**
   - "Odpri ta link na računalniku"
   - "Preberi README.md"
   - "Če ne razumeš, pokliči [trusted tech contact]"

---

## README.md (Repo Root) — Draft Outline (SI+EN)

```markdown
# Kogler Homelab

To je domači strežnik in omrežje družine Kogler.
Vse je opisano tako, da lahko deluje brez Domna.

## Za družino (v slovenščini)
→ [Dokumentacija za družino](docs/family/README.md)

## Za vzdrževalce (in English)
→ [Network Architecture](docs/technical/01-network-architecture.md)
→ [Home Server Hardware](docs/technical/02-home-server-hardware.md)
→ [VPS Infrastructure](docs/technical/03-vps-infrastructure.md)
→ [VPN & Remote Access](docs/technical/04-vpn-and-remote-access.md)
→ [Smart Home & Voice](docs/technical/05-smart-home-and-voice.md)
→ [Backup & Disaster Recovery](docs/technical/06-backup-and-disaster-recovery.md)
→ [IaC & Automation](docs/technical/07-iaac-and-automation.md)

## Hitra pomoč
- [Kontakti](docs/family/08-kontakti-za-pomoc.md)
- V družinskem sefu so 1Password gesla in link do te strani
```

---

## Family Guide Topics to Write

| Guide | Audience | Content |
|-------|----------|---------|
| **WiFi usage** | Wife, kids | "Kogler" for everything. "Kogler IOT" for smart devices. "Kogler guest" for visitors. |
| **Immich** | Wife | How to view, upload, share photos from phone. How to create albums. |
| **OpenCloud** | Wife, kids | How to save, share, and find files. Windows Explorer integration. |
| **VPN (Tailscale)** | Wife, kids (14+) | Open app → tap Connect. Check: whatismyip.com shows home IP. |
| **Travel router** | Wife | Plug in. Connect to "Family-Traveling". Open `potovalni.vpn` in browser. Enter hotel Wi-Fi details. If hotel has login page: first connect phone to hotel Wi-Fi directly. |
| **Server restart** | Wife | Where the rack is. Which button to press (with photo). Wait 5 minutes. |
| **Restore from backup** | Trusted tech contact | High-level steps. Link to technical docs for details. |
| **Smart home** | Everyone | How to use the dashboard. Voice commands (when implemented). |

---

## Language Convention

| Content | Language | Reason |
|---------|----------|--------|
| Family guides | **Slovenian** | Target audience |
| Technical docs | **English** | Tooling, community, broader audience |
| Code comments | **English** | Convention |
| README.md | **Bilingual** | Entry point for both audiences |
| Commit messages | **English** | Convention |

---

## Not Yet Written

The `docs/family/` guides don't exist yet — they depend on:
1. Services being deployed (Immich, OpenCloud, Tailscale)
2. Screenshots of actual interfaces
3. Travel router prototype working

> **Recommendation:** Write these incrementally as each service goes live. Don't try to document everything upfront.