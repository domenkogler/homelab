import json,urllib.request,urllib.error,base64
U="http://127.0.0.1:1234/v1/chat/completions"
def call(extra,q="What is 17*23? Answer with just the number.",mx=400,img=None):
    b={"model":"agent-gemma-26b","max_tokens":mx,"messages":[{"role":"user","content":q}]}
    if img: b["messages"][0]["content"]=[{"type":"text","text":q},{"type":"image_url","image_url":{"url":img}}]
    b.update(extra)
    r=urllib.request.Request(U,data=json.dumps(b).encode(),headers={"Content-Type":"application/json"})
    try:
        d=json.loads(urllib.request.urlopen(r,timeout=300).read());m=(d.get("choices") or [{}])[0].get("message",{})
        return "prompt=%s out=%s content=%r reasoning=%s"%(
          (d.get("usage") or {}).get("prompt_tokens"),(d.get("usage") or {}).get("completion_tokens"),
          (m.get("content") or "")[:60],"yes" if (m.get("reasoning_content") or "") else "no")
    except urllib.error.HTTPError as e: return "HTTP%s %s"%(e.code,e.read().decode("utf-8","replace")[:100])
    except Exception as e: return "ERR %s"%type(e).__name__
print("baseline                  :",call({}))
print("chat_template_kwargs off  :",call({"chat_template_kwargs":{"enable_thinking":False}}))
print("template_kwargs off       :",call({"template_kwargs":{"enable_thinking":False}}))
print("enable_thinking top-level :",call({"enable_thinking":False}))
