import json, urllib.request, os, concurrent.futures as cf
BASE="http://localhost:8000/v1"; TOK=os.environ["VLLM_PROBE_TOKEN"]
PROMPTS=[
 "Write a Python function computing the nth Fibonacci number with memoization, then show the first 10 values as a comment.",
 "Extract {name, date, amount} from this text as strict JSON, nothing else: 'On March 3rd, Ada Lovelace invoiced 1,250 EUR for consulting.'",
 "A train leaves at 14:00 traveling 90 km/h. A second train leaves the same station at 15:00 at 120 km/h. At what time does the second overtake the first? Show your reasoning briefly.",
 "All bloops are razzies. All razzies are lazzies. Are all bloops definitely lazzies? Answer yes or no and justify in one sentence.",
 "Review this snippet for bugs and fix them: def avg(xs): return sum(xs)/len(xs)",
 "Summarize in exactly 3 bullet points: Photosynthesis converts light energy into chemical energy in chloroplasts. The Calvin cycle fixes CO2 into glucose using ATP and NADPH.",
 "I have a red box, a blue box, and a green box. I move the marble from red to blue, then from blue to green, then from green to red. Where is the marble now? One word answer plus one sentence.",
 "Prove briefly that the square root of 2 is irrational.",
 "Write a one-paragraph explanation of how a cache works, aimed at a 10-year-old.",
 "What is the difference between symmetric and asymmetric encryption? 2 sentences each.",
]
def call(prompt, max_tokens=256):
    body=json.dumps({"model":"spark/qwen3.8-flash-next","messages":[{"role":"user","content":prompt}],"temperature":0,"max_tokens":max_tokens}).encode()
    req=urllib.request.Request(BASE+"/chat/completions",data=body,headers={"Content-Type":"application/json","Authorization":"Bearer "+TOK})
    with urllib.request.urlopen(req,timeout=600) as r: return json.load(r)
def one(pair):
    p,idx=pair
    out=[]
    for _ in range(2):
        try: out.append((call(p)["choices"][0]["message"]["content"] or "").encode())
        except Exception as e: out.append(("ERR:"+str(e)).encode())
    return idx,out
def run(conc, n=30):
    pairs=[(PROMPTS[i%len(PROMPTS)],i) for i in range(n)]
    res={}
    with cf.ThreadPoolExecutor(max_workers=conc) as ex:
        for idx,out in ex.map(one, pairs): res[idx]=out
    same=sum(1 for a,b in res.values() if a==b)
    diff=n-same; errs=sum(1 for a,b in res.values() if a.startswith(b"ERR") or b.startswith(b"ERR"))
    return same,diff,errs
for conc in (1,2):
    same,diff,errs=run(conc,30)
    print(f"conc={conc}: n=30 token-identical={same} diff={diff} errs={errs} flake_rate={diff/30*100:.1f}%")
