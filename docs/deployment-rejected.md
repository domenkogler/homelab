---
title: Deployment — Rejected / Dropped Decision Log
role: log
domain: deployment
status: active
tags: [deployment, rejected, decision-log]
---
# Deployment — Rejected / Dropped

> **Role:** Decision log — deploy-toolchain / VPS-host / hypervisor options the homelab evaluated and
> declined. Sorted by subject, one row per subject. This log is the per-domain **decision-log SSOT**.
> **Links to:** `deployment.md`, `CONVENTIONS.md` (§8.3)
> **Linked from:** `index.md`, `deployment.md`

> Each row is `| <subject> | <rejected|dropped|superseded> | <why> |` — no dates, no links, no prose.
> **Append-only:** add rows, never rewrite or delete an existing one; rows are keyed by subject (`CONVENTIONS.md` §8.3).
> Evidence = the current-state text in the owning doc.

## Decisions

| Subject                                                                        | Status     | Why                                                             |
|--------------------------------------------------------------------------------|------------|-----------------------------------------------------------------|
| "oldsrv has NO write path at all" as a standing state                          | superseded | push by seat, pull by runner: a scoped write key exists         |
| Adopting a discovered hand-made key into the vault                             | rejected   | promotes a one-time key to a managed secret                     |
| `ansible_run_tags == ['all']` equality                                         | rejected   | it is a tuple; membership is the only form                      |
| Authentik-as-LDAP Samba (`authentik-ldap_bind`)                                | superseded | NAS passdb is local tdbsam                                      |
| Catalog-generating `cockpit-pi-web_api`                                        | rejected   | `--create` mints a new value; clients use the live one          |
| Cohere embed-v4 (`cohere_api`)                                                 | superseded | embed/rerank local via Ollama `:rocm`                           |
| Contabo VPS                                                                    | superseded | netcup RS 2000 G12 replaces it as the public edge               |
| Control node = the admin laptop                                                | superseded | oldsrv is the primary control node, laptop is rescue-only       |
| Doco-CD                                                                        | dropped    | second Docker-socket deploy path; Ansible is the single path    |
| `doco-cd_password` webhook HMAC                                                | superseded | single Ansible-only deploy path                                 |
| DSH as LiteLLM consumer (`dsh_api`)                                            | rejected   | harness removed; parked, not re-minted                          |
| `dsh`/`pi-dev` tailscale preauth keys                                          | dropped    | harnesses removed, rows `enabled: false`                        |
| Excluding `core.config_entries` from HA standby rsync                          | rejected   | standby loses the voice pipeline on failover                    |
| `gen_wg_key()` provisioner helper                                              | dropped    | unused; `wg genkey` is authoritative                            |
| `git bundle` runner seeding                                                    | rejected   | plants a commit GitHub has never seen                           |
| iDrive e2 S3 (`kopia-s3_api`)                                                  | superseded | Kopia targets the backup Box over SSH/SFTP                      |
| Kogler IOT WAN SSID / VLAN 21                                                  | superseded | collapsed into Kogler IOT plus `wan_allow`                      |
| Kogler Kids SSID                                                               | superseded | firewall MAC list on VLAN 10; the VLAN 40 definition remains    |
| Metabase OIDC (`metabase_oidc`)                                                | dropped    | Metabase OSS has no OIDC, paid tier only                        |
| `metabase-forgejo_ro` (`db_ro_sync`)                                           | superseded | Metabase removed from the VPS; keys commented out               |
| MinIO S3 (`minio_login`)                                                       | superseded | Immich originals use the live Hetzner Box CIFS                  |
| `Mitogen`                                                                      | rejected   | speedup gate never fired; bulk op pre-pass removed the cost     |
| `oldsrv-rsync` runner key                                                      | superseded | shredded; no live grant accepts it                              |
| Parallel LiteLLM `bootstrap-keys`                                              | superseded | reverted; the `docker exec -i` probe cannot fan out             |
| Persisted Authentik api-intent token (`authentik-provision_api`)               | superseded | ephemeral per-run token via `ak shell`                          |
| Phase-2 build — AMD Ryzen 9 9900X + Radeon AI PRO R9700 + Proxmox VE (~€4,449) | superseded | spark GB10 gives more local inference per euro                  |
| Pi-99 `ProxyJump` hop                                                          | superseded | the Mgmt99 vNIC reaches `.99` direct                            |
| `prometheus-internal_api` (internal service auth)                              | superseded | VictoriaMetrics/Logs plaintext basic auth replaces it           |
| Proxmox (local hypervisor, Phase 1)                                            | rejected   | oldsrv stays bare-metal; passthrough conflicts with the dGPU  |
| Proxmox role + VM lab                                                          | superseded | spark GB10 is a bare-metal node, no hypervisor                  |
| RouterOS REST API transport                                                    | rejected   | management speaks the binary API on tcp/8728                    |
| Second `Private` vault for the runner (`op_api` note)                          | superseded | one vault, one lookup credential                                |
| `SLSKD_TOKEN` token option                                                     | superseded | slskd 0.26 removed it; use `SLSKD_PASSWORD`                     |
| `soulseek_login` duplicate item                                                | superseded | merged into `slskd_login`; env names were the bug               |
| SSH commit signing (`GitHub sign`)                                             | dropped    | key left GitHub; seats run `commit.gpgsign=false`               |
| The cockpit/harness seat must be a non-human account                           | rejected   | not applied: the owner seat holds neither token nor fleet key   |
| The owner's GitHub identity keys resident on the control/dev node              | rejected   | read-only deploy token plus the signing key instead             |
| The **`Private` vault** as the home of the `GitHub sign` / `GitHub auth` keys  | superseded | both keys moved into `Homelab-ansible` for headless pulls       |
| TOFU for GitHub host keys                                                      | rejected   | pinned from `api.github.com/meta`, cross-checked on the wire    |
| `user.signingkey=key::<pub>` as the seat's signing-key form                    | rejected   | the `key::` form dies without `SSH_AUTH_SOCK`; a key file signs |
| `vps-op-write_api` item title                                                  | superseded | renamed `op-write_api`, old title deleted                       |
| watchtower                                                                     | rejected   | bypasses the Ansible/Renovate gate, breaks HA version parity    |
| WSL Bridged networking                                                         | superseded | NIC pin fails on WiFi/hotspot; NAT is durable                   |
| WSL `mirrored` networking                                                      | rejected   | wedges ARP for the gateway, survives `wsl --shutdown`           |
| `Yacht web UI`                                                                 | rejected   | extra VPS web surface, drifts from the Ansible compose model    |

> **Not a deployment-domain decision:** guest-network / storage / services rejections live in their own
> `<domain>-rejected.md` files — see [`services-rejected.md`](services-rejected.md),
> [`storage-rejected.md`](storage-rejected.md), [`network-rejected.md`](network-rejected.md),
> [`smart-home-rejected.md`](smart-home-rejected.md).
> **SSOT note:** this log is the decision-log SSOT for the deploy/hypervisor domain.
