"""HD-474: is 32 768 real for Qwen3-VL on this box, or does it look real and fail?

Load -c 32768 --parallel 1, read the same PDH dedicated-memory counter used for every other
memory claim this session, then send one request whose prompt is ~32k tokens so acceptance is
measured rather than inferred from what the loader was asked for.
"""
import json
import os
import subprocess
import time
import urllib.error
import urllib.request

LMS = os.path.expandvars(r"%USERPROFILE%\.lmstudio\bin\lms.exe")
CTR = r"\GPU Adapter Memory(luid_0x00000000_0x0001a051_phys_0)\Dedicated Usage"
U = "http://127.0.0.1:1234/v1/chat/completions"
MODEL = "vis-qwenvl"


def lms(args, to=900):
    r = subprocess.run([LMS] + args, capture_output=True, stdin=subprocess.DEVNULL,
                       timeout=to, env={**os.environ, "PYTHONUTF8": "1"})
    return r.stdout.decode("utf-8", "replace")


def gpu_gib():
    out = subprocess.run(
        ["powershell", "-NoProfile", "-Command",
         "(Get-Counter '%s').CounterSamples.CookedValue" % CTR],
        capture_output=True, timeout=120).stdout.decode("utf-8", "replace").strip()
    try:
        return float(out.splitlines()[-1]) / 2**30
    except Exception:
        return -1.0


def loaded_ctx():
    for line in lms(["ps"], 90).splitlines():
        if MODEL in line:
            return line.strip()
    return None


def fits(n_tok):
    body = {"model": MODEL, "max_tokens": 1, "stream": False,
            "messages": [{"role": "user", "content": "x" * (n_tok * 4)}]}
    r = urllib.request.Request(U, data=json.dumps(body).encode(),
                               headers={"Content-Type": "application/json"})
    try:
        d = json.loads(urllib.request.urlopen(r, timeout=900).read())
        return "accepted prompt_tokens=%s" % (d.get("usage") or {}).get("prompt_tokens")
    except urllib.error.HTTPError as e:
        return "HTTP%s %s" % (e.code, e.read().decode("utf-8", "replace")[:60])
    except Exception as e:
        return "FAIL %s" % type(e).__name__


print("GPU dedicated before: %.2f GiB" % gpu_gib())
lms(["unload", "--all"], 300)
time.sleep(5)
t0 = time.time()
lms(["load", "qwen3-vl-30b-a3b-instruct", "--gpu", "max", "-c", "32768",
     "--parallel", "1", "--identifier", MODEL, "-y"], 900)
for _ in range(40):
    time.sleep(3)
    if loaded_ctx():
        break
print("load %.0fs  ps: %s" % (time.time() - t0, loaded_ctx()))
print("GPU dedicated after load: %.2f GiB" % gpu_gib())
for n in (8192, 24576, 32768):
    print("  %6d token request: %s" % (n, fits(n)), flush=True)
print("GPU dedicated after 32k probe: %.2f GiB" % gpu_gib())
