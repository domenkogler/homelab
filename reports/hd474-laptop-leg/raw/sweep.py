import json,base64,urllib.request,urllib.error,subprocess,os,time,sys
LMS=os.path.expandvars(r"%USERPROFILE%\.lmstudio\bin\lms.exe")
def run(args,to=600):
    return subprocess.run([LMS]+args,capture_output=True,stdin=subprocess.DEVNULL,
                          timeout=to,env={**os.environ,"PYTHONUTF8":"1"}).stdout.decode("utf-8","replace")
def loaded(): return "agent-gemma-26b" in run(["ps"],90)
def rel():
    run(["load","google/gemma-4-26b-a4b","--gpu","max","-c","32768","--identifier","agent-gemma-26b","-y"],900)
    for _ in range(40):
        time.sleep(4)
        if loaded(): return True
    return False
def ask(p):
    u="data:image/jpeg;base64,"+base64.b64encode(open(p,"rb").read()).decode()
    b={"model":"agent-gemma-26b","max_tokens":1200,"messages":[{"role":"user","content":[
      {"type":"text","text":"Read out ONLY text you can literally read in this photo. One per line. If nothing is legible reply exactly: NOTHING LEGIBLE"},
      {"type":"image_url","image_url":{"url":u}}]}]}
    r=urllib.request.Request("http://127.0.0.1:1234/v1/chat/completions",data=json.dumps(b).encode(),headers={"Content-Type":"application/json"})
    try:
        d=json.loads(urllib.request.urlopen(r,timeout=600).read()); m=(d.get("choices") or [{}])[0].get("message",{})
        return "OK prompt=%s content=%r"%((d.get("usage") or {}).get("prompt_tokens"),(m.get("content") or "")[:240])
    except urllib.error.HTTPError as e: return "HTTP%s %s"%(e.code,e.read().decode("utf-8","replace")[:60])
    except Exception as e: return "ERR %s"%type(e).__name__
for w in (320,640,896,1120,1600):
    p="reports/hd474-laptop-leg/raw/r%d.jpg"%w
    if not os.path.exists(p): print(w,"missing"); continue
    if not loaded() and not rel(): print(w,"no model"); continue
    print("%5dpx (%7d B): %s"%(w,os.path.getsize(p),ask(p))); sys.stdout.flush()
