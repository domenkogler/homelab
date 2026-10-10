---
title: Services — Rejected / Dropped Decision Log
role: log
domain: services
status: active
tags: [services, rejected, decision-log]
---
# Services — Rejected / Dropped

> **Role:** Decision log — services and service-level options the `services` domain evaluated and rejected,
> dropped or superseded. Sorted alphabetically by subject, one row per subject. This log is the per-domain
> **decision-log SSOT**.
> **Links to:** `services.md`, `CONVENTIONS.md` (§8.3)
> **Linked from:** `index.md`, `services.md`

> Each row is `| <subject> | <rejected|dropped|superseded> | <why> |` — no dates, no links, no prose.
> **Append-only:** add rows, never rewrite or delete an existing one; rows are keyed by subject (`CONVENTIONS.md` §8.3).
> Evidence = the current-state text in the owning doc.

## Decisions

| Subject                                                            | Status     | Why                                                                |
|--------------------------------------------------------------------|------------|--------------------------------------------------------------------|
| `--enforce-eager` to bound the engine's peak memory                | rejected   | Peak memory is already bounded by the graph cap                    |
| `antheas/spark_hwmon` DKMS hwmon driver                            | dropped    | Deferred: out-of-tree DKMS module on an OOM-prone host            |
| AnythingLLM                                                        | dropped    | Open WebUI is the family web AI layer                              |
| arr-door patch `*_bind` loopback→Home-IP hunks                     | superseded | Routed publishes already use `oldsrv_home_ip` on `main`            |
| arr-door patch — the trio's split-horizon seed rows                | superseded | Rows come from the derived `zone_kogler_si` list                   |
| `bge-reranker` on CPU                                              | superseded | 5.3 s per 20-doc rerank vs 0.34–0.50 s on the dGPU                 |
| Cockpit tailnet surfaces pinned to oldsrv's node only              | superseded | Both nodes serve the name (`tailnet: dual`)                        |
| Coding harnesses (pi.dev / DSH) behind the LiteLLM gateway         | rejected   | Provider drops params silently; retry re-prefills; no config saved |
| Cohere embed-v4 @1536 + Cohere rerank                              | superseded | Local bge-m3 (1024-dim) + bge-reranker-v2-m3 replace both          |
| `dgxtop` NVML TUIs                                                 | rejected   | No metrics endpoint; VRAM panels read N/A on GB10                  |
| Dockge                                                             | rejected   | One Ansible-templated compose model; it would only fork it         |
| `dsh` + `pi-dev` as `docker_services` entries                      | dropped    | Harnesses removed; registry stays `enabled: false`                 |
| Edge model — VPS-only internal all-app edge                        | superseded | Home-LAN internal edge added for WAN-out survival                  |
| FP16 GGUF for the pinned embed/rerank legs                         | rejected   | Q8_0 chosen: +269 MiB VRAM, +18 % latency, no ranking gain         |
| Ghostfolio                                                         | rejected   | Actual's tracking account covers portfolio tracking                |
| GoCardless (Nordigen)                                              | superseded | Enable Banking replaces it; free personal sign-ups discontinued    |
| HD 630 iGPU (ANV/Vulkan) as rerank/embed/STT device                | rejected   | Slower than CPU, eats host RAM, busy as Xorg + QSV                 |
| Headscale on oldsrv                                                | superseded | public by nature, co-located with the VPS edge                     |
| `HostRegexp({host:.+})` as the `:80 → :443` redirect catch-all     | rejected   | v2 template matches nothing; plain `.+` works on v3                |
| `HostRegexp({host:.+})` catch-all on spark service routes          | rejected   | Matches nothing on v3; serving rules must name the host            |
| `kftof/bge-reranker-v2-m3-onnx-int8-avx2` as primary               | rejected   | 1.8× only without VNNI; CPU placement is rejected anyway           |
| Leaving media/seerr/seerrng unrouted at the VPS edge               | superseded | The VPS edge routes all three over WG S2S                          |
| LiteLLM `openai/` provider for harness calls                       | superseded | Harnesses use OpenAI-compat `/v1` rows directly                    |
| LiteLLM `openai/` provider for the llama.cpp embed row             | rejected   | `encoding_format: null` breaks llama.cpp; use `hosted_vllm/`       |
| LiteLLM `os.environ/` key reference in a DB model row              | rejected   | Not expanded in DB params; use the container env instead           |
| LiteLLM → spark name resolution by DNS or IP `api_base`            | rejected   | Seed invariant, one-leg DNS, no IP SAN; `extra_hosts` used         |
| `llm-d` as spark's router/gateway                                  | dropped    | Kubernetes inference-pool stack; LiteLLM fronts vLLM               |
| LMCache as spark's persistent KV tier                              | rejected   | Silent shared-prefix corruption on GB10; pinned L1 RAM             |
| LocPilot                                                           | superseded | Office MCP path replaces the whole-family UI role                  |
| Matrix bridges — WhatsApp/Messenger/Signal                         | rejected   | Sole user, native Signal works, no federation; account ban risk    |
| Metabase as a standing VPS service                                 | dropped    | VPS RAM is the binding constraint; revival target is oldsrv        |
| Metabase LDAP/SSO auth                                             | rejected   | Sole user; OSS LDAP is a second login, not SSO                     |
| Moving spark to the CRS328 for 10 GbE                              | rejected   | RB4011 has no 10 G copper; CRS328 offers SFP+/2.5 G                |
| n8n LiteLLM scoped key today                                       | rejected   | The workflow makes no LLM call; unused key + vault item            |
| n8n public route (`traefik-public` on `auto`)                      | dropped    | Alert path is docker-network; the tailnet edge serves the UI       |
| Ollama `:rocm` as the primary embedding engine                     | superseded | llama.cpp Vulkan: 15 ms vs ~500 ms, half the VRAM                  |
| Ollama as a rerank host or STT host                                | rejected   | No released Ollama serves `/api/rerank`; models never pulled       |
| Open WebUI two-instance split (`owui-int` + `owui-public`)         | dropped    | Deferred: one live instance, no second audience                    |
| Pangolin                                                           | dropped    | Traefik is the single reverse-proxy + auto-SSL edge                |
| PGVector as the RAG vector store                                   | superseded | Qdrant: hybrid dense+sparse BM25, independent of the chat UI       |
| Pi-hole as the ad blocker                                          | superseded | Technitium Advanced Blocking on the existing HA DNS tier           |
| Portainer                                                          | rejected   | One Ansible-templated compose model; it would only fork it         |
| Raising the KV pool above 16 GiB in bf16                           | rejected   | Boot-side headroom ceiling; fp8 is the next byte                   |
| `remote-pi` client + WebSocket relay                               | rejected   | Payload not end-to-end encrypted in the current version            |
| Rotating the Soulseek password from the diagnosis                  | dropped    | Risk accepted; transcript deleted, one account exposed             |
| RustDesk server on oldsrv                                          | rejected   | A rescue tool must not sit behind what it rescues                  |
| Signal as the fleet's alert delivery channel                       | superseded | Matrix `#homelab-alerts`; SMTP stays as fail-safe                  |
| Silencing the systemd-ssh-generator vsock kmsg noise               | dropped    | console-only noise; blacklist and stub declined                    |
| socat bridge for the DGX dashboard on the LAN                      | superseded | Replaced by the `spark-dashboard` file-provider sidecar            |
| spark as the single local-inference tier                           | superseded | Pinned services moved to the oldsrv RX 7600                        |
| spark's OOM CRIT threshold lowered to 5 GiB (`SPARK_OOM_CRIT_GIB`) | rejected   | 5 GiB sits below the last visible sample; kills read 1.6 GiB       |
| `spark/*` grant to the dev-harness scoped keys                     | dropped    | Deferred: never a model-registration side-effect                   |
| `spark/*` wildcard grant to the simple-querier scoped keys         | rejected   | Row-scoped grants per consumer instead                             |
| `text-embeddings-inference` (`cpu-1.9.4`) as primary rerank engine | rejected   | 5.3 s at ~790 % CPU; OOM-killed warmup                             |
| The `--gpu-memory-utilization` percentage governor                 | rejected   | Replaced by explicit bytes (`spark_vllm_kv_cache_memory`)          |
| The clock-cap read-back assert on GB10                             | rejected   | No such field exists on this driver                                |
| The `MemAvailable` reading alone as the memory-budget metric       | rejected   | Inflates under pressure; use `MemAvailable − CmaFree`              |
| The NVFP4 multi-model set on spark                                 | superseded | One big model: `spark/qwen3.8-flash-next`                          |
| The trio's A record on the VPS primary                             | rejected   | No VPS edge route; seeded `lan_only` with a `.ts` twin             |
| The `usable = MemFree − CmaFree` gauge (WARN 4 / CRIT 2)           | rejected   | Inverted metric; rises under pressure                              |
| `Theroxenes/local-reranker-rocm` TEI ROCm fork                     | rejected   | 0 stars, no releases; solves a placement the tier dropped          |
| TradeSight                                                         | rejected   | Trade Republic exports structured CSV/Excel natively               |
| Triton Inference Server as the spark engine                        | superseded | spark serves with vLLM                                             |
| Uncapped CUDA graph capture in the vLLM profile                    | rejected   | Graphs above `max_num_seqs` strand ~7 GiB                          |
| Vision-LLM leg on the oldsrv RX 7600 (Qwen3-VL 2B/4B)              | dropped    | VRAM ledger 8.4–11.9 GiB > 8 GiB; no arbiter, revisit gated        |
| VPS deferred to Phase 2+                                           | superseded | public edge runs on the VPS from day one                           |
| `whisper.cpp` GGML_HIP / ROCm build for STT                        | rejected   | No published ROCm artifact; a self-build with no Renovate trail    |
| ZeroClaw (system-management agent) on the VPS                      | rejected   | Fleet credentials on the internet-facing host                      |
| Zipline dashboard behind Authentik Forward-Auth                    | rejected   | Native OIDC; Forward-Auth would double-auth                        |
| Zipline global content blocklists                                  | rejected   | Owner stores executables privately; quota + TTL bound it           |
| Zipline S3 / object-storage datasource                             | rejected   | Local filesystem datasource on VPS NVMe                            |
| `zy84338719/dgx-spark-exporter` (`:9876/metrics`)                  | rejected   | Duplicates the Alloy unix collectors already on every host         |
| Authentik Forward-Auth on *arr/downloader UIs                      | superseded | home edge must survive WAN-out                                     |
| `DisableAutoTMMByDefault=false`                                    | rejected   | changes seeding far past categories                                |
| Dropping the CF-gated torrent site                                 | rejected   | FlareSolverr already solves it                                     |
| gluetun native `privado` provider                                  | superseded | upstream dropped it, custom WireGuard                              |
| Indexers registered per-arr, no Prowlarr                           | rejected   | three edits forever, loses tags                                    |
| Jellyfin SSO                                                       | rejected   | SSO accounts cannot fall back to local login                       |
| Murglar in the automated ladder                                    | dropped    | client app, no API                                                 |
| Navidrome door as a DNS-lane bolt-on                               | rejected   | needs own edge routes + zone row                                   |
| Per-add `autoTMM=true`                                             | rejected   | cannot make the arrs send it                                       |
| Prowlarr HTTP via gluetun SOCKS5                                   | rejected   | not listening, global, VPN-blocked                                 |
| Public Forward-Auth on `media.kogler.si`                           | rejected   | TV/client apps cannot do Authentik                                 |
| qBittorrent `max_ratio_act` 1 or 2                                 | rejected   | pause only; others delete data                                     |
| Readarr books tier                                                 | dropped    | Readarr effectively unmaintained                                   |
| Recyclarr profile-policy switch                                    | dropped    | rewrites live profiles, no cost yet                                |
| Router-side per-IP P2P cap                                         | dropped    | never implemented, container env caps                              |
| SABnzbd `dir`/`temp_dir` ini keys                                  | superseded | SAB 5 reads `complete_dir`/`download_dir`                          |
| SABnzbd `local_ip` locality option                                 | superseded | measured key is `local_ranges`                                     |
| SABnzbd published on the Home IP                                   | superseded | loopback-only publish now                                          |
| Shared bind mount to restore hardlinks                             | rejected   | rewrites every stored arr path                                     |
| slskd `SLSKD_TOKEN` auth                                           | superseded | removed in 0.26, user/pass only                                    |
| slskd as a Lidarr download client                                  | rejected   | Lidarr 3.1 schema has no Soulseek type                             |
| Tube Archivist re-enable                                           | dropped    | ES path.repo still unfixed                                         |
| `url-dl.` subdomain                                                | superseded | renamed `lidarr-ydl.`                                              |
| WireGuard / `modem-lan` in `local_ranges`                          | rejected   | peer ranges are not "this house"                                   |
| `ydl.` as the downloader subdomain                                 | rejected   | tool is music-only, name says lidarr                               |
| Actual Budget nightly image (native EB sync)                       | rejected   | mutable tag; no Renovate semver trail                              |
| Actual Budget on the VPS                                           | rejected   | financial data stays on the LAN plane                              |
| AI copilot container for Actual categorization                     | rejected   | the n8n-native loop covers it                                      |
| Authentik client / Forward-Auth on office.kogler.si                | rejected   | WOPI uses a shared JWT; breaks the editor                          |
| Classic Element (Android/iOS) as the mobile client                 | rejected   | Tuwunel serves no `r0` SSO-redirect route                          |
| Cloudflare proxy (orange cloud)                                    | rejected   | CrowdSec needs real client IPs at the edge                         |
| Credit-card SMS/email alert parsing (Phase 1)                      | dropped    | monthly CSV is the anchor                                          |
| CrowdSec's bundled Metabase image                                  | rejected   | CrowdSec Web UI is its dashboard surface                           |
| Crypto.com / Curve integration                                     | dropped    | both accounts unused                                               |
| Direct exposure without Cloudflare DNS                             | rejected   | same result, no benefit                                            |
| Edge rewrite of r0->v3 for classic Element                         | rejected   | imitates an API the origin does not serve                          |
| Hand-authoring MSC2965 into the client well-known                  | rejected   | forks homeserver identity into IaC                                 |
| Hand-created OIDC providers in the Authentik UI                    | rejected   | blueprint config-as-code plus credential glue                      |
| Home-app DNS "everything -> VIP"                                   | rejected   | VIP normally sits on the Pi                                        |
| Homelable native OIDC login                                        | dropped    | single-owner admin tool behind the LAN ACL                         |
| `labels: publish=` compose mechanism                               | superseded | publishes thread through `*_bind` vars                             |
| LibreOffice / OpenOffice on Linux clients                          | rejected   | ONLYOFFICE preserves MS formatting better                          |
| Matrix `/_matrix/*` behind Forward-Auth                            | rejected   | federation and native clients need direct reach                    |
| nftables rate limiting for the RustDesk relay                      | rejected   | a silent drop is a dead support session                            |
| One OpenCloud OIDC provider per client type                        | rejected   | one issuer; single `OC_OIDC_ISSUER`                                |
| ONLYOFFICE Docs-native TLS                                         | rejected   | keeps single-cert issuer + CrowdSec on every edge                  |
| ONLYOFFICE Documents app as the phone's cloud client               | rejected   | connectors need a password, no SSO                                 |
| OpenCloud photo backup                                             | rejected   | Immich owns family photos                                          |
| Pairdrop LAN-only exposure                                         | superseded | public P2P on both pairdrop and drop names                         |
| Persisted vault token `authentik-provision_api`                    | dropped    | upstream auto-rotation invalidates it                              |
| RustDesk WebSocket ports 21118/21119                               | rejected   | web client unused; X-Real-IP spoofable there                       |
| `tailscale serve :8080..8085` dashboard sidecar                    | superseded | traefik-tailnet edge serves clean URLs                             |
| `traefik-internal` started on forward takeover                     | dropped    | edge runs always on oldsrv                                         |
| `vps-op-write_api` vault item name                                 | superseded | renamed to `op-write_api`                                          |
| Wine / VM / Windows license on the oldsrv desktop                  | rejected   | native Debian + native ONLYOFFICE                                  |

> **Not a services-domain decision:** hypervisor / deploy / storage / network / smart-home UI rejections (Proxmox, Doco-CD, iDrive, MinIO, TileBoard, netplan…) live in their own `<domain>-rejected.md` files — see [`deployment-rejected.md`](deployment-rejected.md), [`storage-rejected.md`](storage-rejected.md), [`network-rejected.md`](network-rejected.md), [`smart-home-rejected.md`](smart-home-rejected.md).
> **SSOT note:** this log is the decision-log SSOT for the services domain.
