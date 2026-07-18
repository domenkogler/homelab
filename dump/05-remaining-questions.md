# 🟢 All Open Questions — Resolved

---

**1. Rename `/opt/nextcloud/` directories to `/opt/opencloud/`?**

**→ Keep as-is for now.** Will test both on deblab before deciding. Infomaniak likely chosen for degoogling anyway.

---

**2. Cloudflare proxy or expose VPS IP directly?**

**→ Not decided. Needs investigation.** Both paths documented.

---

**3. Home Assistant: stay on Raspberry Pi 4 or migrate to Proxmox LXC?**

**→ Stays on Raspberry Pi 4.** Backup LXC on home server. HA configs move to this repo.

---

**4. Immich photos on Hetzner Storage Box — also back up to iDrive e2?**

**→ Yes,** photos go to iDrive e2 via Kopia for off-site redundancy.

---

**5. Domain and subdomain names?**

| Service | Subdomain | Access |
|---------|-----------|--------|
| Immich | `foto.kogler.si` | Public |
| OpenCloud | `file.kogler.si` | Public |
| Authentik | `sso.kogler.si` | Public |
| Forgejo | `git.kogler.si` | Public |
| Kopia Web UI | `bck.kogler.si` | Public (SSO) |
| Headscale | `vpn.kogler.si` | Public |
| Grafana | `stats.kogler.si` | Public (SSO) |
| Home Assistant | `ha.kogler.lan` | Local |
| Technitium | `dns.kogler.lan` | Local |
| Pi-hole | `ad.kogler.lan` | Local |

Suggested additions (to consider): `traefik.kogler.lan`, `pve.kogler.lan`, `pve-home.kogler.lan`, `status.kogler.si`, `sec.kogler.lan`, `auto.kogler.lan`, `docker.kogler.lan`.

---

**6. Wake word phrase?**

**→ "Hey, assistant"** (tentative — family meeting still needed).

---

**7. Wall-mounted tablet for TileBoard?**

**→ Not decided yet.**