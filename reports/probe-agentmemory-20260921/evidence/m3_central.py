#!/usr/bin/env python3
"""M3: is "central" real? One instance, four clients, per-client scoping, concurrency.

The REST plane is loopback-only by construction (0.9.29 renders host: 127.0.0.1 itself
and clobbers any operator edit to the rendered runtime config), so a remote client
reaches it only through a local forwarder. This driver stands up its own ephemeral
python forwarder (the brief's "ephemeral forwarder only - no IaC") and then plays each
client as a separate process talking to the central instance as its integration would.

Modes:
  forward [PORT]   -- TCP forwarder 0.0.0.0:PORT -> 127.0.0.1:3111
  client NAME      -- capture (prompt AND tool), own recall, cross-client read
  concurrent N     -- N simultaneous clients against one instance
"""
import json
import os
import socket
import sys
import threading
import time
import urllib.request

BASE = os.environ.get("AM_URL", "http://127.0.0.1:3111")
SECRET_FILE = os.environ.get("AM_SECRET_FILE", "/home/domen/amprobe/.amsecret")
SECRET = open(SECRET_FILE, encoding="utf-8").read().strip() if os.path.exists(SECRET_FILE) else ""

# (client, integration kind, project tag, unique fact it plants)
CLIENTS = [
    ("pi", "native-plugin", "lane-pi",
     "pi client planted fact: the probe lane branch is session-20260921-2259 and its "
     "guard script is scripts/guard-session.sh"),
    ("openclaw", "plugin", "lane-openclaw",
     "openclaw client planted fact: the OpenClaw gateway token lives in the vault item "
     "openclaw-litellm_api and its budget is 30 per 30d"),
    ("hermes", "plugin", "lane-hermes",
     "hermes client planted fact: Hermes memory providers allow exactly one active "
     "provider at a time and MEMORY.md is always on"),
    ("openhands", "mcp", "lane-openhands",
     "openhands client planted fact: OpenHands has no native adapter so it uses the "
     "MCP surface and must capture both prompts and tool results"),
]


def hdr():
    h = {"content-type": "application/json"}
    if SECRET:
        h["authorization"] = "Bearer " + SECRET
    return h


def call(path, body, timeout=60):
    t0 = time.time()
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(),
                                 headers=hdr(), method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return round(time.time() - t0, 3), json.loads(r.read().decode())


def plant(name, project, fact):
    """Capture the way a harness hook does: a prompt turn AND a tool turn."""
    out = []
    for hook, data in (
        ("prompt_submit", {"prompt": fact}),
        ("post_tool_use", {"toolName": "bash",
                           "toolInput": {"command": "echo " + fact[:40]},
                           "toolOutput": fact}),
    ):
        lat, r = call("/agentmemory/observe", {
            "hookType": hook, "sessionId": "m3-" + name, "project": project,
            "cwd": "/home/domen/amprobe", "timestamp": "2026-09-22T02:00:00Z",
            "data": data})
        out.append({"hook": hook, "latency_s": lat, "ok": "observationId" in r,
                    "id": r.get("observationId")})
    return out


def recall(query, limit=5):
    lat, d = call("/agentmemory/search", {"query": query, "limit": limit, "format": "full"})
    txt = "\n".join((r.get("observation") or {}).get("narrative") or ""
                    for r in (d.get("results") or []))
    sess = sorted({(r.get("observation") or {}).get("sessionId", "")
                   for r in (d.get("results") or [])})
    return lat, txt, sess, d


def mode_client(name):
    kind = next(k for n, k, p, f in CLIENTS if n == name)
    project = next(p for n, k, p, f in CLIENTS if n == name)
    fact = next(f for n, k, p, f in CLIENTS if n == name)
    row = {"client": name, "kind": kind, "project": project}
    row["capture"] = plant(name, project, fact)
    key = fact.split("planted fact:")[1].strip()[:34]
    lat, txt, sess, _ = recall(key)
    row["own_recall"] = {"latency_s": lat, "found": key[:18] in txt, "sessions": sess}
    cross = {}
    for n2, _k2, _p2, f2 in CLIENTS:
        if n2 == name:
            continue
        k2 = f2.split("planted fact:")[1].strip()[:24]
        _, t2, s2, _ = recall(k2)
        cross[n2] = {"found": k2 in t2, "sessions": s2}
    row["cross_client_read"] = cross
    print(json.dumps(row, ensure_ascii=False)[:420], flush=True)
    return row


def mode_concurrent(n):
    q = "the probe lane branch is session-20260921-2259 and its guard script"
    res = []
    lock = threading.Lock()

    def one(i):
        try:
            lat, txt, sess, _ = recall(q)
            with lock:
                res.append({"i": i, "latency_s": lat,
                            "hit": "session-20260921-2259" in txt, "err": None})
        except Exception as e:  # noqa: BLE001
            with lock:
                res.append({"i": i, "err": type(e).__name__ + ":" + str(e)[:80]})

    ts = [threading.Thread(target=one, args=(i,)) for i in range(n)]
    t0 = time.time()
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    lats = sorted(r["latency_s"] for r in res if r.get("err") is None)
    out = {"n": n, "wall_s": round(time.time() - t0, 2),
           "errors": [r for r in res if r.get("err")], "ok": len(lats),
           "latency_min": lats[0] if lats else None,
           "latency_median": lats[len(lats) // 2] if lats else None,
           "latency_max": lats[-1] if lats else None,
           "hits": sum(1 for r in res if r.get("hit")), "per_request": res}
    print(json.dumps(out, ensure_ascii=False)[:600], flush=True)
    return out


def mode_forward(port):
    def pump(src, dst):
        try:
            while True:
                b = src.recv(65536)
                if not b:
                    break
                dst.sendall(b)
        except Exception:
            pass
        try:
            dst.shutdown(socket.SHUT_WR)
        except Exception:
            pass

    def handle(c):
        s = socket.create_connection(("127.0.0.1", 3111))
        a = threading.Thread(target=pump, args=(c, s), daemon=True)
        b = threading.Thread(target=pump, args=(s, c), daemon=True)
        a.start(); b.start(); a.join(); b.join()
        c.close(); s.close()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", int(port)))
    srv.listen(16)
    print("forwarding 0.0.0.0:%s -> 127.0.0.1:3111" % port, flush=True)
    while True:
        c, _a = srv.accept()
        threading.Thread(target=handle, args=(c,), daemon=True).start()


if __name__ == "__main__":
    m = sys.argv[1]
    if m == "client":
        json.dump(mode_client(sys.argv[2]),
                  open("/home/domen/amprobe/logs/m3-client-%s.json" % sys.argv[2],
                       "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    elif m == "concurrent":
        json.dump(mode_concurrent(int(sys.argv[2])),
                  open("/home/domen/amprobe/logs/m3-concurrent-%s.json" % sys.argv[2],
                       "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    elif m == "forward":
        mode_forward(sys.argv[2] if len(sys.argv) > 2 else "3119")
