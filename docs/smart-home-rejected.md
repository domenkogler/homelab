---
title: Smart Home — Rejected / Dropped Decision Log
role: log
domain: smart-home
status: active
tags: [smart-home, rejected, decision-log]
---
# Smart Home — Rejected / Dropped

> **Role:** Decision log — smart-home device / UI / architecture options the homelab evaluated and declined;
> the per-domain **decision-log SSOT**. Sorted alphabetically by subject, one row per subject. The
> current-state fact a decision settled lives in the owning doc, not here.
> **Links to:** `smart-home.md`, `interfaces.md`, `CONVENTIONS.md` (§8.3)
> **Linked from:** `index.md`, `smart-home.md`

> Each row is `| <subject> | <rejected|dropped|superseded> | <why> |` — no dates, no links, no prose.
> **Append-only:** add rows, never rewrite or delete an existing one; rows are keyed by subject (`CONVENTIONS.md` §8.3).
> Evidence = the current-state text in the owning doc.

## Decisions

| Subject                                                  | Status       | Why                                                    |
|----------------------------------------------------------|--------------|--------------------------------------------------------|
| Authentik OIDC on ha                                     | rejected     | HA stays local-auth and WAN-independent                |
| Automatic failover/failback supervision                  | rejected     | Manual only: no false negatives, no split-brain        |
| Bose & Denon (HEOS) audio                                | rejected     | Cloud dependency; Bose dropped old-model support       |
| HA LLM leg shape (vendor component / wait / relax #24)   | superseded   | Core ships a stock litellm conversation integration    |
| HA recorder database on a remote Postgres                | rejected     | HA history would depend on a remote host               |
| HAOS box as the HA host                                  | superseded   | HA primary runs on the Pi                              |
| HmIP-RFUSB stick (local Homematic)                       | rejected     | HAP cloud stays; IP-only failover, no RaspberryMatic   |
| JBL Authentics audio                                     | rejected     | Look does not fit; needs a separate floor subwoofer    |
| Minisforum MS-A2 as a voice/AI processor                 | rejected     | Central LLM on the oldsrv GPU avoids a second device   |
| openai_conversation as the HA LLM leg                    | rejected     | Targets OpenAI's hosted endpoint only; no base URL     |
| Smart-speaker mics (Alexa/Google)                        | rejected     | Closed; raw audio cannot reach a local LLM             |
| Sonos audio                                              | rejected     | No Chromecast; closed ecosystem                        |
| TileBoard                                                | dropped      | Obsolete; the native HA Dashboard replaces it          |
| Weather 2000 (SI) as the forecast source                 | dropped      | Single authoritative source: core `meteoblue`          |
| X-Forwarded-For stripping on the standby HA edge         | rejected     | Hides the fault; extend ha_trusted_proxies instead     |

> **Not a smart-home-domain decision:** services / deploy / storage / network rejections live in their own `<domain>-rejected.md`. See [`services-rejected.md`](services-rejected.md), [`deployment-rejected.md`](deployment-rejected.md), [`storage-rejected.md`](storage-rejected.md), [`network-rejected.md`](network-rejected.md).
> **SSOT note:** this log is the decision-log SSOT for the smart-home domain.
