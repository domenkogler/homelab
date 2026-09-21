import os, struct, glob, collections, json
root='/home/domen/amprobe/data/state_store.db'
runs=collections.Counter(); files=collections.Counter()
def scan(p):
    b=open(p,'rb').read()
    try: t=b.decode('utf-8')
    except Exception: return None
    hits=0
    for tok in ('"embedding":', '"vector":', '"vec":', '"dims":', '"dimensions":'):
        i=0
        while True:
            i=t.find(tok,i)
            if i<0: break
            hits+=1
            seg=t[i:i+90]
            if tok=='"dims":' or tok=='"dimensions":':
                runs[seg[seg.find(':')+1:seg.find(':')+12].strip(' ,"')] += 1
            i+=5
    if hits: files[os.path.basename(p)[:40]]=hits
    return hits
n=0; tot=0
for p in glob.glob(root+'/*'):
    if os.path.isfile(p):
        h=scan(p)
        if h: n+=1; tot+=h
print("files with embedding/vector/dims keys:", n, "| total key hits:", tot)
print("literal dims values seen:", dict(list(runs.items())[:10]))
print("top files:", files.most_common(4))
# float64 scan on one observation file
p=[x for x in glob.glob(root+'/mem%3Aobs%3As01*')]
if p:
    b=open(p[0],'rb').read()
    for width,fmt,code in ((4,'<f','f32'),(8,'<d','f64')):
        best=0; cur=0
        for i in range(0,len(b)-width,width):
            v=struct.unpack(fmt,b[i:i+width])[0]
            if v==v and -2.0<v<2.0 and abs(v)>1e-9: cur+=1; best=max(best,cur)
            else: cur=0
        print("%s max aligned run: %d values = %d dims if %s" % (code,best,best,code))
