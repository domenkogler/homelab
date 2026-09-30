"""Is the SKU misread sampling noise or a real perception limit? (HD-476, 2026-09-30)

91_vision_repeat.py read the rack label as CRS326-24G-2S+RM three times at the file's own sampling
defaults (general.sampling.temp 0.7), while the free-form pass earlier said CRS326-24P-2S+RM and
docs/network-rack.md U15 says CRS328-24P-4S+ with a label photo behind it. Two candidate causes:

  * sampling - fix temperature 0 and it stops wobbling, i.e. the digits are readable but the
    decoder is not deterministic; or
  * perception - greedy answers agree with each other and still disagree with the doc, i.e. this
    tower cannot read this label and the vision leg must not be trusted to transcribe a SKU.

The image is prefix-cached after the first ask (61.1 s then 1.9 s in 91_...), so each of these
costs seconds. Ask greedily, twice, plus a second question whose answer is independent of the
model number: if it can count the SFP ports, that is a different kind of seeing than OCR.
"""
import base64
import json
import os
import time
import urllib.request

RAW = os.path.dirname(os.path.abspath(__file__))
LOG = open(os.path.join(RAW, "92-vision-greedy.txt"), "a", encoding="utf-8", buffering=1, newline="\n")
U = "http://127.0.0.1:1234/v1/chat/completions"
uri = "data:image/jpeg;base64," + base64.b64encode(
    open(os.path.join(RAW, "original8160.jpg"), "rb").read()).decode()


def ask(text, temperature, max_tokens=64, to=900):
    body = {"model": "vision-qwen3vl-30b", "max_tokens": max_tokens, "stream": False,
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": text},
                {"type": "image_url", "image_url": {"url": uri}}]}]}
    if temperature is not None:
        body["temperature"] = temperature
    req = urllib.request.Request(U, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json",
                                          "Authorization": "***"})
    t0 = time.time()
    d = json.loads(urllib.request.urlopen(req, timeout=to).read())
    m = (d.get("choices") or [{}])[0].get("message", {})
    return ((m.get("content") or "").strip(), d.get("usage") or {}, time.time() - t0)


LOG.write("\n===== GREEDY VISION %s =====\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
Q1 = ("Read the model number on the switch label exactly as printed (starts with CRS). "
      "Answer with the model number only.")
for i in (1, 2, 3):
    txt, u, wall = ask(Q1, 0.0)
    LOG.write("temp=0 pass %d: %r (prompt=%s completion=%s wall=%.1fs)\n"
              % (i, txt[:80], u.get("prompt_tokens"), u.get("completion_tokens"), wall))
Q2 = ("How many SFP+/SFP+ combination ports does that switch have, and how many total Ethernet "
     "ports? Answer as two numbers with a comma, Ethernet first.")
txt, u, wall = ask(Q2, 0.0)
LOG.write("temp=0 ports: %r (prompt=%s wall=%.1fs)\n" % (txt[:100], u.get("prompt_tokens"), wall))
Q3 = ("What text is printed on the white label strip on the patch panel above the switch? "
     "Quote it exactly, up to three lines.")
txt, u, wall = ask(Q3, 0.0)
LOG.write("temp=0 panel: %r (prompt=%s wall=%.1fs)\n" % (txt[:160], u.get("prompt_tokens"), wall))
LOG.write("expected per docs/network-rack.md: U15 'MikroTik CRS328-24P-4S+ Switch' -> 24 Ethernet "
          "ports (PoE) + 4 SFP+, label photo docs/assets/images/CRS328.png\n")
LOG.write("===== GREEDY VISION FINISHED %s =====\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
print(open(os.path.join(RAW, "92-vision-greedy.txt"), encoding="utf-8").read()[-1400:])
