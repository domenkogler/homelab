#!/usr/bin/env python3
"""P0 slot probe: which (model-string, api_base-suffix) does each OV slot actually need?

Runs INSIDE the openviking venv (so it exercises the exact litellm version OV ships).
Never prints the key; prints key length only. Compact one-line results.
"""
import os
import sys

KEY = os.environ.get("LITELLM_KEY", "").strip()
if not KEY:
    _p = os.path.expanduser("~/ovprobe/.litellm_key")
    if os.path.exists(_p):
        KEY = open(_p, encoding="utf-8").read().strip()
assert KEY, "no key"
print(f"key_present={bool(KEY)} key_len={len(KEY)}")
print(f"python={sys.version.split()[0]}")
import litellm  # noqa: E402

from importlib.metadata import version as _v  # noqa: E402

print(f"litellm={_v('litellm')}")
os.environ.setdefault("LITELLM_LOCAL_MODEL_COST_MAP", "True")

BASES = [
    "http://10.10.1.30:4000",
    "http://10.10.1.30:4000/v1",
]
EMBED_MODELS = ["bge-m3-vk", "openai/bge-m3-vk", "hosted_vllm/bge-m3-vk"]
RERANK_MODELS = ["local-rerank", "openai/local-rerank", "jina_ai/local-rerank", "jina/local-rerank"]
CHAT_MODELS = ["spark/qwen3.8-flash-next", "openai/spark/qwen3.8-flash-next"]


def cls(e):
    s = type(e).__name__
    return f"{s}: {str(e)[:150]}".replace("\n", " ")


print("--- EMBED ---")
for m in EMBED_MODELS:
    for b in BASES:
        try:
            r = litellm.embedding(
                model=m, api_key=KEY, api_base=b, input=["test sentence"], timeout=30
            )
            v = r.data[0]["embedding"] if isinstance(r.data[0], dict) else r.data[0].embedding
            dim = len(v) if isinstance(v, list) else "NONLIST:" + str(type(v))
            first = (v[0] if isinstance(v, list) else "b64")
            print(f"OK   embed model={m:26s} base={b:34s} dim={dim} first={first}")
        except Exception as e:  # noqa: BLE001
            print(f"FAIL embed model={m:26s} base={b:34s} {cls(e)}")

print("--- RERANK ---")
for m in RERANK_MODELS:
    for b in BASES:
        try:
            r = litellm.rerank(
                model=m,
                api_key=KEY,
                api_base=b,
                query="what port does x run on",
                documents=["x runs on port 8080", "unrelated text about cats"],
            )
            res = r.results if hasattr(r, "results") else r.get("results")
            print(f"OK   rerank model={m:26s} base={b:34s} n={len(res) if res else 0}")
        except Exception as e:  # noqa: BLE001
            print(f"FAIL rerank model={m:26s} base={b:34s} {cls(e)}")

print("--- CHAT (thinking measurement, HD-387) ---")
for m in CHAT_MODELS:
    for b in BASES:
        for label, extra in (
            ("bare", {}),
            ("think_off", {"chat_template_kwargs": {"enable_thinking": False}}),
        ):
            try:
                kw = dict(
                    model=m,
                    api_key=KEY,
                    api_base=b,
                    messages=[{"role": "user", "content": "Reply with exactly: PONG"}],
                    max_tokens=64,
                    timeout=180,
                    stream=False,
                )
                kw.update(extra)
                r = litellm.completion(**kw)
                u = r.usage
                ud = u.model_dump() if hasattr(u, "model_dump") else dict(u)
                ctd = ud.get("completion_tokens_details") or {}
                if hasattr(ctd, "model_dump"):
                    ctd = ctd.model_dump()
                print(
                    f"OK   chat model={m:34s} {label:9s} prompt={ud.get('prompt_tokens')} "
                    f"compl={ud.get('completion_tokens')} reasoning={ctd.get('reasoning_tokens')} "
                    f"keys={sorted(ctd.keys())}"
                )
            except Exception as e:  # noqa: BLE001
                print(f"FAIL chat model={m:34s} {label:9s} base={b} {cls(e)}")
