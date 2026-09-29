"""Is ctx the problem, or the JPEG decode? Separate the two variables on the real rack photo.

photo  = 8160x6120 (50 MP) - the file the owner pointed at
small  = the SAME photo resized, so the only variable is decode cost
"""
import base64
import json
import subprocess
import urllib.request
import urllib.error
import os

M = "agent-gemma-26b"
B = "http://127.0.0.1:1234/v1"
PHOTO = r"D:\source\domenkogler\homelab\docs\assets\images\20260812_185130.jpg"
OUT = "reports/hd474-laptop-leg/raw"


def post(body, timeout=300):
    req = urllib.request.Request(B + "/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        d = json.loads(urllib.request.urlopen(req, timeout=timeout).read())
        msg = (d.get("choices") or [{}])[0].get("message", {})
        return {"ok": True,
                "content": (msg.get("content") or "")[:400],
                "reasoning": (msg.get("reasoning_content") or "")[:200],
                "usage": d.get("usage")}
    except urllib.error.HTTPError as e:
        return {"ok": False, "HTTP": e.code,
                "body": e.read().decode("utf-8", "replace")[:200]}
    except Exception as e:
        return {"ok": False, "err": "%s: %s" % (type(e).__name__, str(e)[:160])}


def ask(uri, q, mx=350):
    return post({"model": M, "max_tokens": mx, "messages": [{"role": "user", "content": [
        {"type": "text", "text": q},
        {"type": "image_url", "image_url": {"url": uri}}]}]})


# Make a resized copy with Windows' own tool (no PIL dependency): System.Drawing via PowerShell
small = OUT + "/rack_small.jpg"
if not os.path.exists(small):
    ps = ("Add-Type -AssemblyName System.Drawing;"
          "$img=[System.Drawing.Image]::FromFile('%s');"
          "$w=1280;$h=[int]($img.Height*($w/$img.Width));"
          "$b=New-Object System.Drawing.Bitmap($w,$h);"
          "$g=[System.Drawing.Graphics]::FromImage($b);"
          "$g.InterpolationQuality='High';$g.DrawImage($img,0,0,$w,$h);"
          "$b.Save('%s',[System.Drawing.Imaging.ImageFormat]::Jpeg);"
          "$g.Dispose();$b.Dispose();$img.Dispose();"
          "Write-Host ('made ' + $w + 'x' + $h)"
          % (PHOTO.replace("\\", "\\\\"), small.replace("\\", "\\\\")))
    print(subprocess.run(["powershell", "-NoProfile", "-Command", ps],
                         capture_output=True, text=True).stdout.strip())

Q = ("This is a photo of my homelab equipment. Describe what is on the rack: how many units/"
     "devices you can see, and read out any label or text that is legible.")

raw = open(PHOTO, "rb").read()
big = "data:image/jpeg;base64," + base64.b64encode(raw).decode()
sraw = open(small, "rb").read()
sml = "data:image/jpeg;base64," + base64.b64encode(sraw).decode()

print("\nA small resized copy (%d bytes):" % len(sraw))
print("  ", json.dumps(ask(sml, Q))[:900])
print("\nB full 50 MP photo (%d bytes), the one that crashed before:" % len(raw))
print("  ", json.dumps(ask(big, Q))[:900])
