#!/usr/bin/env python3
"""Laptop serving leg — THE MATRIX, THE GATE, THE PROBES (HD-474).

LM Studio on the Win11 host, reached from WSL over its OpenAI-compatible endpoint. Mirrors the
spark pattern one-for-one:

  scripts/laptop-llm/profiles.yml   catalogue + dial       (= IaC group_vars §spark_llm_profiles)
  laptop-llm.py matrix              what the dial offers, offline, no token
  laptop-llm.py gate                hard invariants + canaries, offline  (= check_spark_llm_gate.py)
  laptop-llm.py probe-*             live measurements that make a row true (= spark-llm-probe.py)
  scripts/win/lmstudio-llm.ps1      the Windows-side applier            (= 90-llm-switch-model.yml)

Two structural differences from spark: the laptop is not Ansible-managed, so profiles.yml is the
SSOT instead of the inventory; and the ceiling is a BIOS iGPU carve, not a discrete GPU pool.
Nothing is hardcoded — no profile name, no path, no model identifier.

    python3 scripts/laptop-llm.py matrix
    python3 scripts/laptop-llm.py gate --self-test
    python3 scripts/laptop-llm.py budget --profile agent-unified-64k
    python3 scripts/laptop-llm.py probe-client
    python3 scripts/laptop-llm.py probe-ctx --model <lmstudio identifier>
"""
from __future__ import annotations

import argparse
import base64
import copy
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("FATAL: needs pyyaml — sudo apt-get install -y python3-yaml")

HERE = Path(__file__).resolve().parent
SPEC = HERE / "laptop-llm" / "profiles.yml"
PI_SPEC = HERE / "pi-config" / "models-spec.yml"
GiB = 1024 ** 3


def dig(d, dotted, default=None):
    cur = d
    for part in str(dotted).split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur


def expand(spec, cfg):
    """Resolve '{host.model_library}' references against the config itself, then %VAR%/$VAR."""
    if isinstance(spec, str):
        for _ in range(6):
            only = re.fullmatch(r"\{([^{}]+)\}", spec.strip())
            if only:
                spec = dig(cfg, only.group(1))
                continue
            if "{" in spec and "}" in spec:
                spec = re.sub(r"\{([^{}]+)\}", lambda m: str(dig(cfg, m.group(1), "")), spec)
                continue
            break
        spec = re.sub(r"%([^%]+)%", lambda m: os.environ.get(m.group(1), m.group(0)), spec)
        return os.path.expandvars(spec)
    if isinstance(spec, dict):
        return {k: expand(v, cfg) for k, v in spec.items()}
    if isinstance(spec, list):
        return [expand(v, cfg) for v in spec]
    return spec


def load(path=SPEC):
    cfg = yaml.safe_load(Path(path).read_text())
    cfg["_dir"] = str(Path(path).resolve().parent)
    return cfg


def kv_of(cfg, prof, model):
    """KV bytes at this profile's window. kv_factor entries are {factor, requires}: llama.cpp only
    honours a quantized KV cache with flash attention ON, so the requirement travels with the
    factor instead of living as tribal knowledge in someone's head."""
    ent = dig(cfg, f"kv_factor.{prof.get('kv_cache_type')}")
    if not isinstance(ent, dict):
        return None, None
    bpt, ctx = model.get("kv_bytes_per_token") or 0, prof.get("num_ctx") or 0
    return int(ctx * bpt * ent["factor"]), ent.get("requires")


def budget(cfg, name, view=False):
    p = dig(cfg, f"profiles.{name}")
    if not p:
        return None
    m = dig(cfg["models"], p["model"]) or {}
    kv, _ = kv_of(cfg, p, m)
    carve = 100 * GiB if view else (dig(cfg, "host.gpu_carve_bytes") or 0)
    floor = 0 if view else (dig(cfg, "host.held_floor_bytes") or 0)
    mmproj = (m.get("mmproj_bytes") or 0) if "image" in (p.get("input") or []) else 0
    state = m.get("state_bytes_per_sequence") or 0
    w = m.get("weights_bytes") or 0
    need = w + mmproj + (kv or 0) + state + floor
    return dict(name=name, label=p.get("label"), weights=w, mmproj=mmproj, kv=kv or 0, state=state,
                floor=floor, need=need, carve=carve, margin=carve - need, fits=need <= carve,
                ctx=p.get("num_ctx"), kv_type=p.get("kv_cache_type"), mtp=bool(p.get("mtp")),
                certified=p.get("certified"), client_ctx=p.get("client_context_window"))


# ────────────────────────────────── the gate ──────────────────────────────────
def gate(cfg, names=None):
    """One profile that cannot fit or cannot boot fails the whole run — same policy as the spark
    gate, because each of these maps to a failure this repo has already paid for.

     1 the dial names a real profile
     2 the runtime version is pinned in git (§7) — an auto-updating app is not a pin
     3 the model row has a positive kv_bytes_per_token (0 makes invariant 5 a silent pass)
     4 num_ctx ≤ the model's native window
     5 weights + projector + KV + recurrent state + held floor ≤ the iGPU carve
     6 a quantized KV cache requires flash_attention: true, else the profile costs more than it claims
     7 client contextWindow ≤ num_ctx and maxTokens < contextWindow — pi's 400 lands here
     8 image input requires a projector ON THE FILE and a passed vision probe
     9 mtp and image input are mutually exclusive ("--mmproj not yet supported with MTP")
    10 a `tool` capability requires a passed tool probe
    11 uncertified profiles need allow_uncertified: true
    """
    errs = []
    names = names or [dig(cfg, "active")]
    allow = bool(dig(cfg, "allow_uncertified"))
    carve = dig(cfg, "host.gpu_carve_bytes") or 0
    floor = dig(cfg, "host.held_floor_bytes") or 0

    if dig(cfg, "runtime.engine") == "lmstudio" and not dig(cfg, "runtime.version"):
        errs.append("runtime.version is null: LM Studio auto-updates, so nothing may be certified "
                    "against an unpinned engine. Record the installed version in profiles.yml (§7).")

    for n in names:
        p = dig(cfg, f"profiles.{n}")
        if not p:
            errs.append(f"profile '{n}' is not in the catalogue "
                        f"(valid: {', '.join(dig(cfg, 'profiles', {}) or {})})")
            continue
        m = dig(cfg["models"], p.get("model")) or {}
        if not m:
            errs.append(f"profile {n}: model '{p.get('model')}' is not in models")
            continue
        if not m.get("kv_bytes_per_token"):
            errs.append(f"profile {n}: model {p['model']} kv_bytes_per_token="
                        f"{m.get('kv_bytes_per_token')!r} — a 0 here makes the budget check pass "
                        "silently. Derive it from the layer/KV-head/head-dim triple and record the basis.")
        ctx, nat = p.get("num_ctx") or 0, m.get("native_context_window")
        if nat and ctx > nat:
            errs.append(f"profile {n}: num_ctx {ctx} > native window {nat}")
        kv, req = kv_of(cfg, p, m)
        if kv is None:
            errs.append(f"profile {n}: kv_cache_type {p.get('kv_cache_type')!r} not in kv_factor")
            kv = 0
        elif req and not p.get("flash_attention"):
            errs.append(f"profile {n}: kv_cache_type {p['kv_cache_type']} needs flash_attention: true "
                        "(llama.cpp honours a quantized KV cache only with FA on). Turn FA on or go "
                        "back to f16 — claiming q8_0 while booting without FA is a budget lie, and "
                        "FA-on-Vulkan for this hybrid arch is itself unproven here.")
        mmproj = (m.get("mmproj_bytes") or 0) if "image" in (p.get("input") or []) else 0
        need = (m.get("weights_bytes") or 0) + mmproj + kv + (m.get("state_bytes_per_sequence") or 0) + floor
        if need > carve:
            errs.append(f"profile {n}: needs {need/GiB:.2f} GiB (weights {(m.get('weights_bytes') or 0)/GiB:.2f}"
                        f" + projector {mmproj/GiB:.2f} + KV {kv/GiB:.2f} + state "
                        f"{(m.get('state_bytes_per_sequence') or 0)/GiB:.2f} + floor {floor/GiB:.2f}) "
                        f"> carve {carve/GiB:.1f} GiB — raise the carve, drop a tier, or shrink num_ctx")
        cwin, mt = p.get("client_context_window"), p.get("client_max_tokens")
        if cwin and ctx and cwin > ctx:
            errs.append(f"profile {n}: client contextWindow {cwin} > num_ctx {ctx} — the harness would "
                        "400 mid-session (prompt-llm.md §6)")
        if cwin and mt and mt >= cwin:
            errs.append(f"profile {n}: maxTokens {mt} must leave headroom below contextWindow {cwin}")
        inp = p.get("input") or ["text"]
        if "image" in inp:
            if m.get("vision") not in ("mmproj", "fused"):
                errs.append(f"profile {n}: input claims image but model {p['model']} is vision="
                            f"{m.get('vision')!r}. A GGUF only sees if the projector is on disk (fused "
                            "vision keys in the header, or a sibling mmproj-*.gguf) — read the file, "
                            "not the model page.")
            elif m.get("vision") == "mmproj" and not m.get("mmproj_bytes"):
                # The hole blind-canary found: vision:mmproj with mmproj_bytes 0 means the projector
                # is either not on disk or not in the budget — and either way the profile lies.
                errs.append(f"profile {n}: model {p['model']} is vision:mmproj but mmproj_bytes="
                            f"{m.get('mmproj_bytes')!r} — the projector is not budgeted. A load that "
                            "needs a file the budget never counted fails at load time, on the airport.")
            elif p.get("vision_probe") != "passed" and dig(cfg, "vision_policy.allow_probeless_image_claim") is not True:
                errs.append(f"profile {n}: input claims image but vision_probe={p.get('vision_probe')!r}. "
                            "Run: laptop-llm.py probe-vision --image <file>")
        if p.get("mtp") and "image" in inp:
            errs.append(f"profile {n}: mtp: true with image input — llama.cpp does not support --mmproj "
                        "with MTP yet. Two profiles, same weights, one loaded at a time.")
        if "tool" in (p.get("capabilities") or []) and p.get("tool_probe") not in ("passed", "not-applicable"):
            errs.append(f"profile {n}: capabilities claim `tool` but tool_probe={p.get('tool_probe')!r} "
                        "(never advertise a switch that 400s)")
        if not p.get("certified") and not allow:
            errs.append(f"profile {n} is not certified: {p.get('uncertified_reason')} "
                        "— set allow_uncertified: true to run it anyway")
    return errs


# Each canary breaks ONE invariant and must fail loudly — an invariant no canary tests is an
# invariant nobody knows is enforced. Paths are write-targets inside the parsed config.
CANARIES = [
    ("typo-canary", "active", "nonsense-profile-name", "is not in the catalogue"),
    ("nopin-canary", "runtime.version", None, "runtime.version is null"),
    ("zerokv-canary", "models.qwen36-35b-a3b-mtp.kv_bytes_per_token", 0, "makes the budget check pass"),
    ("native-canary", "profiles.agent-unified.num_ctx", 10_000_000, "> native window"),
    ("tool-canary", "profiles.agent-unified.tool_probe", "failed", "tool_probe"),
    ("mtpvision-canary", "profiles.agent-unified.mtp", True, "not support --mmproj"),
    ("client-canary", "profiles.agent-unified.client_context_window", 1_048_576, "would 400 mid-session"),
    ("badkvtype-canary", "profiles.agent-unified.kv_cache_type", "q8-x", "not in kv_factor"),
    ("nofa-canary", "profiles.agent-unified-64k.flash_attention", False, "needs flash_attention: true"),
    ("model-canary", "profiles.fim-coder-3b.model", "no-such-model", "is not in models"),
    ("blind-canary", "models.qwen36-35b-a3b-mtp.mmproj_bytes", 0, "not budgeted"),
    ("budget-canary", "host.gpu_carve_bytes", 12 * GiB, "raise the carve"),
    ("uncert-canary", "allow_uncertified", False, "not certified"),
]


def cmd_matrix(cfg, _a=None):
    act = dig(cfg, "active")
    print(f"# laptop serving profiles — dial active={act} (runtime {dig(cfg,'runtime.engine')} "
          f"{dig(cfg,'runtime.version') or 'UNPINNED'}; ceiling "
          f"{(dig(cfg,'host.gpu_carve_bytes') or 0)/GiB:.0f} GiB iGPU carve)")
    print("   profile                 ctx     kv     weights+proj+KV+state+floor        margin  flags")
    for n in dig(cfg, "profiles", {}) or {}:
        b = budget(cfg, n)
        flags = (["CERTIFIED"] if b["certified"] else ["UNCERTIFIED"]) + (["MTP"] if b["mtp"] else [])
        print(f"{'*' if n == act else ' '} {n:<22} {b['ctx']:<7}{b['kv_type']:<6} "
              f"{b['weights']/GiB:6.2f}+{b['mmproj']/GiB:4.2f}+{b['kv']/GiB:4.2f}+{b['state']/GiB:4.2f}+{b['floor']/GiB:4.2f}"
              f" = {b['need']/GiB:6.2f}  {b['margin']/GiB:+6.2f}  {','.join(flags)}")
    print("\n  ⚠ UNCERTIFIED = the quality/speed claim is UNMEASURED on this hardware.")
    return 0


def cmd_budget(cfg, a):
    b = budget(cfg, a.profile, view=a.view)
    if not b:
        print("unknown profile")
        return 2
    print(f"profile {b['name']}: {b['label']}")
    print(f"  weights   {b['weights']/GiB:7.2f} GiB")
    print(f"  projector {b['mmproj']/GiB:7.2f} GiB  (counted only when input includes image)")
    print(f"  KV cache  {b['kv']/GiB:7.2f} GiB  ({b['ctx']} tokens, {b['kv_type']})")
    print(f"  GDN state {b['state']/GiB:7.2f} GiB  (constant per sequence, not per token)")
    print(f"  held floor{b['floor']/GiB:7.3f} GiB")
    print(f"  = {b['need']/GiB:.2f} GiB vs {b['carve']/GiB:.2f} GiB → margin {b['margin']/GiB:+.2f} GiB "
          f"{'FITS' if b['fits'] else 'DOES NOT FIT'}")
    print(f"  client window (pi/Continue): {b['client_ctx']}")
    return 0 if b["fits"] else 1


def cmd_gate(cfg, a):
    if a.self_test:
        bad = 0
        for name, path, val, expect in CANARIES:
            c = copy.deepcopy(cfg)
            if "." in path:
                parent, leaf = path.rsplit(".", 1)
                d = dig(c, parent)
            else:
                parent, leaf, d = None, path, c
            if not isinstance(d, dict) or leaf not in d:
                print(f"  {name:<18} BROKEN CANARY — path {path} does not exist")
                bad += 1
                continue
            d[leaf] = val
            # Two passes, unioned: the default one reads the DIAL (so a typo in `active` is caught),
            # the explicit one walks EVERY catalogue entry (several canaries target a non-active
            # profile, and an entry the gate never looks at will fail on the first deploy that
            # selects it).
            e = gate(c) + gate(c, list((dig(c, "profiles", {}) or {}).keys()))
            ok = any(expect in x for x in e)
            print(f"  {name:<18} {'caught' if ok else 'MISSED'}")
            if not ok:
                print(f"    expected '{expect}' in: {[x[:90] for x in (e or ['(gate passed!)'])]}")
                bad += 1
        print(f"\nself-test: {len(CANARIES)-bad}/{len(CANARIES)} canaries caught")
        return 1 if bad else 0
    names = [a.profile] if a.profile else None
    errs = gate(cfg, names)
    if errs:
        print(f"laptop-llm-gate: FAIL ({len(errs)}):")
        for e in errs:
            print(f"  - {e}")
        return 1
    print(f"laptop-llm-gate: PASS ({len(CANARIES)} invariants, "
          f"{len(names or [dig(cfg,'active')])} profile(s), active={dig(cfg,'active')})")
    return 0


def server_base(cfg, from_wsl=None):
    port = dig(cfg, "runtime.api_port", 1234)
    if from_wsl is None:
        from_wsl = os.name == "posix"
    # The CONTRACTED seat is Windows-native (owner, 2026-09-29): pi.dev on Win11 talks to
    # 127.0.0.1:1234 and /etc/wsl.conf is not touched — Nat mode is there deliberately. This function
    # is the DEBUG path for the other seat, and the rule still holds: probe loopback first and use it
    # only if something answers, else DISCOVER the gateway, never hardcode it (a written-down NAT
    # address is a Tuesday-afternoon outage). A gateway answer from WSL means "exposed to network" is
    # on and the Nat route works; it does NOT make the WSL seat supported — models-spec says
    # `native_only: true`, and probe-client honours that.
    if from_wsl and not _listening("127.0.0.1", port):
        try:
            out = subprocess.run(["ip", "route", "show", "default"], capture_output=True, text=True).stdout
            gw = re.search(r"default via (\S+)", out)
            if gw:
                return f"http://{gw.group(1)}:{port}/v1"
        except Exception:
            pass
    return f"http://127.0.0.1:{port}/v1"


def _in_wsl():
    """/proc/version is the documented guest marker — and the ONLY reliable one here, because both
    seats of this laptop report the same hostname (`DomenP14s`), which is why the spec carries
    `native_only:` instead of a second host name."""
    try:
        return "microsoft" in open("/proc/version").read().lower()
    except OSError:
        return False


def _listening(host, port, timeout=0.35):
    import socket
    try:
        with socket.create_connection((host, int(port)), timeout=timeout):
            return True
    except OSError:
        return False


def _post(base, path, payload, token, timeout):
    req = urllib.request.Request(base + path, data=json.dumps(payload).encode(), method="POST",
                                 headers={"Content-Type": "application/json",
                                          "Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def cmd_probe_health(cfg, a):
    base = server_base(cfg)
    try:
        d = _post(base, "/chat/completions",
                  {"model": a.model, "messages": [{"role": "user", "content": "Reply with OK."}],
                   "max_tokens": 8, "stream": False}, a.token or "lmstudio", a.timeout)
    except Exception as e:
        print(f"FAIL — {base} unreachable: {type(e).__name__}: {e}")
        print("  check: server running · port · 'Expose server to network' ON · Defender rule for the")
        print("  WSL/NAT subnet · Windows firewall profile for that network being Private")
        return 2
    print(f"OK {base} model={a.model} :: "
          f"{(d.get('choices') or [{}])[0].get('message', {}).get('content','')!r}")
    return 0


def cmd_probe_ctx(cfg, a):
    """The real usable window. LM Studio clamps context_length at LOAD time, so an oversized
    request fails at the validator instead of with a clean 400 — binary-search what actually fits
    and write THAT into the catalogue (the spark probe found 20 468 against a nominal 32 768)."""
    tok = a.token or "lmstudio"

    def fits(n):
        try:
            _post(server_base(cfg), "/chat/completions",
                  {"model": a.model, "messages": [{"role": "user", "content": "x" * max(16, n // 4)}],
                   "max_tokens": 1, "stream": False}, tok, a.timeout)
            return True
        except urllib.error.HTTPError as e:
            return e.code not in (400, 413, 422)
        except Exception:
            return None

    lo, hi, best = 1, a.hi, None
    while lo <= hi:
        mid = (lo + hi) // 2
        r = fits(mid)
        if r is None:
            print(f"  [{mid}] server unreachable/timeout — cannot measure")
            return 2
        print(f"  [{mid:>7}] {'OK' if r else 'refused'}")
        if r:
            lo, best = mid + 1, mid
        else:
            hi = mid - 1
    print(f"\nusable completion tokens at a {a.hi}-token context: {best}")
    print("→ if that is under a profile's num_ctx, LOWER num_ctx in profiles.yml and re-render pi's")
    print("  models.json. Never trust the marketing window (docs/spark-llm-profiles.md).")
    return 0


def cmd_probe_fim(cfg, a):
    """docs/hardware-workstation.md:64 demands a FIM-trained model and says Instruct variants "do
    not do it"; Qwen2.5-Coder's own card documents chat-template FIM on Instruct. Settle the
    disagreement with a cursor-shaped completion instead of an argument."""
    prof = dig(cfg, f"profiles.{a.profile}") or {}
    m = dig(cfg["models"], prof.get("model")) or {}
    prefix = ('def is_palindrome(s):\n'
              '    """Return True if s reads the same backwards."""\n    ')
    try:
        d = _post(server_base(cfg), "/completions",
                  {"model": a.model or m.get("identifier"), "prompt": prefix, "max_tokens": 64,
                   "temperature": 0.0, "stop": ["\ndef ", "\nclass "]}, a.token or "lmstudio", a.timeout)
    except Exception as e:
        print(f"FIM probe could not reach the server: {type(e).__name__}: {e}")
        return 2
    txt = (d.get("choices") or [{}])[0].get("text", "")
    NL = chr(10)
    specials = ["<|" + "im_start" + "|>", "<|" + "fim_prefix" + "|>", "```", NL + NL]
    echoed = any(t in txt for t in specials)
    looks = bool(txt.strip()) and not echoed
    print(f"prompt tokens: {d.get('usage', {})}")
    print("completion[:200]: " + repr(txt[:200]))
    print()
    if looks:
        print("FIM probe: the model continued the body without echoing the cursor or a control token.")
        print("  It is USABLE for insert, but docs/hardware-workstation.md:64 is about a model TRAINED")
        print("  for FIM: judge whether it stops at a dedent and whether it invented the signature it")
        print("  was handed. Then MEASURE trigger latency (HD-401 gate 5: sub-second is an assumption,")
        print("  and a slow trigger makes a tab model a toy). Set fim_probe: passed only after that.")
        return 0
    print("FIM probe: the model echoed the cursor / a control token instead of completing. This file is")
    print("  not serving FIM — get the -Python-FIM variant (docs/hardware-workstation.md:64) and update")
    print("  the model row. A filler tab is exactly what decision #28's follow-up was written to avoid.")
    return 1


def cmd_probe_tools(cfg, a):
    tool = {"type": "function", "function": {
        "name": "run_shell", "description": "Run a shell command on the user's machine.",
        "parameters": {"type": "object", "properties": {"command": {"type": "string"}},
                       "required": ["command"]}}}
    try:
        d = _post(server_base(cfg), "/chat/completions",
                  {"model": a.model, "messages": [{"role": "user", "content": "List the files in /tmp."}],
                   "tools": [a.tool] or [tool], "tool_choice": "auto", "max_tokens": 128, "stream": False},
                  a.token or "lmstudio", a.timeout)
    except Exception as e:
        print(f"tools probe errored (this is a result, not a crash): {type(e).__name__}: {e}")
        return 1
    ch = (d.get("choices") or [{}])[0]
    msg = ch.get("message", {})
    if msg.get("tool_calls"):
        print(f"tool_calls: {json.dumps(msg['tool_calls'])[:400]}")
        print("→ tool_probe: passed")
        return 0
    print(f"NO tool_calls (finish_reason={ch.get('finish_reason')}). Content starts: "
          f"{(msg.get('content') or '')[:200]!r}")
    print("→ a harness that advertises tools on this model will fail them. Keep `tool` OUT of the")
    print("  profile's capabilities (the gate refuses the claim without this probe).")
    return 1
def cmd_probe_speed(cfg, a):
    """tok/s and TTFT at the SHAPE the harness really sends. Prefill is the compute-bound half and
    this iGPU has 16 CU, so a tiny 'Hello' number proves nothing (HD-401 gate 3)."""
    import time
    prompt = a.prompt or ("You are a coding agent. " * 300)
    t0 = time.time()
    try:
        d = _post(server_base(cfg), "/chat/completions",
                  {"model": a.model, "messages": [{"role": "user", "content": prompt}],
                   "max_tokens": a.max_tokens, "stream": False}, a.token or "lmstudio", a.timeout)
    except Exception as e:
        print(f"speed probe failed: {type(e).__name__}: {e}")
        return 2
    dt = time.time() - t0
    u = d.get("usage", {}) or {}
    pt, ct = u.get("prompt_tokens", 0), u.get("completion_tokens", 0)
    print(f"wall {dt:.1f}s | prompt {pt} tok ({pt/dt if dt else 0:.0f} t/s) | "
          f"completion {ct} tok ({ct/dt if dt else 0:.1f} t/s)")
    print("  Record engine, template, thinking state and KV setting with this number — HD-469 run #2:")
    print("  a score without its configuration is not evidence.")
    return 0


def cmd_probe_vision(cfg, a):
    """One real image, asked about concretely. `input: [text, image]` in the client contract is a
    LIE until this passes — and on a laptop that has never loaded a projector on this engine, "it
    has vision files" is not evidence (HD-401 gate 4: the mmproj must run on the iGPU, not CPU)."""
    p = Path(a.image)
    if not p.exists():
        print(f"no image at {a.image} — pass one with --image (a screenshot of this repo's README works)")
        return 2
    mime = "image/png" if p.suffix.lower() in (".png",) else "image/jpeg"
    uri = f"data:{mime};base64,{base64.b64encode(p.read_bytes()).decode()}"
    try:
        d = _post(server_base(cfg), "/chat/completions",
                  {"model": a.model, "max_tokens": 80, "stream": False,
                   "messages": [{"role": "user", "content": [
                       {"type": "text", "text": "How many separate images are in this file? One word."},
                       {"type": "image_url", "image_url": {"url": uri}}]}]},
                  a.token or "lmstudio", a.timeout)
    except Exception as e:
        print(f"vision probe FAILED to load the image: {type(e).__name__}: {e}")
        print("  That is the answer the gate needs: an imported GGUF whose projector the engine cannot")
        print("  attach behaves EXACTLY like a text-only model, except the client advertises images.")
        return 1
    msg = (d.get("choices") or [{}])[0].get("message", {})
    print("reply: " + repr((msg.get("content") or "")[:200]))
    print("usage: " + json.dumps(d.get("usage", {})))
    print("→ If it described the image, set vision_probe: passed on that profile. Then check WHERE it")
    print("  ran: a CPU-side vision tower costs tens of seconds per image, which is a different answer.")
    return 0


def cmd_probe_client(cfg, a):
    """Drift between what the engine serves and what the client is TOLD. pi's contextWindow /
    maxTokens / input come from scripts/pi-config/models-spec.yml; if that says more than the
    profile can serve, pi 400s mid-session. The cheap test that prevents the bad afternoon."""
    act = dig(cfg, "active")
    p = dig(cfg, f"profiles.{act}") or {}
    if not PI_SPEC.exists():
        print(f"client drift: SKIP — {PI_SPEC} not found")
        return 0
    spec = yaml.safe_load(PI_SPEC.read_text())
    # providers/models are LISTS keyed by `id` in that spec (a list keeps render order, which the
    # file declares to be part of the contract) — so look them up by id, never by mapping key.
    prov = next((x for x in (spec.get("providers") or []) if x.get("id") == a.provider), None)
    if not prov:
        print(f"client drift: FAIL — provider '{a.provider}' is not in {PI_SPEC.name} (yet). "
              "The renderer needs a `hosts:` row for it or the laptop renders without it.")
        return 1
    import socket
    if prov.get("hosts") and socket.gethostname().lower() not in [str(h).lower() for h in prov["hosts"]]:
        print(f"client drift: SKIP — provider '{a.provider}' is scoped to hosts={prov['hosts']}, "
              f"this host is {socket.gethostname()!r}")
        return 0
    if prov.get("native_only") and _in_wsl():
        # The seat decision (owner, 2026-09-29): local models are served to pi.dev ON Win11, and
        # /etc/wsl.conf stays as it is on purpose. So a probe run from the Linux guest is not measuring
        # a supported path — say so instead of failing a contract that was never addressed to it.
        print(f"client drift: SKIP — provider '{a.provider}' is native_only and this is WSL2. The "
              "contract lives on the Windows seat; run this probe there (pi.dev on Win11).")
        return 0
    m = next((x for x in (prov.get("models") or []) if x.get("id") == a.model), None)
    if not m:
        print(f"client drift: FAIL — model '{a.model}' not under provider '{a.provider}'.models")
        return 1
    errs = []
    want = {"contextWindow": p.get("client_context_window"), "maxTokens": p.get("client_max_tokens"),
            "input": p.get("input") or ["text"], "reasoning": bool(m.get("reasoning"))}
    for k, v in want.items():
        if m.get(k) != v:
            errs.append(f"{k}: client says {m.get(k)!r}, active profile '{act}' serves {v!r}")
    base = (prov.get("baseUrl") or "").rstrip("/")
    live = server_base(cfg).rstrip("/")
    if base and base != live:
        # mirrored mode legitimately makes the spec's 127.0.0.1 and a discovered gateway describe the
        # same Windows host, so compare the PORT and accept loopback-vs-gateway as the two valid
        # shapes. What must NOT survive is a different port or a different machine, silently.
        pm = re.match(r"http://([^:/]+):(\d+)", base)
        pl = re.match(r"http://([^:/]+):(\d+)", live)
        if not (pm and pl and pm.group(2) == pl.group(2)
                and pm.group(1) in ("127.0.0.1", "localhost", pl.group(1))):
            errs.append(f"baseUrl {base} != anything that reaches the engine ({live}). "
                        "mirrored mode → 127.0.0.1; Nat → the discovered gateway. Check "
                        "networkingMode, the server port, and 'Expose server to network'.")
    if errs:
        print(f"client drift: FAIL ({len(errs)})")
        for e in errs:
            print(f"  - {e}")
        print("  → fix profiles.yml (active / client_*) or models-spec.yml, then re-render. Never leave")
        print("    the client's numbers ahead of the engine's.")
        return 1
    print(f"client drift: PASS — {a.provider}/{a.model} matches profile '{act}' "
          f"(contextWindow={want['contextWindow']}, maxTokens={want['maxTokens']}, "
          f"input={want['input']}, reasoning={want['reasoning']})")
    return 0


def cmd_presets(cfg, _a):
    """Emit the LM Studio config-preset JSON for every profile, to the repo copy. LM Studio has no
    Modelfile: its per-model load settings live in %USERPROFILE%\\.lmstudio\\config-presets\\*.json,
    which is why they are GENERATED here and git-tracked (CONVENTIONS §15 — config that exists only
    on a laptop does not exist). settings.json itself is NOT tracked: it holds hfDownloadToken."""
    out = {}
    for n, p in (dig(cfg, "profiles", {}) or {}).items():
        m = dig(cfg["models"], p["model"]) or {}
        ident = a_ident(cfg, p)
        out[n] = {"label": p.get("label"), "identifier": ident,
                  "contextLength": p.get("num_ctx"), "kvCacheType": p.get("kv_cache_type"),
                  "flashAttention": bool(p.get("flash_attention")),
                  "speculativeDecodingMTP": bool(p.get("mtp")),
                  "mtpDraftTokens": p.get("mtp_draft_tokens"),
                  "offloadKVCacheToGpu": True, "gpuOffloadLayers": p.get("offload_layers", "max"),
                  "evalBatchSize": 512, "temperature": (p.get("sampling_params") or {}).get("temperature"),
                  "topP": (p.get("sampling_params") or {}).get("top_p"),
                  "topK": (p.get("sampling_params") or {}).get("top_k"),
                  "systemPrompt": None, "triggerRules": []}
        mm = expand(m.get("mmproj_path"), cfg) if "image" in (p.get("input") or []) else None
        out[n]["mmproj"] = mm
        if "image" in (p.get("input") or []) and not mm:
            out[n]["_warning"] = ("profile claims image input but the model row has no mmproj_path — "
                                  "the preset would load a blind model")
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0


def cmd_settings(cfg, _a=None):
    """The settings.json keys the applier owns, already path-expanded. Emitted here rather than read
    off the YAML by PowerShell because path expansion (%USERPROFILE%, {host.model_library}) is the
    catalogue's job — two expanders is two chances to disagree about where the library is, and the
    second one gets blamed when models appear to 're-download'."""
    keys = expand(dig(cfg, "runtime.settings_keys", {}) or {}, cfg)
    print(json.dumps({"keys": keys, "settings": expand(dig(cfg, "runtime.settings"), cfg),
                      "presets_dir": expand(dig(cfg, "runtime.presets"), cfg),
                      "lms": expand(dig(cfg, "runtime.lms"), cfg),
                      "library": expand(dig(cfg, "host.model_library"), cfg),
                      "engine_version_declared": dig(cfg, "runtime.version")}, indent=2))
    return 0


def a_ident(cfg, p):
    """Model identifier for the engine. NEVER hardcoded: a model row's `identifier` if the operator
    recorded what `lms ls` reports, else the upstream repo + quant as the fetch hint."""
    m = dig(cfg["models"], p["model"]) or {}
    return m.get("identifier") or f"{m.get('upstream')}:{p.get('model')}"


def main():
    ap = argparse.ArgumentParser(description="laptop serving-leg driver (profiles.yml is the SSOT)")
    ap.add_argument("--spec", default=str(SPEC))
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("matrix").set_defaults(fn=cmd_matrix)
    b = sub.add_parser("budget"); b.add_argument("--profile"); b.add_argument("--view", action="store_true")
    b.set_defaults(fn=cmd_budget)
    g = sub.add_parser("gate"); g.add_argument("--profile"); g.add_argument("--self-test", action="store_true")
    g.set_defaults(fn=cmd_gate)

    for name, fn, model in (("probe-health", cmd_probe_health, True),
                            ("probe-ctx", cmd_probe_ctx, True),
                            ("probe-tools", cmd_probe_tools, True),
                            ("probe-speed", cmd_probe_speed, True),
                            ("probe-vision", cmd_probe_vision, True),
                            ("probe-fim", cmd_probe_fim, False)):
        s = sub.add_parser(name); s.add_argument("--model"); s.add_argument("--token")
        s.add_argument("--timeout", type=int, default=300)
        if model:
            s.add_argument("--tool", action="append")
        if name == "probe-ctx":
            s.add_argument("--hi", type=int, default=131072)
        if name == "probe-speed":
            s.add_argument("--max-tokens", type=int, default=128); s.add_argument("--prompt")
        if name == "probe-vision":
            s.add_argument("--image", required=True)
        if name == "probe-fim":
            s.add_argument("--profile", default=dig(load(), "active"))
        s.set_defaults(fn=fn)

    c = sub.add_parser("probe-client")
    cli = dig(load(), "client", {}) or {}
    c.add_argument("--provider", default=cli.get("pi_provider", "laptop-lmstudio"))
    c.add_argument("--model", default=cli.get("pi_model", "local"))
    c.set_defaults(fn=cmd_probe_client)
    sub.add_parser("presets").set_defaults(fn=cmd_presets)
    sub.add_parser("settings").set_defaults(fn=cmd_settings)
    ap.add_argument("--json", action="store_true")

    a = ap.parse_args()
    cfg = load(a.spec)
    if a.cmd.startswith("probe-") and not getattr(a, "model", None) and a.cmd != "probe-client":
        # The engine's identifier comes from the catalogue + `lms ls`, never from this script.
        p = dig(cfg, f"profiles.{dig(cfg,'active')}") or {}
        a.model = a_ident(cfg, p)
    sys.exit(a.fn(cfg, a) or 0)


if __name__ == "__main__":
    main()
