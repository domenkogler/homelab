#!/usr/bin/env python3
"""
spark-llm-probe.py — converge a Spark LLM PROFILE into EVIDENCE (HD-469).

One command per gate, run AFTER a profile converge, against whatever profile is
live. Nothing here writes to the box; every probe is an HTTP call to the OpenAI
endpoint the clients use, so it tests the real path (edge → engine), not the
container in isolation.

  Endpoint SSOT: --base-url is required (the legs differ on purpose):
    https://llm.ts.kogler.si/v1     tailnet → spark edge → ENGINE --api-key (auth = this bearer)
    http://localhost:8000/v1        on-box only (ssh spark)
  Key SSOT: 1Password item `spark-llm_api`, field `credential` — read via the op
    CLI at runtime. NEVER put the bearer in argv, a file, or the transcript: it is
    read into memory and only its LENGTH is ever printed (scripts/rotate-spark-llm-key.sh
    uses the same item; docs/deployment-ai-stack-secrets.md §4a owns the consumer list).
  Engine SSOT: context length + concurrency expectations are read from
    IaC/ansible/group_vars/spark.yml `spark_llm_profiles[<profile>]` — a probe can
    never pass against a stale number the operator typed.

Usage (each subcommand prints PASS/FAIL + the measured number):
  scripts/spark-llm-probe.py --base-url … matrix              # ALL profiles, local, no token
  scripts/spark-llm-probe.py --base-url … profile reasoning    # one profile, local, no token
  scripts/spark-llm-probe.py --base-url https://llm.ts.kogler.si/v1 health
  scripts/spark-llm-probe.py --base-url … reasoning            # binary on/off
  scripts/spark-llm-probe.py --base-url … budget 2048          # thinking_token_budget
  scripts/spark-llm-probe.py --base-url … effort high          # native reasoning_effort (UNPROVEN)
  scripts/spark-llm-probe.py --base-url … ctx 131072           # real depth, ~6 tokens/word
  scripts/spark-llm-probe.py --base-url … concurrent 4 --max-tokens 64
  scripts/spark-llm-probe.py --base-url … all --profile reasoning

`matrix` and `profile` are the LOCAL legs: they touch the repo only — no HTTP, no
1Password, no token, so lane-brief step 0 needs no dummy `--token-env`.

Exit: 0 all probes passed, 1 any failure, 2 usage/env. Additive-only: unknown
subcommand is a usage error, never a silent no-op.
"""
import argparse
import json
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPARK_VARS = ROOT / "IaC" / "ansible" / "group_vars" / "spark.yml"
HOST_VARS = ROOT / "IaC" / "ansible" / "host_vars" / "spark.kogler.si.yml"
VAULT_ITEM = "spark-llm_api"
VAULT_VAULT = "Homelab-ansible"
# ~6 English tokens/word for Qwen-style BPE (docs/pi-harness.md §3 uses 1.38 chars/token
# for the request body; the filler below is repetitive so real-token math is safer).
TOKENS_PER_WORD = 6
WORD = ("The quick brown fox jumps over the lazy dog while the historian records "
        "each leap in a ledger of small orange notebooks. ")


def die(msg, code=2):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def read_key():
    """Bearer from 1Password. Returns (key, note). Never printed."""
    try:
        out = subprocess.run(
            ["op", "read", f"op://{VAULT_VAULT}/{VAULT_ITEM}/credential"],
            capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
    except FileNotFoundError:
        die("op CLI not found — install 1Password CLI or pass --token-env NAME")
    if out.returncode != 0 or not out.stdout.strip():
        die(f"cannot read op://{VAULT_VAULT}/{VAULT_ITEM}/credential "
            f"({(out.stderr or '').strip()[:120] or 'empty'}) — see docs/1password.md §1")
    return out.stdout.strip()


def servable(profiles):
    """The servable subset of the catalogue: HD-489 keys beginning with `_` are YAML merge
    anchors of shared defaults, not profiles. Selecting one would probe a config that was
    never meant to boot, and listing them in the matrix would hide the real rows."""
    return {k: v for k, v in (profiles or {}).items() if not k.startswith("_")}


def profile_spec(name):
    """Engine expectations straight from the IaC SSOT (no operator-typed numbers)."""
    profiles = servable(catalogue().get("spark_llm_profiles"))
    if name not in profiles:
        die(f"profile '{name}' not in {SPARK_VARS.relative_to(ROOT)} "
            f"(valid: {', '.join(sorted(profiles))})")
    return profiles[name]


def catalogue():
    """The whole profile section of group_vars/spark.yml — the SSOT for every number a
    probe or a report may quote. Fail-loud: a missing key is an error, never a default
    (CONVENTIONS §2/§7; the fp8 bytes/token constant was hardcoded HERE once and was
    wrong by ~18 % for exactly the reason this function exists)."""
    import yaml
    data = yaml.safe_load(SPARK_VARS.read_text(encoding="utf-8")) or {}
    for key in ("spark_llm_profiles", "spark_llm_kv_bytes_per_token",
                "spark_llm_pool_ceiling_bytes", "spark_llm_device_hold_ceiling_bytes"):
        if key not in data:
            die(f"{key} is missing from {SPARK_VARS.relative_to(ROOT)} — refusing to guess it")
    return data


def active_profile(cat):
    """Which profile host_vars would converge RIGHT NOW (the dial lives there; the
    group_vars value is only the fallback). Used by `matrix` to mark the live row."""
    import yaml
    if HOST_VARS.is_file():
        host = yaml.safe_load(HOST_VARS.read_text(encoding="utf-8")) or {}
        if host.get("spark_llm_profile"):
            return host["spark_llm_profile"]
    return cat.get("spark_llm_profile", "(unset)")


def kv_slots(spec, cat):
    """(bytes/token, slots, ok_flags) for one profile. A PROJECTION, always printed as
    one: the authoritative number is the engine's own `Available KV cache memory` /
    `GPU KV cache size` boot-log pair (prompt-llm.md §0.2)."""
    per_tok = cat["spark_llm_kv_bytes_per_token"]
    dtype = spec["kv_cache_dtype"]
    pool = int(spec["kv_cache_memory"])
    window = int(spec["max_model_len"])
    if dtype not in per_tok:
        die(f"kv_cache_dtype '{dtype}' has no bytes/token constant "
            f"(known: {', '.join(sorted(per_tok))})")
    bpt = int(per_tok[dtype])
    slots = pool // bpt if pool else 0
    fc = spec.get("fixed_cost_bytes")
    hold = (int(fc) + pool) if fc else None
    checks = {
        "pool≥window": slots >= window or pool == 0,
        # Per-profile ceiling wins when the profile declares one (`fast`'s 20 GB / 112.7e9
        # measured exception); the certified global still binds every profile that stays quiet
        # about it. Read from `spec` — the resolved profile dict. A 2026-10-03 refactor made
        # these constants per-profile and this line kept naming a `profile` variable that is not
        # in scope: `profile <name>` died with a NameError, while check_spark_llm_gate.py stayed
        # green because it re-derives the same math independently. That divergence IS the point —
        # a probe that cannot run proves nothing, and its own gate could not see it.
        "pool≤ceiling": pool <= int(spec.get("pool_ceiling_bytes") or cat["spark_llm_pool_ceiling_bytes"]),
        "host-floor": (hold is None and pool == 0) or (hold is not None
                        and hold <= int(spec.get("device_hold_ceiling_bytes") or cat["spark_llm_device_hold_ceiling_bytes"])),
    }
    return bpt, slots, hold, checks


def print_profile_rows(specs, cat, active=None):
    """The offline matrix: catalogue → slots → host floor, for every profile at once."""
    for name, spec in specs.items():
        engine = spec.get("engine", "?")
        mark = "  ← ACTIVE (spark_llm_profile)" if name == active else ""
        print(f"\n  {name}{mark}")
        print(f"    label          = {spec.get('label')}")
        print(f"    engine / model = {engine} / {spec.get('model_subdir')}"
              f"  [image {spec.get('image', spec.get('engine'))}]")
        print(f"    ctx / seqs     = {spec.get('max_model_len')} / {spec.get('max_num_seqs')}")
        print(f"    reasoning      = {spec.get('reasoning_surface')}")
        print(f"    client ctx     = {spec.get('client_context_window')} "
              f"(scripts/pi-config/models-spec.yml must carry this)")
        print(f"    certified      = {bool(spec.get('certified'))}"
              + ("" if spec.get("certified") else f"  ← reason: {str(spec.get('uncertified_reason','')).strip()[:110]}…"))
        if engine != "vllm":
            frac = "·"
            args = spec.get("args_extra") or []
            for i, a in enumerate(args):
                if str(a).startswith("--mem-fraction-static") and i + 1 < len(args):
                    frac = args[i + 1]
            print(f"    pool           = sglang-sized (--mem-fraction-static {frac}); "
                  f"read the startup log, not a projection")
            continue
        bpt, slots, hold, checks = kv_slots(spec, cat)
        verdict = " ".join(f"{k}={'OK' if v else 'BREACH'}" for k, v in checks.items())
        print(f"    KV             = {spec['kv_cache_dtype']}, {int(spec['kv_cache_memory']):,} B "
              f"@ {bpt:,} B/token = {slots:,} slots = {slots / int(spec['max_model_len']):.2f} × window")
        print(f"    device hold    = fixed {spec.get('fixed_cost_bytes', '(none)')} + pool = "
              f"{hold:,} B" if hold else "    device hold    = (fixed_cost_bytes undeclared)")
        print(f"    gate mirror    = {verdict}   (authoritative: scripts/check_spark_llm_gate.py)")


class Endpoint:
    def __init__(self, base_url, key, timeout):
        self.base = base_url.rstrip("/")
        # /health is NOT under /v1 — derive the origin once instead of hoping the
        # server normalises "/v1/../health".
        self.origin = self.base[:-3].rstrip("/") if self.base.endswith("/v1") else self.base
        self.key = key
        self.timeout = timeout

    def post(self, path, payload):
        req = urllib.request.Request(
            f"{self.base}/{path.lstrip('/')}",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json",
                     "Authorization": f"Bearer {self.key}"},
            method="POST")
        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                return json.loads(r.read().decode()), time.time() - t0, r.status
        except urllib.error.HTTPError as e:
            return {"_error": e.read().decode()[:300]}, time.time() - t0, e.code

    def get(self, path, absolute=False):
        url = (self.origin if absolute else self.base) + "/" + path.lstrip("/")
        req = urllib.request.Request(
            url, headers={"Authorization": f"Bearer {self.key}"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                raw = r.read().decode(errors="replace")
                try:
                    return json.loads(raw), r.status
                except json.JSONDecodeError:
                    # /health on this vLLM build is 200 with an EMPTY body;
                    # return the raw text so the caller can judge, never crash.
                    return raw, r.status
        except urllib.error.HTTPError as e:
            return {"_error": e.read().decode()[:200]}, e.code

    def chat(self, messages, extra=None, max_tokens=48, timeout=None):
        payload = {"model": self.model, "max_tokens": max_tokens,
                   "messages": messages, "temperature": 0}
        if extra:
            payload.update(extra)
        saved = self.timeout
        if timeout:
            self.timeout = timeout
        try:
            return self.post("chat/completions", payload)
        finally:
            self.timeout = saved

    def usage_tokens(self, resp):
        u = resp.get("usage") or {}
        return u.get("prompt_tokens"), u.get("completion_tokens")

    def resolve_model(self):
        d, code = self.get("models")
        if code != 200:
            die(f"/models → HTTP {code}: {d.get('_error', '')}")
        ids = [m.get("id") for m in d.get("data", [])]
        print(f"  models: {ids}")
        if len(ids) != 1:
            print("  ⚠ expected exactly ONE served id (HD-370 single-model contract)")
        self.model = ids[0]


def reasoning_text(resp):
    ch = (resp.get("choices") or [{}])[0]
    msg = ch.get("message") or {}
    # This build names the thinking output `reasoning` (Qwen3-style), not
    # `reasoning_content` (the legacy field). Read both so the probe works on
    # either build; measured on 2026-09-28 (HD-469 cert): enable_thinking=true
    # → message.reasoning populated, reasoning_content null. If a future build
    # flips the field, BOTH are read and the non-empty one wins.
    return (msg.get("reasoning") or msg.get("reasoning_content") or ""), (msg.get("content") or "")


def verdict(name, ok, detail):
    print(f"  {'PASS' if ok else 'FAIL'}  {name}: {detail}")
    return ok


class Probes:
    def __init__(self, ep):
        self.ep = ep
        self.results = []

    def record(self, name, ok, detail):
        self.results.append(verdict(name, ok, detail))

    def health(self):
        d, code = self.ep.get("health", absolute=True)
        # vLLM answers /health with HTTP 200 and an EMPTY body (measured on
        # this fork, 2026-09-28); do not json.loads an empty body.
        ok = code == 200
        self.record("health", ok, f"HTTP {code} body={str(d)[:60]!r}")

    def binary_reasoning(self):
        q = [{"role": "user", "content": "A snail climbs 3 ft/day and slips 2 ft/night from a 30 ft well. How many days? Reason carefully, then answer with the number."}]
        off, _, c1 = self.ep.chat(q, {"chat_template_kwargs": {"enable_thinking": False}})
        on, _, c2 = self.ep.chat(q, {"chat_template_kwargs": {"enable_thinking": True}})
        ro, co = reasoning_text(off)
        rn, cn = reasoning_text(on)
        self.record("auth+completion", c1 == 200 and c2 == 200, f"off={c1} on={c2}")
        self.record("thinking OFF emits no reasoning", not ro,
                    f"reasoning_len={len(ro)} content_len={len(co)}")
        self.record("thinking ON emits reasoning", bool(rn),
                    f"reasoning_len={len(rn)} content_len={len(cn)}")

    def budget(self, budget):
        q = [{"role": "user", "content": "Plan a 5-day Kyoto itinerary with reasoning about transit. Then give the plan."}]
        r, _, code = self.ep.chat(q, {
            "chat_template_kwargs": {"enable_thinking": True, "preserve_thinking": True},
            "thinking_token_budget": budget}, max_tokens=max(600, budget))
        rt, _ = reasoning_text(r)
        pt, ct = self.ep.usage_tokens(r)
        # The budget is a CAP on emitted thinking; allow tokenizer slack, fail on >2×.
        self.record(f"budget {budget}", code == 200 and (not rt or len(rt) < budget * 4 * 2),
                    f"http={code} reasoning_chars={len(rt)} prompt={pt} completion={ct}")

    def effort(self, level):
        """NATIVE graded effort. Expected to FAIL on the certified vLLM build —
        that failure is the measurement that keeps supportsReasoningEffort: false
        honest (docs/pi-harness.md §2)."""
        q = [{"role": "user", "content": "Which is faster: radix sort or comparison sort? Explain."}]
        a, t1, ca = self.ep.chat(q, {"reasoning_effort": "low"})
        b, t2, cb = self.ep.chat(q, {"reasoning_effort": "high"})
        ra, _ = reasoning_text(a)
        rb, _ = reasoning_text(b)
        same = len(ra) == len(rb) and ra == rb
        self.record(f"effort {level} honored?", not same,
                    f"http={ca}/{cb} reasoning {len(ra)}→{len(rb)} chars, "
                    f"identical={same} (identical ⇒ engine IGNORES reasoning_effort)")

    def ctx(self, target, max_tokens=24):
        # Size by MEASURED bytes/token, not the 6-words/token guess: the repetitive
        # filler above tokenizes denser than prose (measured 2026-09-28:
        # 12209 body chars → 2352 tokens = 5.19 chars/token), and an over-sized
        # prompt would trip the engine's max_model_len boot-gate with a 400 — an
        # honest gate, but a probe that cannot reach its own target. Build the
        # prompt to a REAL depth of ≥ 0.90 × target token-slots minus a safety
        # margin, then assert against 0.8 × target (gate 3 in
        # spark/llm-profiles/README.md: "prompt_tokens ≥ 80 % of the ask").
        body_chars_per_tok = 5.2       # measured for WORD (12209 chars → 2352 tok)
        room = target * 0.90            # stay under max_model_len even at target=262144
        chars = int(room * body_chars_per_tok * 0.9)  # ×0.9 belts-and-braces
        unit = (WORD + f"{target} ")
        filler = unit * max(1, chars // len(unit))
        q = [{"role": "user", "content": f"Read this, then say only OK. {filler}\n"
                                         f"NEEDLE: the code word is ORANGE-LEDGER-7741. Say OK."}]
        r, dt, code = self.ep.chat(q, None, max_tokens=max_tokens, timeout=max(900, target // 20))
        pt, ct = self.ep.usage_tokens(r)
        body_mb = len(json.dumps(q)) / 1e6
        self.record(f"ctx {target}", code == 200 and (pt or 0) >= target * 0.8,
                    f"http={code} prompt={pt} (asked≈{target}, body {body_mb:.1f} MB) "
                    f"completion={ct} {dt:.1f}s {r.get('_error', '')[:120]}")

    def concurrent(self, n, max_tokens):
        q = [{"role": "user", "content": "Reply with exactly one short sentence about the number 7."}]
        threads = []
        import threading
        out = []

        def worker():
            _, dt, code = self.ep.chat(q, None, max_tokens=max_tokens)
            out.append((code, dt))
        t0 = time.time()
        for _ in range(n):
            th = threading.Thread(target=worker)
            th.start()
            threads.append(th)
        for th in threads:
            th.join()
        wall = time.time() - t0
        codes = [c for c, _ in out]
        lats = sorted(d for _, d in out)
        self.record(f"concurrency {n}", codes.count(200) == n and wall < max(60, 40 * n),
                    f"200s={codes.count(200)}/{n} wall={wall:.1f}s "
                    f"lat min/med/max={lats[0]:.1f}/{statistics.median(lats):.1f}/{lats[-1]:.1f}s")

    def summary(self):
        bad = self.results.count(False)
        total = len(self.results)
        print(f"\n{total - bad}/{total} probes passed")
        return 0 if bad == 0 else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base-url", default=None,
                    help="e.g. https://llm.ts.kogler.si/v1 (required for every HTTP leg; "
                         "not needed by the local legs `matrix` and `profile`)")
    ap.add_argument("--token-env", default=None, help="env var holding the bearer (default: read 1Password)")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--profile", default=None, help="expected profile (checks ctx/seqs against IaC)")
    ap.add_argument("--max-tokens", type=int, default=64)
    ap.add_argument("cmd", nargs="?", default="all",
                    choices=["all", "health", "profile", "matrix", "reasoning", "budget",
                             "effort", "ctx", "concurrent"])
    ap.add_argument("arg", nargs="?", default=None)
    a = ap.parse_args()

    # LOCAL legs read only the repo: no bearer, no 1Password, no network. (Step 0 of the
    # lane brief runs these before anything is up on the box, and a probe that needs the
    # vault to print a catalogue is a probe the operator has to fake a token for.)
    local_only = a.cmd in ("profile", "matrix")
    key = None
    if local_only:
        print(f"local leg ({a.cmd}) — repo only, no bearer read, no HTTP")
    else:
        if not a.base_url:
            die("--base-url is required for the HTTP legs (…/v1 on the tailnet, "
                "http://localhost:8000/v1 on the box)")
        if a.token_env:
            import os
            key = os.environ.get(a.token_env, "").strip()
            if not key:
                die(f"--token-env {a.token_env} is empty")
        else:
            key = read_key()
        print(f"endpoint {a.base_url}  bearer len={len(key)} (value not printed)")
    ep = Endpoint(a.base_url, key, a.timeout) if not local_only else None   # local legs never touch it

    if a.cmd == "matrix":
        # Pure-local: every profile, every invariant, one screen. This is the command the
        # operator runs BEFORE picking a profile; the authoritative version of the checks
        # is scripts/check_spark_llm_gate.py (wired into validate-all.sh).
        cat = catalogue()
        print_profile_rows(servable(cat["spark_llm_profiles"]), cat,
                           active=active_profile(cat))
        return 0

    if a.cmd == "profile":
        # Pure-local: no HTTP at all, so it works before the engine is even up.
        name = a.arg or die("profile <name> required")
        cat = catalogue()
        spec = profile_spec(name)
        for k in ("engine", "max_model_len", "max_num_seqs", "kv_cache_dtype",
                  "kv_cache_memory", "fixed_cost_bytes", "certified",
                  "client_context_window", "reasoning_surface"):
            print(f"  {k:22s}= {spec.get(k)}")
        bpt, slots, hold, checks = kv_slots(spec, cat)
        print(f"  {'bytes/token':22s}= {bpt:,} (from spark_llm_kv_bytes_per_token — not hardcoded)")
        print(f"  {'kv slots':22s}= {slots:,} ({slots / spec['max_model_len']:.2f} × full window)")
        if hold is not None:
            # Same per-profile-then-global resolution the role asserts (tasks/main.yml:235);
            # printing the global here showed 104.113e9 against a 112.7e9 that was actually
            # gating — a row that reads as a BREACH while the check says OK.
            hold_ceil = int(spec.get("device_hold_ceiling_bytes")
                            or cat["spark_llm_device_hold_ceiling_bytes"])
            print(f"  {'device hold':22s}= {hold:,} B vs ceiling {hold_ceil:,} B"
                  f"{'  (per-profile)' if spec.get('device_hold_ceiling_bytes') else '  (global)'}")
        for k, v in checks.items():
            print(f"  {'gate mirror ' + k:22s}= {'OK' if v else 'BREACH'}")
        print("  NOTE: slots is a PROJECTION. The number of record is the engine's own")
        print("        'Available KV cache memory' + 'GPU KV cache size' boot-log pair.")
        return 0

    # Completion probes need a served model id; resolve it once, here.
    ep.resolve_model()
    p = Probes(ep)
    if a.cmd in ("all", "health"):
        p.health()
    if a.cmd in ("all", "reasoning"):
        p.binary_reasoning()
    if a.cmd == "budget":
        p.budget(int(a.arg or die("budget <tokens> required")))
    if a.cmd == "effort":
        p.effort(a.arg or "high")
    if a.cmd == "ctx":
        p.ctx(int(a.arg or die("ctx <tokens> required")))
    if a.cmd == "concurrent":
        p.concurrent(int(a.arg or die("concurrent <n> required")), a.max_tokens)
    if a.cmd == "all":
        spec = profile_spec(a.profile or die("all --profile <name> required"))
        p.ctx(int(spec["max_model_len"]))
        p.concurrent(int(spec["max_num_seqs"]), a.max_tokens)
    return p.summary()


if __name__ == "__main__":
    sys.exit(main())
