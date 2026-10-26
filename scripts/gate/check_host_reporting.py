#!/usr/bin/env python3
"""check_host_reporting.py — a monitoring host that publishes NOTHING is a finding, not a gap.

WHY THIS EXISTS. Every metric-side alert rule reads the store, and the store can only speak about
series that exist. The fleet's staleness rule for the hygiene collector is written correctly for that
world — unfiltered A leg + a threshold expression, so every host keeps a value to compare against —
and it therefore cannot see the one shape where a host contributes no value at all: a collector host
whose own scrape leg died publishes neither its heartbeat nor `up{job="alloy"}`, so nothing becomes a
value, nothing crosses a threshold, and every rule stays `Normal` while the host is dark. It is not an
outage a rule can see by asking "is the number old?" — the number never arrived. On the box that
started this, the exporter was `active` and answering its own loopback port, the Alloy unit was
`active`, and the host's nut/zfs exporters still looked green in the same store because a DIFFERENT
host scrapes those. A missing instance is an anomaly about a set the store does not contain, so the
check has to bring that set itself.

THE EXPECTED SET COMES FROM THE INVENTORY, NOT FROM THE STORE. `[monitoring]` in
`IaC/ansible/inventory.ini` is the SSOT for "this box must publish"; "hosts that report" is derived
from what happens to report, which is the thing that went wrong. Anything in that group with no series
is a finding, and a reporter no inventory declares is a finding too, so both directions of drift close
in one check.

WHICH INSTRUMENT CARRIES THIS, HONESTLY: an offline check, not a ruler rule. A recording or alerting
rule can only compare values the backend holds, and the expected set is inventory state — so a
rule-shaped version needs the expected set IN the backend first, and the form that ships is ONE generated
`absent_over_time` rule per `[monitoring]` host (rendered from `groups['monitoring']` by the monitoring
role's alert-rule template, because an expected series that nothing publishes is a green that never
loaded). So paging is covered by the rule, and this file is the half the rule cannot be: the DIAGNOSIS. A
page says a host went dark; only this run says WHICH of the four shapes it is, and it answers between
converges on the seat that has the route. ⚠ What it does not carry is the page itself — it answers when
somebody runs it, which is the reason the rule exists and not a reason to retire this.

FOUR SHAPES PER HOST, kept apart on purpose, because they are different faults with different fixes:
  BLIND              nothing carries instance=<host>            → the host's own scrape leg is dead
  SCRAPE LEG DEAD    series exist, no `up{job="alloy"}`         → Alloy runs, it is not shipping
  COLLECTOR STALE    Alloy reports, the heartbeat does not      → `homelab-hygiene` on that box
  UNDECLARED         a reporter no `[monitoring]` host names    → inventory and store disagree
The heartbeat's VALUE is deliberately not judged here: a `homelab_hygiene_scrape_ok 0` row is a
reporting host, and what its zero means is that rule's business, not this file's.

Exit: 0 every expected host reporting · 1 finding(s) · 2 could not run (no inventory, no endpoint, no
creds, a store read that failed, an expected set too small to be real). Stdlib + ssh/curl/op only. It
writes nothing and restarts nothing — this is the READ; the repair it points at is the serving-probe
leg in `roles/monitoring`.

Transport — the endpoint is IaC `victoria_backend_host` (:8428), reachable over wg-s2s; a laptop has
no route, so two forms, and neither is guessed:
  VM_SSH_HOST=<host>   default `oldsrv` — run the curl THERE, the hop that answers from this seat
  VM_URL=http://h:8428 direct form, for a seat that does have the route
  creds: 1Password `Homelab-ansible/victoria-metrics_api` via the ONE reader
  (`scripts/lib/vault_read.py`, one ID-addressed read, its count printed), else VM_USERNAME + VM_PASSWORD.
  Values never reach argv, stdout or git — lengths only, per CONVENTIONS §6.

Flags: `--show` prints the expected set; `--inventory DIR` points at another tree (the self-test);
`--fixture FILE` answers the queries from recorded JSON instead of the store — the ONLY way this file
fabricates a read, and it prints a FIXTURE banner when used; `--dump-fixture` produces that JSON from
the live store; `--self-test` builds the fixtures and proves the verdict can still redden.

    python3 scripts/gate/check_host_reporting.py            # the live read, the real verdict
    python3 scripts/gate/check_host_reporting.py --self-test
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402
from vault_read import Boundary as _ReadBoundary, read_item as _read_item  # noqa: E402

ROOT = _hl_root(__file__)
INVENTORY = "IaC/ansible/inventory.ini"
GROUP_VARS = "IaC/ansible/group_vars/all/main.yml"
GROUP = "monitoring"
ALLOY_UP = 'up{job="alloy"}'
HYGIENE = "homelab_hygiene_scrape_ok"
# The floor under the expected set, not its count. Below it the PARSE is broken and every host would
# count as "in sync" — a walk that found nothing printing a green is the failure mode this repo calls
# corpus-assertion (CONVENTIONS §6), so the floor refuses rather than reports. Five hosts are declared
# today; 4 is the floor.
EXPECTED_FLOOR = 4


# --------------------------------------------------------------------------- #
# The expected set: the inventory, parsed. Never a list typed into this file.  #
# --------------------------------------------------------------------------- #
def expected_hosts(root: Path) -> list[str]:
    """Host names from the `[monitoring]` section of the INI inventory.

    Section-scoped and comment-stripped. Unscoped, this hands back every host in the file and a box
    that runs no Alloy becomes a permanent false finding; the inline `#` comments carry each host's
    reason for being in the group, so they are stripped before the name is taken."""
    path = root / INVENTORY
    if not path.is_file():
        raise RuntimeError(f"no inventory at {path}")
    out, inside = [], False
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            inside = line[1:-1].split(":")[0].strip() == GROUP
            continue
        if inside:
            name = line.split()[0]
            if name and name not in out:
                out.append(name)
    return sorted(out)


# --------------------------------------------------------------------------- #
# The observed set: three queries, one per claim.                             #
# --------------------------------------------------------------------------- #
def series_query(hosts: list[str]) -> str:
    """`count by (instance)` over every series whose instance is one of ours.

    Two shapes this query has to survive, both measured against the live backend:

    * The dots are escaped. An unescaped dot is a regex any-char, so a look-alike name could satisfy
      a host it is not, and a matcher wider than the name it prints can be green about the wrong box.
    * Each escape is DOUBLED, and a `__name__` selector is present. A label matcher takes a STRING
      literal, so the regex backslash has to be written twice; and a selector with no metric name at
      all is parsed by VictoriaMetrics as a WITH template, which answers `cannot parse string literal
      … invalid syntax` rather than "no data". The metric-name half is what makes "does ANYTHING
      carry this instance" expressible at all, so it stays."""
    alt = "|".join(re.escape(h).replace("\\", "\\\\") for h in hosts)   # one backslash in, two out
    return f'count by (instance) ({{__name__=~".+", instance=~"{alt}"}})'


def endpoint(root: Path) -> str:
    """The Victoria endpoint from IaC — `victoria_backend_host`, which IS `wg_s2s_vps.ip`.

    Resolved, never duplicated: an IP literal here would be a second owner of an address the address
    SSOT already owns."""
    text = (root / GROUP_VARS).read_text(encoding="utf-8")
    ref = re.search(r"^victoria_backend_host:\s*\"?\{\{\s*([\w.]+)\s*\}\}", text, re.M)
    if ref:
        parent, _, key = ref.group(1).rpartition(".")
        block = re.search(rf"^{re.escape(parent)}:\n((?:[ \t]+.*\n)+)", text, re.M)
        val = re.search(rf"^\s+{re.escape(key)}:\s*\"?([\d.]+)", block.group(1), re.M) if block else None
        return val.group(1) if val else ""
    lit = re.search(r"^victoria_backend_host:\s*\"?([\d.]+)", text, re.M)
    return lit.group(1) if lit else ""


def creds() -> tuple[str, str]:
    u, p = os.environ.get("VM_USERNAME", ""), os.environ.get("VM_PASSWORD", "")
    if u and p:
        return u, p
    # One ID-addressed read of the one item this leg needs, through the ONE reader
    # (scripts/lib/vault_read.py): no ambient pair, no vault write, and the reader's own
    # `print_cost` line states the price — a run's quota price belongs in the log, not in a guess.
    # No credential is a named boundary: an `op` called without one is the Win11 desktop-app route, a
    # consent dialog per read rather than an error.
    try:
        vr = _read_item("victoria-metrics_api", "Homelab-ansible")
        item = vr.only()
        vr.print_cost("check_host_reporting.py")
    except (_ReadBoundary, OSError, ValueError) as exc:
        raise RuntimeError(f"{exc} and VM_USERNAME/VM_PASSWORD are unset") from exc
    got: dict[str, str] = {}
    for f in item["fields"]:
        key = f["id"] if f["id"] in ("username", "password", "credential") else f["label"]
        if key in ("username", "password", "credential") and f["value"]:
            got.setdefault(key, f["value"])
    if "password" not in got and "credential" in got:
        got["password"] = got["credential"]
    if not got.get("username") or not got.get("password"):
        raise RuntimeError("victoria-metrics_api username/password unreadable through the shared "
                           "read — the item holds no field named for either")
    return got["username"], got["password"]


def backend_url(root: Path) -> tuple[str, str]:
    """(url, hop) — the hop is empty when this seat has the route itself."""
    url = os.environ.get("VM_URL", "")
    if url:
        return url.rstrip("/"), ""
    hop = os.environ.get("VM_SSH_HOST", "oldsrv")     # the documented default hop, named not guessed
    ep = endpoint(root)
    if not ep:
        raise RuntimeError(f"victoria_backend_host did not resolve from {GROUP_VARS}")
    return f"http://{ep}:8428", hop


def query_live(expr: str, url: str, hop: str, u: str, p: str) -> list[dict]:
    """One instant query. The creds ride STDIN, never argv.

    `ssh hop "curl -u $1:$2 …"` would put the pair in the process list of BOTH boxes, and the
    remote leg must not take them from argv for the same reason. So the far side reads four lines —
    user, password, endpoint, query — off ONE pipe, writes them into a 0600 curl config, and unlinks
    it (the shape `scripts/bench/spark/vm-tokens.sh` already proves live). One ssh per query, and no
    `ssh` inside any read loop of ours, which is the stdin trap CONVENTIONS §6 names: a loop whose
    body calls ssh silently ends after the first item and reports success anyway."""
    if '\n' in u or '\n' in p or '"' in p:
        # A newline would desynchronise the four-line wire and a `"` would break the curl config line.
        raise RuntimeError("the vault credential contains a newline or a double quote; "
                           "this transport cannot carry it safely")
    if hop:
        script = ('read -r u; read -r p; read -r url; read -r q; '
                  'c=$(mktemp); chmod 600 "$c"; '
                  'printf "user = \\"%s:%s\\"\\n" "$u" "$p" > "$c"; '
                  'curl -sS -m 20 -K "$c" -G --data-urlencode "query=$q" "$url/api/v1/query"; '
                  'rc=$?; rm -f "$c"; exit $rc')
        r = subprocess.run(["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", hop, script],
                           input=f"{u}\n{p}\n{url}\n{expr}\n", capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
    else:
        cfg = ""
        try:
            fd, cfg = tempfile.mkstemp()
            with os.fdopen(fd, "w") as fh:
                fh.write(f'user = "{u}:{p}"\n')
            r = subprocess.run(["curl", "-s", "-m", "20", "-K", cfg, "-G",
                                "--data-urlencode", f"query={expr}", f"{url}/api/v1/query"],
                               capture_output=True, text=True, encoding="utf-8", errors="replace")
        finally:
            if cfg:
                os.unlink(cfg)
    if r.returncode != 0 or not r.stdout.strip():
        raise RuntimeError(f"store read failed (rc {r.returncode}): "
                           f"{(r.stderr or '').strip()[:120] or 'empty response'}")
    try:
        body = json.loads(r.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"the store answer was not JSON: {exc}") from exc
    if body.get("status") != "success":
        raise RuntimeError(f"the store answered {body.get('status')!r}: {str(body.get('error'))[:120]}")
    return body["data"]["result"]


def fold(rows: list[list[dict]]) -> dict:
    """Three query results → instance → {alloy, hygiene, series}. One shape for live and fixture."""
    out: dict = {}
    for key, row in zip(("alloy", "hygiene", "series"), rows):
        for r in row:
            inst = (r.get("metric") or {}).get("instance", "")
            if not inst:
                continue
            slot = out.setdefault(inst, {"alloy": False, "hygiene": False, "series": 0})
            slot[key] = True if key != "series" else int(float(r["value"][1]))
    return out


def read_live(root: Path, hosts: list[str]) -> dict:
    url, hop = backend_url(root)
    u, p = creds()
    # Lengths only: the rule is that a probe shows how long a secret is, never what it is.
    print(f">>> creds: user={len(u)} chars, secret={len(p)} chars (values not printed)",
          file=sys.stderr)
    return fold([query_live(f"max by (instance) ({ALLOY_UP})", url, hop, u, p),
                 query_live(f"max by (instance) ({HYGIENE})", url, hop, u, p),
                 query_live(series_query(hosts), url, hop, u, p)])


# --------------------------------------------------------------------------- #
# The verdict. The ONLY place this file decides anything.                     #
# --------------------------------------------------------------------------- #
def judge(expected: list[str], observed: dict) -> tuple[list[str], int]:
    findings: list[str] = []
    healthy = 0
    for host in expected:
        row = observed.get(host)
        if row is None or not row.get("series"):
            findings.append(
                f"BLIND             {host}: no series carries instance={host} — the host publishes "
                "nothing, so no metric rule can see it. Its own exporters may still read green under "
                "whoever else scrapes them, which is what makes this invisible from a board.")
            continue
        if not row.get("alloy"):
            findings.append(
                f"SCRAPE LEG DEAD   {host}: {int(row['series'])} series exist but "
                f"`up{{job=\"alloy\",instance=\"{host}\"}}` does not — Alloy is not shipping this "
                "host's scrapes")
            continue
        if not row.get("hygiene"):
            findings.append(
                f"COLLECTOR STALE   {host}: Alloy reports, the hygiene heartbeat does not — the class "
                "the staleness rule already owns, so fix the collector, not the scrape leg")
            continue
        print(f"  ok    {host}  {int(row['series'])} series")
        healthy += 1
    for inst in sorted(set(observed) - set(expected)):
        findings.append(
            f"UNDECLARED        {inst}: carries {ALLOY_UP} or the heartbeat, but no [{GROUP}] host "
            "in the inventory names it — the inventory and the store disagree")
    return findings, healthy


def report(expected: list[str], observed: dict, source: str) -> int:
    findings, healthy = judge(expected, observed)
    print(f"expected set: {len(expected)} [{GROUP}] host(s) from {INVENTORY} — {source}")
    for f in findings:
        print(f"  FINDING  {f}")
    if findings:
        print(f"FAIL: {len(findings)} finding(s); {healthy}/{len(expected)} expected host(s) healthy")
        return 1
    print(f"OK: every [{GROUP}] host reports — {healthy} host(s), Alloy up + heartbeat present")
    return 0


# --------------------------------------------------------------------------- #
# Fixture form: the same verdict, with the store replaced by a recorded read. #
# --------------------------------------------------------------------------- #
def load_fixture(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"fixture unreadable ({path}): {exc}") from exc
    if not isinstance(data, dict) or not data:
        raise RuntimeError(f"fixture holds no observations ({path}) — refusing to call that healthy")
    out = {}
    for inst, row in data.items():
        if not isinstance(row, dict) or "series" not in row:
            raise RuntimeError(f"fixture row {inst!r} has no `series` — refusing to guess a verdict")
        out[inst] = {"alloy": bool(row.get("alloy")), "hygiene": bool(row.get("hygiene")),
                     "series": int(row["series"])}
    return out


# --------------------------------------------------------------------------- #
# --self-test: the canaries. Each re-runs THIS file over a fixture tree.      #
# --------------------------------------------------------------------------- #
# Five, because the real inventory declares five and the floor under the expected set must be cleared
# by the fixture the way it is cleared in production — a fixture tree below the floor would exercise
# the refusal path in every case and prove nothing about the verdict.
HOSTS = ["a.example.test", "b.example.test", "c.example.test", "d.example.test", "e.example.test"]


def fixture_store(drop: str = "", shape: str = "blind") -> dict:
    """Every expected host healthy, then mutated in exactly ONE way."""
    store = {h: {"alloy": True, "hygiene": True, "series": 40} for h in HOSTS}
    if not drop:
        return store
    store[drop] = {"blind": {"alloy": False, "hygiene": False, "series": 0},
                   "stale": {"alloy": True, "hygiene": False, "series": 12},
                   "no-alloy": {"alloy": False, "hygiene": True, "series": 12}}[shape]
    return store


def fixture_tree(root: Path, name: str, hosts: list[str]) -> Path:
    """A two-file inventory tree: the expected set the checker must read, and nothing else."""
    d = root / name / "IaC/ansible"
    d.mkdir(parents=True, exist_ok=True)
    (d / "inventory.ini").write_text(
        f"[{GROUP}]\n" + "\n".join(f"{h}          # a fixture host" for h in hosts) + "\n",
        encoding="utf-8")
    g = d / "group_vars/all"
    g.mkdir(parents=True, exist_ok=True)
    (g / "main.yml").write_text('victoria_backend_host: "{{ wg_s2s_vps.ip }}"\n'
                                'wg_s2s_vps:\n  ip: "192.0.2.1"\n', encoding="utf-8")
    return root / name


def self_test() -> int:
    fails = 0
    n_cases = 0
    tmp = Path(tempfile.mkdtemp(prefix="host-reporting-"))
    try:
        tree = fixture_tree(tmp, "base", HOSTS)
        wider = fixture_tree(tmp, "wider", HOSTS + ["f.example.test"])
        none = fixture_tree(tmp, "none", [])

        def case(name: str, store, want_rc: int, says: str, where: Path = tree,
                 raw: str | None = None):
            nonlocal fails, n_cases
            n_cases += 1
            fp = tmp / f"{name}.json"
            fp.write_text(raw if raw is not None else json.dumps(store), encoding="utf-8")
            r = subprocess.run([sys.executable, str(Path(__file__).resolve()),
                                "--inventory", str(where), "--fixture", str(fp)],
                               capture_output=True, text=True, encoding="utf-8", errors="replace")
            out = r.stdout + r.stderr
            if r.returncode == want_rc and says in out:
                print(f"  ok    {name}  (rc {r.returncode})")
                return
            fails += 1
            print(f"  FAIL  {name}: rc {r.returncode} want {want_rc}, wanted {says!r} in")
            for line in out.splitlines()[:8]:
                print(f"        | {line}")

        # The honest baseline: everything the inventory declares is reporting.
        case("baseline", fixture_store(), 0, "OK: every")
        # THE canary this file exists for: ONE host stops emitting every series. Nothing else in the
        # store changes and no rule's threshold moves, so the ONLY way to see it is the expected set.
        case("blind-host", fixture_store("b.example.test"), 1, "BLIN")
        case("blind-host-names-it", fixture_store("b.example.test"), 1, "b.example.test")
        # The set comes from the INVENTORY, not from what reports: the store is byte-identical to the
        # baseline above and ONLY the inventory differs (one more host declared). A check that derived
        # its expectations from the store would print OK here, which is the blindness itself.
        case("inventory-declares-more", fixture_store(), 1, "BLIN", where=wider)
        # ...and the other direction: a reporter no inventory names is drift too, not a bonus host.
        case("undeclared-reporter", {**fixture_store(),
                                     "g.example.test": {"alloy": True, "hygiene": True, "series": 9}},
             1, "UNDECLARED")
        # The three shapes stay three shapes: each names a different fix, so collapsing two of them
        # into one label is a real weakening, and each arm reddens if it happens.
        case("collector-stale", fixture_store("b.example.test", "stale"), 1, "COLLECTOR STALE")
        case("scrape-leg-dead", fixture_store("b.example.test", "no-alloy"), 1, "SCRAPE LEG DEAD")
        # A check that reads nothing must refuse, never print OK: an empty store, a row with no
        # `series` field, and an inventory whose [monitoring] section parses empty.
        case("empty-store", {}, 2, "SKIP", where=tree)
        case("malformed-fixture", None, 2, "refusing to guess",
             raw='{"a.example.test": {"alloy": true}}')
        case("empty-expected-set", fixture_store(), 2, "parse failure", where=none)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if fails:
        print(f"FAIL: {fails} self-test case(s) — the expected-set verdict has lost its teeth")
        return 1
    print(f"OK: the expected-set verdict separates every shape it names ({n_cases} cases)")
    return 0


# --------------------------------------------------------------------------- #
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="the live read (the default; the gate form)")
    ap.add_argument("--show", action="store_true", help="print the expected set and exit")
    ap.add_argument("--dump-fixture", action="store_true",
                    help="run the live read and print the fixture JSON (evidence, not a verdict)")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--inventory", default=str(ROOT), help="repo root to read the inventory from")
    ap.add_argument("--fixture", help="answer the queries from this JSON instead of the store")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()

    root = Path(args.inventory).resolve()
    try:
        expected = expected_hosts(root)
    except RuntimeError as exc:
        print(f"SKIP: {exc}", file=sys.stderr)
        return 2
    if len(expected) < EXPECTED_FLOOR:
        # An expected set this small is a broken parse, not a fleet: with nothing expected, every
        # host is trivially "in sync" and the check would print a green it never earned.
        print(f"SKIP: only {len(expected)} [{GROUP}] host(s) parsed from {INVENTORY}; the floor is "
              f"{EXPECTED_FLOOR}, so this is a parse failure", file=sys.stderr)
        return 2
    if args.show:
        print("\n".join(expected))
        return 0

    if args.fixture:
        try:
            observed = load_fixture(Path(args.fixture))
        except RuntimeError as exc:
            print(f"SKIP: {exc}", file=sys.stderr)
            return 2
        print("FIXTURE: the store below is a recorded file, not VictoriaMetrics", file=sys.stderr)
        return report(expected, observed, f"fixture {Path(args.fixture).name}")

    try:
        if args.dump_fixture:
            url, hop = backend_url(root)
            u, p = creds()
            rows = [query_live(f"max by (instance) ({ALLOY_UP})", url, hop, u, p),
                    query_live(f"max by (instance) ({HYGIENE})", url, hop, u, p),
                    query_live(series_query(expected), url, hop, u, p)]
            print(json.dumps(fold(rows), indent=2, sort_keys=True))
            return 0
        observed = read_live(root, expected)
    except (RuntimeError, OSError) as exc:
        # No route, no vault, no endpoint: a boundary, printed. A SKIP is never a pass (CONVENTIONS §6).
        print(f"SKIP: the store could not be read — {exc}", file=sys.stderr)
        return 2
    return report(expected, observed, "live read")


if __name__ == "__main__":
    raise SystemExit(main())
