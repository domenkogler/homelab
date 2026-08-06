#!/usr/bin/env python3
"""Refresh the plan-task model tier cache from the OpenRouter API.

Fetch https://openrouter.ai/api/v1/models, recompute tier assignments, and print
three things for the human to review:
  * TRACKED models (with CHANGED price/tier flags when they moved),
  * NEW candidates available on OpenRouter that we don't track yet,
  * REMOVED models that are no longer fetchable.

Then adopt + persist what the human approves:
  --apply      persist tracked models with their updated price/tier
  --add ID,..  adopt specific NEW candidate ids and persist them
  --add-new    adopt every relevant NEW OpenRouter model and persist them

Usage:
    python scripts/refresh-model-cache.py [--cache references/model-cache.json]
    python scripts/refresh-model-cache.py --apply                 # update tracked prices/tiers
    python scripts/refresh-model-cache.py --add-new --apply       # adopt all relevant new + update prices
    python scripts/refresh-model-cache.py --add openai/some-new --apply

By default it only DRY-RUNS and prints the diff. Use --apply / --add / --add-new
(any of which implies a write) to save.
"""
import argparse
import json
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

API = "https://openrouter.ai/api/v1/models"
DEFAULT_CACHE = "references/model-cache.json"

# Age past which the cache is flagged stale and a refresh should be the loud
# default rather than an opt-in.
STALE_AFTER_DAYS = 30


def fmt_age(dt: datetime) -> str:
    now = datetime.now(timezone.utc)
    secs = max(0, (now - dt).total_seconds())
    if secs < 60:
        return f"{int(secs)}s"
    if secs < 3600:
        return f"{int(secs // 60)}m"
    if secs < 86400:
        return f"{secs / 3600:.1f}h"
    days = secs / 86400
    if days < 30:
        return f"{days:.1f}d"
    if days < 365:
        return f"{days / 30:.1f}mo"
    return f"{days / 365:.1f}y"


def staleness(old: dict) -> str:
    raw = old.get("fetched_at")
    if not raw:
        return "unknown (no fetched_at)"
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return f"unparsable ({raw})"
    age = fmt_age(dt)
    if (datetime.now(timezone.utc) - dt) > timedelta(days=STALE_AFTER_DAYS):
        return f"{age} (STALE >{STALE_AFTER_DAYS}d — refresh recommended)"
    return age

# tier assignment by keyword in the id/name. Order matters: earlier rules win.
# T4 first (very strong), then small models (T1), then fast/cheap (T2), then T3.
TIER_RULES = [
    ("T4", ["claude-sonnet", "gpt-5-pro", "gpt-5.5", "gpt-5.6-sol", "claude-opus", "opus"]),
    ("T1", ["nano", "openrouter/free", "free", "-3b", "-8b"]),
    ("T2", ["deepseek-v4-flash", "deepseek-v3.2", "qwen3-coder-flash", "gemini-2.5-flash", "gpt-5-mini"]),
    ("T3", ["gpt-5", "gemini-2.5-pro", "deepseek-v4-pro", "qwen3-coder-plus", "minimax-m2", "grok-4"]),
]


def tier_for(pid: str, name: str) -> str:
    low = (pid + " " + name).lower()
    for tier, keys in TIER_RULES:
        if any(k in low for k in keys):
            return tier
    return "T2"  # sensible default; refine in TIER_RULES


def extract_caps(m):
    """Summarize a model's capabilities from OpenRouter fields into a compact
    dict + a short flag string. Stable across refreshes and small enough to live
    in the cache next to price/tier."""
    arch = m.get("architecture") or {}
    in_mods = sorted(set(arch.get("input_modalities") or []))
    out_mods = sorted(set(arch.get("output_modalities") or []))
    params = set(m.get("supported_parameters") or [])
    flags = []
    if "tools" in params or "tool_choice" in params:
        flags.append("tools")
    if "structured_outputs" in params or "response_format" in params:
        flags.append("json")
    if {"include_reasoning", "reasoning_effort"} & params:
        flags.append("reasoning")
    vision = bool({"image", "video"} & set(in_mods))
    audio = bool({"audio"} & (set(in_mods) | set(out_mods)))
    summary_bits = [f"in:{','.join(in_mods) or '-'}", f"out:{','.join(out_mods) or '-'}"]
    summary_bits += flags
    if vision:
        summary_bits.append("vision")
    if audio:
        summary_bits.append("audio")
    return {
        "in": in_mods,
        "out": out_mods,
        "tools": "tools" in flags,
        "json": "json" in flags,
        "reasoning": "reasoning" in flags,
        "vision": vision,
        "audio": audio,
        "summary": " ".join(summary_bits),
    }


def fetch_models():
    req = urllib.request.Request(API, headers={"User-Agent": "plan-task-skill"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.load(r)
    out = []
    for m in data.get("data", []):
        p = m.get("pricing") or {}
        try:
            # OpenRouter pricing is USD per token; store as USD per 1M tokens.
            pin = float(p.get("prompt") or 0) * 1_000_000
            pout = float(p.get("completion") or 0) * 1_000_000
        except (TypeError, ValueError):
            pin, pout = 0.0, 0.0
        out.append({
            "id": m.get("id"),
            "tier": tier_for(m.get("id", ""), m.get("name", "")),
            "ctx": m.get("context_length"),
            "price_in": pin,
            "price_out": pout,
            "caps": extract_caps(m),
        })
    return out


TIER_RANK = {"T1": 1, "T2": 2, "T3": 3, "T4": 4}


def tier_rank(t: str) -> int:
    return TIER_RANK.get(t, 99)


def relevant_new(new_models, fresh):
    """Pick the newcomers worth offering as adoption candidates: zero-cost
    models, the globally cheapest few, and the cheapest of each tier.
    Filters out the long tail of irrelevant models so the table stays readable."""
    if not new_models:
        return []
    tier_cheapest = {}
    for m in fresh:
        if m["price_in"] < 0:  # OpenRouter 'auto'/'routing' pseudo-models use a -1e6 sentinel
            continue
        c = tier_cheapest.get(m["tier"])
        if c is None or m["price_in"] < c["price_in"]:
            tier_cheapest[m["tier"]] = m
    tier_cheapest_ids = {m["id"] for m in tier_cheapest.values()}
    global_cheap_ids = {m["id"] for m in sorted((x for x in fresh if x["price_in"] >= 0),
                                                  key=lambda x: x["price_in"])[:3]}
    out = []
    for m in new_models:
        if m["price_in"] < 0:
            continue  # routing/auto pseudo-models are not real adoption candidates
        if m["price_in"] == 0.0 or m["id"] in tier_cheapest_ids or m["id"] in global_cheap_ids:
            out.append(m)
    return sorted(out, key=lambda x: (tier_rank(x["tier"]), x["price_in"]))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cache", default=DEFAULT_CACHE)
    ap.add_argument("--apply", action="store_true",
                    help="persist tracked models with their updated price/tier")
    ap.add_argument("--add", default="",
                    help="adopt these NEW candidate ids (comma-separated) and persist them")
    ap.add_argument("--add-new", action="store_true",
                    help="adopt every relevant NEW OpenRouter model and persist them")
    args = ap.parse_args()

    try:
        with open(args.cache, encoding="utf-8") as f:
            old = json.load(f)
    except FileNotFoundError:
        old = {"models": []}

    old_by_id = {m["id"]: m for m in old.get("models", [])}

    # Report cache age BEFORE any fetch so the human can decide with context.
    print(f"cache: {args.cache}")
    raw = old.get("fetched_at")
    try:
        dt = datetime.fromisoformat((raw or "").replace("Z", "+00:00"))
        print(f"  fetched_at : {raw}")
        print(f"  now        : {datetime.now(timezone.utc).isoformat()}")
        print(f"  age        : {fmt_age(dt)}")
        if (datetime.now(timezone.utc) - dt) > timedelta(days=STALE_AFTER_DAYS):
            print(f"  (STALE: older than {STALE_AFTER_DAYS}d — refresh recommended)")
    except (TypeError, ValueError):
        print(f"  fetched_at : {raw!r} (unparsable — treat as stale)")

    fresh = fetch_models()
    print(f"fetched {len(fresh)} models")
    fresh_by_id = {m["id"]: m for m in fresh}

    tracked_updated = [fresh_by_id[i] for i in old_by_id if i in fresh_by_id]
    new_models = [m for m in fresh if m["id"] not in old_by_id]
    removed = [i for i in old_by_id if i not in fresh_by_id]

    def caps_short(c):
        i = "/".join(c.get("in") or []) or "-"
        o = "/".join(c.get("out") or []) or "-"
        s = f"{i}->{o}"
        for k, ch in [("tools", "T"), ("json", "J"), ("reasoning", "R"), ("vision", "V"), ("audio", "A")]:
            if c.get(k):
                s += f"·{ch}"
        return s[:40]

    def row(m, note=""):
        print(f"{m['id']:44s} {m['tier']:<4} ${m['price_in']:>10.4f} ${m['price_out']:>10.4f}  {caps_short(m.get('caps', {})):<34} {note}")

    hdr = f"{'id':44s} {'tier':<4} {'in/M':>12} {'out/M':>10}  caps{'':<30} note"
    print("\n== TRACKED (id, tier, price_in/M, price_out/M, caps) ==")
    print(hdr)
    for m in sorted(tracked_updated, key=lambda x: (tier_rank(x["tier"]), x["price_in"])):
        o = old_by_id.get(m["id"], {})
        if o and (o.get("price_in") != m["price_in"] or o.get("price_out") != m["price_out"]
                  or o.get("tier") != m["tier"]):
            row(m, f"CHANGED from {o.get('tier')} ${o.get('price_in')}/M")
        else:
            row(m, "(unchanged)")

    cand = relevant_new(new_models, fresh)
    print("\n== NEW candidates on OpenRouter (adopt with --add <id> or --add-new) ==")
    if cand:
        print(hdr)
        for m in cand:
            row(m, "NEW")
        others = len(new_models) - len(cand)
        if others:
            print(f"  ... plus {others} more new models not surfaced (filtered as not relevant).")
    else:
        print("  (none)")

    if removed:
        print("\n== REMOVED from OpenRouter (no longer fetchable) ==")
        for i in sorted(removed):
            print(f"  {i}")

    # --- adoption + write ---
    adopted = []
    if args.add:
        for i in (x.strip() for x in args.add.split(",") if x.strip()):
            if i in fresh_by_id and i not in old_by_id:
                adopted.append(fresh_by_id[i])
            elif i in old_by_id:
                print(f"NOTE: --add '{i}' is already tracked (skipped)")
            else:
                print(f"WARNING: --add '{i}' not found on OpenRouter; skipped")
    if args.add_new:
        adopted = cand[:]
    seen = set()
    adopted = [m for m in adopted if not (m["id"] in seen or seen.add(m["id"]))]

    write = args.apply or args.add or args.add_new
    if write:
        old["fetched_at"] = datetime.now(timezone.utc).isoformat()
        old["models"] = tracked_updated + adopted
        # NOTE: tier_defaults / difficulty_defaults are intentionally left as
        # curated human choices. Plan-time selection re-derives the cheapest
        # model per difficulty from the models list (selection-algorithm.md), so
        # a newly adopted cheaper model is used automatically without silently
        # rewiring the published defaults to a semantically odd pick (e.g. a
        # free media model). Edit tier_defaults/difficulty_defaults by hand if
        # you want a new default.
        with open(args.cache, "w", encoding="utf-8") as f:
            json.dump(old, f, indent=2, ensure_ascii=False)
        print(f"\nWrote cache ({len(old['models'])} models, {len(adopted)} new) to: {args.cache}")
    else:
        print("\nDRY RUN (no write). Use --apply (tracked prices) and/or --add / --add-new (new candidates) to save.")


if __name__ == "__main__":
    sys.exit(main())
