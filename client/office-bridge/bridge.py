# FastAPI/Streamable-HTTP wrapper for the client-side Office MCP bridges.
#
# This is the SINGLE Headscale endpoint (HD-109): one bind host (Headscale IP only),
# one auth token, routing to N backend stdio COM MCP servers (ppt-mcp, word-mcp-live,
# sbroenne excelcli, DIY excel GetActiveObject fallback).
#
# Open WebUI (server-side) connects here via streamablehttp_client(url, headers=...),
# exactly as its backend/open_webui/utils/mcp/client.py does.
#
# NOTE: skeleleton. Requires the pinned deps in requirements.txt (mcp, fastapi, uvicorn,
# httpx, pyjwt or similar) installed on the client. mcp is NOT present in this repo so this
# file is written to the documented MCP Streamable HTTP + stdio subprocess protocol and is
# intended to be validated on a Windows client at deploy time.
import asyncio
import json
import os
import ssl
import sys
from pathlib import Path
from typing import Dict, Optional

import httpx
import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse
from mcp.client import streamable_http as mcp_http
from mcp.client.stdio import stdio_client, StdioServerParameters

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
# Backends: command + args that launch each pinned COM MCP server.
#   - ppt-mcp:            [uvx, ppt-mcp]
#   - word-mcp-live:      [uvx, word-mcp-live]
#   - sbroenne excalcli:  [path/to/excelcli.exe] (standalone; exclusive access)
#   - diy excel fallback: [python, excel_fallback.py]  (GetActiveObject attach mode)
BACKENDS: Dict[str, StdioServerParameters] = {
    "powerpoint": {
        "command": "uvx",
        "args": ["ppt-mcp"],
        "env": dict(os.environ),
    },
    "word": {
        "command": "uvx",
        "args": ["word-mcp-live"],
        "env": dict(os.environ),
    },
    # NOTE: excel uses sbroenne's standalone CLI (exclusive access mode) by default.
    "excel": {
        "command": os.environ.get("EXCEL_CLI", r"C:\Program Files\ExcelMcp\excelcli.exe"),
        "args": [],
        "env": dict(os.environ),
    },
}
# Optional attach-mode fallback (GETACTIVEOBJECT on the live sheet the user is typing in).
FALLBACK_EXCEL = os.environ.get("EXCEL_FALLBACK", r"C:\Program Files\ExcelMcp\excel_fallback.py")

# Single auth token (HD-109). Injected via env on the client; never hardcoded/committed.
TOKEN = os.environ.get("OFFICE_BRIDGE_TOKEN", "")
# Bind host: Headscale interface only (default 100.64/10 overlay), NEVER 0.0.0.0 (HD-109).
BIND_HOST = os.environ.get("OFFICE_BRIDGE_HOST", "127.0.0.1")
BIND_PORT = int(os.environ.get("OFFICE_BRIDGE_PORT", "8766"))
TLS_CERT = os.environ.get("OFFICE_BRIDGE_TLS_CERT", "")
TLS_KEY = os.environ.get("OFFICE_BRIDGE_TLS_KEY", "")

app = FastAPI(title="Office MCP Bridge", version="0.1.0")


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
def _authorize(req: Request) -> None:
    if not TOKEN:
        # fail-closed: refuse when no token is configured (never run token-less)
        raise HTTPException(status_code=503, detail="bridge token not configured")
    auth = req.headers.get("authorization", "")
    bearer = auth.removeprefix("Bearer ").strip() if auth else ""
    # short-circuit constant-time-ish compare
    if bearer != TOKEN:
        raise HTTPException(status_code=401, detail="unauthorized")


# ---------------------------------------------------------------------------
# Subprocess backend manager: one persistent stdio session per COM app
# (mirrors the app-isolation / lazy-connect model from the research doc).
# ---------------------------------------------------------------------------
class BackendManager:
    def __init__(self) -> None:
        self._sessions: Dict[str, "MCPClient"] = {}
        self._lock = asyncio.Lock()

    async def get(self, name: str):
        async with self._lock:
            if name not in self._sessions:
                self._sessions[name] = await self._open(name)
            return self._sessions[name]

    async def _open(self, name: str):
        params = BACKENDS[name]
        streams = await stdio_client(params)
        read, write = await streams.__aenter__()  # unless ManagedSession used
        # Use the mcp python SDK ClientSession over the stdio streams to speak MCP.
        from mcp import ClientSession  # local import: mcp is a pinned client dep
        session = await ClientSession(read, write).__aenter__()
        await session.initialize()
        return session

    async def list_tools(self, name: str):
        sess = await self.get(name)
        res = await sess.list_tools()
        return [t.name for t in res.tools]

    async def call(self, name: str, tool: str, args: dict):
        sess = await self.get(name)
        result = await sess.call_tool(tool, args)
        # Normalize ContentBlock results to a serializable payload for the client.
        return _content_to_plain(result.content)


def _content_to_plain(blocks):
    out = []
    for b in blocks:
        if hasattr(b, "text"):
            out.append({"type": "text", "text": b.text})
        elif isinstance(b, dict):
            out.append(b)
    return out


manager = BackendManager()


# ---------------------------------------------------------------------------
# HTTP routes (Streamable HTTP MCP)
# ---------------------------------------------------------------------------
# The MCP Streamable HTTP transport uses POST /mcp (JSON messages) and returns
# a stream (application/json, potentially multipart for SSE). The FastMCP / mcp SDK
# provides THIS plumbing; we wire a single /mcp endpoint that fans out to the backend.
# Below is the skeleton of that fan-out; the SDK's streamable_http_client + FastMCP
# server replace the raw plumbing shown here at deploy time.
#
# For Open WebUI compatibility we expose:
#   POST /mcp            -> MCP JSON-RPC (initialize / tools/list / tools/call)
#   GET  /healthz        -> liveness (token not required, but Headscale-bound only)
# Each remote <backend> is reachable at /mcp only after auth; per-backend subpath
# (e.g. /mcp/powerpoint) is optional if distinct connections are desired.

@app.get("/healthz")
async def healthz():
    return {"ok": True, "backends": list(BACKENDS.keys())}


@app.api_route("/mcp", methods=["POST", "GET"], name="mcp")
async def mcp_endpoint(req: Request):
    await _authorize(req)  # enforced on every MCP call (HD-109)
    # ---- deploy-time detail ----
    # Use mcp.server.fastmcp (FastMCP) mounted over streamable_http for the STABLE
    # path, and forward each incoming tools/Call request to manager.call(...).
    # This skeleton keeps the orchestration explicit; wire FastMCP transport here.
    body = await req.json()
    method = body.get("method")
    if method == "tools/list":
        # aggregate tool lists from all live backends into one unified namespace
        tools = []
        for name in BACKENDS:
            tools += await manager.list_tools(name)
        return JSONResponse({"jsonrpc": "2.0", "id": body.get("id"),
                             "result": {"tools": tools}})
    if method == "tools/call":
        params = body.get("params", {})
        tool = params.get("name")
        args = params.get("arguments", {})
        for name in BACKENDS:
            if tool and tool in await manager.list_tools(name):
                result = await manager.call(name, tool, args)
                return {"jsonrpc": "2.0", "id": body.get("id"),
                        "result": {"content": result}}
        raise HTTPException(status_code=404, detail=f"tool {tool!r} not found on any backend")
    if method == "initialize":
        return JSONResponse({"jsonrpc": "2.0", "id": body.get("id"), "result": {
            "protocolVersion": "2025-03-26",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "office-bridge", "version": "0.1.0"},
        }})
    raise HTTPException(status_code=400, detail="unsupported method")


# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
def _tls_ctx():
    if not (TLS_CERT and TLS_KEY):
        return None
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(TLS_CERT, TLS_KEY)
    return ctx


def main() -> None:
    # Enforce Headscale-only bind: refuse to run on 0.0.0.0 (HD-109).
    if BIND_HOST in ("0.0.0.0", ""):
        sys.exit("Refusing to bind Office bridge to 0.0.0.0 (HD-109). "
                 "Set OFFICE_BRIDGE_HOST to a Headscale overlay IP.")
    ssl_ctx = _tls_ctx()
    uvicorn.run(app, host=BIND_HOST, port=BIND_PORT, ssl_certfile=TLS_CERT or None,
                ssl_keyfile=TLS_KEY or None, ssl_ca_certs=None)


if __name__ == "__main__":
    main()