"""HD-474: is the vision crash a pixel-dimension limit or a JPEG-decoder bug?

Discriminators:
  * sweep width 1120 (last known good) -> 1280 (known bad), plus 1152/1216
  * same dimensions encoded as PNG vs JPEG  -> decoder-specific or dimension-only
  * image FIRST then text (Gemma 4 documented order) vs text-first
Reloads the model after each crash so the sweep can finish unattended.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

RAW = os.path.dirname(os.path.abspath(__file__))
SRC = r"D:/source/domenkogler/homelab/docs/assets/images/20260812_185130.jpg"
LMS = os.path.expandvars(r"%USERPROFILE%\.lmstudio\bin\lms.exe")
URL = "http://127.0.0.1:1234/v1/chat/completions"
MODEL = "agent-gemma-26b"
KEY = "google/gemma-4-26b-a4b"


def lms(args, to=900):
    return subprocess.run(
        [LMS] + args, capture_output=True, stdin=subprocess.DEVNULL,
        timeout=to, env={**os.environ, "PYTHONUTF8": "1"},
    ).stdout.decode("utf-8", "replace")


def loaded():
    return MODEL in lms(["ps"], 90)


def rel():
    lms(["load", KEY, "--gpu", "max", "-c", "32768", "--identifier", MODEL, "-y"], 900)
    for _ in range(45):
        time.sleep(4)
        if loaded():
            return True
    return False


def make(w, ext):
    out = os.path.join(RAW, "b%d%s" % (w, ext))
    if os.path.exists(out):
        return out
    fmt = "Png" if ext == ".png" else "Jpeg"
    ps = (
        "Add-Type -AssemblyName System.Drawing;"
        "$i=[System.Drawing.Image]::FromFile('%s');"
        "$w=%d;$h=[int]($i.Height*($w/$i.Width));"
        "$b=New-Object System.Drawing.Bitmap($w,$h);"
        "$g=[System.Drawing.Graphics]::FromImage($b);"
        "$g.InterpolationQuality='High';"
        "$g.DrawImage($i,0,0,$w,$h);"
        "$b.Save('%s',[System.Drawing.Imaging.ImageFormat]::%s);"
        "$g.Dispose();$b.Dispose();$i.Dispose();"
    ) % (SRC.replace("/", "\\"), w, out.replace("/", "\\"), fmt)
    subprocess.run(["powershell", "-NoProfile", "-Command", ps],
                   capture_output=True, timeout=180)
    return out


def ask(path, image_first=True):
    ext = os.path.splitext(path)[1]
    mime = "image/png" if ext == ".png" else "image/jpeg"
    du = "data:%s;base64,%s" % (mime, base64.b64encode(open(path, "rb").read()).decode())
    txt = {"type": "text", "text": "How many patch panels can you count? Reply with a number."}
    img = {"type": "image_url", "image_url": {"url": du}}
    content = [img, txt] if image_first else [txt, img]
    body = {"model": MODEL, "max_tokens": 2048,
            "messages": [{"role": "user", "content": content}]}
    r = urllib.request.Request(URL, data=json.dumps(body).encode(),
                               headers={"Content-Type": "application/json"})
    try:
        d = json.loads(urllib.request.urlopen(r, timeout=900).read())
        m = (d.get("choices") or [{}])[0].get("message", {})
        u = d.get("usage") or {}
        return "OK  in=%-5s out=%-4s content=%r" % (
            u.get("prompt_tokens"), u.get("completion_tokens"),
            (m.get("content") or "")[:70])
    except urllib.error.HTTPError as e:
        return "HTTP%s %s" % (e.code, e.read().decode("utf-8", "replace")[:60])
    except Exception as e:
        return "DEAD %s" % type(e).__name__


def main():
    log = open(os.path.join(RAW, "64-vision-boundary.txt"), "w", encoding="utf-8")

    def say(s):
        print(s)
        sys.stdout.flush()
        log.write(s + "\n")
        log.flush()

    say("=== boundary sweep: image-first, max_tokens 2048 ===")
    # 1120 jpg is already measured OK; cells below are the decisive ones.
    for w, ext in ((1280, ".jpg"), (1280, ".png"), (1120, ".png"), (1152, ".jpg")):
            if not loaded() and not rel():
                say("%5d%s SKIP no model" % (w, ext))
                continue
            p = make(w, ext)
            r = ask(p)
            say("%5dpx %-4s (%7d B)  %s" % (w, ext, os.path.getsize(p), r))
            if r.startswith("DEAD") or r.startswith("HTTP4"):
                say("      -> reloading")
                rel()
    say("=== text-first control at 1120 (documented order is image-first) ===")
    if not loaded() and not rel():
        say("no model")
    else:
        say("1120px text-first: %s" % ask(make(1120, ".jpg"), image_first=False))


main()
