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


# FIXED 2026-09-30 01:44 (this session). The original said `def say(s)`, but PHASE 3 and PHASE 4
# call it as say(fmt % args, flush=True). That raised TypeError AFTER the first 32k accept had
# already burned ~8 minutes of prefill, so the ladder printed its header and died - twice: the
# 2026-09-30 01:03 run "killed on the owner's instruction at 01:16" and this one died of the same
# bug on its own. Symptom to remember: a phase header with no body line is a crashed driver, not a
# model that is thinking. LOG.flush() per line so a later crash cannot eat an earlier measurement.
def say(s, flush=True):
    print(s, flush=True)
    LOG.write(s + "\n")
    LOG.flush()


# Run one phase band from the command line: `python -X utf8 hd477_run.py 3` runs phases 3 and 4.
# Phases 0-2 already have captures; re-loading a 17 GB model to re-measure the projector costs a
# minute, so make it optional rather than mandatory.
ONLY_FROM = max(0, int(sys.argv[1])) if len(sys.argv) > 1 else 0


def band(n):
    return n >= ONLY_FROM


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


def accept(words, to=2700, ident=None):
    """One non-streaming request sized by WORDS so real token count is what we claim.
    to=2700 (45 min) is the per-step wall-clock bound: a hung request must not eat the night."""
    b = {"model": ident, "max_tokens": 1, "stream": False,
         "messages": [{"role": "user", "content": "homelab " * words}]}
    t0 = time.time()
    try:
        r = urllib.request.Request(U, data=json.dumps(b).encode(),
                                   headers={"Content-Type": "application/json"})
        d = json.loads(urllib.request.urlopen(r, timeout=to).read())
        u = d.get("usage") or {}
        return "ACCEPTED prompt_tokens=%s wall=%.0fs"\
               % (u.get("prompt_tokens"), time.time() - t0)
    except urllib.error.HTTPError as e:
        return "HTTP%s %s wall=%.0fs" % (e.code, e.read().decode("utf-8", "replace")[:70], time.time() - t0)
    except Exception as e:
        return "FAIL %s wall=%.0fs" % (type(e).__name__, time.time() - t0)


def phase(title):
    say("\n===== %s  (%s) =====" % (title, time.strftime("%H:%M:%S")))


def run():
    say("HD-477 run START %s (python %s, only_from=%d)" % (time.strftime("%Y-%m-%d %H:%M:%S"),
                                                           sys.version.split()[0], ONLY_FROM))
    if band(0):
        phase("PHASE 0  what is on disk / indexed")
        say(lms(["ls"], 180)[-1500:])
    else:
        say("PHASE 0 skipped by argv")

    if band(1):
        phase("PHASE 1  vision-enabled weights @32768 (the certified leg) - baseline")
        base = load(VISION_KEY, "g-vision-32k", 32768, 1)
        say("idle before load %.2f GiB | after load %.2f GiB" % (base, gpu_gib()))
        ps = lms(["ps"], 90)
        say("ps: " + ([l for l in ps.splitlines() if "g-vision-32k" in l] or ["NOT LOADED"])[0])
    else:
        say("PHASE 1 skipped by argv")

    if TEXTONLY_KEY not in lms(["ls"], 180):
        say("text-only variant not indexed yet; trying lms import --hard-link")
        say(lms(["import", r"D:\llm\models\domen\gemma-4-26B-A4B-textonly\gemma-4-26B-A4B-it-Q4_K_M.gguf",
                 "--hard-link", "--user-repo", "domen/gemma-4-26b-a4b-textonly", "-y"], 600)[-600:])
        say("indexed now: %s" % (TEXTONLY_KEY in lms(["ls"], 180)))
    if TEXTONLY_KEY not in lms(["ls"], 180):
        say("SKIPPING phases 2-4: text-only variant never appeared in lms ls")
        return

    if band(2):
        phase("PHASE 2  text-only variant @32768 - what does the projector cost?")
        base = load(TEXTONLY_KEY, "g-text-32k", 32768, 1)
        say("idle before %.2f GiB | after load %.2f GiB  (delta vs phase 1 is the projector + ViT cost)"
            % (base, gpu_gib()))
        say("ps: " + ([l for l in lms(["ps"], 90).splitlines() if "g-text-32k" in l] or ["NOT LOADED"])[0])
    else:
        say("PHASE 2 skipped by argv")

    if band(3):
        phase("PHASE 3  context ladder on the text-only variant")
        for ctx, words in ((32768, 10400), (49152, 10400), (65536, 10400)):
            ident = "g-text-%dk" % (ctx // 1024)
            b2 = load(TEXTONLY_KEY, ident, ctx, 1)
            if ident not in lms(["ps"], 90):
                say("%6d: LOAD FAILED (gpu %.2f GiB)" % (ctx, gpu_gib()))
                continue
            loaded_gib = gpu_gib()
            cold = accept(words, ident=ident)
            say("%6d: loaded gpu=%.2f GiB (idle before load was %.2f) | cold %s | gpu after %.2f GiB"
                % (ctx, loaded_gib, b2, cold, gpu_gib()))
            # Shorter prompt on the SAME load: what a prefix-cache hit costs at this window. Cold
            # minus warm is the honest prefill number; "wall" alone mixes prefill and cache state.
            say("%6d: warm/cache probe %s" % (ctx, accept(max(64, words // 8), ident=ident)))
    else:
        say("PHASE 3 skipped by argv")

    if band(4):
        phase("PHASE 4  recall probe at ~28k tokens of REAL prose (acceptance is not memory)")
        # Filler made of real repository prose, not 'homelab homelab': a degenerate repeat is
        # remembered by nothing and measures nothing. Needle sits at ~92% depth. The 110 000 chars
        # of docs prose measured 31 761 prompt_tokens on this engine (~3.5 chars/token) - and that
        # cold prefill took 1984 s, which is why this phase is the expensive one.
        import glob
        src = []
        for f in sorted(glob.glob(r"D:/source/domenkogler/homelab-wt-hd474/docs/*.md"))[:14]:
            try:
                src.append(open(f, encoding="utf-8", errors="replace").read())
            except Exception:
                pass
        body = "\n".join(src)
        while len(body) < 120000:
            body += "\n" + body[:40000]
        # 100 000 chars, not 110 000: the first pass measured 31 761 prompt_tokens for 110 000 chars,
        # and a 1024-token REPLY on top of that is 32 785 > num_ctx 32 768 - a clean 400 from the
        # window validator, i.e. the probe would have measured the ceiling and reported it as memory.
        # Input budget + max_tokens must fit the window; that is the same invariant probe-client
        # enforces between client_context_window and maxTokens, and it bites here too.
        body = body[:100000]
        needle = "\nThe service tag for this host is KR-7391-QX.\n"
        prompt = body[:int(len(body) * 0.92)] + needle + body[int(len(body) * 0.92):]
        ident = "g-text-recall"
        load(TEXTONLY_KEY, ident, 32768, 1)
        # max_tokens 1024, NOT 64. The first pass of this probe burned its whole 64-token budget on
        # reasoning (usage: completion_tokens=64, reasoning_tokens=61), `content` came back EMPTY,
        # and the needle check reported False. That is the same test bug that made probe-vision call
        # a working projector blind (prompt-lmstudio.md §0 / README §6 D4): this server cannot switch
        # thinking off, so a small budget measures the thinking channel, not the model's memory.
        # The verdict therefore reads content FIRST and falls back to reasoning, and prints both
        # tails so a truncated answer is visible as one instead of being read as a failure.
        b = {"model": ident, "max_tokens": 1024, "stream": False,
             "messages": [{"role": "user", "content": prompt +
                           "\n\nQuestion: what is the service tag for this host? Answer with the tag only."}]}
        t0 = time.time()
        try:
            r = urllib.request.Request(U, data=json.dumps(b).encode(),
                                       headers={"Content-Type": "application/json"})
            d = json.loads(urllib.request.urlopen(r, timeout=2700).read())
            m = (d.get("choices") or [{}])[0].get("message", {})
            content = (m.get("content") or "").strip()
            reasoning = (m.get("reasoning_content") or "").strip()
            txt = content + " " + reasoning
            u = d.get("usage") or {}
            say("recall probe: prompt_tokens=%s wall=%.0fs answer=%r needle_found=%s"
                % (u.get("prompt_tokens"), time.time() - t0, content[:120], "KR-7391-QX" in txt))
            say("recall usage: %s" % json.dumps(u))
            if not content:
                say("recall: content was EMPTY (thinking ate the budget). reasoning tail: %r"
                    % reasoning[-160:])
                say("recall in reasoning only: %s  <-- treat as INCONCLUSIVE, not as a failure"
                    % ("KR-7391-QX" in reasoning))
        except Exception as e:
            say("recall probe failed: %s after %.0fs" % (type(e).__name__, time.time() - t0))
        say(lms(["ps"], 90)[-400:])
    else:
        say("PHASE 4 skipped by argv")


run()
say("\nHD-477 run finished %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
