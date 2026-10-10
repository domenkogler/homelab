---
title: Hardware — Rejected / Dropped Decision Log
role: log
domain: hardware
status: active
tags: [hardware, rejected, decision-log]
---
# Hardware — Rejected / Dropped

> **Role:** Decision log — machine, GPU, node-sizing and power options this homelab evaluated and
> declined; the per-domain **decision-log SSOT**. One row per decision, sorted by subject. The
> current-state fact a decision settled lives in the owning doc, not here.
> **Links to:** `hardware.md`, `hardware-spark.md`, `hardware-nas.md`, `CONVENTIONS.md` (§8.3)
> **Linked from:** `index.md`, `hardware.md`

> Each row is `| <subject> | <rejected|dropped|superseded> | <why> |` — no dates, no links, no prose.
> **Append-only:** add rows, never rewrite or delete an existing one; rows are keyed by subject
> (`CONVENTIONS.md` §8.3). Evidence = the current-state text in the owning doc.

## Decisions

| Subject                                                   | Status     | Why                                                           |
|-----------------------------------------------------------|------------|---------------------------------------------------------------|
| `agent-unified` arms (Qwen3.6-35B-A3B)                    | dropped    | weights never fetched, off the catalogue                      |
| Baseline ratchet-down rule                                | rejected   | re-rolled the boot-floor coin-flip, spawned spurious recycles |
| BIOS default ≈8.4 GB reservation without a UMA carve      | superseded | the owner set the UMA carve to 32 GiB                         |
| `fast` profile 25 GB KV pool                              | superseded | left no host floor, ~7.9 GiB usable at rest                   |
| Gemma 4 26B A4B as the vision leg                         | rejected   | dies above ~1120 px image long side                           |
| Gemma-agentic / Qwen-VL-looking split                     | superseded | the runtime serves FIM and vision only                        |
| GL.iNet Comet KVM (GL-RM1)                                | dropped    | never purchased, no device on site                            |
| Global hold ceiling candidate A (112.774e9)               | rejected   | its 12 GiB reserve is ~9.3 GiB on the machine                 |
| Global hold ceiling candidate C (101.951e9)               | rejected   | would make 7 running arms illegal                             |
| Global hold ceiling candidate D (97.656e9)                | rejected   | would make 8 arms illegal, awq-mmap included                  |
| `gpu_render_gid` 104 (the Debian-table render gid)        | superseded | gid 104 is ssl-cert here, render is 992                       |
| HA Modbus UPS sensors                                     | dropped    | monitoring is NUT over USB HID only                           |
| More swap to absorb the global OOM                        | rejected   | killer fired with 8.25 of 16.77 GiB swap unused             |
| `num_ctx` 150016 window                                   | dropped    | retired with the agent leg, the window is 32 768              |
| NUT upsd ACCEPT/REJECT ACL pair                           | superseded | nut-server 2.8.1 ignores both keywords                        |
| Ollama as the laptop runtime                              | rejected   | no mmproj instruction, same Vulkan engine, no ROCm            |
| Out-of-band power purchase for oldsrv                     | dropped    | owner: no purchase, no ruling, no WoL window                  |
| PSI memory full as the watchdog's primary trigger         | rejected   | no lead time: ten samples read 0.0 before the kill           |
| Publishing plain `spark.kogler.si` into MagicDNS          | rejected   | tailnet clients get the edge IP for the host name             |
| Qwen3.6 q8_0 KV cache                                     | dropped    | a 0.31 GiB saving not worth the FA dependency                 |
| Strix Halo (Ryzen AI MAX+ 395 / Radeon 8060S) as this box | superseded | wrong SoC; Strix Point is ~90 GB/s                            |
| `tank/important` + `tank/data-with-media` layout          | superseded | tank holds user data only, media lives on bulk                |
| Watchdog idle-recycle term (baseline + 8 GiB after idle)  | rejected   | ~20-min cold start; no margin both reachable and above peak   |
| Workstation agent leg (Gemma 4 26B A4B)                   | dropped    | prefill minutes and erratic; the harness uses spark           |
| zram on spark for OOM relief                              | rejected   | acts on anon only, spends the DRAM the GPU carve needs     |

> **Not a hardware-domain decision:** service / AI-plane / deploy / storage / network / smart-home
> rejections live in their own `<domain>-rejected.md` files:
> [`deployment-rejected.md`](deployment-rejected.md), [`services-rejected.md`](services-rejected.md),
> [`services-ai-rejected.md`](services-ai-rejected.md), [`storage-rejected.md`](storage-rejected.md),
> [`network-rejected.md`](network-rejected.md), [`smart-home-rejected.md`](smart-home-rejected.md).
