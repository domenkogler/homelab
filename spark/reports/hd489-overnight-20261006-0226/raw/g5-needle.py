#!/usr/bin/env python3
"""Gate-5 needle probe (HD-489 lane brief, Step 2).

Plant the pi global-instructions marker inside a >=235,000-token filler at ~90 %
depth, ask for it back verbatim. Matching is the token-subsequence rule from
spark/llm-profiles/README.md (encode(marker) minus first+last token, checked as
a subsequence of the response's tokens) — the exact judgement runs in the vllm
container (docker exec), which holds the real tokenizer.

Read-only on the box: builds the prompt locally, POSTs to the public endpoint,
never writes the bearer. Prints only lengths, never the key.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

MARK = b"MARKER-START"
TARGET = 239000          # tokens we aim for (>=235000 depth, <=250000 safety)
MIN_PROMPT_TOKENS = 235000
MAX_PROMPT_TOKENS = 250000
# chars/token measured 2026-10-06 in the vllm container on the full doc mix:
# CONVENTIONS+README+spark-llm-profiles+hardware-spark = 3.336; retry loop re-cals.
INITIAL_CPT = 3.34

FILLER_SOURCES = [
    "CONVENTIONS.md",
    "README.md",
    "docs/spark-llm-profiles.md",
    "docs/hardware-spark.md",
]


def read_filler():
    texts = []
    for p in FILLER_SOURCES:
        if os.path.exists(p):
            texts.append(open(p, encoding="utf-8").read())
    return "\n\n".join(texts)


def build_prompt(marker_text: str, attempt: int, target_tokens: int, cpt: float) -> str:
    """Filler with the marker at ~90 % depth; sized for `target_tokens` tokens."""
    base = read_filler()
    rot = (attempt * 7919) % max(1, len(base) - 1)
    filler = (base[rot:] + base[:rot]) * 60
    chars = int(target_tokens * cpt)
    if len(filler) > chars:
        filler = filler[:chars]
    pos90 = int(len(filler) * 0.90)
    marker_block = (
        f"\n\nMARKER-START\n{marker_text}\nMARKER-END\n\n"
        'Pay attention: somewhere above there is a block delimited by "MARKER-START" '
        'and "MARKER-END". Find it and reproduce its exact content verbatim, '
        "everything between the two delimiter lines, with no commentary and no edits."
    )
    return filler[:pos90] + marker_block + filler[pos90:]


def chat(prompt: str, url: str, bearer: str, model: str) -> dict:
    body = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0,
        "max_tokens": 2048,
    }
    req = urllib.request.Request(
        url + "/chat/completions",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {bearer}",
            "Content-Type": "application/json",
        },
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            resp = json.load(r)
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", "replace")
        # vLLM: "...your prompt contains at least N input tokens ... (parameter=input_tokens, value=N)"
        m = re.search(r"value=(\d+)", msg)
        return {
            "error": msg[:300],
            "prompt_tokens": int(m.group(1)) if m else 0,
            "completion_tokens": 0,
            "_wall_s": round(time.time() - t0, 1),
        }
    resp["_wall_s"] = round(time.time() - t0, 1)
    return resp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--marker", required=True)
    ap.add_argument("--model", default="spark/qwen3.8-flash-next")
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--attempt", type=int, required=True)
    ap.add_argument("--token-env", default="OPENAI_API_KEY")
    a = ap.parse_args()

    bearer = os.environ.get(a.token_env, "")
    marker = open(a.marker, encoding="utf-8").read()
    out = a.outdir

    cpt = INITIAL_CPT
    target_tokens = TARGET
    prompt = build_prompt(marker, a.attempt, target_tokens, cpt)
    resp = chat(prompt, a.url, bearer, a.model)
    pt = resp.get("usage", {}).get("prompt_tokens") or resp.get("prompt_tokens", 0) or 0
    for run in range(1, 4):
        if MIN_PROMPT_TOKENS <= pt <= MAX_PROMPT_TOKENS and "error" not in resp:
            break
        if pt > 0 and len(prompt) > 0:
            cpt = len(prompt) / pt          # server-true ratio (its own count)
        if pt < MIN_PROMPT_TOKENS:
            target_tokens = TARGET
        elif pt > MAX_PROMPT_TOKENS:
            target_tokens = int(pt * 0.97)  # shrink below the wall
        else:
            break
        prompt = build_prompt(marker, a.attempt, target_tokens, cpt)
        resp = chat(prompt, a.url, bearer, a.model)
        pt = resp.get("prompt_tokens", 0)

    text = ""
    if "error" in resp:
        status = "HTTP-ERROR"
    else:
        text = (resp.get("choices") or [{}])[0].get("message", {}).get("content", "")
        status = "PASS-DEPTH" if pt >= MIN_PROMPT_TOKENS else "FAIL-DEPTH"
    open(os.path.join(out, f"g5-needle-{a.attempt}-response.txt"), "w", encoding="utf-8").write(text or "")
    open(
        os.path.join(out, f"g5-needle-{a.attempt}-usage.json"), "w", encoding="utf-8"
    ).write(
        json.dumps({"prompt_tokens": pt, "completion_tokens": resp.get("completion_tokens"),
                    "wall_s": resp.get("_wall_s"), "cpt_used": round(cpt, 3),
                    "status": status, "error": resp.get("error")})
    )
    print(f"attempt {a.attempt}: {status} prompt_tokens={pt} wall={resp.get('_wall_s')}s "
          f"reply_chars={len(text or '')} (cpt={cpt:.3f})")


if __name__ == "__main__":
    main()