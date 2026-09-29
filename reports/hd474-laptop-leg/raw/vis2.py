import base64
import json
import urllib.request
import urllib.error

B = "http://127.0.0.1:1234/v1"
M = "agent-gemma-26b"


def post(body):
    req = urllib.request.Request(B + "/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        d = json.loads(urllib.request.urlopen(req, timeout=240).read())
        ch = (d.get("choices") or [{}])[0]
        msg = ch.get("message", {})
        return {"content": (msg.get("content") or "")[:160],
                "reasoning": (msg.get("reasoning_content") or "")[:160],
                "usage": d.get("usage")}
    except urllib.error.HTTPError as e:
        return {"HTTP": e.code, "body": e.read().decode("utf-8", "replace")[:200]}


def uri(path, mime):
    return "data:%s;base64,%s" % (mime, base64.b64encode(open(path, "rb").read()).decode())


PNG = "reports/hd474-laptop-leg/raw/bars.png"
q = "How many white horizontal bars are inside the frame? Answer with a single digit."

# baseline with NO image at all - the same text prompt
print("1 text only     :", json.dumps(post({"model": M, "max_tokens": 60, "messages": [
    {"role": "user", "content": q}]})))

# same with the image attached
print("2 text+image    :", json.dumps(post({"model": M, "max_tokens": 60, "messages": [
    {"role": "user", "content": [
        {"type": "text", "text": q},
        {"type": "image_url", "image_url": {"url": uri(PNG, "image/png")}}]}]})))

# does the server even accept the image part? ask it to describe, bigger budget
print("3 describe      :", json.dumps(post({"model": M, "max_tokens": 400, "messages": [
    {"role": "user", "content": [
        {"type": "text", "text": "Describe this image factually: colours, shapes, counts."},
        {"type": "image_url", "image_url": {"url": uri(PNG, "image/png")}}]}]})))
