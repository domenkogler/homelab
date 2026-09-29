"""HD-477: Gemma 4 26B A4B, text-only, larger context. Unattended run.

Answers three questions with measurements, in this order:
  1. baseline: the SAME weights with the projector attached (the certified leg) at 32k
  2. text-only variant (hardlinked GGUF, no mmproj in its folder): what does the projector cost?
  3. how far does the text-only variant's context go, and what does each step cost in GiB and TTFT?

Every phase writes its own file under raw/ so a crash mid-run does not lose the earlier phases.
Nothing here edits profiles.yml or todo.md - it only measures.
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

RAW = os.path.dirname(os.path.abspath(__file__))
LMS = os.path.expandvars(r"%USERPROFILE%\.lmstudio\bin\lms.exe")
CTR = r"\GPU Adapter Memory(luid_0x00000000_0x0001a051_phys_0)\Dedicated Usage"
U = "http://127.0.0.1:1234/v1/chat/completions"
VISION_KEY = "google/gemma-4-26b-a4b"
TEXTONLY_KEY = "gemma-4-26b-a4b-textonly"
LOG = open(os.path.join(RAW, "80-hd477-gemma-textonly.txt"), "a", encoding="utf-8", buffering=1)


def say(s):
    print(s, flush=True)
    LOG.write(s + "\n")


def lms(args, to=900):
    try:
        r = subprocess.run([LMS] + args, capture_output=True, stdin=subprocess.DEVNULL,
                           timeout=to, env={**os.environ, "PYTHONUTF8": "1"})
    except subprocess.TimeoutExpired:
        return "<<lms %s timed out>>" % args[0]
    return r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")


def gpu_gib():
    o = subprocess.run(["powershell", "-NoProfile", "-Command",
                        "(Get-Counter '%s').CounterSamples.CookedValue" % CTR],
                       capture_output=True, timeout=120).stdout.decode("utf-8", "replace")
    try:
        return float(o.splitlines()[-1]) / 2**30
    except Exception:
        return -1.0


def load(key, ident, ctx, par=None):
    lms(["unload", "--all"], 300)
    time.sleep(6)
    base = gpu_gib()
    a = [key, "--gpu", "max", "-c", str(ctx), "--identifier", ident, "-y"]
    if par:
        a += ["--parallel", str(par)]
    lms(["load"] + a, 1200)
    for _ in range(60):
        time.sleep(4)
        if ident in lms(["ps"], 90):
            return base
    return base


def ttft(words=1500):
    """Time to first generated token, and the accepted prompt size, at a real prompt shape.
    Words (not 'xxxx') because a character run tokenizes ~2:1 and silently tests half the window."""
    b = {"model": None, "max_tokens": 2, "stream": True,
         "messages": [{"role": "user", "content": "homelab " * words}]}
    out = {}
    t0 = time.time()
    try:
        r = urllib.request.Request(U, data=json.dumps(b).encode(),
                                   headers={"Content-Type": "application/json"})
        for line in urllib.request.urlopen(r, timeout=3600):
            if line.startswith(b"data:"):
                out = {"ttft": time.time() - t0}
                break
    except urllib.error.HTTPError as e:
        return "HTTP%s %s (%.0fs)" % (e.code, e.read().decode("utf-8", "replace")[:70], time.time() - t0)
    except Exception as e:
        return "FAIL %s (%.0fs)" % (type(e).__name__, time.time() - t0)
    return "first byte at %.1fs" % out.get("ttft", -1)


def accept(words):
    """One non-streaming request sized by WORDS so real token count is what we claim."""
    b = {"model": None, "max_tokens": 1, "stream": False,
         "messages": [{"role": "user", "content": "homelab " * words}]}
    t0 = time.time()
    try:
        r = urllib.request.Request(U, data=json.dumps(b).encode(),
                                   headers={"Content-Type": "application/json"})
        d = json.loads(urllib.request.urlopen(r, timeout=5400).read())
        u = d.get("usage") or {}
        return "ACCEPTED prompt_tokens=%s wall=%.0fs" % (u.get("prompt_tokens"), time.time() - t0)
    except urllib.error.HTTPError as e:
        return "HTTP%s %s wall=%.0fs" % (e.code, e.read().decode("utf-8", "replace")[:70], time.time() - t0)
    except Exception as e:
        return "FAIL %s wall=%.0fs" % (type(e).__name__, time.time() - t0)


def phase(title):
    say("\n===== %s  (%s) =====" % (title, time.strftime("%H:%M:%S")))


def run():
    phase("PHASE 0  what is on disk / indexed")
    say(lms(["ls"], 180)[-1500:])

    phase("PHASE 1  vision-enabled weights @32768 (the certified leg) - baseline")
    base = load(VISION_KEY, "g-vision-32k", 32768, 1)
    say("idle before load %.2f GiB | after load %.2f GiB" % (base, gpu_gib()))
    say("ps: " + [l for l in lms(["ps"], 90).splitlines() if "g-vision-32k" in l][0]
        if "g-vision-32k" in lms(["ps"], 90) else "ps: NOT LOADED")

    phase("PHASE 2  text-only variant @32768 - what does the projector cost?")
    if TEXTONLY_KEY not in lms(["ls"], 180):
        say("text-only variant not indexed yet; trying lms import --hard-link")
        say(lms(["import", r"D:\\llm\\models\\domen\\gemma-4-26B-A4B-textonly\\gemma-4-26B-A4B-it-Q4_K_M.gguf",
                 "--hard-link", "--user-repo", "domen/gemma-4-26B-A4B-textonly", "-y"], 600)[-600:])
        say("indexed now: %s" % (TEXTONLY_KEY in lms(["ls"], 180)))
    if TEXTONLY_KEY in lms(["ls"], 180):
        base = load(TEXTONLY_KEY, "g-text-32k", 32768, 1)
        say("idle before %.2f GiB | after load %.2f GiB  (delta vs phase 1 is the projector + ViT cost)"
            % (base, gpu_gib()))
        say("ps: " + ([l for l in lms(["ps"], 90).splitlines() if "g-text-32k" in l] or ["NOT LOADED"])[0])

        phase("PHASE 3  context ladder on the text-only variant")
        for ctx, words in ((32768, 10400), (49152, 10400), (65536, 10400)):
            b2 = load(TEXTONLY_KEY, "g-text-%dk" % (ctx // 1024), ctx, 1)
            if "g-text-%dk" % (ctx // 1024) not in lms(["ps"], 90):
                say("%6d: LOAD FAILED (gpu %.2f GiB)" % (ctx, gpu_gib()))
                continue
            say("%6d: loaded gpu=%.2f GiB (idle was %.2f) | %s" %
                (ctx, gpu_gib(), b2, accept(words)), flush=True)
        phase("PHASE 4  recall probe at ~28k tokens of REAL prose (acceptance is not memory)")
        # Filler made of real repository prose, not 'homelab homelab': a degenerate repeat is
        # remembered by nothing and measures nothing. Needle sits at ~92% depth.
        import glob
        src = []
        for f in glob.glob(r"D:/source/domenkogler/homelab-wt-hd474/docs/*.md")[:14]:
            try:
                src.append(open(f, encoding="utf-8", errors="replace").read())
            except Exception:
                pass
        body = "\n".join(src)
        while len(body) < 120000:
            body += "\n" + body[:40000]
        body = body[:110000]
        needle = "\nThe service tag for this host is KR-7391-QX.\n"
        prompt = body[:int(len(body) * 0.92)] + needle + body[int(len(body) * 0.92):]
        ident = "g-text-recall"
        load(TEXTONLY_KEY, ident, 32768, 1)
        b = {"model": ident, "max_tokens": 64, "stream": False,
             "messages": [{"role": "user", "content": prompt +
                           "\n\nQuestion: what is the service tag for this host? Answer with the tag only."}]}
        t0 = time.time()
        try:
            r = urllib.request.Request(U, data=json.dumps(b).encode(),
                                       headers={"Content-Type": "application/json"})
            d = json.loads(urllib.request.urlopen(r, timeout=5400).read())
            m = (d.get("choices") or [{}])[0].get("message", {})
            txt = (m.get("content") or "") + " " + (m.get("reasoning_content") or "")
            u = d.get("usage") or {}
            say("recall probe: prompt_tokens=%s wall=%.0fs answered=%r KR-7391-QX present in answer: %s"
                % (u.get("prompt_tokens"), time.time() - t0,
                   (m.get("content") or "")[:70], "KR-7391-QX" in txt), flush=True)
        except Exception as e:
            say("recall probe failed: %s after %.0fs" % (type(e).__name__, time.time() - t0))
        say(lms(["ps"], 90)[-400:])
    else:
        say("SKIPPING phases 2-4: text-only variant never appeared in lms ls")


run()
say("\nHD-477 run finished %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
