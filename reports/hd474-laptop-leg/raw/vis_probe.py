import base64
import json
import urllib.request
import urllib.error

B = "http://127.0.0.1:1234/v1"
M = "agent-gemma-26b"
IMG = "D:/source/domenkogler/homelab/docs/assets/images/20260812_185130.jpg"

raw = open(IMG, "rb").read()
print("photo bytes:", len(raw))


def post(body):
    req = urllib.request.Request(B + "/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        return "OK", json.loads(urllib.request.urlopen(req, timeout=240).read())
    except urllib.error.HTTPError as e:
        return "HTTP %s" % e.code, e.read().decode("utf-8", "replace")[:500]


# A: full-size jpeg, exactly as the probe sends it
uri = "data:image/jpeg;base64," + base64.b64encode(raw).decode()
st, r = post({"model": M, "max_tokens": 60, "messages": [
    {"role": "user", "content": [
        {"type": "text", "text": "What object is in this photo? One short phrase."},
        {"type": "image_url", "image_url": {"url": uri}}]}]})
print("A full jpeg      :", st, str(r)[:300])

# B: the loaded model's own view of itself - does it think it has a vision tower?
try:
    d = json.loads(urllib.request.urlopen(B.replace("/v1", "/api/v0/models"), timeout=30).read())
    for m in d.get("data", []):
        print("C model record   :", json.dumps(m)[:700])
except Exception as e:
    print("C model record   : err", e)
