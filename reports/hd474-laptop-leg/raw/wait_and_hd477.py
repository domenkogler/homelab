"""Wait for the in-flight Qwen-VL 32k job, then run HD-477 unattended.

Ordering is the whole point: unloading models now would kill the prefill that has been running
since 00:43, and its acceptance number is HD-476's evidence. So poll for its output file, then cut
over to llmster (owner installed it: C:\\Users\\domen\\.lmstudio\\llmster\\0.0.25-1), because a second
server on the same GPU would fight for VRAM while the context ladder measures it.

Every step is logged to 81-overnight-wrapper.txt. Nothing here edits repo config.
"""
import os
import subprocess
import time

RAW = os.path.dirname(os.path.abspath(__file__))
CTX = os.path.join(RAW, "ctx32k.out")
OUT = os.path.join(RAW, "81-overnight-wrapper.txt")
LMS = os.path.expandvars(r"%USERPROFILE%\.lmstudio\bin\lms.exe")
LOGH = open(OUT, "a", encoding="utf-8", buffering=1)


def say(s):
    print(s, flush=True)
    LOGH.write("%s %s\n" % (time.strftime("%H:%M:%S"), s))


def sh(cmd, to=600):
    try:
        r = subprocess.run(cmd, capture_output=True, stdin=subprocess.DEVNULL, timeout=to, shell=True,
                           env={**os.environ, "PYTHONUTF8": "1"})
    except subprocess.TimeoutExpired:
        return "<<timeout>>"
    return (r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")).strip()


say("=== wrapper up; waiting for the 32k job to finish ===")
deadline = time.time() + 45 * 60
while time.time() < deadline:
    if os.path.exists(CTX) and os.path.getsize(CTX) > 0:
        say("ctx32k finished: " + open(CTX, encoding="utf-8", errors="replace").read().strip()[:400])
        break
    time.sleep(30)
else:
    say("ctx32k never produced output within 45 min - proceeding anyway")

say("=== cutover to llmster daemon (owner installed 0.0.25-1) ===")
say(sh('"%s" server stop' % LMS, 120)[:200])
say(sh("taskkill /IM \"LM Studio.exe\" /T /F", 180)[:200])
time.sleep(20)
say("after kill, lms status: " + sh('"%s" daemon status' % LMS, 60)[:200])
say(sh('"%s" daemon up' % LMS, 300)[:400])
for _ in range(30):
    st = sh('"%s" daemon status' % LMS, 60)
    if "running" in st.lower():
        say("daemon up: " + st[:200])
        break
    time.sleep(10)
    say(sh('"%s" daemon up' % LMS, 300)[:200])
say(sh('"%s" server start' % LMS, 180)[:200])
time.sleep(15)
say("lms ls after cutover: " + sh('"%s" ls' % LMS, 240)[-400:])

say("=== running HD-477 ===")
say(sh('python -X utf8 "%s"' % os.path.join(RAW, "hd477_run.py"), 7200)[-4000:])
say("=== wrapper done ===")
