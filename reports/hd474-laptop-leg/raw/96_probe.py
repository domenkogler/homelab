"""96_probe.py — ask the SAME question of the crops, greedily, and let "not visible" be an answer.

The question differs from the one in raw/91/92 on purpose: those assumed a switch label was in frame,
which is exactly what a tile may not contain, and an assumption baked into a prompt is how you buy a
confident hallucination. So this version permits "NOT VISIBLE". Consequence, recorded up front: the
answers here are comparable to EACH OTHER, and only directionally comparable to the five full-frame
answers in raw/91/92 (same decoding temperature 0, different wording).

What settles the question:
  * if a tile that contains the label reads CRS328-24P-4S+ -> it was resolution, not perception, and
    the vision leg is exonerated on this label; the standing limit becomes "do not ask for an SKU
    across a wide frame", which is a usable rule for the seam design.
  * if tiles still say CRS326-24G-2S+RM at native pixels -> perception floor, and the corrected note
    in the rack doc and in the profile row stands as written.
  * if a tile with NO switch in it answers a CRS number -> confabulation, which is the worst of the
    three outcomes and the most important to know before anyone ships a rack-photo workflow.

prompt_tokens per image are printed too: they are how the crop strategy prices itself, and they
expose the ViT grid (a tile does not cost half the parent's tokens for a reason worth knowing).

Usage: python 96_probe.py <image> [<image> ...]     (default: the 2x3 grid + the downscaled frame)
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.request

RAW = os.path.dirname(os.path.abspath(__file__))
LOG = open(os.path.join(RAW, "96-crop-probe.txt"), "a", encoding="utf-8", buffering=1, newline="\n")
U = "http://127.0.0.1:1234/v1/chat/completions"
MODEL = "vision-qwen3vl-30b"
Q = ("Read the MODEL NUMBER of the rack-mount switch label in this image, exactly as printed. "
     "If no switch label is visible in this image, answer with exactly: NOT VISIBLE")
DEFAULT = ["96-tile-r0c0.jpg", "96-tile-r0c1.jpg", "96-tile-r0c2.jpg",
           "96-tile-r1c0.jpg", "96-tile-r1c1.jpg", "96-tile-r1c2.jpg",
           "96-full-fifth.jpg"]


def say(s):
    print(s, flush=True)
    LOG.write(s + "\n")
    LOG.flush()


def ask(path, to=900):
    raw = open(path, "rb").read()
    # mime by extension, so a PNG in the repo (docs/assets/images/CRS328.png) can be fed through the
    # same instrument as the JPEG crops - the label photo is the only image here with a KNOWN answer.
    mime = "image/png" if path.lower().endswith(".png") else "image/jpeg"
    uri = "data:%s;base64," % mime + base64.b64encode(raw).decode()
    body = {"model": MODEL, "temperature": 0.0, "max_tokens": 64, "stream": False,
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": Q},
                {"type": "image_url", "image_url": {"url": uri}}]}]}
    req = urllib.request.Request(U, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json",
                                          "Authorization": "***"})
    t0 = time.time()
    try:
        d = json.loads(urllib.request.urlopen(req, timeout=to).read())
    except Exception as e:
        return {"err": "%s: %s" % (type(e).__name__, str(e)[:180]), "wall": time.time() - t0}
    m = (d.get("choices") or [{}])[0].get("message", {})
    u = d.get("usage") or {}
    return {"text": (m.get("content") or "").strip(), "pt": u.get("prompt_tokens"),
            "ct": u.get("completion_tokens"), "wall": time.time() - t0}


say("\n===== CROP PROBE %s =====" % time.strftime("%Y-%m-%d %H:%M:%S"))
say("model=%s temperature=0.0 max_tokens=64" % MODEL)
say("question: " + Q)
ps = subprocess.run([os.path.expandvars(r"%USERPROFILE%\.lmstudio\bin\lms.exe"), "ps"],
                    capture_output=True, timeout=90).stdout.decode("utf-8", "replace")
say("resident: " + " | ".join(l.strip() for l in ps.splitlines() if l.strip())[:170])

for name in (sys.argv[1:] or DEFAULT):
    p = name if os.path.isabs(name) else os.path.join(RAW, name)
    if not os.path.exists(p):
        say("SKIP %s (missing)" % os.path.basename(name))
        continue
    r = ask(p)
    kb = os.path.getsize(p) // 1024
    if "err" in r:
        say("%-20s %4d KB  ERROR %s" % (os.path.basename(name), kb, r["err"]))
    else:
        say("%-20s %4d KB  prompt=%5s  %.1fs  -> %r"
            % (os.path.basename(name), kb, r["pt"], r["wall"], r["text"][:80]))
say("expected if readable: docs/network-rack.md U15 = 'MikroTik CRS328-24P-4S+ Switch' "
    "(label photo docs/assets/images/CRS328.png)")
say("previous full-frame answers (raw/91/92, temperature 0 and default): CRS326-24G-2S+RM x5, "
    "CRS326-24P-2S+RM x1")
say("===== CROP PROBE FINISHED %s =====" % time.strftime("%Y-%m-%d %H:%M:%S"))
