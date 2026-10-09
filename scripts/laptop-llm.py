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
    python3 scripts/laptop-llm.py budget --profile vision-qwen3vl-30b
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

# The CONTRACTED seat is Windows-native (owner 2026-09-29), and on Win11 a plain
# `python scripts\laptop-llm.py …` runs with the console/locale codec = cp1252. Measured live
# 2026-09-29 (HD-474): that made this driver die before it could say anything — UnicodeDecodeError
# reading the UTF-8 catalogue, and UnicodeEncodeError printing '⚠'/'→'. Every
# scripts/win/lmstudio-llm.ps1 call therefore failed in its FIRST catalogue read. UTF-8 is forced
# in both directions here rather than trusting the caller to export PYTHONUTF8=1.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):    # redirected / closed streams
        pass

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
    # encoding explicit: profiles.yml is UTF-8 and the Windows seat's default codec is not.
    cfg = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
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
#
# 2026-10-09: the runtime's agent legs left the catalogue (docs/hardware-workstation.md §Served
# leg), and seven canaries targeted those profiles or their model row. Every one of them moved to a
# surviving target that exercises the SAME invariant — none was dropped, none was softened, and the
# count is what `gate --self-test` prints, not what this list is aiming at.
CANARIES = [
    ("typo-canary", "active", "nonsense-profile-name", "is not in the catalogue"),
    ("nopin-canary", "runtime.version", None, "runtime.version is null"),
    ("zerokv-canary", "models.qwen3vl-30b-a3b.kv_bytes_per_token", 0, "makes the budget check pass"),
    ("native-canary", "profiles.vision-qwen3vl-30b.num_ctx", 10_000_000, "> native window"),
    ("tool-canary", "profiles.vision-qwen3vl-30b.tool_probe", "failed", "tool_probe"),
    ("mtpvision-canary", "profiles.vision-qwen3vl-30b.mtp", True, "not support --mmproj"),
    ("client-canary", "profiles.vision-qwen3vl-30b.client_context_window", 1_048_576,
     "would 400 mid-session"),
    ("badkvtype-canary", "profiles.vision-qwen3vl-30b.kv_cache_type", "q8-x", "not in kv_factor"),
    ("nofa-canary", "profiles.fim-coder-3b.flash_attention", False, "needs flash_attention: true"),
    ("model-canary", "profiles.fim-coder-3b.model", "no-such-model", "is not in models"),
    ("blind-canary", "models.qwen3vl-30b-a3b.mmproj_bytes", 0, "not budgeted"),
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


def msg_text(msg):
    """Read what the model actually said. This server (developer.separateReasoningContentInAPI)
    puts a reasoning model's output in reasoning_content and leaves content EMPTY until it is
    done thinking, so a probe that reads only content reports silence from a healthy server.
    Returns (text, kind) where kind is 'content' or 'reasoning'."""
    c = (msg.get("content") or "").strip()
    if c:
        return c, "content"
    r = (msg.get("reasoning_content") or "").strip()
    if r:
        return r, "reasoning"
    if msg.get("tool_calls"):
        return json.dumps(msg["tool_calls"])[:120], "tool_calls"
    return "", "empty"


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
    msg = (d.get("choices") or [{}])[0].get("message", {})
    txt, kind = msg_text(msg)
    if kind == "empty":
        print(f"WARN {base} answered but returned NOTHING in content OR reasoning_content "
              f"(model={a.model}). Server is up; the reply is empty. Try a larger --timeout / "
              f"max_tokens, or check the template.")
        return 0
    note = "  <-- reasoning model: content is empty BY DESIGN, output is in reasoning_content" \
        if kind == "reasoning" else ""
    print(f"OK {base} model={a.model} [{kind}] :: {txt[:120]!r}{note}")
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


# A cursor-shaped infill, not a continuation. The gap is ONE token wide and only the middle
# resolves it: 'x = a ' + <GAP> + ' + b' must be bridged by '+ '. Nothing else in the file
# supplies that token, so a model that merely continues prose cannot pass.
FIM_CASES = [
    dict(name="python-bridge", prefix="x = a ", suffix=" + b",
         must_contain="+", must_not_contain=("x = a", "a  + b")),
    dict(name="def-body", prefix="def area(r):\n    return ", suffix="\n\ndef perim(r):",
         must_contain="3.14", must_not_contain=("def area",)),
]


def fim_self_test():
    """A test that cannot fail is not evidence (CONVENTIONS §6). The original merged probe failed a
    PERFECT completion because its detector treated a plain blank line as a control-token echo, and
    it never tested infill at all (prefix only = continuation). These canaries breed one WRONG verdict
    per failure shape and refuse a classifier that lets any of them through."""
    bad = 0
    good = ["+ b", "3.14 * r * r"]
    print("fim self-test (each line is a canary that MUST be caught):")
    # 1 a good bridge must PASS
    for t, c in zip(good, FIM_CASES):
        ok = _fim_verdict(t, c)[0]
        print(f"  good bridge {c['name']:<14} {'caught' if ok else 'MISSED'}")
        bad += 0 if ok else 1
    # 2 echoing the cursor / re-printing the whole file must FAIL
    for t, c in [("x = a " + " + b", FIM_CASES[0]), ("def area(r):\n    return 0", FIM_CASES[1])]:
        ok = _fim_verdict(t, c)[0]
        print(f"  echo          {c['name']:<14} {'caught' if not ok else 'MISSED'}")
        bad += 0 if not ok else 1
    # 3 empty must FAIL
    ok = _fim_verdict("", FIM_CASES[0])[0]
    print(f"  empty completion {'caught' if not ok else 'MISSED'}")
    bad += 0 if not ok else 1
    # 4 control-token echo must FAIL
    ok = _fim_verdict("<|" + "fim_middle" + "|>", FIM_CASES[0])[0]
    print(f"  control token  echo      {'caught' if not ok else 'MISSED'}")
    bad += 0 if not ok else 1
    print(f"\nfim self-test: {6-bad}/6 verdicts correct")
    return 1 if bad else 0


def _fim_verdict(txt, case):
    """(passed, why). Deliberately narrow: it asks whether the completion BRIDGES the gap, and it
    only calls it an echo when the completion repeats the prefix/suffix or leaks a control token —
    never on 'blank line', which is ordinary code."""
    if not txt or not txt.strip():
        return False, "empty completion"
    low = txt
    for tok in ("<|", "[INST]", "```"):
        if tok in low:
            return False, f"leaked control/markup token {tok!r}"
    for rep in (case["must_not_contain"] or ()):
        if rep in low:
            return False, f"repeated the handed text {rep!r} (echo, not infill)"
    if case["must_contain"] not in low:
        return False, f"did not supply the bridging text {case['must_contain']!r}"
    return True, "bridged the gap"


def _fim_profile(cfg):
    """The FIM leg's profile name, found by its capability rather than by the dial. Since the
    2026-10-09 retirement the active profile is the resident GENERATION leg (vision), so defaulting
    this probe to `active` would silently measure the wrong model — and a probe that measures the
    wrong model and prints a verdict is worse than one that fails. `capabilities: [insert]` is what
    marks the tab-completion row in the catalogue."""
    hits = [n for n, p in (dig(cfg, "profiles", {}) or {}).items()
            if "insert" in (p.get("capabilities") or [])]
    return hits[0] if len(hits) == 1 else None


def cmd_probe_fim(cfg, a):
    """docs/hardware-workstation.md:64 demands a FIM-trained model and says Instruct variants "do
    not do it"; Qwen2.5-Coder's own card documents chat-template FIM on Instruct. Settle the
    disagreement with a cursor-shaped infill instead of an argument.

    Rewritten 2026-09-29 (HD-474): the merged version sent a PREFIX ONLY, which measures
    continuation and cannot answer the question, and its detector counted a blank line as a
    control-token echo, so a correct completion was reported as FAIL. Measured on this box: the
    model completed 'def is_palindrome' perfectly and the probe called it an echo."""
    if a.self_test:
        return fim_self_test()
    prof_name = a.profile or _fim_profile(cfg)
    if not prof_name:
        print("probe-fim: the catalogue does not name exactly one FIM leg (a profile with "
              "capabilities: [insert]), so the probe cannot pick a model for itself. Pass --profile.")
        return 2
    prof = dig(cfg, f"profiles.{prof_name}") or {}
    if not prof:
        print(f"probe-fim: profile '{prof_name}' is not in the catalogue "
              f"(valid: {', '.join((dig(cfg, 'profiles', {}) or {}).keys())})")
        return 2
    m = dig(cfg["models"], prof.get("model")) or {}
    model = a.model or m.get("identifier")
    passes, results = 0, []
    print(f"FIM leg: profile '{prof_name}' -> model {model!r} "
          f"(the dial is active={dig(cfg, 'active')!r}; the FIM leg is found by its `insert` "
          "capability, not by what is resident)")
    for case in FIM_CASES:
        # Both shapes: the raw cursor gap, and the chat-template FIM form the model card documents.
        prompt = a.prompt_tmpl.format(prefix=case["prefix"], suffix=case["suffix"]) if a.prompt_tmpl \
            else case["prefix"] + case["suffix"]
        try:
            d = _post(server_base(cfg), "/completions",
                      {"model": model, "prompt": prompt, "max_tokens": 32, "temperature": 0.0,
                       "stop": [case["suffix"]] if case["suffix"] else None},
                      a.token or "lmstudio", a.timeout)
        except Exception as e:
            print(f"FIM probe could not reach the server: {type(e).__name__}: {e}")
            return 2
        txt = (d.get("choices") or [{}])[0].get("text", "")
        # the server echoes nothing; strip the prompt we know it received
        body = txt.replace(prompt, "")
        ok, why = _fim_verdict(body, case)
        passes += 1 if ok else 0
        results.append((case["name"], ok, why, body))
        print(f"  {case['name']:<14} {'PASS' if ok else 'FAIL'}  {why}")
        print(f"      bridged text: {body[:120]!r}")
    print()
    if passes == len(FIM_CASES):
        print(f"FIM probe: {passes}/{len(FIM_CASES)} cursor-shaped infills bridged correctly. The model DOES")
        print("  infill on these weights — Qwen's card is right and docs/hardware-workstation.md:64's")
        print("  'Instruct variants do not do it' is wrong for this quantised pair. Still measure trigger")
        print("  latency before trusting it (HD-401 gate 5), then set fim_probe: passed.")
        return 0
    print(f"FIM probe: {passes}/{len(FIM_CASES)} passed. Not a reliable infiller on this load — the FIM row")
    print("  changes model (the -Python-FIM pair named in docs/hardware-workstation.md:64), and the doc")
    print("  claim is recorded as tested rather than assumed.")
    return 1


def cmd_probe_tools(cfg, a):
    tool = {"type": "function", "function": {
        "name": "run_shell", "description": "Run a shell command on the user's machine.",
        "parameters": {"type": "object", "properties": {"command": {"type": "string"}},
                       "required": ["command"]}}}
    # tool_choice is NOT sent on purpose: LM Studio 0.4.25 rejects tool_choice:"auto" with HTTP 400
    # (measured 2026-09-29), and a probe that reports that 400 as "the model cannot use tools" takes
    # a WORKING capability out of the client contract. Omitting it is also the honest test - the
    # harness does not pin the choice either.
    payload = {"model": a.model, "messages": [{"role": "user", "content": "List the files in /tmp."}],
               "tools": [t for t in (a.tool or [])] or [tool], "max_tokens": 128, "stream": False}
    try:
        d = _post(server_base(cfg), "/chat/completions", payload, a.token or "lmstudio", a.timeout)
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace")[:300]
        except Exception:
            pass
        print(f"tools probe: server rejected the REQUEST with HTTP {e.code}: {body}")
        print("  That is a contract error on the SERVER, not a verdict on the model. Do NOT set")
        print("  tool_probe: failed from this - fix the request shape and re-run. (HD-474 measured")
        print("  exactly this with tool_choice, while the same model produced valid tool_calls.)")
        return 3
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
    this iGPU has 16 CU, so a tiny 'Hello' number proves nothing (HD-401 gate 3).

    Added 2026-09-30 (HD-474), because the old default prompt ("You are a coding agent. " * 300) is
    a degenerate repeat the prefix cache swallows and chars/4 arithmetic lies (a run of 'xxxx' hits
    ~2:1, real prose ~4.5:1) - so the shape was never the shape and the window was never the window.
      --prompt-file  real prose, not a repeat; the file IS the prompt shape and goes in the record
      --ttft         stream and time the FIRST token; non-streaming wall alone cannot separate
                     prefill from decode, and TTFT is what a user feels
      --label        what to call this shape in the log (e.g. cold-8k)
    Always report usage.prompt_tokens, never an estimate (docs §Traps)."""
    import time
    if a.prompt_file:
        prompt = Path(a.prompt_file).read_text(encoding="utf-8", errors="replace")
        shape = f"{a.label or a.prompt_file} ({len(prompt)} chars)"
    else:
        prompt = a.prompt or ("You are a coding agent. " * 300)
        shape = f"built-in default repeat ({len(prompt)} chars) - NOT a real prompt shape"
    base, tok = server_base(cfg), a.token or "lmstudio"
    body = {"model": a.model, "messages": [{"role": "user", "content": prompt}],
            "max_tokens": a.max_tokens, "stream": bool(a.ttft)}
    if a.ttft:
        # OpenAI-compatible servers (LM Studio among them) omit `usage` from a stream UNLESS asked:
        # without this the probe printed "prompt 0 tok | completion 0 tok" next to a real TTFT, and
        # a rate with no token count is exactly the kind of number this repo refuses to record.
        body["stream_options"] = {"include_usage": True}
    t0 = time.time()
    ttft = None
    try:
        if a.ttft:
            import urllib.request as ur
            req = ur.Request(base + "/chat/completions", data=json.dumps(body).encode(),
                             headers={"Content-Type": "application/json",
                                      "Authorization": f"Bearer {tok}"})
            d = None
            for line in ur.urlopen(req, timeout=a.timeout):
                s = line.decode("utf-8", "replace").strip()
                if not s.startswith("data:"):
                    continue
                chunk = s[5:].strip()
                if chunk == "[DONE]":
                    break
                j = json.loads(chunk)
                if j.get("usage"):
                    d = j
                delta = ((j.get("choices") or [{}])[0].get("delta") or {})
                if ttft is None and (delta.get("content") or delta.get("reasoning_content")
                                     or delta.get("tool_calls")):
                    ttft = time.time() - t0
            if d is None:
                d = {"usage": {}}
        else:
            d = _post(base, "/chat/completions", body, tok, a.timeout)
    except urllib.error.HTTPError as e:
        print(f"speed probe: HTTP {e.code} (contract/server error, not a measurement): "
              f"{e.read().decode('utf-8','replace')[:120]}")
        return 3
    except Exception as e:
        print(f"speed probe failed: {type(e).__name__}: {e}")
        return 2
    dt = time.time() - t0
    u = d.get("usage", {}) or {}
    pt, ct = u.get("prompt_tokens", 0), u.get("completion_tokens", 0)
    if a.ttft and not pt:
        print(f"[{a.label or 'shape'}] prompt shape: {shape}")
        print(f"  wall {dt:.1f}s | TTFT {ttft if ttft is not None else float('nan'):.2f}s | "
              "NO usage in the stream — this is NOT a tok/s measurement. Record the TTFT only, or "
              "re-run without --ttft for the combined number.")
        return 0
    decode_wall = max(dt - (ttft or 0), 0.001)
    print(f"[{a.label or 'shape'}] prompt shape: {shape}")
    if a.ttft:
        # TTFT is everything before the first token, so on a COLD prompt prompt_tokens/TTFT is the
        # prefill rate. On a WARM one it is the prefix-cache hit rate instead - measured 2026-09-30:
        # 10 610 tokens answered in 0.63 s, which divides to 16 969 "t/s" and is not a prefill speed.
        # The label the operator passed (cold-* / warm-*) says which, and the print says it too,
        # because a number that silently changes meaning between two runs of one command is how a
        # 16 969 t/s figure ends up in a doc as though it were hardware.
        lab = (a.label or "").lower()
        kind = ("first-token on a WARM prompt = PREFIX-CACHE HIT, not prefill" if lab.startswith("warm")
                else "prefill (cold prompt)" if lab.startswith("cold")
                else "first-token rate (prefill only if this prompt was cold)")
        rate = ("%.0f t/s %s" % (pt/ttft, kind)) if (ttft and pt) else "first-token rate n/a"
        print(f"  wall {dt:.1f}s | TTFT {ttft if ttft is not None else float('nan'):.2f}s | "
              f"prompt {pt} tok | completion {ct} tok | decode {ct/decode_wall if ct else 0:.1f} t/s | {rate}")
    else:
        print(f"  wall {dt:.1f}s | prompt {pt} tok ({pt/dt if dt else 0:.0f} t/s combined) | "
              f"completion {ct} tok ({ct/dt if dt else 0:.1f} t/s)")
    print("  Record engine, template, thinking state and KV setting with this number — HD-469 run #2:")
    print("  a score without its configuration is not evidence.")
    return 0


def _vision_verdict(txt, expect):
    """(passed | None, why). Mechanical on purpose: `input: [image]` is a client-contract claim, so
    the verdict may not be "it said something nice about the picture". The reply must contain
    something ONLY the image can supply (--expect), and the classifier must reject the three ways a
    blind model fakes success: empty (thinking budget ate max_tokens - the false negative HD-474
    actually shipped with), a refusal, and a control-token leak."""
    if not txt or not txt.strip():
        return False, ("empty reply: either max_tokens was eaten by reasoning_content or the "
                       "projector never attached (a GGUF without its mmproj behaves exactly like "
                       "a text-only model)")
    low = txt.lower()
    for bad in ("i cannot see", "i can't see", "i do not see", "i don't see", "no image",
                "i am unable", "as an ai"):
        if bad in low:
            return False, f"the model did not look at the image ({bad!r})"
    for tok in ("<|", "image_url", "data:image"):
        if tok in low:
            return False, f"leaked control/markup token {tok!r}"
    if not expect:
        return None, "inconclusive: no --expect, so there is nothing ONLY the image could supply"
    missing = [e for e in expect if e.lower() not in low]
    if missing:
        return False, f"reply does not contain {missing} - only the image can supply it"
    return True, "reply contains " + ", ".join(repr(e) for e in expect)


def vision_self_test():
    """A test that cannot fail is not evidence (CONVENTIONS §6). One canary per failure shape, and
    one POSITIVE canary, because a detector that fails everything would also pass this exercise."""
    cases = [
        ("the label on the switch reads CRS328-24P-4S+RM", ("crs328",), True),
        ("", ("crs328",), False),
        ("I cannot see any image in this request.", ("crs328",), False),
        ("the label reads CRS320-24T-4S+RM", ("crs328",), False),
        ("<|image|> CRS328", ("crs328",), False),
        ("the label reads CRS328-24P-4S+RM", None, None),
    ]
    bad = 0
    print("vision verdict self-test (each line is a canary that MUST be caught):")
    for txt, exp, want in cases:
        got, why = _vision_verdict(txt, exp)
        ok = got is want
        print(f"  {('pass' if want else ('inconclusive' if want is None else 'fail')):<13} "
              f"{(txt or '<empty>')[:38]:<40} {'caught' if ok else 'MISSED (' + str(got) + ')'}")
        if not ok:
            print(f"    why={why}")
            bad += 1
    print(f"\nvision self-test: {len(cases)-bad}/{len(cases)} verdicts correct")
    return 1 if bad else 0


def cmd_probe_vision(cfg, a):
    """One real image, asked about concretely. `input: [text, image]` in the client contract is a
    LIE until this passes — and on a laptop that has never loaded a projector on this engine, "it
    has vision files" is not evidence (HD-401 gate 4: the mmproj must run on the iGPU, not CPU).

    REWRITTEN 2026-09-30 (HD-474). Three defects in the previous version, each of which produced a
    WRONG verdict on this box:
      * max_tokens was hardcoded to 80. This server cannot turn thinking off (chat_template_kwargs
        and enable_thinking are ignored - all four spellings tested), so on a reasoning model the
        whole budget goes to reasoning_content and `content` comes back EMPTY: a WORKING vision leg
        was reported as a failure. Budget is 1024 by default now, and msg_text() reads
        reasoning_content too.
      * it read msg['content'] only - the same class of bug cmd_probe_health already fixed.
      * it caught every exception as "the model is blind". A 4xx is a CONTRACT error and the
        {"error":"terminated"} 400 is the engine-crash signature (Gemma dies above ~1120 px long
        side, engine exit 3221226505) - three different things, and the gate may only be driven by
        the third."""
    if a.self_test:
        return vision_self_test()
    p = Path(a.image)
    if not p.exists():
        print(f"no image at {a.image} — pass one with --image (a screenshot of this repo's README works)")
        return 2
    mime = "image/png" if p.suffix.lower() in (".png",) else "image/jpeg"
    uri = f"data:{mime};base64,{base64.b64encode(p.read_bytes()).decode()}"
    payload = {"model": a.model, "max_tokens": a.max_tokens, "stream": False,
               "messages": [{"role": "user", "content": [
                   {"type": "text", "text": a.question},
                   {"type": "image_url", "image_url": {"url": uri}}]}]}
    print(f"image {p.name} ({p.stat().st_size/1e6:.1f} MB) -> model={a.model} "
          f"max_tokens={a.max_tokens}")
    import time
    t0 = time.time()
    try:
        d = _post(server_base(cfg), "/chat/completions", payload, a.token or "lmstudio", a.timeout)
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace")[:200]
        except Exception:
            pass
        print(f"vision probe: HTTP {e.code} after {time.time()-t0:.0f}s: {body}")
        low = body.lower()
        if "does not support image" in low or "not support image input" in low:
            print("  MODALITY VERDICT, and a useful one: the server itself refuses images for this")
            print("  load, because no projector is attached. That is the text-only leg behaving as")
            print("  the contract says - keep `image` out of that profile's input list. Measured")
            print("  2026-09-30 on a load with no projector attached: HTTP 400 in 0 s naming the")
            print("  served id and 'does not support image inputs' - the LOUD failure this contract")
            print("  was shaped to have.")
            return 1
        if "terminat" in body:
            print("  ENGINE CRASH signature. This is a real capability failure: this build dies on")
            print("  this image (measured: Gemma 4 exits 3221226505 above ~1120 px long side). Keep")
            print("  image input OFF the profile, or resize in the client before it leaves the box.")
            return 1
        print("  That is a CONTRACT/server error, not a verdict on the model's eyes. Do NOT set")
        print("  vision_probe: failed from it - fix the request shape and re-run.")
        return 3
    except Exception as e:
        print(f"vision probe FAILED to reach the server: {type(e).__name__}: {e}")
        print("  Server/engine problem, not a vision verdict. Check `lms daemon status` first - the")
        print("  service is llmster, not the GUI, and a missing tray icon means nothing.")
        return 2
    wall = time.time() - t0
    msg = (d.get("choices") or [{}])[0].get("message", {})
    txt, kind = msg_text(msg)
    u = d.get("usage", {}) or {}
    pt = u.get("prompt_tokens")
    print(f"reply [{kind}] after {wall:.1f}s: {txt[:300]!r}")
    print(f"usage: {json.dumps(u)}")
    if pt:
        print(f"  image cost: {pt} prompt_tokens in {wall:.1f}s = {pt/max(wall,0.001):.1f} t/s effective "
              "(prefill-dominated). Record this - HD-401 gate 4 is 'where did the tower run', and a")
        print("  CPU-side tower shows up here as tens of seconds per image.")
    passed, why = _vision_verdict(txt, a.expect)
    if passed is None:
        print(f"VERDICT inconclusive: {why}")
        print("  Re-run with --expect <string only the image contains> to make it a verdict.")
        return 2
    print(f"VERDICT {'PASS' if passed else 'FAIL'}: {why}")
    if passed:
        print("→ set vision_probe: passed on that profile, and record the LARGEST image that survived")
        print("  (this engine crashes on some sizes, so the client resize rule is part of the contract).")
        return 0
    print("→ keep `image` OUT of that profile's input list. The gate refuses the claim, and a client")
    print("  that advertises eyes it does not have fails silently instead of loudly.")
    return 1


def _renderer():
    """Load scripts/render-pi-config.py — the dash in its filename makes it non-importable by name,
    so it is loaded by path. ONE host matcher for both scripts, because two spellings of 'is this
    the machine' is exactly what made probe-client SKIP and the renderer DROP on the same box
    (2026-09-30: gethostname() is `Domen_P14s`, the spec row says `domenp14s`). A fallback copy here
    would be the same bug wearing a trench coat, so a failed import is fatal on purpose."""
    import importlib.util
    path = HERE / "render-pi-config.py"
    spec = importlib.util.spec_from_file_location("render_pi_config", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def cmd_probe_client(cfg, a):
    """Drift between what the engine serves and what the client is TOLD. pi's contextWindow /
    maxTokens / input come from scripts/pi-config/models-spec.yml; if that says more than the
    profile can serve, pi 400s mid-session. The cheap test that prevents the bad afternoon."""
    act = dig(cfg, "active")
    p = dig(cfg, f"profiles.{act}") or {}
    if not PI_SPEC.exists():
        print(f"client drift: SKIP — {PI_SPEC} not found")
        return 0
    spec = yaml.safe_load(PI_SPEC.read_text(encoding="utf-8"))
    # providers/models are LISTS keyed by `id` in that spec (a list keeps render order, which the
    # file declares to be part of the contract) — so look them up by id, never by mapping key.
    prov = next((x for x in (spec.get("providers") or []) if x.get("id") == a.provider), None)
    if not prov:
        print(f"client drift: FAIL — provider '{a.provider}' is not in {PI_SPEC.name} (yet). "
              "The renderer needs a `hosts:` row for it or the laptop renders without it.")
        return 1
    import socket
    if prov.get("hosts"):
        me = socket.gethostname()
        if not _renderer().host_matches(me, prov["hosts"]):
            print(f"client drift: SKIP — provider '{a.provider}' is scoped to hosts={prov['hosts']}, "
                  f"this host is {me!r} (compared as {_renderer().host_norm(me)!r} vs "
                  f"{[_renderer().host_norm(x) for x in prov['hosts']]})")
            print("  If this IS that machine, the spec's hosts: row is mis-spelled and the RENDERER")
            print("  drops the provider from the picker too — pi would never see it. Check "
                  '`python -c "import socket;print(socket.gethostname())"` on the seat and fix the')
            print("  spec. Do not 'fix' this by passing --host: that is how the mismatch was hidden.")
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
    # `reasoning` compares the client row against the PROFILE's thinking surface, not against the
    # spec row's own field: a row that says `reasoning: true` while the engine has no thinking
    # channel is the empty-`content` bug this repo already paid for, and comparing the row to itself
    # could never fail, so it proved nothing (CONVENTIONS §6: a check that cannot fail is not
    # evidence).
    want = {"contextWindow": p.get("client_context_window"), "maxTokens": p.get("client_max_tokens"),
            "input": p.get("input") or ["text"],
            "reasoning": (p.get("reasoning_surface") or "none") != "none"}
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
    # RESIDENCY. Not belt-and-braces: LM Studio's OpenAI endpoint does NOT police the `model`
    # field. Measured 2026-09-30 with only the vision leg loaded, a request naming
    # `no-such-model-here` was answered ('PONG') in 0.4 s BY THE RESIDENT MODEL. A row naming a leg
    # that is not loaded therefore does not 400 - it silently answers from the wrong model and the
    # harness never knows. Image requests ARE policed (400 'does not support image inputs'); text
    # is not, and nothing else in the stack catches it. So probe-client does.
    try:
        with urllib.request.urlopen(server_base(cfg).rstrip("/") + "/models", timeout=5) as r:
            served = [m.get("id") for m in json.loads(r.read().decode()).get("data", [])]
    except Exception as e:
        served = None
        print(f"  (residency not checked: {type(e).__name__} reading /v1/models)")
    if served and a.model not in served:
        print(f"client drift: FAIL — the client names '{a.model}' but the engine serves {served}.")
        print("  This server does NOT reject a wrong model id: it answers from whatever is resident,")
        print("  so pi would silently run the OTHER leg. Load it (lmstudio-llm.ps1 switch -Profile")
        print(f"  '{a.model}') or accept that the row is not live right now.")
        return 1
    print(f"client drift: PASS — {a.provider}/{a.model} matches profile '{act}' "
          f"(contextWindow={want['contextWindow']}, maxTokens={want['maxTokens']}, "
          f"input={want['input']}, reasoning={want['reasoning']})"
          + (f" — and the engine is serving it: {served}" if served else ""))
    return 0


def cmd_baseurl(cfg, _a):
    """The endpoint the clients must use, resolved exactly the way the probes resolve it. The
    Windows applier's Get-Api (called by `init`) already invoked `laptop-llm.py baseurl`, but the
    command existed only as the internal server_base() helper — so `init` threw AFTER writing
    settings.json and the presets, i.e. a half-applied init. Measured 2026-09-29 (HD-474)."""
    print(server_base(cfg))
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
        # servedId is the identifier the SERVER serves and the CLIENT must name. It is derived from
        # the profile name on purpose: models-spec.yml's row id has to equal what /v1/models lists,
        # and a hand-kept identifier is exactly the kind of second copy that drifts (probe-client
        # then 400s in the middle of someone's session). `lms load` needs `-y` and `-c`, and its
        # `--identifier` is what lands here.
        out[n] = {"label": p.get("label"), "identifier": ident, "servedId": n,
                  "parallel": p.get("parallel", 1),
                  "loadable": ":" not in ident,
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
        if ":" in ident:
            # `upstream:profile` is a FETCH hint from the catalogue, not a library key. `lms load`
            # would hang on the interactive picker without -y, or load the wrong thing with it.
            w = ("model %s is not in the library yet (identifier %r is a fetch hint). Fetch it "
                 "deliberately; the applier refuses to download 20 GB as a side effect of a switch."
                 % (p["model"], ident))
            out[n]["_warning"] = (out[n].get("_warning", "") + " " + w).strip()
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
            # 1024, not 128: on a reasoning model whose thinking cannot be switched off server-side,
            # a small budget is spent entirely on reasoning_content and the probe measures thinking.
            s.add_argument("--max-tokens", type=int, default=1024); s.add_argument("--prompt")
            s.add_argument("--prompt-file", help="real prose as the prompt shape (never a 'xxxx' run)")
            s.add_argument("--label", help="name of this shape in the record (e.g. cold-8k)")
            s.add_argument("--ttft", action="store_true",
                           help="stream and time the first token: separates prefill from decode")
        if name == "probe-vision":
            s.add_argument("--image", required=True)
            s.add_argument("--expect", action="append",
                           help="string ONLY the image can supply; repeatable. Without it the "
                                "probe is a description, not a verdict")
            s.add_argument("--question", default="Read any text, model number or label visible in "
                                                "this photo, exactly as printed.")
            s.add_argument("--max-tokens", type=int, default=1024,
                           help="budget for the REPLY; >=1024 on a reasoning model or thinking eats it")
            s.add_argument("--self-test", action="store_true",
                           help="check the verdict classifier against known wrong answers")
        if name == "probe-fim":
            # No default here on purpose: the FIM leg is resolved inside the probe from its
            # `insert` capability, because the ACTIVE profile is a generation leg and would be the
            # wrong model to put a cursor gap in front of.
            s.add_argument("--profile", default=None)
            s.add_argument("--self-test", action="store_true",
                           help="breed wrong verdicts and refuse any detector that passes them")
            s.add_argument("--prompt-tmpl", default=None,
                           help="prompt shape; {prefix} and {suffix} are substituted. Default is the "
                                "raw cursor gap; pass the chat-template FIM form to test that surface.")
        s.set_defaults(fn=fn)

    c = sub.add_parser("probe-client")
    cli = dig(load(), "client", {}) or {}
    c.add_argument("--provider", default=cli.get("pi_provider", "laptop-lmstudio"))
    c.add_argument("--model", default=cli.get("pi_model", "local"))
    c.set_defaults(fn=cmd_probe_client)
    sub.add_parser("baseurl").set_defaults(fn=cmd_baseurl)
    sub.add_parser("presets").set_defaults(fn=cmd_presets)
    sub.add_parser("settings").set_defaults(fn=cmd_settings)
    ap.add_argument("--json", action="store_true")

    a = ap.parse_args()
    cfg = load(a.spec)
    if a.cmd.startswith("probe-") and not getattr(a, "model", None) and a.cmd not in ("probe-client",
                                                                                       "probe-fim"):
        # The engine's identifier comes from the catalogue + `lms ls`, never from this script.
        # probe-fim is excluded: it resolves its own leg, because the active profile is not the
        # FIM model.
        p = dig(cfg, f"profiles.{dig(cfg,'active')}") or {}
        a.model = a_ident(cfg, p)
    sys.exit(a.fn(cfg, a) or 0)


if __name__ == "__main__":
    main()
