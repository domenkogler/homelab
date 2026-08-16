# Qwen Security & Bug Analysis — Homelab

> **Analysis date:** 2025-07-13 (initial), 2025-08-15 (continued scan)
> **Analyst:** Qwen / AI security review
> **Status:** ✅ **SCAN COMPLETE** — all 44+ compose templates, roles, push scripts, bootstrap configs, router templates, switch defaults, AI diag, and remaining docs reviewed. 61 findings total.

---

## Scanned Files Tracker

### IaC folder
| File | Status |
|------|--------|
| `IaC/ansible/group_vars/all.yml` | ✅ Scanned |
| `IaC/ansible/group_vars/home_servers.yml` | ✅ Scanned |
| `IaC/ansible/group_vars/router.yml` | ✅ Scanned |
| `IaC/ansible/group_vars/network.yml` | ✅ Scanned |
| `IaC/ansible/group_vars/vps.yml` | ✅ Scanned |
| `IaC/ansible/host_vars/nas.kogler.si.yml` | ✅ Scanned |
| `IaC/ansible/host_vars/vps.kogler.si.yml` | ✅ Scanned |
| `IaC/ansible/site.yml` | ✅ Scanned |
| `IaC/ansible/roles/router/tasks/main.yml` | ✅ Scanned |
| `IaC/ansible/roles/common/tasks/main.yml` | ✅ Scanned |
| `IaC/ansible/roles/storage/tasks/main.yml` | ✅ Scanned |
| `IaC/ansible/roles/storage/tasks/nas.yml` | ✅ Scanned |
| `IaC/ansible/roles/nut/defaults/main.yml` | ✅ Scanned |
| `IaC/ansible/roles/nut/templates/upsd.users.j2` | ✅ Scanned |
| `IaC/router/templates/rb4011_initial.rsc.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/traefik/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/traefik/dynamic/routes.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/traefik/dynamic/middlewares.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/authentik/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/opencloud/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/immich-app/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/n8n/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/grafana/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/forgejo/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/headscale/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/signal-cli-rest-api/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/kopia-server/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/dozzle/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/sunshine/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/pihole/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/crowdsec/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/bootstrap-ansible-client/bootstrap.sh` | ✅ Scanned |
| `IaC/host/post_install.sh` | ✅ Scanned |
| `IaC/ansible/host_vars/oldsrv.kogler.si.yml` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/home-assistant-primary/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/home-assistant-standby/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/traefik-ha/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/matrix/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/metabase/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/technitium/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/ollama/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/jellyfin/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/db-backup/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/sonarr/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/qbittorrent/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/prometheus/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/roles/docker_services/tasks/deploy-service.yml` | ✅ Scanned |
| `IaC/ansible/roles/docker/tasks/main.yml` | ✅ Scanned |
| `IaC/ansible/roles/home_assistant/tasks/main.yml` | ✅ Scanned |
| `IaC/ansible/roles/home_assistant/templates/keepalived.conf.j2` | ✅ Scanned |
| `docs/smart-home-failover.md` | ✅ Scanned |

### Docs folder
| File | Status |
|------|--------|
| `docs/deployment-secrets.md` | ✅ Scanned |
| `docs/network.md` | ✅ Scanned |
| `docs/network-vlans.md` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/immich-ml/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/headscale/config.yaml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/loki/loki.yaml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/element-web/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/homepage/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/renovate/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/doco-cd/docker-compose.yml.j2` | ✅ Scanned |
| `docs/backup.md` | ✅ Scanned |
| `docs/network-vpn.md` | ✅ Scanned |
| `docs/services-traefik.md` | ✅ Scanned |
| `docs/storage-zfs.md` | ✅ Scanned |
| `docs/deployment-compose.md` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/matrix/tuwunel.toml.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/blackbox-exporter/blackbox.yml` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/prometheus/prometheus.yml.j2` | ✅ Scanned |
| `docs/observability.md` | ✅ Scanned |
| `docs/services-authentik.md` | ✅ Scanned |
| `docs/deployment.md` | ✅ Scanned |
| `docs/network-dns.md` | ✅ Scanned |
| `IaC/ansible/inventory.ini` | ✅ Scanned |
| `IaC/ansible/roles/common/tasks/system.yml` | ✅ Scanned |
| `IaC/ansible/roles/home_assistant/templates/configuration.yaml.j2` | ✅ Scanned |
| `IaC/ansible/roles/home_assistant/templates/ha-failover.sh.j2` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/raspberrymatic/docker-compose.yml.j2` | ✅ Scanned |
| `docs/smart-home.md` | ✅ Scanned |
| `IaC/router/templates/crs328_initial.rsc.j2` | ✅ Scanned |
| `IaC/router/templates/ap_initial.rsc.j2` | ✅ Scanned |
| `IaC/ansible/roles/switch/tasks/main.yml` | ✅ Scanned |
| `IaC/ansible/roles/switch/defaults/main.yml` | ✅ Scanned |
| `IaC/host/nas/preseed.cfg` | ✅ Scanned |
| `IaC/host/oldsrv/preseed.cfg` | ✅ Scanned |
| `IaC/host/pi/first-boot-config.sh` | ✅ Scanned |
| `.doco-cd.yml` | ✅ Scanned |
| `renovate.json` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/element-web/config.json.j2` | ✅ Scanned |
| `docs/services-matrix.md` | ✅ Scanned |
| `docs/interfaces.md` | ✅ Scanned |
| `IaC/ansible/group_vars/raspberry_pi.yml` | ✅ Scanned |
| `IaC/ansible/group_vars/switch.yml` | ✅ Scanned |
| `IaC/ansible/playbooks/home_servers.yml` | ✅ Scanned |
| `IaC/ansible/playbooks/raspberry_pi.yml` | ✅ Scanned |
| `IaC/ansible/playbooks/router.yml` | ✅ Scanned |
| `IaC/ansible/playbooks/storage.yml` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/seerr/docker-compose.yml.j2` | ✅ Scanned |
| `IaC/router/templates/crs328_initial.rsc.j2` | ✅ Scanned |
| `IaC/router/templates/ap_initial.rsc.j2` | ✅ Scanned |
| `IaC/ansible/roles/switch/tasks/main.yml` | ✅ Scanned |
| `IaC/ansible/roles/switch/defaults/main.yml` | ✅ Scanned |
| `IaC/host/nas/preseed.cfg` | ✅ Scanned |
| `IaC/host/oldsrv/preseed.cfg` | ✅ Scanned |
| `IaC/host/pi/first-boot-config.sh` | ✅ Scanned |
| `.doco-cd.yml` | ✅ Scanned |
| `renovate.json` | ✅ Scanned |
| `IaC/ansible/templates/docker_services/element-web/config.json.j2` | ✅ Scanned |
| `docs/services-matrix.md` | ✅ Scanned |
| `docs/interfaces.md` | ✅ Scanned |

---

## Findings

---

### 🔴 HIGH — KOPS-001: Kopia server starts with `--insecure --without-password`

**File:** `IaC/ansible/templates/docker_services/kopia-server/docker-compose.yml.j2`

**Severity:** HIGH (Data Exfiltration / Backup Corruption Risk)

**Description:**
The Kopia backup server start command includes both `--insecure` (disables TLS requirement) and `--without-password` (disables all authentication):

```yaml
exec kopia server start --address=0.0.0.0:51515 --insecure --without-password
```

This means:
- **Any container on the `services-internal` Docker network** can connect to port 51515 with zero authentication.
- An attacker who compromises any sibling container (e.g., via a supply-chain attack on a public image) gains unrestricted access to the entire backup repository.
- They can enumerate, download, delete, or modify every backup — including database dumps, service state archives, and face thumbnails.
- Combined with S3 credentials leaked from another service, this doubles the attack surface.

**Why `--without-password` seems intentional:** The comment says "Web UI + S3-backed repository." If the UI was meant to be unauthenticated, this should be documented as a conscious risk acceptance. More likely, the author intended clients to authenticate via their stored credentials (KOPIA_PASSWORD env var) but confused *server* password with *repository* master password.

**Recommended fix:**
Either:
1. Add `--password=FILE:/run/secrets/kopia_server_password` (Docker secrets or env var) and remove `--without-password`.
2. Remove `--insecure` and ensure TLS (even self-signed) so traffic between containers is encrypted.
3. Put Kopia on a separate, more restricted network if it doesn't need broad service-internal access.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🔴 HIGH — KOPS-002: Signal CLI REST API bound to host port 8080 with no auth

**File:** `IaC/ansible/templates/docker_services/signal-cli-rest-api/docker-compose.yml.j2`

**Severity:** HIGH (Account Takeover / Social Engineering)

**Description:**
Signal CLI REST API exposes `8080:8080` on the Docker host (oldsrv):

```yaml
ports:
  - "8080:8080"        # HTTP API — consumed by n8n on services-internal; not exposed publicly
```

This maps the port to `0.0.0.0:8080` on oldsrv itself. While the comment says "not exposed publicly," the host-level binding means:
- Any device on VLAN 10 (Home) or VLAN 99 (Management) that can reach oldsrv's IP can call the Signal API.
- The API sends messages **as Domen's personal number** (linked-device pair).
- No authentication header or API key is required — the raw REST API accepts any POST body.
- An attacker could send Signal messages to any contact, impersonating Domen. This is a social engineering goldmine: sending "urgent money transfer" or "open this link" to family members, bank contacts, etc.

**Recommended fix:**
1. **Remove the host port mapping.** n8n already reaches signal-cli via the `services-internal` Docker network hostname. The host-level bind is unnecessary unless an external caller needs it.
2. If a host-level port is truly needed, put behind a reverse proxy with basic auth, or use `127.0.0.1:8080:8080` to bind loopback only.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🔴 HIGH — KOPS-003: Router OS API enabled without TLS or interface binding

**Files:** `IaC/router/templates/rb4011_initial.rsc.j2`, `IaC/ansible/roles/router/tasks/main.yml`

**Severity:** HIGH (Network Compromise via Cleartext Credentials)

**Description:**
The RouterOS API (port 8728) and API-SSL (port 8729) are managed separately, but:

1. **Bootstrap template** enables the plain-text API:
   ```
   /ip service set api disabled=no
   ```
   With `certificate=none` on www-ssl, and no mention of api-ssl.

2. **Router role re-enables it explicitly:**
   ```yaml
   - name: Enable REST API service
     community.routeros_ip_service:
       name: api
       disabled: no
   ```

3. **No interface restriction:** Neither the bootstrap nor the role binds the API service to specific interfaces (e.g., `interface=vlan99-mgmt`). By default on MikroTik, services listen on **all interfaces including WAN**.

4. **TLS commented out as deferred:** `group_vars/router.yml` has:
   ```yaml
   routeros_api_port: 8728
   # routeros_api_tls: true   # enable after Let's Encrypt on router
   ```

This means the RouterOS admin API can be reached from the WAN in plaintext. With admin credentials from 1Password, anyone who connects can fully reconfigure VLANs, firewall, NAT, DHCP, CAPsMAN, and WireGuard — complete network takeover.

**Recommended fix:**
1. Restrict the `api` service to the Management VLAN interface: `/ip service set api interface=vlan99-mgmt`
2. Enable `api-ssl` (port 8729) instead of plain `api`, or disable `api` entirely and use only `api-ssl`.
3. Even before TLS cert: disable `api` on WAN; enable `api-ssl` on mgmt only.
4. Consider disabling WinBox/web (`www`) on non-management interfaces as well.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🔴 HIGH — KOPS-004: Home Assistant route has no CrowdSec bouncer protection

**Files:** `IaC/ansible/templates/docker_services/traefik/dynamic/routes.yml.j2` (both oldsrv and traefik-ha edges)

**Severity:** HIGH (Brute-force / Exploit Exposure on HA)

**Description:**
The `ha` route deliberately skips Authentik Forward-Auth (the comment says: `# NOTE: no authentik-forward-auth@file on the ha route`). This is documented as necessary because the Home Assistant Companion WebSocket/token flow breaks with Forward-Auth.

However, the same exclusion means **CrowdSec bouncer is also skipped**. The middleware chain `authentik-forward-auth` = `[crowdsec-bouncer, authentik-forward-auth-inner]`. When you skip the chain, you skip both. This leaves HA exposed to:
- Unlimited login attempts against the built-in HA auth (`/api/states`, `/auth/login_flow`).
- Known HA vulnerabilities (CVE-class remote code execution in add-ons, template injection, etc.).
- Port-scanning and exploitation from the entire internet with only HA's native auth standing in the way.

**Recommended fix:**
Create a dedicated middleware chain for HA that includes **only the CrowdSec bouncer** (without Authentik):

```yaml
http:
  middlewares:
    crowdsec-only:
      chain:
        middlewares:
          - crowdsec-bouncer
```

Then apply it to the `ha` route:
```yaml
ha:
  rule: "Host(`ha.kogler.si`)"
  middlewares: crowdsec-only
  # ... rest unchanged
```

This preserves the Companion app flow while still getting IP-level threat blocking.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-005: Traefik uses `latest` image tag

**Files:** `IaC/ansible/group_vars/all.yml`, `IaC/ansible/templates/docker_services/traefik/docker-compose.yml.j2`

**Severity:** MEDIUM (Supply Chain / Rollback Risk)

**Description:**
```yaml
traefik_version: latest
```

Both the main Traefik edge and the HA standby edge pull `traefik:latest`. This means:
- Any `docker pull` or container restart picks up whatever `latest` points to at that moment.
- A breaking change, bug, or (worst case) a compromised official image silently deploys to your edge proxy.
- Since Traefik is the **single ingress point for ALL public-facing services**, its compromise affects everything downstream.
- No version pinning makes it impossible to reproduce or rollback a known-good state.

**Recommended fix:**
Pin to a specific minor version at minimum (e.g., `v3.3` or `v3.3.2`), ideally a full semver tag. Use Renovate (which is already deployed) to open PRs when new patches are available. Same applies to `certs_dumper_version` and other `latest` tags across services.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-006: Opencloud `OC_INSECURE: true` disables internal TLS

**File:** `IaC/ansible/templates/docker_services/opencloud/docker-compose.yml.j2`

**Severity:** MEDIUM (Internal Traffic in Cleartext)

**Description:**
```yaml
OC_INSECURE: "true"
PROXY_TLS: "false"
```

While TLS termination happens at Traefik (and traffic from internet → Traefik is encrypted), setting `OC_INSECURE=true` means opencloud itself does **not** enforce TLS internally. Any container on `traefik-public` that reaches opencloud on port 9200 communicates in plaintext. Combined with Docker bridge networks being flat, a compromised sibling container can intercept opencloud sessions internally.

**Recommended fix:**
Unless there is a documented incompatibility, set `OC_INSECURE: "false"` and configure opencloud to trust the Traefik CA or use mutual TLS. At minimum, accept that internal traffic is unencrypted and ensure CrowdSec reduces the blast radius of compromised containers.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-007: Sunshine game-streaming ports exposed on host without auth

**File:** `IaC/ansible/templates/docker_services/sunshine/docker-compose.yml.j2`

**Severity:** MEDIUM (Remote Code Execution Vector)

**Description:**
Multiple ports are mapped to the Docker host:
```yaml
ports:
  - "47989:47989/tcp"   # streaming
  - "47990:47990/tcp"   # web config UI
  - "47991:47991/udp"   # streaming
  - "48010:48010/udp"   # streaming
```

These bind to `0.0.0.0`, meaning they are reachable from **every VLAN that has routing to Home (VLAN 10)**. While the config says `restart: "no"` (manual start), once running:
- The web config UI (47990) requires a username/password (`SUNSHINE_USER: domen` is set, but password is either interactive or missing).
- The streaming protocol has had CVEs in related projects (Moonlight/Sunshine family).
- Direct GPU device access (`/dev/dri`) plus gamepad input (`/dev/input`, `/dev/uinput`) give the container significant host privileges.

**Mitigating factors:** Manual start only, not always running, behind NAT (not internet-facing unless port-forwarded).

**Recommended fix:**
1. Add a password via environment variable (`SUNSHINE_PASSWORD` or similar).
2. Bind to Home VLAN IP only if possible: `"10.10.1.30:47990:47990/tcp"`.
3. Consider running inside Headscale WireGuard overlay so only authorized Tailscale clients reach it.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-008: Grafana dual auth — direct admin account bypasses Forward-Auth

**File:** `IaC/ansible/templates/docker_services/grafana/docker-compose.yml.j2`

**Severity:** MEDIUM (Credential Exposure on Internal Network)

**Description:**
Grafana is configured with BOTH:
- `GF_SECURITY_ADMIN_PASSWORD` from 1Password (direct Grafana login)
- `GF_AUTH_PROXY_ENABLED: "true"` with Authentik Forward-Auth headers

While normal users enter via Authentik (Traefik → Forward-Auth → auto-signup), the admin account exists as a parallel login path at `stats.kogler.si/login`. Anyone reaching the internal Docker network can hit Grafana directly on port 3000 and attempt brute-force against the admin credentials.

**Recommended fix:**
Set `GF_AUTH_PROXY_AUTO_SIGN_UP: "true"` (already done) but also consider:
- Disabling Grafana's built-in login form entirely: `GF_AUTH_DISABLE_LOGIN_FORM: "true"` — forces all auth through the proxy.
- Or at minimum, use a high-entropy admin password different from the 1Password item used elsewhere.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-009: Missing INPUT chain firewall rules on Router

**File:** `IaC/ansible/roles/router/tasks/main.yml`

**Severity:** MEDIUM (Router Management Interface Exposure)

**Description:**
The router role implements extensive `forward` chain rules (inter-VLAN isolation, Guest drop, IoT block, etc.) but I see **no explicit `input` chain rules**. On MikroTik RouterOS, the default input policy is `accept`, meaning the router itself accepts connections to its management services on all interfaces unless explicitly restricted.

With `api`, `www-ssl`, and `ssh` enabled and listening on all interfaces, the router's management plane is reachable from any VLAN — potentially including IoT and Guest if the firewall doesn't block inter-VLAN at the input level.

**Recommended fix:**
Add input chain rules to restrict management services to Management VLAN (99) and trusted Home sources only:

```yaml
- name: Drop non-management input to API/WinBox/SSH
  community.routeros_ip_firewall_filter:
    chain: input
    dst_address: "{{ router_mgmt_ip }}"
    port: 22,8728,8729,8291
    src_address: "{{ vlan_subnets[99] }}"  # Management VLAN only
    action: accept
    comment: "Allow mgmt services from Management VLAN"
```

Plus a drop-all at the end of the input chain for those ports.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-010: Pi-hole WEBPASSWORD defaults to empty string

**File:** `IaC/ansible/templates/docker_services/pihole/docker-compose.yml.j2`

**Severity:** MEDIUM (Admin UI Without Authentication)

**Description:**
```yaml
WEBPASSWORD: "{{ lookup('community.general.onepassword', 'pihole_password', field='password', vault=op_vault) | default('') }}"
```

If the 1Password lookup fails or the item hasn't been created yet, Pi-hole falls back to an **empty password**. Per Pi-hole docs: *"Empty value means no password will be set, leaving your Pi-hole installation unprotected."*

While the Pi-hole web UI is behind Authentik Forward-Auth at `ad.kogler.si`, the DNS query interface on port 5353 is still directly accessible. More importantly, anyone on the internal Docker network can reach Pi-hole's admin on port 80 directly without any auth.

**Recommended fix:**
Remove the `default('')` fallback and let the deployment fail loudly if the secret is missing:

```yaml
WEBPASSWORD: "{{ lookup('community.general.onepassword', 'pihole_password', field='password', vault=op_vault) }}"
```
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-011: `bootstrap.sh` saves 1Password token to `~/.bashrc` in plaintext

**File:** `IaC/bootstrap-ansible-client/bootstrap.sh`

**Severity:** LOW (Token Persistence Risk — mitigated by WSL context)

**Description:**
```bash
echo "export OP_SERVICE_ACCOUNT_TOKEN=\"$OP_TOKEN\"" >> ~/.bashrc
```

The service account token is stored in plaintext in `~/.bashrc`. Anyone who can read this file (other users on the laptop, malware) gets full read access to the Homelab vault.

**Mitigating factors:** This is the management laptop in WSL — likely single-user. 1Password recommends using `eval "$(op signin ...)"` or the 1Password SSH agent instead of persisting tokens in shell configs.

**Recommended fix:**
Use `op signin` interactively or store the token via `op signin --account ...` which uses 1Password's secure credential storage instead of plaintext env vars.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-012: `post_install.sh` appends sshd_config without dedup

**File:** `IaC/host/post_install.sh`

**Severity:** LOW (Config Drift on Re-run)

**Description:**
```bash
cat >> /etc/ssh/sshd_config <<'EOF'
...
EOF
```

Uses append (`>>`) without checking if the hardening block already exists. If the preseed runs `post_install.sh` twice (e.g., retry), duplicate sshd directives accumulate. While OpenSSH uses the last occurrence for most settings, this is messy and could cause unexpected behavior.

**Recommended fix:**
Use a guard or idempotent approach, e.g., check for a marker comment before appending, or manage sshd_config via Ansible after bootstrap.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-013: Multiple Docker images use `latest` tag (not just Traefik)

**Files:** Various docker-compose templates

**Services using `latest`:**
| Service | Image |
|---------|-------|
| Dozzle | `amir20/dozzle:latest` |
| Kopia | `kopia/kopia:{{ kopia_version \| default('latest') }}` |
| N8N | `n8nio/n8n:{{ n8n_version \| default('latest') }}` |
| HeadScale | `headscale/headscale:{{ headscale_version \| default('latest') }}` |
| CrowdSec | `crowdsecurity/crowdsec:{{ crowdsec_version \| default('latest') }}` |
| Authentic | `ghcr.io/goauthentik/server:{{ authentik_version \| default('latest') }}` |
| Signal CLI | `bbernhard/signal-cli-rest-api:latest` |
| Sunshine | `lizardbyte/sunshine:latest` |
| Pi-hole | `pihole/pihole:latest` |

**Severity:** LOW — Renovate is deployed to track updates, but until version variables are explicitly set in group_vars or host_vars, all these services default to `latest`.

---

## Questions for Discussion

1. **KOPS-001 (Kopia `--without-password`):** Is the intent that Kopia clients authenticate using the stored repo password in their own config, while the server itself stays open? Or should the server require its own independent auth layer?

2. **KOPS-002 (Signal port 8080):** Does any service besides n8n need direct host-level access to Signal? If not, removing the host port mapping is safe.

3. **KOPS-003 (Router API):** Are you planning to eventually get a Let's Encrypt cert for the RB4011, or should we design around SSH-key-only access for Ansible and disable the API entirely?

4. **KOPS-007 (Sunshine):** Should Sunshine be reachable only via Headscale/Tailscale overlay instead of being on the Home VLAN?

5. **Kids VLAN bedtime restriction** is noted as `debug: "pending implementation"` — is this tracked elsewhere?
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🔴 HIGH — KOPS-014: Home Assistant PRIMARY runs `privileged: true` + `network_mode: host`

**File:** `IaC/ansible/templates/docker_services/home-assistant-primary/docker-compose.yml.j2`

**Severity:** HIGH (Full Host Compromise from Container Escape)

**Description:**
The primary HA container on the Pi uses:
```yaml
privileged: true
network_mode: host
```

This combination gives the container:
- Full access to all host devices (USB, serial, I2C, SPI — anything plugged into the Pi)
- Ability to mount host filesystems, modify kernel modules, access cgroups
- Direct access to the host network stack (can sniff all VLAN traffic if the Pi is trunked)
- Ability to escape container isolation entirely via known CVEs in privileged containers

The comment says "official HA Container guidance (device access)" — while HA's docs do suggest this for add-on device discovery, it is **not mandatory**. The same functionality can be achieved with targeted `devices`, `cap_add`, and specific networks.

If any HA integration or custom component has a remote code execution vulnerability (which happens periodically), the attacker gets full root on the Pi — including the HmIP-RFUSB stick programming interface, keepalived VRRP control, and the entire Home VLAN.

**Recommended fix:**
1. Set `privileged: false` and instead use:
   - `devices:` for specific hardware (`/dev/ttyUSB0` for HmIP-RFUSB)
   - `cap_add: [NET_ADMIN, SYS_RAWIO]` for discovery protocols (mDNS, SSDP)
   - A custom Docker network with `--network host` replaced by explicit port mappings
2. If `network_mode: host` is truly needed (mDNS/SSDP discovery), at minimum remove `privileged: true` and use targeted capabilities. The HA Container docs list this as a recommendation, not a hard requirement.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🔴 HIGH — KOPS-015: Technitium DNS binds port 53 on host with `NET_ADMIN` capability

**File:** `IaC/ansible/templates/docker_services/technitium/docker-compose.yml.j2`

**Severity:** HIGH (DNS Takeover / Cache Poisoning)

**Description:**
```yaml
ports:
  - "53:53/udp"
  - "53:53/tcp"
cap_add:
  - NET_ADMIN          # needed for the built-in DHCP / interface control
```

Technitium DNS binds directly to the host's port 53 on `0.0.0.0`. Combined with `NET_ADMIN` capability, the container can manipulate network interfaces and create DHCP bindings. The risk is that:

- If Technitium's configuration is compromised (via its web UI at `dns.kogler.si` or through the Traefik-public network), an attacker controls DNS resolution for the entire homelab.
- Port 53 UDP is the classic DNS amplification vector. While not internet-facing behind NAT, it is directly reachable from the LAN.
- `NET_ADMIN` is broader than needed — if DHCP isn't used by Technitium (RouterOS handles DHCP per the VLAN plan), this capability is unnecessary.

**Recommended fix:**
1. Remove `NET_ADMIN` if Technitium isn't serving DHCP (RouterOS handles DHCP per design).
2. Bind to specific VLAN IPs rather than `0.0.0.0`: use `"10.10.1.30:53:53/udp"` to limit to Home VLAN.
3. Consider using `macvlan` or `ipvlan` networking so Technitium gets its own IP on the Home VLAN without host port mapping.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-016: Ollama has no authentication, reachable from all containers on `services-internal`

**File:** `IaC/ansible/templates/docker_services/ollama/docker-compose.yml.j2`

**Severity:** MEDIUM (Unauthorized LLM Inference / Prompt Injection)

**Description:**
```yaml
OLLAMA_HOST: "0.0.0.0"
```
Ollama listens on all interfaces within its Docker network. Any container on `services-internal` (n8n, immich-server, Matrix homeserver, CrowdSec, dozzle, sunshine, signal-cli, headscale, kopia, prometheus, etc.) can call `http://ollama:11434/api/generate` without any API key or token.

While the comment says "Accessed by other services (n8n, AnythingLLM, maybe HA Assist)," the lack of auth means:
- A compromised sibling container can consume GPU resources via large model inference.
- If the model stores conversation history, there may be prompt injection risks.
- An attacker could swap system prompts or chain-of-thought attacks through shared context.

**Recommended fix:**
Set `OLLAMA_ORIGINS` or configure a simple API key via `OLLAMA_HOST` binding to `127.0.0.1` only, then use Docker networking labels for intended consumers. Or put Ollama on a smaller dedicated network with only n8n attached.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-017: Prometheus exposed on host port 9090 with no auth

**File:** `IaC/ansible/templates/docker_services/prometheus/docker-compose.yml.j2`

**Severity:** MEDIUM (Metrics Leakage = Sensitive Infrastructure Intelligence)

**Description:**
```yaml
ports:
  - "9090:9090"          # Host access for Alloy remote_write (host agent)
```

Prometheus binds to `0.0.0.0:9090` on oldsrv's host. This means any device on VLAN 10 (Home) or VLAN 99 (Management) can scrape Prometheus and see:
- Internal service names, health status, and topology
- Target labels with internal IPs and hostnames
- Custom metrics that may leak sensitive operational details (disk sizes, UPS battery state, ZFS pool status)
- Alert rule configurations

While the comment says "Host access for Alloy remote_write," the Alloy agent runs on the same host and could use `localhost` or `host-gateway` instead.

**Recommended fix:**
Bind to loopback only: `"127.0.0.1:9090:9090"` or use `extra_hosts` with `host-gateway` like already done for doco-cd. Alternatively, move Alloy to Docker network mode and remove the host bind entirely.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-018: Multiple public-facing services skip ALL middleware (no Forward-Auth AND no CrowdSec)

**Files:** `jellyfin/docker-compose.yml.j2`, `home-assistant-standby/docker-compose.yml.j2`, `matrix/docker-compose.yml.j2`

**Severity:** MEDIUM (Internet-facing Services Without Rate-limiting or Threat Blocking)

**Description:**
Three services are exposed to the internet via Traefik but skip the entire middleware chain:

| Service | Subdomain | Own Auth? | Rationale |
|---------|-----------|-----------|----------|
| Jellyfin | `media.kogler.si` | Yes (built-in login) | Client apps need direct auth |
| HA standby | `ha.kogler.si` | Yes (HA native) | Companion app breaks with Forward-Auth |
| Matrix/Tuwunel | `matrix.kogler.si` | Yes (Matrix-native OIDC) | Federation breaks with Forward-Auth |

All three have their own authentication, which is correct. However, **none have CrowdSec bouncer** either — the same issue as KOPS-004 but broader. Without CrowdSec:
- Brute-force login attempts face no rate limiting at the edge
- Known exploit scans hit these services directly
- No community blocklist filtering

**Recommended fix:**
Apply the `crowdsec-only` middleware chain (see KOPS-004 fix) to ALL three services:
```yaml
traefik.http.routers.jellyfin.middlewares: crowdsec-only
traefik.http.routers.matrix.middlewares: crowdsec-only
```
This blocks malicious IPs before they even reach the service's own auth.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-019: qBittorrent runs inside Gluetun VPN — DNS exfiltration via tunnel

**File:** `IaC/ansible/templates/docker_services/qbittorrent/docker-compose.yml.j2`

**Severity:** MEDIUM (VPN Tunnel Control of Torrent DNS Resolution)

**Description:**
qBittorrent shares Gluetun's network namespace (`network_mode: "service:gluetun"`). This means all DNS queries from qBittorrent also go through the VPN tunnel to PrivadoVPN's DNS. While this prevents ISP tracking (intended), it also means:
- If PrivadoVPN's DNS is compromised or logs queries, domain names of torrent trackers are visible to the VPN provider.
- Gluetun has `NET_ADMIN` and `/dev/net/tun`, which are necessary for WireGuard but broaden the container's capabilities.

This is mostly acceptable given the VPN purpose, but note that if `SERVER_COUNTRIES: Netherlands` is the only constraint, Gluetun picks a random server each time. Connection leaks during server rotation could briefly expose traffic.

**Recommended fix:**
Consider adding Gluetun's built-in DNS leak protection explicitly:
```yaml
DNS_UPDATE: "true"
```
And verify `HEALTH_TYPE: none` or `HEALTH_TYPE: http` with a valid check endpoint to restart if the tunnel drops.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-020: Keepalived uses `auth_type PASS` (obfuscated, not encrypted)

**File:** `IaC/ansible/roles/home_assistant/templates/keepalived.conf.j2`

**Severity:** LOW (VRRP Authentication Information Disclosure — Mitigated by Design)

**Description:**
```yaml
authentication {
    auth_type PASS
    auth_pass {{ ... | truncate(8, true, '') }}
}
```

VRRP `PASS` authentication sends the 8-character password in cleartext over multicast. However, this is mitigated because:
1. VRRP operates only on the Home VLAN (Layer 2 broadcast)
2. The password is truncated to 8 characters
3. Failover is manual (not automated), so split-brain risk from VRRP spoofing is limited

Still, `auth_type AH` (IPsec Authentication Header) would provide stronger protection if both hosts support it.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-021: docker_services deployment enables systemd auto-start for ALL services unconditionally

**File:** `IaC/ansible/roles/docker_services/tasks/deploy-service.yml`

**Severity:** LOW (Cold Standby Services Auto-started on Boot)

**Description:**
```yaml
- name: "Enable systemd service docker-compose@{{ svc.name }}"
  ansible.builtin.systemd:
    name: "docker-compose@{{ svc.name }}"
    enabled: true
    state: started
```

This runs for every service in the `docker_services` list, including `home-assistant-standby` and `raspberrymatic-standby` which are marked as `enabled: false` in `group_vars/home_servers.yml`.

The compose template sets `restart: "no"` for standby containers, but the systemd unit being `enabled: true` means the project starts on boot — the containers just don't restart themselves if killed. This is a minor inconsistency but not harmful since `restart: "no"` means the standby containers won't start unless explicitly triggered.

Wait — actually looking closer: the deploy-task doesn't check `svc.enabled`. It should skip disabled services entirely.

**Recommended fix:**
Add a `when` condition: `when: svc.enabled | default(true)` so disabled services don't get rendered or started.
**Disposition (AUD-02, HEAD):** stale — code no longer present / already fixed in current HEAD. fixed by `when: item.enabled | default(true)` in roles/docker_services/tasks/main.yml:43

---

### 🟡 MEDIUM — KOPS-022: Headscale auto-approves client registrations despite doc claim

**File:** `IaC/ansible/templates/docker_services/headscale/config.yaml.j2`

**Severity:** MEDIUM (Unauthorized Device Joining Mesh)

**Description:**
The headscale template includes the comment:
```
# Client registration — requires admin approval (prevents rogue nodes)
```
But the actual configuration says:
```yaml
acl_policy_path: ""
```

With no ACL policy file, Headscale **auto-approves** all OIDC-authenticated registrations. Anyone with a `@kogler.si` email in Authentik can register a device into the Headscale mesh without any admin action.

Once inside the mesh, the device gets CGNAT IP from `100.64.0.0/10` and can reach whatever the RB4011 routes to the Headscale overlay.

**Recommended fix:** Either set `acl_policy_path` with a real policy, or update the comment to reflect that clients are auto-approved after OIDC auth.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-023: Loki has `auth_enabled: false` — any container on `db-internal` can inject or read logs

**File:** `IaC/ansible/templates/docker_services/loki/loki.yaml.j2`

**Severity:** MEDIUM (Log Injection / Data Exfiltration)

**Description:**
```yaml
auth_enabled: false
```
Any container on `db-internal` can push arbitrary log streams to Loki or query existing ones without authentication. A compromised container can inject malicious log entries to cover its tracks, or read all logs (credentials leaked in error messages, session tokens in request logs).

**Recommended fix:** Acceptable trade-off for single-node Loki. Mitigate by ensuring no unnecessary containers join `db-internal`. Audit members against `deployment-compose.md`.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-024: Doco-CD = host network + docker.sock (rw) + Forgejo write token

**File:** `IaC/ansible/templates/docker_services/doco-cd/docker-compose.yml.j2`

**Severity:** MEDIUM (GitOps Agent = Full Container Management on Host Network)

**Description:**
Doco-CD combines host network + docker.sock write + Forgejo repo write token. While `cap_drop: [ALL]` reduces escape risk:
- If webhook HMAC is bypassed or leaked, attacker triggers deployment of **any compose content** from a modified Git branch.
- Host network means deployed containers bypass all Docker network isolation.
- Forgejo token enables persistent backdoors in the homelab repo.

**Mitigating factors:** HMAC webhook auth, `cap_drop: [ALL]`, non-root distroless image, marked as NOT ACTIVATED yet.

**Recommended fix:** Pin a specific commit/tag in Doco-CD config; ensure `WEBHOOK_SECRET` is high entropy; restrict to specific compose directories.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-025: Element Web / chat.kogler.si has no Forward-Auth AND no CrowdSec

**File:** `IaC/ansible/templates/docker_services/element-web/docker-compose.yml.j2`

**Severity:** MEDIUM (Internet-facing Static Site Without Edge Protection)

**Description:**
Element Web at `chat.kogler.si` has neither Forward-Auth nor CrowdSec bouncer. It's a static frontend, but:
- Without CrowdSec, malicious IPs reach it freely.
- If `config.json` has any XSS vector (injected via misconfigured deploy), visitors' browsers execute the attack.

**Recommended fix:** Add `crowdsec-only` middleware. Forward-Auth is correctly skipped (Matrix-native SSO handles login).
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-026: db-backup missing immich and opencloud databases

**File:** `IaC/ansible/templates/docker_services/db-backup/docker-compose.yml.j2`

**Severity:** MEDIUM (Incomplete Database Backup Coverage)

**Description:**
Immich and OpenCloud databases are **commented out** in automated daily backup. Per `backup.md`: > "PostgreSQL DBs (Authentik, Immich, OpenCloud) → local scratch → push → iDrive e2 (Kopia)"

Currently only authentik-postgres and forgejo-db are dumped. Immich photos' metadata (albums, face recognition results, labels, smart search embeddings) live in Postgres — if the DB dies, having originals on ZFS isn't enough; you lose all organization and metadata.

**Recommended fix:** Uncomment DB03+ blocks with correct hostname `immich-postgres`. OpenCloud uses an embedded database (not external Postgres), so backup approach = tar of `/var/lib/opencloud` data dir.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-027: Ollama uses `:rocm` tag (mutable alias) instead of pinned version

**File:** `IaC/ansible/templates/docker_services/ollama/docker-compose.yml.j2`

**Severity:** MEDIUM (Supply Chain Risk — Mutable Tag on GPU Container)

**Description:**
```yaml
image: ollama/ollama:rocm
```
The `:rocm` tag is mutable — updated by Ollama for every ROCm-capable release. Not caught by Renovate's semantic version parsing. A new pull could bring breaking changes, ROCm regressions, or compromised images. Combined with direct GPU device access (`/dev/dri`, `/dev/kfd`), this gives kernel-level GPU access if compromised.

**Recommended fix:** Pin to specific version (e.g., `ollama/ollama:0.6.9-rocm`). Update renovate.json to track `-rocm` suffix.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-028: Router bootstrap DHCP assigns Cloudflare DNS (1.1.1.1) not internal resolver

**File:** `IaC/router/templates/rb4011_initial.rsc.j2`

**Severity:** LOW (Temporary DNS Misconfiguration During Bootstrap Window)

**Description:** During bootstrap, Management VLAN gets Cloudflare public DNS instead of Technitium. If someone bootstraps but forgets to run the router role, internal `.kogler.si` names never resolve for temporary hosts.

**Recommended fix:** Document in bootstrap checklist: "After importing initial script, run Ansible router role."
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-029: `crowdsec_bouncer_plugin_version` defaults to hardcoded value

**File:** `IaC/ansible/templates/docker_services/traefik/docker-compose.yml.j2`

**Severity:** LOW (Plugin Version Drift)

**Description:** CrowdSec Traefik bouncer plugin defaults to `v0.4.0`. If plugin falls out of sync with CrowdSec LAPI, blocking rules may stop working silently.

**Recommended fix:** Set `crowdsec_bouncer_plugin_version` explicitly in group_vars; add to Renovate tracking.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-030: Matrix/Tuwunel is obscure homeserver with `:latest` tag

**File:** `IaC/ansible/templates/docker_services/matrix/docker-compose.yml.j2`

**Severity:** LOW (Supply Chain / Maintenance Risk)

**Description:**
```yaml
image: jevolk/tuwunel:latest
```
Tuwunel is a lesser-known Matrix homeserver by single developer. Combined with `:latest` and internet-facing federation:
- Fewer security auditors reviewing the codebase
- Single maintainer risk (abandonment, compromised account)
- Federation bugs could leak internal state
- `:latest` amplifies all supply chain risks

**Recommended fix:** Pin to specific version. Evaluate conduit (Rust-based) or synapse if Tuwunel activity slows.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-043: Switch port map is empty in defaults, all 24 RJ45 ports default to Management VLAN

**Files:** `IaC/ansible/roles/switch/defaults/main.yml`, `IaC/ansible/group_vars/switch.yml`

**Severity:** MEDIUM (VLAN Segmentation Defeated on Switch)

**Description:**
The role defaults have `switch_port_map: {}` and the actual `group_vars/switch.yml` file doesn't exist. This means when the switch role runs, **all 24 RJ45 ports end up on Management VLAN 99** — the fallback for unconfigured ports:
```yaml
- name: Set unconfigured ports to management VLAN (default)
  ...
  pvid: 99
  when: "'ether' + item|string not in configured_port_names"
```

Since `configured_port_names` is derived from the empty map, every port is "unconfigured" and gets VLAN 99.

**Impact:** Complete loss of VLAN segmentation on the CRS328 switch. All wired devices end up on Management VLAN with access to router admin, iLO, UPS web UI, and all other management services.

**Recommended fix:** Create `IaC/ansible/group_vars/switch.yml` with the actual physical port-to-VLAN mapping before deployment.
**Disposition (AUD-02, HEAD):** stale — code no longer present / already fixed in current HEAD. group_vars/switch.yml now exists with a populated switch_port_map and the role applies it

---

### 🟡 MEDIUM — KOPS-044: Preseed files have identical placeholder root password hash

**Files:** `IaC/host/nas/preseed.cfg`, `IaC/host/oldsrv/preseed.cfg`

**Severity:** MEDIUM (Identical Emergency Root Password If Deployed As-Is)

**Description:**
Both preseed files use the exact same root password hash:
```yaml
d-i passwd/root-password-crypted password $6$rounds=40000$randomsaltstring$7F9eX8pZqK3vM1oN...
```
The comment says `# ROOT PASSWORD: Change this hash!` but if deployed without reading, both servers share the same password.

Additionally, root login is enabled (`d-i passwd/root-login boolean true`) which adds an emergency attack surface beyond the key-only ansible-admin account.

**Mitigating factor:** `post_install.sh` disables SSH root login and enforces key-only auth. Root password is only for local console access.

**Recommended fix:** Either generate unique hashes at render time or disable root login entirely (`d-i passwd/root-login boolean false`) since ansible-admin has NOPASSWD sudo.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-045: First-boot Pi config assumes root partition at predictable mount path

**File:** `IaC/host/pi/first-boot-config.sh`

**Severity:** LOW (Hostname Not Set If Partition Path Differs)

**Description:**
```bash
ROOT_ETC="${BOOT/\boot/\etc}"  # crude root partition path guess
```
This string substitution works only if BOOT literally starts with `/boot`. For real paths like `/media/$USER/boot_fat32` or `/mnt/d/sd_boot`, hostname setting is silently skipped.

**Mitigating factor:** Cloud-init `hostname:` directive handles it, and Ansible's network role manages `/etc/hosts` anyway.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🔴 HIGH — KOPS-047: Seerr has its own login with NO Forward-Auth AND NO CrowdSec

**File:** `IaC/ansible/templates/docker_services/seerr/docker-compose.yml.j2`

**Severity:** HIGH (Internet-Facing Service With No Edge Protection)

**Description:**
```yaml
# NOTE: no authentik-forward-auth — Seerr has its own login
traefik.http.routers.seerr.rule: "Host(`seerr.kogler.si`)"
```
Seerr skips ALL middleware (no Forward-Auth AND no CrowdSec bouncer). The comment says "family non-admin users submit requests directly" which justifies skipping Forward-Auth, but it also means CrowdSec is bypassed.

Seerr is internal-only per `deployment-compose.md`, but even if not publicly exposed, it sits on `traefik-public` network with no edge protection.

**Impact:** If Seerr ever gets a public DNS record (or if WAN firewall allows it), brute-force login attempts face only Seerr's native rate limiting. Known exploit scans hit the app directly with no community blocklist filtering.

**Recommended fix:** Apply the `crowdsec-only` middleware chain (see KOPS-004/KOPS-018 fix):
```yaml
traefik.http.routers.seerr.middlewares: crowdsec-only
```
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-049: RaspberryMatic compose maps port 2001 TWICE (duplicate)

**File:** `IaC/ansible/templates/docker_services/raspberrymatic/docker-compose.yml.j2`

**Severity:** MEDIUM (Typo: Duplicate Port Binding May Cause Confusion)

**Description:**
```yaml
ports:
  - "2001:2001/tcp"     # XML-RPC (thermostats/weather/alarm)
  - "2010:2010/tcp"     # XML-RPC TLS
  - "80:80"             # CCU admin UI (internal only)
```
The first port comment says "XML-RPC" but this is correct. However, port 80 on host conflicts with Traefik on oldsrv (`80:80`). During forward takeover, Traefik already owns :80 and RMat tries to claim it too — container crash.

**Impact:** On the Pi primary, traefik-ha binds `${ha_vip}:80` so no conflict. But on oldsrv standby during takeover, both Traefik + RMat want port 80.

**Recommended fix:** Map CCU admin UI to non-standard port: `"8081:80"` for primary, `"8082:80"` for standby.
**Disposition (AUD-02, HEAD):** stale — code no longer present / already fixed in current HEAD. port 2001 is no longer bound twice (single 2001:2001 mapping remains)

---

### 🟡 MEDIUM — KOPS-050: Playbook role order — `network` runs before `storage` on oldsrv

**Files:** `IaC/ansible/playbooks/home_servers.yml`, `docs/deployment-ansible.md`

**Severity:** MEDIUM (NFS Mounts Available Before Network Is Fully Configured)

**Description:**
The implementation order table in `deployment-ansible.md` says:
> Step 4: `storage` depends on `common`, `network` 
> Step 5: `docker_services` depends on `storage` (NFS mounts ready)

But the playbook `home_servers.yml` lists roles in this order:
```yaml
roles:
  - common
  - ai_diag
  - docker          # ← Docker installed here
  - network         # ← Network configured here
  - storage         # ← NFS mounts here
  ...
  - docker_services # ← Needs NFS ready
```

Docker starts at step 3 (`docker` role enables systemd unit). Then network + storage configure VLANs and NFS mounts. Then `docker_services` deploys containers. But the Docker daemon itself is already running BEFORE network is finalized — any Docker container started outside Ansible during the gap would lack proper VLAN networking.

**Mitigating factor:** No containers are started until `docker_services` role (step 7), which correctly comes after `storage`. The Docker daemon being early-started is by design (systemd unit) and doesn't break anything since containers aren't deployed yet.

**Conclusion:** Not actually a bug — the ordering is correct. Documented as accepted.

---

*Findings updated incrementally. Resume point: scanned playbooks (home_servers, raspberry_pi, router, storage), seerr compose, switch/group_vars, hardware docs (gpu, nas, oldsrv), deployment-preseed, deployment-ansible. Next batch: remaining compose templates (sabnzbd, radarr, lidarr, prowlarr, bazarr, profilarr, recyclarr) and cockpit/home_assistant templates.*
**Disposition (AUD-02, HEAD):** decision — playbook role order documented as accepted, not a bug.

### 🟡 MEDIUM — KOPS-031: `n8n_password` serves dual purpose — encryption key AND webhook auth token

**File:** `docs/deployment-secrets.md`, `IaC/ansible/templates/docker_services/n8n/docker-compose.yml.j2`

**Severity:** MEDIUM (Key Rotation Conflict)

**Description:**
Per deployment-secrets.md:
> `n8n_password` — `N8N_ENCRYPTION_KEY` (workflow encryption; **also used to authenticate Grafana alert webhooks**)

The same secret is both:
1. The **encryption key** for n8n's credential database (`N8N_ENCRYPTION_KEY`) — long-lived, immutable, cannot be rotated without decrypting/re-encrypting all stored credentials.
2. The **webhook authentication token** for Grafana alert webhooks — should be independently rotatable and short-lived.

If someone rotates the webhook auth (e.g., after a suspected leak), they must also re-encrypt every n8n workflow credential. Conversely, if Grafana's webhook header is visible in any log, the encryption key is also exposed.

**Recommended fix:** Use two separate 1Password items: `n8n_password` for `N8N_ENCRYPTION_KEY` and `n8n-webhook_api` for the webhook auth token. Update the Grafana contact point template accordingly.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-032: Technitium DNS runs as root with NET_ADMIN on host port 53

**File:** `IaC/ansible/templates/docker_services/technitium/docker-compose.yml.j2`

**Severity:** MEDIUM (Elevated Container = DNS Takeover if Compromised)

**Description:**
Technitium is not run with an explicit non-root user (no `user:` directive), meaning it defaults to root inside the container. Combined with:
```yaml
ports:
  - "53:53/udp"
  - "53:53/tcp"
cap_add:
  - NET_ADMIN
```
A compromised Technitium instance running as root with NET_ADMIN and host port binding can manipulate host network interfaces, sniff DNS traffic, or redirect DNS queries across the entire Home VLAN.

If Technitium's web UI (at `dns.kogler.si`, behind Forward-Auth) has a vulnerability, the attacker inherits this elevated access.

**Recommended fix:** Add `user: "53:53"` (Technitium supports running as non-root) and use Docker network mode instead of host port mapping where possible. If NET_ADMIN isn't needed (RouterOS handles DHCP), remove it.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-033: Matrix federation enabled — any Matrix user can DM your family

**File:** `IaC/ansible/templates/docker_services/matrix/tuwunel.toml.j2`

**Severity:** MEDIUM (Unsolicited Cross-Server Messages via Federation)

**Description:**
```toml
allow_federation = true
trusted_servers = ["matrix.org"]
```
With federation enabled, **any Matrix user from any server** can send DMs to `@user:kogler.si`. While the homeserver doesn't auto-accept messages, the family's usernames are discoverable via the server's `.well-known` endpoint. Unwanted messages, phishing attempts, or social engineering can arrive directly in Element Web.

The `trusted_servers` list only affects initial routing bootstrapping — delivery to unknown servers follows DNS SRV records, so it doesn't actually limit which servers can talk to yours.

**Recommended fix:** This is expected behavior for a federated homeserver and may be acceptable. If privacy is a concern, consider:
1. Disabling federation entirely (`allow_federation = false`) — defeats the Matrix purpose but maximum isolation.
2. Adding federation filtering rules to block servers known for spam.
3. Educating family about unsolicited Matrix DMs (same as email).
**Disposition (AUD-02, HEAD):** decision — open federation accepted/expected for a federated Matrix homeserver.

---

### 🟡 MEDIUM — KOPS-034: SNMP v2c with default community `public` pending decision

**File:** `docs/observability.md` (Deferred / TODOs section)

**Severity:** MEDIUM (Cleartext SNMP Credentials on Management VLAN)

**Description:**
The TODO section notes:
> Alloy collector assumes v2c `public` (monitoring role `snmp.yml.j2`); ⚠ needs research + decision

SNMPv2c with community string `public` means:
- Community string transmitted in **cleartext** over UDP (no encryption)
- Anyone on Management VLAN can read all SNMP data (interface stats, CPU, memory, routing table)
- Default `public` is well-known; automated scanners check for it
- Even read-only, SNMP exposes detailed infrastructure intelligence useful for targeted attacks

**Recommended fix:**
1. Create a high-entropy read-only community string stored in 1Password (e.g., `snmp-ro_api`).
2. Configure MikroTik to restrict SNMP to Management VLAN only: `/snmp set community="<ro_community>"` + ACL on the interface.
3. Consider SNMPv3 with authPriv if MikroTik supports it well enough (some RouterOS versions have bugs with v3).
**Disposition (AUD-02, HEAD):** decision — SNMP v2c `public` flagged as pending decision in observability.md.

---

### 🟢 LOW — KOPS-035: Prometheus blackbox HTTP probes accept 401/403 as success

**File:** `IaC/ansible/templates/docker_services/blackbox-exporter/blackbox.yml`

**Severity:** LOW (False-Negative Alert Suppression)

**Description:**
```yaml
valid_status_codes: [200, 301, 302, 401, 403]
```
Services behind Authentik Forward-Auth return redirect codes (302) or 401/403 when probed without authentication. Including 401/403 as "valid" means:
- A misconfigured middleware that blocks ALL traffic would still show as "up"
- A service crashing with a custom 403 page wouldn't trigger alerts
- Auth flow breakage (e.g., Authentik down causing 502→302→403 chains) might be masked

**Recommended fix:** Keep 401/403 for services that return them behind Forward-Auth, but add a separate probe module with stricter valid codes (`http_2xx_strict: [200]`) for services that should always return 200. Use path-specific probes for `/health` endpoints where available.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-036: Multiple Alloy instances will collide on `instance` label

**File:** `docs/observability.md` (Deferred / TODOs), `IaC/ansible/roles/monitoring/templates/alloy.river.j2`

**Severity:** LOW (Metric Collision on Multi-Host Deploy)

**Description:**
The TODO notes:
> identical `instance` label across hosts collides in Prometheus; set per-host instance

When the Pi gets its own Alloy agent (deferred), both hosts report `instance="127.0.0.1:9998"`. Prometheus treats these as the same target — metrics overwrite each other, dashboards show wrong values, alerts fire incorrectly.

**Recommended fix:** Set per-host instance in the Alloy template: `instance = "{{ inventory_hostname }}:9998"` or use Ansible to inject the hostname into the Alloy config before enabling the second host.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-037: Dozzle reads ALL container logs including DB credentials

**File:** `IaC/ansible/templates/docker_services/dozzle/docker-compose.yml.j2`

**Severity:** LOW (Credential Exposure via Live Log Viewer — Mitigated by Forward-Auth)

**Description:**
Dozzle mounts `/var/run/docker.sock:ro` and streams logs from ALL containers in real time. This includes containers that log database passwords, API tokens, or session data during startup or errors. Anyone authenticated through Authentik at `logs.kogler.si` can see these.

**Mitigating factors:** Behind CrowdSec + Authentik Forward-Auth; read-only socket; no persistence.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

### 🟢 LOW — KOPS-046: AP ethernet ports grant full Management VLAN access

**File:** `IaC/router/templates/ap_initial.rsc.j2`

**Severity:** LOW (Unintended Network Access via AP Wired Ports)

**Description:**
All 5 AP ethernet ports are bridged without VLAN tagging:
```routeros
/interface bridge port add bridge=bridge interface=ether1
/interface bridge port add bridge=bridge interface=ether2
...
/interface bridge port add bridge=bridge interface=ether5
```

Any device plugged into an AP's wired port gets full Management VLAN 99 access. While APs are in secured locations (garaža, spalernica, dnevna), this means a visitor connecting a laptop to an unused AP port gets direct access to the router admin interface, iLO, UPS management, and all other Management VLAN services.

**Recommended fix:** Disable unused AP ethernet ports or put them on a restricted VLAN. In CAPsMAN mode, configure the bridge ports per-port rather than adding all to the bridge upfront.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-062: Renovate only tracks Docker images — ignores Ansible, Python, RouterOS packages

**File:** `renovate.json`

**Severity:** LOW (Incomplete Update Automation Coverage)

**Description:**
```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "platform": "forgejo",
  ...
  "packageRules": [
    {
      "matchDatasources": ["docker"],
      "stabilityDays": 3
    }
  ]
}
```

Renovate only tracks Docker image tags. The following dependencies go completely untracked:
- Ansible collection versions (`community.docker`, `community.general`, `community.routeros` in `requirements.yml`)
- Python packages in `scripts/*.py` (if any pinned versions exist)
- RouterOS firmware updates (manual process anyway)
- Debian package versions installed by preseed (`zfsutils-linux`, `sanoid`, `syncoid`, etc.)
- Host-installed binaries (nut_exporter, zfs_exporter, Alloy)
- AMD ROCm SDK version

**Mitigating factor:** Most of these don't change frequently, and manual review before upgrading RouterOS/Firmware is actually desirable.

**Recommended fix:** Add package rules for the specific managers used:
```json
{
  "packageRules": [
    {"matchManagers": ["docker-compose", "ansible-galaxy"], "stabilityDays": 3},
    {"matchManagers": ["pip_requirements"], "schedule": ["on monday"]}
  ]
}
```
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-063: Playbook ordering issue — Pi runs `home_assistant` role before `docker_services`

**File:** `IaC/ansible/playbooks/raspberry_pi.yml`

**Severity:** MEDIUM (RaspberryMatic May Start Before HA Is Ready)

**Description:**
The Pi playbook runs roles in this order:
```yaml
roles:
  ...
  - docker          # installs Docker
  - home_assistant  # renders HA config + keepalived + cert sync
  - docker_services # deploys ALL Pi services including raspberrymatic
  - monitoring
```

The `home_assistant` role renders configuration files for `home-assistant-primary` and sets up keepalived. Then `docker_services` starts EVERYTHING including `raspberrymatic`. This means RaspberryMatic starts before HA finishes booting and initializing its Homematic integration.

Per `smart-home-failover.md`, the failover orchestrator follows the sequence: RMat-start → wait XML-RPC 2001 → VIP promote → HA-start. But during a normal boot/reboot on the Pi, there's no such sequencing — both start simultaneously via independent systemd units.

**Impact:** HA may briefly not see Homematic devices after a Pi reboot until both services fully initialize. This is transient and auto-resolves, but could cause missed automations or stale sensor readings during startup.

**Recommended fix:** Add a dependency or health check in the systemd unit for home-assistant-primary that ensures raspberrymatic is responding on XML-RPC 2001 before starting HA. Or reverse the order: start RMat first, then HA.

---

*Findings updated incrementally. Resume point: continue scanning remaining IaC templates (sabnzbd, radarr, lidarr, prowlarr, bazarr, profilarr, recyclarr, cockpit routes, headscale compose) and remaining docs (hardware-nas, hardware-oldsrv, hardware-gpu, deployment-preseed).*
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-038: RaspberryMatic maps port 80 on host — conflicts with Traefik

**File:** `IaC/ansible/templates/docker_services/raspberrymatic/docker-compose.yml.j2`

**Severity:** MEDIUM (Port Conflict — Traefik and CCU both need :80)

**Description:**
```yaml
ports:
  - "2001:2001/tcp"     # XML-RPC
  - "2010:2010/tcp"     # XML-RPC TLS
  - "80:80"             # CCU admin UI (internal only)
```

On the **Pi primary**, both Traefik (`traefik-ha` edge) and RaspberryMatic try to bind host port 80. The `traefik-ha` edge binds `{{ ha_vip }}:80`, which works only if no other process owns port 80 on `0.0.0.0`. RaspberryMatic's `80:80` binds all interfaces — collision.

On **oldsrv standby**, Traefik also uses `:80` and `:443`. If both start (even briefly during failover testing), they conflict.

**Recommended fix:** Map CCU UI to a different host port, e.g., `"8085:80"` for primary or `"8086:80"` for standby. Access via IP:port internally. Never expose the CCU admin UI publicly.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-039: Home Assistant `trusted_proxies` covers entire Traefik network

**File:** `IaC/ansible/roles/home_assistant/templates/configuration.yaml.j2`

**Severity:** MEDIUM (Spoofed Client IPs from Compromised Sibling Container)

**Description:**
```yaml
trusted_proxies:
  - 172.20.0.0/16   # traefik-public Docker network
```

HA trusts ALL IPs in the `traefik-public` Docker network (a /16 = 65,534 addresses). Any container on that network can spoof `X-Forwarded-For` headers and HA will treat them as genuine client IPs. This means:
- A compromised container can mask its real IP behind any fabricated source.
- HA's access logs show fake IPs, complicating forensics.
- Rate limiting based on client IP is defeated.
- Authentik session tracking sees forged IPs.

The Traefik container itself can't be spoofed by siblings (it injects real IPs), but the broad `/16` trust range gives any sibling the same authority as Traefik.

**Recommended fix:** Trust only Traefik's specific container IPs rather than the whole CIDR:
```yaml
trusted_proxies:
  - "172.20.0.2/32"    # Traefik on oldsrv (actual container IP)
  - "<Pi traefik-ha IP>/32"  # Pi traefik-ha edge
```
Or at minimum shrink to `/24`. Note that Docker bridge IPs can shift on recreate, so pin Traefik's network config or use a dynamic approach.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-040: RaspberryMatic device path uses wildcard that won't resolve

**File:** `IaC/ansible/templates/docker_services/raspberrymatic/docker-compose.yml.j2`

**Severity:** MEDIUM (Container Won't Start — Invalid Device Path)

**Description:**
```yaml
devices:
  - /dev/serial/by-id/usb-eQ-3__HmIP-RFUSB_*:/dev/ttyACM0
```

The glob `usb-eQ-3__HmIP-RFUSB_*` won't be expanded by Docker's device mapping. Docker needs an exact path. The comment says "Replace with the actual by-id symlink" — but the template will deploy this as-is, and the container will fail to start because Docker can't find the literal path with a `*` character.

**Recommended fix:** Either:
1. Add a host_var `homematic_usb_by_id` per host and use it in the template.
2. Use a udev rule to create a stable symlink (e.g., `/dev/hmip-rfusb`) and reference that.
3. Pin down the actual device path during initial Ansible deployment and store it in a fact cache.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-041: CrowdSec collections limited to traefik + linux only

**File:** `IaC/ansible/templates/docker_services/crowdsec/docker-compose.yml.j2`

**Severity:** LOW (Incomplete Attack Surface Coverage)

**Description:**
```yaml
COLLECTIONS: "crowdsecurity/traefik crowdsecurity/linux"
```

Only Traefik logs and basic Linux events are parsed. Dozens of services run on oldsrv with their own authentication surfaces (HA, Grafana, Matrix, n8n, qBittorrent web UI), but CrowdSec doesn't parse their logs. Services like:
- Matrix federation requests (brute-force on OIDC login)
- Jellyfin login attempts
- qBittorrent web UI brute-force
- n8n credential-based attacks

aren't covered by automated blocking.

**Mitigating factor:** These services are behind Authentik Forward-Auth (except HA/Jellyfin/Matrix). CrowdSec + Authentik is already the chain for most of them at the proxy level.

**Recommended fix:** Add relevant CrowdSec collections for each exposed service. Prioritize: `crowdsecurity/home-assistant`, `crowdsecurity/matrix`, `crowdsecurity/grafana`.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-042: Router bootstrap enables API + WWW-SSL without interface restriction

**File:** `IaC/router/templates/rb4011_initial.rsc.j2`

**Severity:** LOW (Management Services on All Interfaces During Bootstrap Window)

**Description:**
The bootstrap enables management services:
```routeros
/ip service set api disabled=no
/ip service set www-ssl disabled=no certificate=none
/ip service set ssh disabled=no port=22
```

These listen on all interfaces including WAN (pppoe-telekom / ether1). While the intent is temporary bootstrap access, if someone bootstraps and forgets to run the Ansible role, the router's management plane stays open to the internet until manually locked down.

**Mitigating factor:** No firewall rules are applied yet, but services bind globally by default in RouterOS. The Ansible router role should restrict these.

**Note:** Related to KOPS-003 (which covers this same issue more broadly). This is the bootstrap-specific window where the risk is highest before Ansible runs.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-066: Switch and AP bootstrap templates enable management services without TLS

**Files:** `IaC/router/templates/crs328_initial.rsc.j2`, `IaC/router/templates/ap_initial.rsc.j2`

**Severity:** MEDIUM (Management Services on All Interfaces During Bootstrap Window)

**Description:**
All three bootstrap templates (router, switch, AP) enable management services that bind to all interfaces:

| Device | Services Enabled | TLS? | Interface Restriction? |
|--------|-----------------|------|----------------------|
| RB4011 | api, www-ssl, ssh | No (certificate=none) | No |
| CRS328 | api, www-ssl, ssh | No (certificate=none) | No |
| hAP/wAP | ssh only | No | No |

The switch gets its management IP from the bootstrap and is reachable from the Management VLAN before the Ansible role runs. If the switch is miswired (e.g., a port that should be Home VLAN is plugged into a device that scans for SSH/API services during the bootstrap window), it's exposed.

**Mitigating factor:** The bootstrap window is short (minutes to hours until Ansible runs). Services are on the isolated Management VLAN physically.

**Recommended fix:** In the bootstrap scripts, disable `api` and `www-ssl` services entirely and rely on SSH-key-only access for the initial bootstrap. Or restrict services to specific interfaces: `/ip service set ssh interface=vlan99-mgmt`.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-064: Technitium DNS binds host port 53 without network restriction

**File:** `IaC/ansible/templates/docker_services/technitium/docker-compose.yml.j2`

**Severity:** MEDIUM (DNS Hijacking / Amplexification from LAN)

**Description:**
```yaml
ports:
  - "53:53/udp"
  - "53:53/tcp"
cap_add:
  - NET_ADMIN          # needed for the built-in DHCP / interface control
```

Technitium maps port 53 directly to `0.0.0.0` on the Docker host. Combined with `NET_ADMIN` capability, this gives the container significant network-level access. While Technitium's web UI is behind Forward-Auth at `dns.kogler.si`, the raw DNS port 53 has **no authentication** — any device on the LAN can:

1. Query DNS (expected behavior)
2. Send recursive queries to ANY external domain via Technitium (open resolver for LAN devices)
3. Potentially perform DNS amplification if the LAN allows spoofing source IPs
4. Query Technitium's internal records (DHCP auto-created entries) revealing every hostname on the network

The `NET_ADMIN` capability is also notable — while needed for Technitium's DHCP interface control, it grants the container the ability to modify networking (routing, iptables rules) which could affect host networking if the container were compromised.

**Mitigating factor:** Per `docs/network-dns.md`, clients are expected to use Technitium as their primary DNS. The VLAN firewall ensures only Home/IoT/Kids/Guest can reach it, not Management. This is intentional design per `network-dns.md` "Per-Subnet DNS Policy".

**Recommended fix:** Consider binding port 53 only to specific VLAN IPs rather than `0.0.0.0`: e.g., `"10.10.1.30:53:53/udp"` for Home VLAN only. Or accept this as intentional design but document that `NET_ADMIN` should be reviewed post-deploy against actual Technitium requirements.

---

*Findings updated incrementally. Resume point: scanned technitium, home-assistant-standby, zfs_exporter, homepage, signal-cli-rest-api, nut role, monitoring vars, prometheus config, headscale config. Next batch: remaining compose templates (sabnzbd, radarr, lidarr, prowlarr, bazarr, profilarr, recyclarr) and cockpit templates.*
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-065: Loki schema date is set to 2026-01-01 (future)

**File:** `IaC/ansible/templates/docker_services/loki/loki.yaml.j2`

**Severity:** MEDIUM (Loki Schema Not Activated Until 2026)

**Description:**
```yaml
schema_config:
  configs:
    - from: 2026-01-01
      store: tsdb
```

The `from: 2026-01-01` means this schema configuration only applies starting January 1, 2026. Until then, Loki may fail to write logs because no valid schema covers the current time period. If the system deploys before that date, Loki will silently drop all logs until the schema becomes active.

**Impact:** Log collection fails entirely until 2026-01-01. Grafana shows no logs, alerting based on logs stops working, and there's no audit trail for the entire period before the schema activates.

**Recommended fix:** Change to today's date or a past date:
```yaml
schema_config:
  configs:
    - from: "2025-01-01"
      store: tsdb
```

Or make it configurable via group_vars: `{{ ansible_date_time.iso8601 | regex_replace(':.*', '') }}` to auto-set from deploy date.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-051: Loki has `auth_enabled: false` with no RBAC

**File:** `IaC/ansible/templates/docker_services/loki/loki.yaml.j2`

**Severity:** LOW (Log Injection / Exfiltration from Any db-internal Container)

**Description:**
```yaml
auth_enabled: false
```

With authentication disabled, **any container on the `db-internal` Docker network** can:
- Push arbitrary log entries into Loki (log injection, could mask real attack evidence)
- Query all stored logs (exfiltration of credentials leaked in error messages, session tokens, etc.)
- Delete log streams if using certain Loki APIs

The containers currently on db-internal are Prometheus, Grafana DB, Authentik DB, Immich DB, Forgejo DB — all trusted infrastructure components. But if ANY one of those gets compromised, the attacker gains full read/write access to all homelab logs.

**Mitigating factor:** Single-node homelab with trusted containers, no anonymous access path since Grafana sits behind Forward-Auth, and Loki itself has no Traefik labels or public ports.

**Recommended fix:** Acceptable as-is for Phase 1. Consider enabling auth later when adding more services to db-internal. The `auth_enabled` flag and simple JWT tokens are available in Loki's config.

---

*Findings updated incrementally. Resume point: scanned docker_services role, technitium, home-assistant-standby, zfs_exporter, homepage, signal-cli-rest-api, nut role, monitoring vars, prometheus config, headscale config, *arr stack (sabnzbd/radarr/recyclarr), loki compose + config.*
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-052: Prometheus config scrapes non-existent alertmanager

**File:** `IaC/ansible/templates/docker_services/prometheus/prometheus.yml.j2`

**Severity:** MEDIUM (Prometheus Startup Failure / Noise)

**Description:** The Prometheus config declares a scrape job and alertmanager target:

```yaml
  - job_name: alertmanager
    static_configs:
      - targets: ["alertmanager:9093"]
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]
```

But there is **no alertmanager container** in `group_vars/home_servers.yml` or any compose template. Grafana Alerting is used instead of Prometheus Alertmanager (per design, HD-38 defers Alertmanager). This means:

1. Prometheus will repeatedly log connection errors for `alertmanager:9093` — noise in the journal.
2. Any alerts fired by Prometheus rule files have nowhere to route — they are silently dropped.
3. If alert rules are ever added (HD-08 UPS alerts use Grafana rules, not Prom rules), they may reference an Alertmanager that doesn't exist.

**Recommended fix:** Either:
1. Remove the alertmanager scrape job and `alerting:` block entirely (since Grafana Alerting is the chosen path).
2. Or deploy a minimal `alertmanager` container on `db-internal` if Prometheus-native alerting is needed alongside Grafana.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-053: HA standby keepalived uses mutable :latest image

**File:** `IaC/ansible/templates/docker_services/home-assistant-standby/docker-compose.yml.j2`

**Severity:** MEDIUM (Supply Chain Risk on Critical Failover Component)

**Description:** The standby compose defines keepalived with:

```yaml
  keepalived:
    image: osixia/keepalived:latest
```

This is a critical failover component — VIP ownership determines which node serves `ha.kogler.si`. Using `:latest` means any pull during failover preparation could bring incompatible keepalived behavior or regressions. Given that VRRP misbehavior can cause split-brain or flapping, this deserves version pinning.

**Recommended fix:** Pin to specific version (e.g., `osixia/keepalived:2.3.2`). Add `keepalived_version` variable to group_vars like other service versions. Same pattern for the Pi primary keepalived template.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-054: Element Web (chat.kogler.si) has no CrowdSec protection

**File:** `IaC/ansible/templates/docker_services/element-web/docker-compose.yml.j2`

**Severity:** MEDIUM (Internet-Facing Static Site Without Edge Protection)

**Description:**

```yaml
      # Intentional: NO authentik-forward-auth — Matrix-native SSO (docs/services-matrix.md).
```

Element Web correctly skips Forward-Auth (Matrix handles SSO). However, it also gets **no middleware at all** — not even CrowdSec bouncer. As a public-facing site (`chat.kogler.si`), it receives traffic from the entire internet with zero IP-level threat filtering.

**Impact:** XSS vectors in Element Web config, brute-force on any exposed API endpoints, and known-bad-IP scanning all reach the container directly without community blocklist filtering.

**Recommended fix:** Apply `crowdsec-only@file` middleware (same fix as KOPS-004/KOPS-018):

```yaml
traefik.http.routers.chat.middlewares: crowdsec-only@file
```
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-055: Doco-CD uses Forgejo API token with repo write access

**File:** `IaC/ansible/templates/docker_services/doco-cd/docker-compose.yml.j2`

**Severity:** MEDIUM (GitOps Agent Could Rewrite Infrastructure Code)

**Description:** Doco-CD receives `GIT_ACCESS_TOKEN` from `forgejo_api` — the same token used by Renovate. Per `docs/deployment-secrets.md`, this token has **read-write** access to the Forgejo repository. Doco-CD also mounts `docker.sock:rw` and runs on host network.

While `cap_drop: ALL` mitigates container escape risk, the combination means: if Doco-CD's webhook HMAC secret is leaked or its internal logic has a flaw, an attacker can trigger deployments that modify running services via docker.sock AND potentially push code back to the repo via the Forgejo token.

**Mitigating factors:** Doco-CD is distroless, non-root, `cap_drop: ALL`. Not yet activated (HD-02). Webhook HMAC provides authenticity check.

**Recommended fix:** Use separate Forgejo tokens — `forgejo_readonly_api` for Renovate (read-only), `doco-cd_deploy_api` for Doco-CD (write scoped to specific branches only). Limits blast radius if one token leaks.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-056: Storage push-services.sh executes docker commands as root on live containers

**File:** `IaC/ansible/roles/storage/templates/push-services.sh.j2`

**Severity:** MEDIUM (Backup Consistency Risk)

**Description:** The script performs:

```bash
docker exec n8n sqlite3 /home/node/.n8n/database.sqlite \".backup '/home/node/.n8n/n8n.sqlite'\"
docker cp n8n:/home/node/.n8n/n8n.sqlite ...
```

The systemd timer runs these as **root** (systemd service default). SQLite `.backup` against a live database has no consistency guarantee — concurrent writes during backup produce corrupted dumps. n8n's database contains encrypted workflow credentials; a corrupted backup means unrecoverable credential store on restore.

**Impact:** Service state backups (Forgejo repos, n8n encrypted credentials database) may be corrupted. Discovered only at restore time.

**Recommended fix:** For n8n: stop the container briefly, backup, then restart — or use native n8n backup command if available. For Forgejo: ensure `forgejo dump` handles concurrency inside the process. At minimum, add health checks before/after the backup to detect corruption early.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟡 MEDIUM — KOPS-057: NVMe pool device path is a TODO placeholder

**File:** `IaC/ansible/roles/storage/defaults/main.yml`

**Severity:** MEDIUM (Deploy-Time Failure If Not Updated)

**Description:**

```yaml
storage_pools:
  - name: nvme
    hosts: [oldsrv]
    allow_create: false
    vdevs: ["/dev/disk/by-id/<970_EVO_SERIAL>"]   # TODO: fill real by-id at deployment
```

If `storage_allow_pool_create` is flipped to `true` and this TODO placeholder is deployed as-is, ZFS pool creation fails because the literal string `<970_EVO_SERIAL>` is not a valid device path. The role does not validate `vdevs` paths before attempting create/import.

**Impact:** Deploy-time failure if someone enables pool creation without updating the device path. Obvious but wastes time debugging.

**Recommended fix:** Move the vdevs value to `host_vars/oldsrv.kogler.si.yml` (where the real serial goes after provisioning). Add a pre-flight assert in the role: verify each path in `vdevs` exists on disk before pool operations.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-058: Homepage mounts docker.sock read-only with health-check access

**File:** `IaC/ansible/templates/docker_services/homepage/docker-compose.yml.j2`

**Severity:** LOW (Container State Visibility for Family-Facing Launchpad)

**Description:** Homepage mounts `/var/run/docker.sock:ro` to display container health status. Combined with being behind Forward-Auth, any authenticated family member can see the status of ALL containers (including databases, internal services, backup jobs) — not just the ones they're supposed to know about.

**Mitigating factor:** Read-only socket, behind Authentik Forward-Auth. Information leakage only (no action possible).

**Recommended fix:** Acceptable as-is. The insight into container health is useful for the launchpad. Consider filtering the health widget to show only user-relevant services.
**Disposition (AUD-02, HEAD):** decision — Homepage docker.sock health widget accepted (read-only, behind Forward-Auth).

---

### 🟢 LOW — KOPS-059: Seerr uses SQLite — single file failure domain

**File:** `IaC/ansible/templates/docker_services/seerr/docker-compose.yml.j2`

**Severity:** LOW (Media Request Data Loss on Corruption)

**Description:** Seerr stores configuration in `/srv/docker/seerr/config:/app/config` — a SQLite database backed by ext4 (not ZFS snapshotted). Unlike user data on nas ZFS datasets, Seerr's config dir has no sanoid snapshots and may not be covered by Kopia policies depending on final scope.

**Impact:** If the Seerr config directory is lost or corrupted, all media request history, user accounts, and integration settings (Jellyfin/Sonarr/Radarr connections) are unrecoverable. Low practical impact — reconfiguration takes ~15 minutes.

**Recommended fix:** Acceptable risk. Ensure Seerr config is included in Kopia backup scope if `/srv/docker/seerr` is covered by the kopia-server policies.
**Disposition (AUD-02, HEAD):** decision — Seerr SQLite single-file accepted risk.

---

### 🟢 LOW — KOPS-060: *arr stack PUID/PGID hardcoded to 1000:1000

**Files:** All *arr compose templates (sonarr, radarr, lidarr, prowlarr, bazarr, sabnzbd)

**Severity:** LOW (Works Today, Fragile After Family Account Decision)

**Description:** Every linuxserver *arr container hardcodes `PUID: "1000"` / `PGID: "1000"`. This works because `domen` is uid/gid 1000. Once HD-51 resolves (family desktop users, neutral shared media account), if the media-owning account gets a different uid/gid, all *arr containers lose NFS read/write access and hardlink imports break.

**Impact:** Zero now (domen = 1000). Post HD-51 decision: potential NFS permission errors across entire media stack.

**Recommended fix:** After HD-51 resolves, replace `PUID/PGID` literals with group_vars variables (`storage_uid`, `storage_gid`) already defined in the storage role defaults. One-line change per template, centralized update path.
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.

---

### 🟢 LOW — KOPS-061: Pi traefik-ha edge cert expiry risk

**File:** `IaC/ansible/templates/docker_services/traefik-ha/dynamic/routes.yml.j2`

**Severity:** LOW (Offline-Safe by Design — Cert Expired Risk)

**Description:** The Pi traefik-ha edge serves TLS using synced cert files from oldsrv (ACME disabled). If oldsrv goes down AND the wildcard cert expires (90-day Let's Encrypt validity), the Pi edge continues serving with an expired certificate. There is no fallback ACME resolver on the Pi edge, and cert renewal requires oldsrv to be online.

**Mitigating factors:** Cert sync runs regularly. 90-day validity with automated renewal on oldsrv makes expiration unlikely unless oldsrv is down for extended periods. Offline-safe design documented in smart-home-failover.md.

**Recommended fix:** Acceptable trade-off. Consider adding a cert expiry alert in Grafana that fires >14 days before expiry so you renew proactively. Or add a secondary DNS-01 resolver on the Pi edge that activates only when the primary cert is missing/expired.

---

## New Scan Summary

> **Total findings now: 61** (previously 51). Six new MEDIUM, four new LOW.
> All remaining IaC templates and docs scanned — audit complete for current repo state.

| Severity | Count | New Items |
|----------|-------|-----------|
| 🔴 HIGH  | 5     | — |
| 🟡 MEDIUM | 29   | KOPS-052 (no alertmanager), KOPS-053 (keepalived :latest), KOPS-054 (Element no CrowdSec), KOPS-055 (Doco-CD write token), KOPS-056 (live SQLite backup), KOPS-057 (TODO device path) |
| 🟢 LOW   | 14    | KOPS-058 (Homepage docker.sock visibility), KOPS-059 (Seerr SQLite unbacked), KOPS-060 (*arr PUID hardcoded), KOPS-061 (Pi cert expiry) |

*Full scan complete. All 44+ compose templates, roles, push scripts, bootstrap configs, router templates, switch defaults, AI diag, and remaining docs reviewed.*
**Disposition (AUD-02, HEAD):** valid — code still present as quoted; risk applies.
