"""HD-476 follow-ups: two things the certify run raised, both cheap, both need the GPU.

1. DOES THE SERVER HONOUR THE MODEL ID? The certify run asked for `no-such-model-here` with an
   image and got back an error naming `agent-gemma-26b` - i.e. with one model resident, LM Studio
   answered for a model that does not exist. If that also happens on the text path, then a WRONG
   model id in models-spec.yml is NOT a loud 400, it is a silent substitution, and the claim in
   docs/hardware-workstation.md ("a dead row is loud") is wrong and has to be corrected. So: send a
   text request naming a model that is not resident and see what comes back.

2. IS THE RACK LABEL STABLE? The first full-resolution pass read `CRS326-24P-2S+RM`; the session
   before this one recorded `CRS328-24P-4S+RM` and docs/network-rack.md U15 says CRS328 with a
   label photo (assets/images/CRS328.png) behind it. Both are real MikroTik SKUs. One probe cannot
   tell a misread from a correction, so ask the SAME targeted question three times and record the
   distribution - that is what "measure" means when the instrument is a language model.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.request

RAW = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(RAW, "..", "..", ".."))
LOG = open(os.path.join(RAW, "91-vision-repeat.txt"), "a", encoding="utf-8", buffering=1, newline="\n")
U = "http://127.0.0.1:1234/v1/chat/completions"
RACK = os.path.join(RAW, "original8160.jpg")
PY = sys.executable


def say(s):
    print(s, flush=True)
    LOG.write(s + "\n")
    LOG.flush()


def post(payload, to=900):
    req = urllib.request.Request(U, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json",
                                          "Authorization": "***"})
    t0 = time.time()
    try:
        d = json.loads(urllib.request.urlopen(req, timeout=to).read())
    except Exception as e:
        return {"_error": "%s: %s" % (type(e).__name__, str(e)[:200]), "_wall": time.time() - t0}
    d["_wall"] = time.time() - t0
    return d


say("\n===== VISION REPEAT %s =====" % time.strftime("%Y-%m-%d %H:%M:%S"))
resident = subprocess.run([os.path.expandvars(r"%USERPROFILE%\.lmstudio\bin\lms.exe"), "ps"],
                          capture_output=True, timeout=90).stdout.decode("utf-8", "replace")
say("resident now: " + " | ".join(l.strip() for l in resident.splitlines() if l.strip())[:200])

say("\n--- 1. unknown model id, TEXT only: does the server substitute the resident model? ---")
d = post({"model": "no-such-model-here", "max_tokens": 8, "stream": False,
          "messages": [{"role": "user", "content": "Reply with the single word: PONG"}]})
if "_error" in d:
    say("answered with HTTP-level error -> substitution does NOT happen on the text path: %s"
        % d["_error"])
else:
    m = (d.get("choices") or [{}])[0].get("message", {})
    say("ANSWERED for a model that does not exist: content=%r reasoning=%r wall=%.1fs"
        % ((m.get("content") or "")[:40], (m.get("reasoning_content") or "")[:40], d["_wall"]))
    say("-> SILENT SUBSTITUTION confirmed: a wrong id in models-spec.yml does not 400, it answers "
        "from whatever is resident. The client contract cannot rely on the server to police it.")

say("\n--- 2. the same targeted question, three times, full-resolution rack photo ---")
uri = "data:image/jpeg;base64," + base64.b64encode(open(RACK, "rb").read()).decode()
Q = ("Look at the label on the rack-mount switch in this photo. Read the MODEL NUMBER exactly as "
     "printed (it starts with the letters CRS). Answer with the model number only.")
for i in (1, 2, 3):
    d = post({"model": "vision-qwen3vl-30b", "max_tokens": 64, "stream": False,
              "messages": [{"role": "user", "content": [
                  {"type": "text", "text": Q},
                  {"type": "image_url", "image_url": {"url": uri}}]}]})
    if "_error" in d:
        say("pass %d: error %s" % (i, d["_error"]))
        continue
    m = (d.get("choices") or [{}])[0].get("message", {})
    u = d.get("usage") or {}
    say("pass %d: %r  (prompt_tokens=%s completion_tokens=%s wall=%.1fs)"
        % (i, ((m.get("content") or m.get("reasoning_content") or "").strip())[:90],
           u.get("prompt_tokens"), u.get("completion_tokens"), d["_wall"]))
say("\ndocs/network-rack.md U15 says: 'MikroTik CRS328-24P-4S+ Switch' "
    "(label photo docs/assets/images/CRS328.png).")
say("===== VISION REPEAT FINISHED %s =====" % time.strftime("%Y-%m-%d %H:%M:%S"))
