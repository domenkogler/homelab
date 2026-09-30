"""HD-474/HD-476 certification run: boot each leg and drive the REPO PROBES at it.

Written 2026-09-30 for the overnight lane. It exists so the numbers in
reports/hd474-laptop-leg/README.md are reproducible: every line in 88-certify.txt is either a
command it ran verbatim or that command's verbatim output. It edits no repo config - flipping
tool_probe / vision_probe / certified in profiles.yml is a human-readable edit made FROM these
numbers, never by this script.

Order matters:
  1. the agent leg, because everything the client contract claims is on that leg;
  2. a deliberate image at the text-only leg, to prove it is blind in the way the contract says
     (an adapter that silently attached anyway would show up here as a PASS, which would mean the
     budget in profiles.yml is lying about the projector);
  3. the vision leg last, because it leaves the biggest thing resident - and the box is then left
     unloaded by the caller, not by this script.

Rule 0 (prompt-lmstudio.md §0): timed numbers may not be taken by a session that is itself served
by this engine. This run was driven from a session served by spark (remote GB10), which is the
allowed side of that rule. Record that in the report, not just here.
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

RAW = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(RAW, "..", "..", ".."))
LMS = os.path.expandvars(r"%USERPROFILE%\.lmstudio\bin\lms.exe")
PY = sys.executable
CTR = r"\GPU Adapter Memory(luid_0x00000000_0x0001a051_phys_0)\Dedicated Usage"
LOG = open(os.path.join(RAW, "88-certify.txt"), "a", encoding="utf-8", buffering=1, newline="\n")

AGENT_KEY = "gemma-4-26b-a4b-textonly"
VISION_KEY = "qwen3-vl-30b-a3b-instruct"
AGENT_ID = "agent-gemma-26b"
VISION_ID = "vision-qwen3vl-30b"
RACK = os.path.join(REPO, "reports", "hd474-laptop-leg", "raw", "original8160.jpg")
SMALL = os.path.join(REPO, "reports", "hd474-laptop-leg", "raw", "rack1120fits.jpg")
SHAPES = [(1800, "1.8k"), (8000, "8k"), (24000, "24k")]


def say(s):
    print(s, flush=True)
    LOG.write(s + "\n")
    LOG.flush()


def gpu_gib():
    o = subprocess.run(["powershell", "-NoProfile", "-Command",
                        "(Get-Counter '%s').CounterSamples.CookedValue" % CTR],
                       capture_output=True, timeout=120).stdout.decode("utf-8", "replace")
    try:
        return float(o.splitlines()[-1]) / 2 ** 30
    except Exception:
        return -1.0


def lms(args, to=1200):
    r = subprocess.run([LMS] + args, capture_output=True, stdin=subprocess.DEVNULL, timeout=to,
                       env={**os.environ, "PYTHONUTF8": "1"})
    return (r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace"))


def boot(key, ident, ctx=32768, par=1):
    """One load, proven three ways: lms ps, /v1/models, and the PDH counter. The engine's
    'offloaded N/N layers' line is NOT read - it is absent at verbosity 3 on this Vulkan build."""
    say("\n--- unload --all ---")
    say(lms(["unload", "--all"], 300).strip()[:400])
    time.sleep(6)
    idle = gpu_gib()
    argv = [key, "--gpu", "max", "-c", str(ctx), "--identifier", ident, "-y", "--parallel", str(par)]
    say("--- lms load %s ---" % " ".join(argv))
    say("idle before load: %.2f GiB dedicated" % idle)
    t0 = time.time()
    say(lms(["load"] + argv, 1800).strip()[:900])
    for _ in range(90):
        time.sleep(4)
        if ident in lms(["ps"], 90):
            break
    ps = [l for l in lms(["ps"], 90).splitlines() if ident in l]
    say("loaded in %.0fs | %s" % (time.time() - t0, (ps or ["NOT LOADED!"])[0].strip()))
    try:
        served = json.load(urllib.request.urlopen("http://127.0.0.1:1234/v1/models", timeout=10))
        say("/v1/models serves: %s" % [m.get("id") for m in served.get("data", [])])
    except Exception as e:
        say("/v1/models unreadable: %s" % e)
    say("dedicated after load: %.2f GiB (delta %.2f GiB)" % (gpu_gib(), gpu_gib() - idle))
    return ident in lms(["ps"], 90)


def probe(args, label=None, to=3600):
    cmd = [PY, "-X", "utf8", os.path.join(REPO, "scripts", "laptop-llm.py")] + args
    say("\n$ %s" % " ".join('"%s"' % c if " " in c else c for c in
                             ["python scripts/laptop-llm.py"] + args))
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=to, cwd=REPO,
                           env={**os.environ, "PYTHONUTF8": "1"})
    except subprocess.TimeoutExpired:
        say("<<timed out after %ds>>" % to)
        return 99
    out = r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")
    say(out.strip())
    say("[exit %d]%s" % (r.returncode, " " + label if label else ""))
    return r.returncode


def main():
    say("\n===== CERTIFY RUN %s (python %s) =====" % (time.strftime("%Y-%m-%d %H:%M:%S"),
                                                       sys.version.split()[0]))
    say("runtime: " + lms(["version"], 60).strip().replace("\n", " | ")[:200])

    if not boot(AGENT_KEY, AGENT_ID):
        say("AGENT LEG DID NOT BOOT - stopping")
        return 2

    probe(["probe-health", "--model", AGENT_ID], "is the seat even reachable")
    probe(["probe-tools", "--model", AGENT_ID], "tool_probe for agent-gemma-26b")

    # tok/s and TTFT at three real prompt shapes of repo prose (87_speed_shapes.py), cold then warm.
    for tokens, name in SHAPES:
        f = os.path.join(RAW, "87-shape-%d.txt" % tokens)
        rel = os.path.relpath(f, REPO).replace("\\", "/")
        if not os.path.exists(f):
            say("missing prompt shape %s - run 87_speed_shapes.py" % f)
            continue
        probe(["probe-speed", "--model", AGENT_ID, "--ttft", "--max-tokens", "256",
               "--label", "cold-%s" % name, "--prompt-file", rel, "--timeout", "2400"],
              "cold shape %s" % name, to=2700)
        if tokens <= 8000:      # the warm repeat of the 24k shape costs another full prefill
            probe(["probe-speed", "--model", AGENT_ID, "--ttft", "--max-tokens", "256",
                   "--label", "warm-%s" % name, "--prompt-file", rel, "--timeout", "2400"],
                  "same prompt again: prefix cache", to=2700)

    # The contract claim that matters most: this leg must NOT see. A PASS here would mean the
    # projector attached anyway and the 0.00 GiB projector line in `budget` is a lie.
    probe(["probe-vision", "--model", AGENT_ID, "--image", SMALL, "--expect", "crs328",
           "--timeout", "600"], "text-only leg MUST fail this")
    # ...and the HTTP-class distinction: a 4xx on an unknown model is a CONTRACT error (exit 3),
    # never a capability verdict (exit 1). Proven without crashing the engine on purpose.
    probe(["probe-vision", "--model", "no-such-model-here", "--image", SMALL, "--timeout", "120"],
          "expect exit 3 = contract error, not a vision verdict")

    if not boot(VISION_KEY, VISION_ID):
        say("VISION LEG DID NOT BOOT - the agent-leg numbers above still stand")
        return 3
    probe(["probe-tools", "--model", VISION_ID], "tool_probe for vision-qwen3vl-30b")
    probe(["probe-vision", "--model", VISION_ID, "--image", RACK, "--expect", "crs328",
           "--timeout", "900"], "the real rack photo at full resolution")
    probe(["probe-vision", "--model", VISION_ID, "--image", SMALL, "--expect", "crs328",
           "--timeout", "600"], "the resized variant, for comparison")
    say("\n$ lms ps")
    say(lms(["ps"], 90).strip())
    say("===== CERTIFY RUN FINISHED %s =====" % time.strftime("%Y-%m-%d %H:%M:%S"))
    return 0


sys.exit(main())
