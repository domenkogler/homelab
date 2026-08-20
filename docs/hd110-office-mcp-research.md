---
title: HD-110 — Office MCP Bridge Research
role: research
domain: services
status: active
tags: [services, ai, office, mcp, research]
---
# HD-110 — Office MCP Bridge: Unified vs Per-App, & Topology

> **Role:** Research — answers the HD-110 question: is a **single unified Office MCP bridge**
> feasible (one Headscale endpoint, one token) that covers Word+Excel+PowerPoint, or do we
> need per-app bridge(s)? Plus the client-topology decision (shared family desktop vs per-laptop).
> **Gates:** HD-111 implementation.
> **Linked from:** `services-office.md` (Office MCP section)

**Status:** Complete (2026-08). A unified bridge is feasible but requires a **thin wrapper**
because every native Office MCP server ships **stdio-only** — and Open WebUI consumes
**remote** MCP over **Streamable HTTP/SSE**.

---

## 1. The decisive fact: transport

- **Open WebUI's MCP client** (`backend/open_webui/utils/mcp/client.py`) connects via
  **`mcp.client.streamable_http.streamablehttp_client(url)`** — it talks to **remote MCP
  servers over HTTP** (with optional auth/headers). Confirmed from upstream source.
- **Every native Office live-edit MCP server evaluated (`ppt-mcp`, `word-mcp-live`,
  `office-mcp`) is `stdio`/`uvx`-local** — they run as a child process *next to the local
  Office app and the open file*. None exposes SSE/HTTP out of the box.

**Consequence:** the client-side Office bridge must be wrapped/exposed over HTTP on a
**Headscale-bound** port + token, so the server-side Open WebUI can reach it. The native
COM server stays stdio-local on the client; the STDIO→HTTP(Streamable/SSE) adapter is the
small glue piece we own.

---

## 2. Candidate live-editing servers (all COM, Windows-only, MIT)

| Candidate | Apps | Tools | Install | Stars / maturity | Transport |
|-----------|------|-------|---------|------------------|-----------|
| **`ykuwai/ppt-mcp`** | **PowerPoint only** | 156 (26 categories) | `uvx ppt-mcp` · PyPI **1.7.0** · Py≥3.10 | 53★ · mature | stdio |
| **`ykarapazar/word-mcp-live`** | **Word only** | 120–124 (COM/JXA) | `uvx word-mcp-live` · PyPI · Py≥3.11 | 182★ · mature | stdio · COM(Win)/JXA(mac) |
| **`sbroenne/mcp-server-excel`** | **Excel only, real COM** | 31 tools / **326 ops** (Power Query, DAX, VBA, `=PY()`) | **standalone C#** MCP server + CLI (`excelcli.exe`) · MIT | **533★ · maintained** | stdio + CLI · COM — **needs exclusive access** (close open workbooks; not Linux/mac/headless) |
| **`JulianPoleszczuk/office-mcp`** | **Unified: PPT + Excel + Word** | 129 | git clone + venv + pywin32 · **not on PyPI** | 0★ · immature | stdio → local TCP bridge → COM |
| `haris-musa/excel-mcp-server` | Excel file-based (openpyxl) | — | PyPI · Python | 4110★ · mature | stdio + **streamable HTTP/SSE native** — no Excel needed → server path |
| `OfficeMCP/OfficeMCP` | Office suite + WPS · **no license** | — | — | 109★ | — (file/automation; unlicensed) |
| `dosev-ai/mcp-office` | Excel/Opp/PwrPt/Word | — | — | 6★ | — |

---

## 3. How the unified candidate works

`JulianPoleszczuk/office-mcp` uses a **two-layer** design that is exactly our model:

```
Open WebUI (server-side, streamablehttp)         ── our wrapper
   │  HTTP (Streamable/SSE, Headscale-only + token) ── our wrapper
   v
   MCP server (server.py, stdio, official mcp SDK)    regs ppt_* / xl_* / doc_* tools
   │  TCP localhost (one JSON obj/line on :8765)
   v
   Office Bridge (bridge/*.py, pywin32)          holds live COM conn, one STA thread per app
   │  COM
   v
   PowerPoint / Excel / Word  (open docs, live edits)
```

- **App isolation:** each Office app = its own COM STA thread + connection + state (a hung
  Word doesn't block Excel). Every COM call is time-limited; dead connections are dropped
  and rebuilt lazily on next use.
- **Lazy connect:** bridge first tries `GetActiveObject` (attaches to an app you already
  opened); only on failure does it `Dispatch` a new instance. Open documents are not disturbed.
- **Protocol:** JSON-lines over TCP — `{"app":"powerpoint","action":"add_slide",...}` →
  `{"ok":true,...}`. `OFFICE_BRIDGE_HOST` defaults to `127.0.0.1`.
- This is the strongest proof that **one process can multiplex all three Office apps**
  behind a single endpoint/token — it literally does so today.

---

## 4. Recommendation (feasible; unified preferred, with a wrapper)

**Recommended topology:** **one unified Office MCP bridge per client** exposing Word +
Excel + PowerPoint tool-groups over **one Headscale-bound HTTP endpoint + one token** —
consumed by server-side Open WebUI. This matches the HD-106/HD-109 decisions. The
`office-mcp` two-layer design (below) is our *architecture reference*, not our build base.

**One route, three mature backends (recommended — not the unified `office-mcp`):**

Own a **thin unified wrapper** that fronts the **mature per-app servers** — no dependence on
immature `office-mcp` (0★, unmaintained risk) or unlicensed `OfficeMCP`. Verified-set bridge:

| App | Live-COM (Windows client) | Server-side / Linux (HD-107) |
|-----|---------------------------|------------------------------|
| **PowerPoint** | `ykuwai/ppt-mcp` (156) | `GongRzhe/Office-PowerPoint-MCP-Server` (python-pptx) |
| **Excel** | `sbroenne/mcp-server-excel` (31/326, exclusive) + DIY GetActiveObject fallback | `haris-musa/excel-mcp-server` (openpyxl, stdio+SSE) |
| **Word** | `ykarapazar/word-mcp-live` (120) | `SecurityRonin/docx-mcp` (tracked changes) / `PsychQuant/che-word-mcp` (234, OOXML) |

> **Every backend is stdio (or sbroenne's CLI) — so the small STDIO→HTTP(Streamable) wrapper
> we own is the single Headscale endpoint** binding one token + one port regardless of how many
> COM backends sit behind it. That is the "one unified surface" goal of HD-109; we do NOT need
> the immature `office-mcp` to achieve it.

---

## 5. Client topology decision

| Model | Pros | Cons |
|-------|------|------|
| **Shared family-office desktop bridge** (v1) | One install, one endpoint/token to manage; the OpenCloud file SSOT means the file round-trips through the shared box. | Only one PC can host the *open* file / live edits at a time; other users live-edit via the shared box (RDP/parsec) or use server-side tools. |
| **Per-laptop bridge** | Each user live-edits their own open file on their own PC. | N bridges to distribute/update/pin; per-user MCP connection mapping in OW; more exposure surface. |

**v1 recommendation:** start with **one bridge on the shared family desktop** (file SSOT via
OpenCloud), prove the wrapper + OW wiring, then scale to per-laptop only if a second live-edit
seat is actually needed. Distribution = repo `client/office-bridge/` (HD-106), Headscale-only
(HD-109).

---

## 6. Open risks / follow-ups (feed HD-111)

- **Excel live path — RESOLVED (2026-08):** `sbroenne/mcp-server-excel` (31/326 ops, MIT,
  533★, standalone COM/CLI) closes the Windows-Excel-live gap. **Caveat:** it wants
  **exclusive access** (close open workbooks; agent takes over & you watch), so it is NOT the
  `GetActiveObject` "edit the exact open sheet" mode. Keep a small DIY `GetActiveObject`
  bridge (pywin32 + FastMCP, stdio) as a **fallback/attach mode** for editing the live sheet
  the user is typing in. Same stdio shape → same wrapper.
- **Rejected:** `2slides` (external cloud API) · `sbroenne/excel-mcp` (old/wrong name) resolved
  to `mcp-server-excel` · `OfficeMCP/OfficeMCP` (unlicensed) · `sbraind` (macOS-only live) ·
  `trsdn` C# PPT (viable alt, VBA/PDF/tray, but ppt-mcp richer & simpler).
- **Wrapper transport library:** evaluate `mcp-proxy` / FastMCP SSE / Streamable-HTTP adapter
  to expose the stdio COM server; verify against OW's `streamablehttp_client` (auth header
  support, token).
- **Version pinning:** `ppt-mcp==1.7.0`, `word-mcp-live` pinned, `sbroenne/mcp-server-excel`
  (release pin / `excelcli.exe` checksum) — all MIT/pinned, matching Flaw-B. Server path:
  `haris-musa`, `GongRzhe`, `SecurityRonin`/`che-word` pinned too.
- **Multi-connection semantics:** "which client owns the open file" — OW maps per-user tools to a
  specific bridge instance; token-per-client alignment (HD-109).