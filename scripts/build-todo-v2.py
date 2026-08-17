#!/usr/bin/env python3
"""build-todo-v2.py — one-shot generator for the todo.md restructure proposal.

Reads todo.md (main worktree), applies a domain-module classification and
status rules, and writes:
  - changelog.md   (19 done rows, dated, full text preserved)
  - todo-new.md    (proposed v2 backlog: decisions front, module tables, park)

Run:  python scripts/build-todo-v2.py
"""
from __future__ import annotations
import re, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent      # worktree root (homelab-todo-reorg)
SRC  = ROOT.parent / "homelab" / "todo.md"          # the CURRENT todo.md in the main worktree
if not SRC.exists():
    SRC = ROOT / "todo.md"

TODAY = datetime.date.today().isoformat()

# --------------------------------------------------------------------------
# 1. Parse todo.md rows
# --------------------------------------------------------------------------
ROW = re.compile(
    r"^\|\s*(HD-\d+[AB]?)\s*\|\s*(\d)\s*\|\s*((?:AI \+ gate|AI \+ Human|AI|Human))\s*\|\s*"
    r"(\*?\*?(open|done)\*?\*?)\s*\|\s*(.*)\s*$"
)
SECTION = re.compile(r"^## Priority (\d)")

def parse() -> list[dict]:
    rows, cur = [], 0
    for line in SRC.read_text(encoding="utf-8").splitlines():
        m = SECTION.match(line)
        if m:
            cur = int(m.group(1)); continue
        m = ROW.match(line)
        if m:
            item = m.group(6).strip()
            item = item.rstrip('|').rstrip()
            rows.append({
                "id": m.group(1), "d": int(m.group(2)), "exec": m.group(3),
                "status": m.group(5), "item": item,
                "pri": cur,
            })
    return rows

# --------------------------------------------------------------------------
# 2. Classification (editorial layer of the proposal)
# --------------------------------------------------------------------------
MODULES = [  # (key, title, one-line description)
    ("net",      "Network & DNS",          "VLANs, firewall, DNS, VPN, router/switch"),
    ("storage",  "Storage, ZFS & UPS",     "NAS datasets, NFS, UPS/NUT"),
    ("platform", "Platform & Deploy",      "Ansible, compose conventions, GitOps, Renovate, Doco-CD"),
    ("services", "Services & Edge",        "Traefik, SSO, service catalog, Matrix, VPS edge"),
    ("observ",   "Observability & Alerting", "Prometheus/Loki/Grafana, exporters, alert rules"),
    ("smart",    "Smart Home",             "HA primary/standby, Homematic, voice, devices"),
    ("ai",       "AI & Office",            "LLM stack, Open WebUI, office MCP, vector DB"),
    ("security", "Security & Secrets",     "secrets hygiene, privilege, firewall, preseed hardening"),
    ("backup",   "Backup & DR",            "ZFS snapshots, Kopia, off-site, restore drills"),
    ("docs",     "Docs & Family",          "family guides, docs, manual"),
    ("finance",  "Finance & Subscriptions","budget apps, banks, billing"),
]

ACTIVE = {  # id -> module key (only for open work rows)
    # net
    "HD-03":"net", "HD-78":"net", "HD-83":"net", "HD-84":"net", "HD-89":"net",
    # storage / UPS
    "HD-06":"storage", "HD-08":"storage", "HD-09":"storage", "HD-26":"storage", "HD-94":"storage",
    # platform
    "HD-02":"platform", "HD-61":"platform", "HD-90":"platform",
    # services & edge
    "HD-60":"services", "HD-43":"services", "HD-44":"services", "HD-46":"services",
    "HD-47":"services", "HD-58":"services", "HD-40A":"services", "HD-40B":"services",
    # observability
    "HD-64":"observ", "HD-85":"observ",
    # smart home
    "HD-04":"smart", "HD-13":"smart", "HD-14":"smart", "HD-15":"smart", "HD-17":"smart",
    "HD-18":"smart", "HD-20":"smart", "HD-21":"smart", "HD-23":"smart", "HD-27":"smart",
    "HD-79":"smart", "HD-72":"smart",
    # ai
    "HD-28":"ai", "HD-100":"ai", "HD-101":"ai", "HD-102":"ai", "HD-103":"ai",
    "HD-104":"ai", "HD-105":"ai", "HD-111":"ai",
    # security
    "HD-59":"security", "HD-62":"security", "HD-65":"security", "HD-77":"security", "HD-80":"security",
    "HD-81":"security", "HD-82":"security", "HD-86":"security", "HD-87":"security",
    "HD-88":"security", "HD-91":"security",
    # backup
    "HD-63":"backup", "HD-49":"backup", "HD-34":"backup",
    # docs
    "HD-32":"docs", "HD-33":"docs",
    # finance
    "HD-57":"finance",
}

DECISIONS = ["HD-22", "HD-24", "HD-25", "HD-29", "HD-39", "HD-52", "HD-53", "HD-54", "HD-55"]
BUYS      = ["HD-30", "HD-31"]
PARK      = ["HD-36", "HD-37", "HD-38", "HD-41", "HD-42", "HD-45", "HD-48"]

# best-effort completion dates (from git-log greps during the proposal)
DATES = {
    "HD-01":"2026-08-15","HD-05":"2026-08-08","HD-07":"2026-08-15","HD-10":"2026-08-15",
    "HD-11":"2026-08-15","HD-12":"2026-08-15","HD-16":"2026-08-15","HD-19":"2026-08-15",
    "HD-35":"2026-08-15","HD-50":"2026-08-15","HD-51":"2026-08-16","HD-56":"2026-08-16",
    "HD-92":"2026-08-16","HD-93":"2026-08-16","HD-106":"2026-08-17","HD-107":"2026-08-17",
    "HD-108":"2026-08-17","HD-109":"2026-08-17","HD-110":"2026-08-17",
}

# --------------------------------------------------------------------------
# 3. Renderers
# --------------------------------------------------------------------------
def md_row(id_, d, exec_, pri, item):
    return f"| {id_} | {d} | {exec_} | {pri} | {item} |"

def render_changelog(done: dict[str, dict]) -> str:
    L = [
        "# Changelog — Kogler Homelab",
        "",
        f"> Append-only log of completed/decided work. Migrated out of `todo.md` on {TODAY}.",
        "> Dates are best-effort git attributions (module/commit dates); verify against the owning doc before",
        "> relying on them — they are advisory, not SSOT.",
        "",
        f"**Done items migrated: {len(done)}** — " + ", ".join(sorted(done)),
        "",
        "## Decisions & research",
        "",
        "| ID | Date | Item |",
        "|----|------|------|",
    ]
    # decisions/research = rows tagged *(decision)* or research in title
    def is_decision(r):
        return "decision" in r["item"] or "research" in r["item"].lower() or "decided" in r["item"]
    for r in sorted(done.values(), key=lambda r: r["id"]):
        if is_decision(r):
            L.append(f"| {r['id']} | {DATES.get(r['id'], '')} | {r['item']} |")
    L += ["", "## Implementation & tooling", "",
          "| ID | Date | Item |", "|----|------|------|"]
    for r in sorted(done.values(), key=lambda r: r["id"]):
        if not is_decision(r):
            L.append(f"| {r['id']} | {DATES.get(r['id'], '')} | {r['item']} |")
    L += ["", "> Decisions were moved into their owning docs; the changelog row keeps the decision summary for "
          "audit trail. Items marked `*(decision)*` are `Decided` rather than `Implemented`.", ""]
    return "\n".join(L) + "\n"

def render_todo(open_rows: list[dict]) -> str:
    by_id = {r["id"]: r for r in open_rows}
    L = [
        "# Homelab TODO Backlog (restructure proposal)",
        "",
        f"> **DRAFT** generated from `todo.md` on {TODAY}. This replaces the old file only after human review.",
        "> The old `todo.md` remains the running backlog until then.",
        "",
        f"**Status:** {len(open_rows)} open · decisions in front · done items → [changelog.md](changelog.md)",
        "",
        "---",
        "",
        "## 0. How this backlog works",
        "",
        "- **One row = one outcome.** New work gets `HD-<next>` and links its owning `docs/*.md`.",
        "- **Priority (P):** 1 = highest (how hot), module = what domain it touches. Priority is per-row, modules group.",
        "- **Executors:** `AI` · `AI + gate` (human checkpoint) · `AI + Human` (joint) · `Human` (blocks).",
        "- **Lifecycle:** open → (decided → front section) → done → changelog. Deferred → park section.",
        "- **Conventions / onboarding:** see the [service-onboarding draft](#7-service-onboarding-draft) and repo conventions in `docs/index.md`.",
        "",
    ]

    # ---- 1. human decisions & buys ---------------------------------------
    L.append("## 1. Human decisions & purchases — review first")
    L.append("")
    L.append("### Decisions (blocking / waiting on a human call)")
    L.append("")
    L.append("| ID | D | Exec | Item |")
    L.append("|----|---|------|------|")
    for i in DECISIONS:
        r = by_id[i]
        L.append(f"| {r['id']} | {r['d']} | {r['exec']} | {r['item']} |")
    L.append("")
    L.append("### Purchases")
    L.append("")
    L.append("| ID | D | Exec | Item |")
    L.append("|----|---|------|------|")
    for i in BUYS:
        r = by_id[i]
        L.append(f"| {r['id']} | {r['d']} | {r['exec']} | {r['item']} |")
    L.append("")

    # ---- 2. active work by module ------------------------------------------
    L.append("## 2. Active work — by module")
    L.append("")
    counts = {}
    for idx, (key, title, desc) in enumerate(MODULES, start=1):
        rows = [by_id[i] for i in ACTIVE if ACTIVE[i] == key and i in by_id]
        rows.sort(key=lambda r: (r["pri"], r["id"]))
        if not rows:
            continue
        counts[key] = len(rows)
        L.append(f"### 2.{idx} {title} — {desc}")
        L.append("")
        L.append("| ID | D | Exec | P | Item |")
        L.append("|----|---|------|---|------|")
        for r in rows:
            L.append(md_row(r["id"], r["d"], r["exec"], r["pri"], r["item"]))
        L.append("")

    # ---- 3. park -------------------------------------------------------------
    L.append("## 3. Park — deferred / optional / Phase 2")
    L.append("")
    L.append("> Items here are not actively worked. They stay visible for planning.")
    L.append("")
    L.append("| ID | D | Exec | Item |")
    L.append("|----|---|------|------|")
    for i in PARK:
        r = by_id[i]
        L.append(f"| {r['id']} | {r['d']} | {r['exec']} | {r['item']} |")
    L.append("")

    # ---- 3b. activation notes (preserved from old todo.md header) --------------------
    L.append("## 3b. Activation notes - HD-02 (Doco-CD)")
    L.append("")
    L.append("> **HD-02 is a MULTI-STAGE task - do NOT attempt as a single run.** Use `plan_task` to")
    L.append("> split into ordered, idempotent tasks with exact validations and an explicit dependency graph.")
    L.append("")
    act = by_id.get("HD-02")
    if act:
        L.append("- Config finalization: turn .doco-cd.yml into the real deploy path (auto_discovery vs per-service compose), compose_files, reference, external_secrets mappings.")
        L.append("- 1Password secret provider: SECRET_PROVIDER=1password + SECRET_PROVIDER_ACCESS_TOKEN in the doco-cd compose env.")
        L.append("- Trigger wiring: webhook /v1/webhook (HTTP 80, WEBHOOK_SECRET HMAC, Forgejo webhook) and/or polling; decide polling vs webhook reachability first.")
        L.append("- Cross-task prerequisite: fix doco-cd metrics port 9120 + host-IP scrape in prometheus.yml.")
        L.append("- Post-deploy hooks: regenerate Homepage config + inventory docs + reload/commit+push. May depend on HD-12 - check before planning.")
        L.append("- Activate + verify: render templates and bring the container up; live activation likely on another host (human gate).")
    L.append("")

    # ---- 4. dependency / status notes -------------------------------------
    L.append("## 4. Status & dependency notes")
    L.append("")
    L.append("- **HD-50 done** → blocks all `docker_services` deployments; **HD-16 done** (Authentik + Forward-Auth middleware) unblocks Forward-Auth services (HD-43/44/46).")
    L.append("- **HD-03 → HD-04 → HD-13** (network redo feeds Pi redo feeds Homematic full-local).")
    L.append("- **HD-06/07 done** → feeds HD-08. **HD-29 → HD-31** (off-site decision gates iDrive purchase).")
    L.append("- 'Implemented, not deployed' rows (HD-03/06/17/46/60/61/62/63/64/94 …) stay open with a ⏳ marker until a live deploy happens — closing requires a deploy/verify pass, not just IaC.")
    L.append("")

    # ---- 5. tally ------------------------------------------------------------
    L.append("## 5. Tally (generated)")
    L.append("")
    L.append(f"- Open rows: {len(open_rows)}")
    L.append(f"- Decisions front: {len(DECISIONS)} · Buys: {len(BUYS)} · Park: {len(PARK)}")
    L.append(f"- Active work per module: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    L.append("")

    # ---- 6. conventions quick-reference -------------------------------------
    L.append("## 6. Conventions quick-reference")
    L.append("")
    L.append("| Area | Rule | Owning doc |")
    L.append("|------|------|-----------|")
    L.append("| Hostnames | single `kogler.si` namespace, flat subdomains | `docs/index.md` Conventions")
    L.append("| IPs | `docs/network-addresses.md` is the SSOT, generated, never hand-edit | `scripts/check_doc_ips.py`")
    L.append("| Secrets | 1Password `Homelab` vault, `<service>_<type>` naming | `docs/deployment-secrets.md`")
    L.append("| Compose | conventions & port binding policy | `docs/deployment-compose.md`")
    L.append("| Ansible | roles/templates/conventions | `docs/deployment-ansible.md`, `IaC/README.md`")
    L.append("| Service catalog | `group_vars/home_servers.yml` + `docs/services.md` | `docs/services.md`")
    L.append("| Validation | `bash scripts/validate-all.sh` before commit | `scripts/`")
    L.append("")

    # ---- 7. service onboarding draft -----------------------------------------
    L.append("## 7. Service-onboarding draft (new-service checklist)")
    L.append("")
    L.append("A uniform 'add a service' path, so a new service doesn't spawn custom habits:")
    L.append("")
    L.append("1. **Exposure & auth decision** — public/internal/Headscale-only; Forward-Auth vs native OIDC. Write the decision in the owning service doc.")
    L.append("2. **Secrets** — create 1Password item(s) `<service>_<type>`; add a catalog row in `docs/deployment-secrets.md`.")
    L.append("3. **Compose template** — `docker_services/<service>/` per `docs/deployment-compose.md` (external networks, pinned tags, no host ports unless justified).")
    L.append("4. **Registry** — add to `group_vars/home_servers.yml` + catalog row in `docs/services.md`.")
    L.append("5. **Edge (if exposed)** — Traefik route + middleware chain (`crowdsec-only`, Forward-Auth).")
    L.append("6. **State & backups** — volume/driver `local`, map any DB into `db-backup`/Kopia scope.")
    L.append("7. **Observability** — exporter/scrape target + Grafana dashboard/alert if needed.")
    L.append("8. **Validation** — `bash scripts/validate-all.sh` green (template + group_vars).")
    L.append("9. **Deploy gate** — first deploy is a human-gated apply (dry-run → single host).")
    L.append("10. **Docs** — family guide + `docs/index.md` map row for family/ops-facing service.")
    L.append("")
    return "\n".join(L) + "\n"

# --------------------------------------------------------------------------
# 4. main
# --------------------------------------------------------------------------
def main():
    rows = parse()
    done = {r["id"]: r for r in rows if r["status"] == "done"}
    open_rows = [r for r in rows if r["status"] == "open"]
    by_id = {r["id"]: r for r in open_rows}

    # verify every open row is classified
    assigned = set(ACTIVE) | set(DECISIONS) | set(BUYS) | set(PARK)
    unclassified = sorted(set(by_id) - assigned)
    if unclassified:
        print("WARNING unclassified open rows:", unclassified)
        sys.exit(1)

    (ROOT / "changelog.md").write_text(render_changelog(done), encoding="utf-8")
    (ROOT / "todo-new.md").write_text(render_todo(open_rows), encoding="utf-8")
    print(f"parsed {len(rows)} rows ({len(done)} done, {len(open_rows)} open)")
    print(f"wrote {ROOT / 'changelog.md'} and {ROOT / 'todo-new.md'}")

if __name__ == "__main__":
    import sys
    main()