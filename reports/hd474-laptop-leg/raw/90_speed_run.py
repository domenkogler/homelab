"""HD-474 tok/s + TTFT at three real prompt shapes — the re-run (HD-401 gate 3).

Why this exists separately from 88_certify.py: the first pass of the shape sweep ran while
probe-speed's streaming request still omitted `stream_options.include_usage`, so it recorded TTFT
with `prompt 0 tok`. A rate with no token count is not a measurement, so the sweep is redone here
against the fixed probe and lands in 90-speed.txt. Cold means a fresh load, no cache; warm means
the SAME prompt again on the same load, which is what a prefix-cache hit actually is.
"""
import os
import subprocess
import sys
import time

RAW = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(RAW, "..", "..", ".."))
LOG = open(os.path.join(RAW, "90-speed.txt"), "a", encoding="utf-8", buffering=1, newline="\n")
ALL_SHAPES = [(1800, "1.8k"), (8000, "8k"), (24000, "24k")]
MODEL = os.environ.get("SPEED_MODEL", "agent-gemma-26b")
# The 24k shape took ~30 min cold and 88_certify.py already ran it AFTER the usage fix landed, so
# the default re-run is the two small shapes that ran BEFORE it (cold-1.8k, warm-1.8k, cold-8k came
# out with `prompt 0 tok`). Pass SPEED_ONLY=1800,8000,24000 to redo everything.
WANT = {int(x) for x in os.environ.get("SPEED_ONLY", "1800,8000").split(",") if x.strip()}
SHAPES = [s for s in ALL_SHAPES if s[0] in WANT]


def say(s):
    print(s, flush=True)
    LOG.write(s + "\n")
    LOG.flush()


def probe(args, to=2700):
    cmd = [sys.executable, "-X", "utf8", os.path.join(REPO, "scripts", "laptop-llm.py")] + args
    say("\n$ python scripts/laptop-llm.py " + " ".join(args))
    r = subprocess.run(cmd, capture_output=True, timeout=to, cwd=REPO,
                       env={**os.environ, "PYTHONUTF8": "1"})
    say((r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")).strip())
    say("[exit %d]" % r.returncode)
    return r.returncode


say("\n===== SPEED RUN %s model=%s shapes=%s =====" % (time.strftime("%Y-%m-%d %H:%M:%S"), MODEL,
                                                       [n for _t, n in SHAPES]))
for tokens, name in SHAPES:
    rel = "reports/hd474-laptop-leg/raw/87-shape-%d.txt" % tokens
    if not os.path.exists(os.path.join(REPO, rel)):
        say("missing %s - run 87_speed_shapes.py" % rel)
        continue
    # max_tokens 256: long enough that decode is measured rather than rounded away (~15 s at
    # 17.5 t/s), short enough that a 24k cold turn does not eat another half hour of the night.
    probe(["probe-speed", "--model", MODEL, "--ttft", "--max-tokens", "256",
           "--label", "cold-%s" % name, "--prompt-file", rel, "--timeout", "2400"])
    probe(["probe-speed", "--model", MODEL, "--ttft", "--max-tokens", "256",
           "--label", "warm-%s" % name, "--prompt-file", rel, "--timeout", "2400"])
say("\n===== SPEED RUN FINISHED %s =====" % time.strftime("%Y-%m-%d %H:%M:%S"))
