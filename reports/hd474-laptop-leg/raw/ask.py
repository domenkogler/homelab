import base64
import json
import os
import sys
import urllib.request
import urllib.error

M = "agent-gemma-26b"
OUT = "reports/hd474-laptop-leg/raw"


def post(path_body, timeout=300):
    req = urllib.request.Request("http://127.0.0.1:1234/v1/chat/completions",
                                 data=json.dumps(path_body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        d = json.loads(urllib.request.urlopen(req, timeout=timeout).read())
        ch = (d.get("choices") or [{}])[0]
        msg = ch.get("message", {})
        return {"ok": True,
                "content": (msg.get("content") or "")[:500],
                "reasoning_len": len(msg.get("reasoning_content") or ""),
                "usage": (d.get("usage") or {}).get("prompt_tokens")}
    except urllib.error.HTTPError as e:
        return {"ok": False, "HTTP": e.code,
                "body": e.read().decode("utf-8", "replace")[:160]}
    except Exception as e:
        return {"ok": False, "err": "%s %s" % (type(e).__name__, str(e)[:140])}


def uri(p):
    mime = "image/png" if p.endswith(".png") else "image/jpeg"
    return "data:%s;base64,%s" % (mime, base64.b64encode(open(p, "rb").read()).decode())


which = sys.argv[1]
Q = sys.argv[2] if len(sys.argv) > 2 else "Describe this image."
print(json.dumps(post({"model": M, "max_tokens": 350, "messages": [{"role": "user", "content": [
    {"type": "text", "text": Q},
    {"type": "image_url", "image_url": {"url": uri(which)}}]}]}), ensure_ascii=False)[:900])
