# Office MCP Bridge — Headscale wiring + Open WebUI registration (HD-111 notes)
# Not yet validated on a Windows client; mcp SDK must be installed to run. This captures
# the intended end-to-end layout so HD-111 implementers have the exact contract.

## Topology
#
#   Server-side Open WebUI (ai.kogler.si)                 [oldsrv/VPS]
#     │  MCP connection: url = https://<client-headscale-ip>:8766/mcp
#     │  Authorization: Bearer <OFFICE_BRIDGE_TOKEN>
#     ▼
#   bridge.py  (FastAPI, Streamable HTTP MCP)       [on the Windows 11 client]
#     │  stdio subprocess, one per app
#     ├──> ppt-mcp            (PowerPoint live, 156 tools)
#     ├──> word-mcp-live      (Word live, 120 tools)
#     └──> excelcli.exe       (sbroenne, exclusive; 31/326)
#              └─ (optional) excel_fallback.py (GetActiveObject attach mode)
#     ▼
#   COM -> open PowerPoint / Word / Excel on the client
#
# Because native COM servers are stdio-only but Open WebUI is streamable HTTP, bridge.py
# is the ONE Headscale endpoint (HD-109): single host IP, single token, one port (8766).

## Headscale
# - bridge binds to OFFICE_BRIDGE_HOST = the client's Headscale overlay IP (100.x), NOT
#   0.0.0.0 (bridge.py refuses it). LAN/public interfaces are not bound (HD-109).
# - Windows firewall: allow OFFICE_BRIDGE_PORT on the Headscale adapter only.
# - Token: generate + store in 1Password `Homelab-ansible` (item e.g. `office_bridge_api`,
#   api -> credential). Injected into bridge.env on the client; never committed (see
#   .gitignore for bridge.env).

## Open WebUI registration
# Administration -> Tools -> add MCP server (remote/streamable):
#   name     = Office Bridge
#   url      = https://<client-headscale-ip>:8766/mcp
#   headers  = Authorization: Bearer <OFFICE_BRIDGE_TOKEN>
# Open WebUI uses mcp.client.streamable_http.streamablehttp_client(url, headers) —
# matches backend/open_webui/utils/mcp/client.py.

## Packaging / distribution (HD-106)
# - This folder is the SSOT package. Serve read-only over Headscale (e.g. from oldsrv
#   static dir), clients pull via install.ps1 / update.ps1.
# - Version pinning (Flaw-B): exact pins in requirements.txt + excelcli.exe SHA256 in
#   install.ps1. Bump in repo -> GitOps refreshes static -> clients self-update.

## Open items (HD-111)
# - Deps (mcp, fastapi, uvicorn, httpx, pywin32) are listed but unvalidated in this repo;
#   must be installed + smoke-tested on a real Windows client with Office present.
# - Confirm the two Excel modes (exclusive sbroenne vs GetActiveObject fallback) and pick
#   default per seat.
# - Multi-client topology: v1 = single bridge on the shared family desktop (see research
#   doc §5); per-laptop later only if a 2nd live-edit seat is required.