import json,os,subprocess,time,urllib.request,urllib.error
U="http://127.0.0.1:1234/v1/chat/completions"; M="vis-qwenvl"
CTR=r"\GPU Adapter Memory(luid_0x00000000_0x0001a051_phys_0)\Dedicated Usage"
def gib():
    o=subprocess.run(["powershell","-NoProfile","-Command","(Get-Counter '%s').CounterSamples.CookedValue"%CTR],capture_output=True,timeout=120).stdout.decode("utf-8","replace")
    try: return float(o.splitlines()[-1])/2**30
    except Exception: return -1.0
for words in (10600, 21000):
    b={"model":M,"max_tokens":1,"stream":False,"messages":[{"role":"user","content":"homelab "*words}]}
    r=urllib.request.Request(U,data=json.dumps(b).encode(),headers={"Content-Type":"application/json"})
    t=time.time()
    try:
        d=json.loads(urllib.request.urlopen(r,timeout=5400).read())
        u=d.get("usage") or {}
        print("%6d words -> ACCEPTED prompt_tokens=%s prefill_wall=%.0fs gpu=%.2f GiB"%(words,u.get("prompt_tokens"),time.time()-t,gib()),flush=True)
    except urllib.error.HTTPError as e:
        print("%6d words -> HTTP%s %s wall=%.0fs gpu=%.2f GiB"%(words,e.code,e.read().decode("utf-8","replace")[:90],time.time()-t,gib()),flush=True)
    except Exception as e:
        print("%6d words -> FAIL %s wall=%.0fs"%(words,type(e).__name__,time.time()-t),flush=True)
