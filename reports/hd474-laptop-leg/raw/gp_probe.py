import json, urllib.request, urllib.error

B = "http://127.0.0.1:1234/v1"
M = "agent-gemma-26b"


def post(path, body):
    req = urllib.request.Request(B + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=180).read())
    except urllib.error.HTTPError as e:
        return {"HTTP": e.code, "body": e.read().decode("utf-8", "replace")[:400]}


one = json.dumps(post("/chat/completions", {"model": M, "messages": [
    {"role": "user", "content": "Reply with exactly: OK"}], "max_tokens": 8}))
print("1 plain chat      :", one[:400])

two = json.dumps(post("/chat/completions", {"model": M, "messages": [
    {"role": "user", "content": "What is 17*23? Answer with the number only."}], "max_tokens": 64}))
print("2 arithmetic      :", two[:500])

tool = {"type": "function", "function": {
    "name": "run_shell", "description": "Run a shell command on the user's machine.",
    "parameters": {"type": "object", "properties": {"command": {"type": "string"}},
                   "required": ["command"]}}}
three = json.dumps(post("/chat/completions", {"model": M, "messages": [
    {"role": "user", "content": "List the files in /tmp."}], "tools": [tool],
    "tool_choice": "auto", "max_tokens": 128}))
print("3 tools (as probe) :", three[:500])

four = json.dumps(post("/chat/completions", {"model": M, "messages": [
    {"role": "user", "content": "List the files in /tmp."}], "tools": [tool], "max_tokens": 128}))
print("4 tools no choice  :", four[:500])
