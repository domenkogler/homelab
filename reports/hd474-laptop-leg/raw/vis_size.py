"""One variable at a time: same model, same request shape, four image sizes.

The synthetic 222-byte PNG worked earlier; the 315 KB resized JPEG returned "terminated".
If the tiny PNG still works and any real JPEG kills the runtime, the mmproj path is broken for
real-world inputs - which is a different (and much worse) finding than "photo too big".
"""
import base64
import json
import subprocess
import time
import urllib.request
import urllib.error
import os

LMS = os.path.expandvars(r"%USERPROFILE%\.lmstudio\bin\lms.exe")
M = "agent-gemma-26b"
KEY = "agent-gemma-26b"
PHOTO = r"D:\source\domenkogler\homelab\docs\assets\images\20260812_185130.jpg"
OUT = "reports/hd474-laptop-leg/raw"


def sh(args, timeout=600):
    return subprocess.run([LMS] + args, capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=timeout).stdout


def post(body, timeout=300):
    req = urllib.request.Request("http://127.0.0.1:1234/v1/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        d = json.loads(urllib.request.urlopen(req, timeout=timeout).read())
        msg = (d.get("choices") or [{}])[0].get("message", {})
        return {"ok": True, "content": (msg.get("content") or "")[:300],
                "usage": d.get("usage")}
    except urllib.error.HTTPError as e:
        return {"ok": False, "HTTP": e.code,
                "body": e.read().decode("utf-8", "replace")[:160]}
    except Exception as e:
        return {"ok": False, "err": "%s %s" % (type(e).__name__, str(e)[:120])}


def loaded():
    return KEY in sh(["ps", ], timeout=60)


def ensure_loaded():
    if loaded():
        return True
    sh(["unload", "--all"], timeout=120)
    time.sleep(2)
    sh(["load", "google/gemma-4-26b-a4b", "--gpu", "max", "-c", "32768",
        "--identifier", KEY, "-y"], timeout=900)
    time.sleep(3)
    return loaded()


def img_uri(path):
    mime = "image/png" if path.endswith(".png") else "image/jpeg"
    return "data:%s;base64,%s" % (mime, base64.b64encode(open(path, "rb").read()).decode())


def make_jpeg(w, name):
    """resize the real photo to width w with Windows' own GDI+, so content is constant"""
    out = os.path.join(OUT, name)
    if os.path.exists(out):
        return out
    ps = ("Add-Type -AssemblyName System.Drawing;"
          "$img=[System.Drawing.Image]::FromFile('%s');"
          "$h=[int]($img.Height*($w/$img.Width));" % PHOTO.replace("\\", "\\\\")
          + "$w=%d;" % w +
          "$b=New-Object System.Drawing.Bitmap($w,$h);"
          "$g=[System.Drawing.Graphics]::FromImage($b);$g.InterpolationQuality='High';"
          "$g.DrawImage($img,0,0,$w,$h);"
          "$b.Save('%s',[System.Drawing.Imaging.ImageFormat]::Jpeg);"
          "$g.Dispose();$b.Dispose();$img.Dispose();" % out.replace("\\", "\\\\"))
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, text=True)
    return out


Q = "How many white horizontal bars are in this image? One digit."
Q2 = "Describe my rack: count the devices and read any legible label."

print("PNG control (222 B, known answer 3):")
if ensure_loaded():
    print("   ", json.dumps({"model": M, "r": post(
        {"model": M, "max_tokens": 300, "messages": [{"role": "user", "content": [
            {"type": "text", "text": Q},
            {"type": "image_url", "image_url": {"url": img_uri(OUT + "/bars.png")}}]}]})["r"] if False else
        post({"model": M, "max_tokens": 300, "messages": [{"role": "user", "content": [
            {"type": "text", "text": Q},
            {"type": "image_url", "image_url": {"url": img_uri(OUT + "/bars.png")}}]}]})}[:0] or
        json.dumps(post({"model": M, "max_tokens": 300, "messages": [{"role": "user", "content": [
            {"type": "text", "text": Q},
            {"type": "image_url", "image_url": {"url": img_uri(OUT + "/bars.png")}}]}]}))[:400])
else:
    print("    could not load")

for w in (320, 640, 1280):
    f = make_jpeg(w, "rack_w%d.jpg" % w)
    if not os.path.exists(f):
        print("w%d: resize failed" % w)
        continue
    print("\nJPEG w=%d (%d bytes):" % (w, os.path.getsize(f)))
    if not ensure_loaded():
        print("    runtime down; reloading failed")
        continue
    r = post({"model": M, "max_tokens": 350, "messages": [{"role": "user", "content": [
        {"type": "text", "text": Q2},
        {"type": "image_url", "image_url": {"url": img_uri(f)}}]}]})
    print("   ", json.dumps(r)[:700])
    print("     still loaded? ", loaded())
