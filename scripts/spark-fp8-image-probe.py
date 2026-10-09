#!/usr/bin/env python3
"""
spark-fp8-image-probe.py — decide whether fp8 main KV is REACHABLE, without booting
anything (HD-469 run #2, step 2 of the spark lane brief `prompt-spark-llm.md`).

WHY. The `graded` profile dies at EngineCore init on the pinned image with
`NotImplementedError: QSA requires a BF16 main KV cache` (qsa.py:187). That line is a
dtype guard in the BUILD, not a property of the model: fp8 main KV on the QSA path
merged upstream as vllm#55557 on 2026-09-16, and the pin here is a day-0 build. The
way to settle "does the image we could pin actually carry it" is TWO READ-ONLY PROBES
that cost seconds and no GPU — not a 20-minute engine boot, and not a converge at all
(`prompt-spark-llm.md`: "read-only beats reboot-first").

Leg A (--skip-box, runs anywhere with egress): what does the tag point at NOW — digest,
push date, and which ARCHITECTURES. CONVENTIONS §7 requires a registry-verified arm64
manifest before any pin, and `versions.yml` claims a multi-arch manifest for a digest
that Docker Hub renders next to an amd64 entry. Nobody has verified it. Nothing here is
"verified" until this leg has printed it.

Leg B (--skip-registry, on the box, read-only): does the image's OWN source carry the
fp8 read path? `docker run --rm --entrypoint sh <pin> -c grep …` — never `--gpus`,
never `-p`, never `-d`, and it REFUSES to start while an ansible-playbook is running
locally or on the box (a half-applied converge on this host is measured, not
theoretical). The image is already on the box, so this pulls nothing.

Verdicts are exits, not vibes:
  0  decided — prints REACHABLE (grep found the fp8 QSA read path in the pin) or
             BLOCKED-ON-IMAGE (= the HD-473 engine-pin lane, not a config flip)
  1  undecided — one leg could not run; the lane brief says an inconclusive probe is
                 NOT a verdict, so go get the missing leg rather than the box
  2  usage / refused (converge in flight)

Stdlib only. No jq, no curl, no vault, no secrets: the registry token is anonymous
`pull` scope and is never printed.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSIONS = ROOT / "IaC" / "ansible" / "group_vars" / "all" / "versions.yml"
NS_REPO = "vllm/vllm-openai"
# What the fp8 read path looks like in the image's own source. Three independent marks:
# the dtype declaration, the fp8 branch, and the guard that killed us. Any hit on the
# first two WITHOUT the third == the build carries it.
FP8_MARKS = ["supported_kv_cache_dtypes", "IS_FP8", "BF16 main KV", "fp8_e4m3", "kv_quant_mode"]
UA = "homelab-spark-llm-probe/1.0 (+scripts/spark-fp8-image-probe.py)"


def die(msg, code=2):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def sh(argv, timeout=120, stdin_null=True):
    """Run argv, capture. Never shell=True: no quoting surprises, no secret expansion."""
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL if stdin_null else None)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except FileNotFoundError:
        return 127, "", f"{argv[0]} not found"
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s"


def get_json(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": UA,
                                               "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode()), None
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code} {e.reason}"
    except Exception as e:  # DNS/proxy/TLS — say what, do not guess (the run #1 lesson)
        return None, f"{type(e).__name__}: {e}"


def pinned_image():
    """The pin from versions.yml — never a copy of it (CONVENTIONS §2: one file)."""
    if not VERSIONS.is_file():
        die(f"{VERSIONS.relative_to(ROOT)} not found")
    for line in VERSIONS.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^spark_vllm_image:\s*\"?([^\"']+)", line)
        if m:
            return m.group(1).strip()
    die("spark_vllm_image not found in versions.yml")


def converge_running(ssh_host=None):
    """A converge in flight on EITHER side. Cheap, and the only way to know.
    The `[a]` bracket is not decoration: a plain pattern in a remote `bash -c` matches
    ITS OWN command line, and a self-match would refuse the probe forever (measured)."""
    rc, out, _ = sh(["pgrep", "-af", "[a]nsible-playbook"])
    if rc == 0 and out:
        return f"local: {out.splitlines()[0][:120]}"
    if ssh_host:
        rc, out, _ = sh(["ssh", "-o", "ConnectTimeout=8", ssh_host,
                         "pgrep -af '[a]nsible-playbook' || true"])
        if rc == 0 and out.strip():
            return f"{ssh_host}: {out.splitlines()[0][:120]}"
    return None


def leg_registry(tags, digest_ref, tag_filter=None, pages=4):
    print("\n── Leg A · registry (read-only, anonymous) ─────────────────────────────")
    undecided = 0
    print(f"pinned image (versions.yml): {digest_ref}")
    # ref form:  vllm/vllm-openai:<tag>@sha256:<hex>
    m = re.match(r"^(.+?):([^@]+)@sha256:([0-9a-f]{64})$", digest_ref)
    if m:
        print(f"  pin parses as repo={m.group(1)} tag={m.group(2)} digest=sha256:{m.group(3)[:12]}…")
    else:
        print("  ⚠ pin does not parse as repo:tag@sha256:… — record that as a finding")
    if tag_filter:
        # Is there ANY newer build we could pin? Asking the tag list is the only honest
        # answer to "does a pinnable digest carry the fp8 read path" — a rebuild under the
        # SAME tag name is exactly what CONVENTIONS §7 forbids us to assume.
        rx = re.compile(tag_filter, re.I)
        seen, page = {}, 1
        while page <= pages:
            data, err = get_json(f"https://hub.docker.com/v2/repositories/{NS_REPO}/tags"
                                 f"?page_size=100&page={page}&ordering=last_updated")
            if err:
                print(f"  tag list page {page}: {err}")
                undecided += 1
                break
            results = data.get("results") or []
            for t in results:
                if rx.search(t.get("name", "")):
                    seen[t["name"]] = t
            if not data.get("next"):
                break
            page += 1
        newest = sorted(seen.items(), key=lambda kv: kv[1].get("last_updated", ""), reverse=True)[:12]
        print(f"  tags matching /{tag_filter}/ in the first {page} page(s): {len(seen)}, newest:")
        for name, t in newest:
            arches = ", ".join(sorted({i.get("architecture", "?") for i in (t.get("images") or [])}))
            print(f"    {t.get('last_updated', '?')}  {name:44s} "
                  f"{(t.get('digest') or '?')[:19]}…  [{arches}]")
    for tag in tags:
        data, err = get_json(f"https://hub.docker.com/v2/repositories/{NS_REPO}/tags/{tag}?page_size=1")
        if err:
            print(f"  {tag}: hub API {err}  ← egress or the tag; UNDECIDED, not 'no arch'")
            undecided += 1
            continue
        imgs = data.get("images") or []
        arches = ", ".join(sorted({i.get("architecture", "?") for i in imgs})) or "(none listed)"
        ours = (data.get("digest") or "").endswith(re.sub(r"^.*@sha256:", "", digest_ref))
        print(f"  {tag}: last_updated={data.get('last_updated', '?')} full_digest="
              f"{(data.get('digest') or '?')[:19]}… architectures=[{arches}] "
              f"({len(imgs)} entries){'  ← IS our pin' if ours else ''}")
        for i in imgs:
            print(f"      · {i.get('architecture')}/{i.get('os')} "
                  f"{str(i.get('digest'))[:19]}… size={i.get('size')}")
    return undecided


def sh_quote(s):
    """POSIX single-quote escaping.
    ssh joins its argv with SPACES and the remote shell re-parses the result — an argv
    element that is itself a shell script is therefore passed UNQUOTED unless we quote it
    here. Measured: without this the container ran, `$P` expanded to empty on the remote
    side, and the probe reported "no fp8 path" off an empty grep (the exact class of
    false negative that a verdict script must not produce)."""
    return "'" + s.replace("'", "'\\''") + "'"


def leg_box(ssh_host, image):
    print("\n── Leg B · the image's own source (no GPU, no writes, NO PULL) ─────────")
    base = ["ssh", "-o", "ConnectTimeout=10", ssh_host]
    rc, out, err = sh(base + ["docker", "image", "inspect", image,
                              "--format", "{{.Architecture}}/{{.Os}}"], timeout=60)
    if rc != 0:
        # NEVER let this probe cause a pull: the ref is ~10 GB compressed and a surprise
        # pull on this link is an hour of someone's window. Resolve the pinned DIGEST to a
        # local image ID and run THAT; if it is not on the box, stop and say so.
        m = re.search(r"sha256:([0-9a-f]{12})", image)
        short = m.group(1) if m else None
        rc2, out2, _ = sh(base + ["docker", "images", "--no-trunc", "--format",
                                 "{{.ID}} {{.Repository}}:{{.Tag}}"], timeout=60)
        hit = next((ln for ln in (out2 or "").splitlines() if short and ln.startswith("sha256:" + short)),
                   None) if short else None
        if not hit:
            print(f"  image inspect FAILED rc={rc}: {(err or out)[:160]}")
            print("  and the pinned digest is NOT in the local image store — REFUSING to pull "
                  "(~10 GB over a 1 G link). Resolve it another way: `docker images --digests` "
                  "on the box, or record the dtype question as OPEN.")
            return None
        image = hit.split()[0]
        print(f"  ref not resolvable by name; running the LOCAL copy by ID instead (no pull): {image[:19]}…")
        rc, out, err = sh(base + ["docker", "image", "inspect", image,
                                  "--format", "{{.Architecture}}/{{.Os}}"], timeout=60)
        if rc != 0:
            print(f"  image inspect FAILED rc={rc}: {(err or out)[:160]}")
            return None
    print(f"  what this box actually runs for that ref: {out}   "
          f"(versions.yml claims multi-arch; THIS is what spark executes)")
    inner = ('P=$(python3 -c "import vllm,os;print(os.path.dirname(vllm.__file__))"); '
             'echo VLLM_DIR=$P; '
             'python3 -c "import vllm;print(\'VLLM_VERSION=\'+vllm.__version__)" 2>/dev/null '
             '|| echo "VLLM_VERSION=<import failed>"; '
             'F=$(ls $P/models/q*/nvidia/qsa.py 2>/dev/null); '
             'echo QSA_FILES=$F; '
             'test -n "$F" || { echo QSA_SEARCH:; ls -d $P/models/*/ 2>/dev/null | head -20; }; '
             'grep -nE "' + "|".join(FP8_MARKS) + '" $F 2>/dev/null | head -40')
    print("  docker run --rm -m 4g --entrypoint sh <image> -c '…grep "
          f"{len(FP8_MARKS)} marks…'")
    rc, out, err = sh(base + ["docker", "run", "--rm", "-m", "4g", "--entrypoint", "sh",
                              image, "-c", sh_quote(inner)], timeout=300)
    if rc != 0:
        print(f"  rc={rc}: {(err or out)[:400]}")
        return None
    ver = None
    qsa_seen = ""
    marks = {}
    for line in out.splitlines():
        if line.startswith("VLLM_VERSION="):
            ver = line.split("=", 1)[1]
        elif line.startswith("QSA_FILES="):
            qsa_seen = line.split("=", 1)[1].strip()
            print(f"  {line.rstrip()}")
        elif line.startswith("VLLM_DIR="):
            print(f"  {line}")
        else:
            for mark in FP8_MARKS:
                if mark in line:
                    marks.setdefault(mark, []).append(line.strip()[:200])
    print(f"  vllm.__version__ = {ver}")
    for mark in FP8_MARKS:
        hits = marks.get(mark, [])
        print(f"  {'HIT ' if hits else '—   '} {mark}: {len(hits)} line(s)")
        for h in hits[:4]:
            print(f"        {h}")
    # The discriminating read: the kernel's own dtype declaration. `fp8` IN that list is
    # the upstream fix; `["auto", "bfloat16"]` is the guard verbatim.
    declared = None
    for h in marks.get("supported_kv_cache_dtypes", []):
        m2 = re.search(r"=\s*(\[.*\])", h)
        if m2:
            declared = m2.group(1)
    if declared:
        print(f"  DECLARED supported_kv_cache_dtypes = {declared}")
    if not marks:
        print("  (no file matched at all — check the QSA_FILES line above; the module path "
              "renames between builds, and 'grep found nothing because it looked in the "
              "wrong place' is NOT the same answer as 'the build has no fp8 path'.)")
    return {"version": ver, "marks": marks, "declared": declared, "files_seen": bool(qsa_seen)}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tags", default="qwen38-flash-next,qwen38-flash-next-arm64-cu130",
                    help="comma list of tags to ask the registry about")
    ap.add_argument("--ssh-host", default="spark", help="host for the read-only docker run (default spark)")
    ap.add_argument("--image", default=None, help="override the ref to inspect (default: the pin)")
    ap.add_argument("--skip-box", action="store_true", help="registry leg only (laptop, no ssh)")
    ap.add_argument("--skip-registry", action="store_true", help="box leg only")
    ap.add_argument("--tag-filter", default="qwen",
                    help="regex of tag names to list newest-first (empty string skips the listing)")
    a = ap.parse_args()

    if shutil.which("ssh") is None and not a.skip_box:
        die("ssh not on PATH — pass --skip-box")
    image = a.image or pinned_image()
    busy = converge_running(None if a.skip_box else a.ssh_host)
    if busy:
        die(f"a converge is in flight ({busy}) — this probe never runs against a "
            f"half-applied host (prompt-spark-llm.md: read-only, never during a converge)", 2)

    undecided = 0
    box = None
    if not a.skip_registry:
        undecided += leg_registry([t.strip() for t in a.tags.split(",") if t.strip()], image,
                                  tag_filter=a.tag_filter or None)
    if not a.skip_box:
        box = leg_box(a.ssh_host, image)
        if box is None:
            undecided += 1

    print("\n── Verdict ─────────────────────────────────────────────────────────────")
    if box is None:
        print("UNDECIDED — the box leg (the only one that reads the engine's own qsa.py) did")
        print("not run. An inconclusive probe is not a verdict: fix the leg, or say in the")
        print("report that the dtype question is OPEN (prompt-spark-llm.md: an UNDECIDED run is not a verdict).")
        return 1
    strong = [m for m in ("IS_FP8", "fp8_e4m3") if box["marks"].get(m)]
    declared = box.get("declared") or ""
    if "fp8" in declared.lower():
        strong = strong or [f"supported_kv_cache_dtypes={declared}"]
    if strong:
        print(f"REACHABLE-ON-THIS-PIN — the pinned build's qsa.py carries {', '.join(strong)}.")
        print("That contradicts run #1's boot failure, so re-read BOTH before touching the")
        print("catalogue: the guard may live in a different file, or the overlay may be what")
        print("suppresses it. Do not flip `graded` on the strength of a grep alone.")
        return 0
    if not box["files_seen"]:
        print("UNDECIDED — no qsa.py was found at the model path we probed. The module")
        print("renames between builds (qwen3_8_flash_next ↔ qwen4exp); locate the file and")
        print("re-run with --image, or record this as OPEN.")
        return 1
    print("BLOCKED-ON-IMAGE — the pinned build carries no fp8 main-KV read path.")
    print("  · `graded` is therefore an ENGINE-PIN question (todo.md HD-473), not a config")
    print("    flip; it stays uncertified and nothing on this box needs to change.")
    print("  · fp8 KV merged upstream as vllm#55557 (2026-09-16) and is NOT in vLLM v0.30.0;")
    print("    the only refs that can carry it are a rebuilt qwen38-flash-next tag or a")
    print("    nightly — and CONVENTIONS §7 needs a REGISTRY-VERIFIED ARM64 digest of it.")
    print("  · if Leg A above printed no arm64 entry, that is the finding, verbatim.")
    if undecided:
        print(f"  (Leg A had {undecided} undecided tag(s) — record which.)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
