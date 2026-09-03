# Kogler Homelab — AI Bootstrap

> **Role:** AI session bootstrap. Read at the start of EVERY coding/agent task. Absolute map to the
> mandatory context + the repo's working contract for agents.
> **Linked from:** `readme-humans.md` (the human/family guide) & `AGENTS.md` guidance.
> **Scope note:** a `prompt-*.md` handoff may supersede this by naming its own context — this file is
> the base, handoff files extend it.

---

## 0. How every session starts (intent-routed, HD-253)

The human ALWAYS starts a session with the universal phrase **"read README.md"** followed by ONE
free-form intent sentence (e.g. *"read README.md — zipline uploads stopped working"*). This file
is the bootstrapper; it carries all background so the intent sentence needs no extra briefing.
The agent then routes the intent — there is NO keyword routing table:

1. **Step-0 ritual, UNCONDITIONAL:** `git status` sanity check + fresh session worktree
   (`../homelab-wt-<date>-<HHMM>`, CONVENTIONS §6) BEFORE any edit — enforced mechanically by
   [`scripts/guard-session.sh`](scripts/guard-session.sh) + a hard gate inside
   [`scripts/validate-all.sh`](scripts/validate-all.sh).
2. **Semantic prior-art sweep:** search todo.md / docs/ — including the `<domain>-rejected.md`
   decision logs, `<domain>-review.md` and `brainstorming/` — plus `git log -S 'HD-XX'` / `git log`
   on the owning doc, and REPORT the prior art found BEFORE proposing any new HD row (side-effect:
   enforces the §8.3 rejected-check and the decision-log re-decide ban; the frozen
   `reports/changelog.md`/`reports/deployment-journal.md` are archive-only).
3. **Depth markers** ("quickly", "just do X") reduce ANALYSIS verbosity only — NEVER safety ritual
   (worktree, validate-all, owning-doc/lifecycle discipline always applies).
4. **Ambiguous intent → ask exactly ONE clarifying question**, then proceed.

Routing changes ORDER/emphasis only — it never eliminates context. Read §1 below, then §2 mandatory
context **in order**. After §2, use `docs/index.md` → "Which Document to Read First" for
task-specific dispatch. Do **not** bulk-read the repo.

---

## 1. Mandatory context (read every session, in this order)

| # | File | Role | Read when |
|---|------|------|-----------|
| 1 | [`CONVENTIONS.md`](CONVENTIONS.md) | Cross-cutting rules index — naming, secrets, SSOT, IaC, lifecycle, service-onboarding (§5) | always — every rule is binding |
| 2 | [`docs/index.md`](docs/index.md) | AI dispatcher / document map — which owning doc to open for your task | always |
| 3 | [`IaC/README.md`](IaC/README.md) | Ansible implementation spec — roles, templates, layout, build order, status | any IaC / compose / template work |
| 4 | [`todo.md`](todo.md) | Backlog + open decisions; §0 lifecycle (HD-XX); pick up or register work | always, before every task |

> **Decisions** live in the owning doc + the `<domain>-rejected.md` decision log (append-only, per
> domain) — never re-decide without checking those + `git log -S 'HD-…'`. Historical rows live in
> the frozen `reports/changelog.md` (archive-only).

---

## 2. State of the world (as of 2026-09-04)

- **Phase 1 (VPS edge) is live.** The VPS runs its full enabled `docker_services` set — Traefik,
  Authentik, the observability backend (prometheus/loki/grafana/blackbox), Technitium DNS primary, etc.
  Evidence: the owning-service docs (✅ status lines) + [`deployment-tasks.md`](deployment-tasks.md) checkbox
  dates + git commit messages; the as-built journal and changelog were frozen 2026-09-01
  (`reports/`, archive-only). **Phase 2 (nas) and Phase 4 (Pi) are provisioned + LIVE (2026-09-03).**
  **oldsrv (Phase 3) is IN PROGRESS — BLOCKED on the `office` ONLYOFFICE repo/key, `amd_rocm` ROCm pins,
  and 3 missing 1P vault items** (HD-318; `docker_services` big deploy gated on them); anything below
  the VPS tier that is not yet live remains *deploy-gated*; verify against
  [`deployment-tasks.md`](deployment-tasks.md) before any "run".
- **How to check what is live vs authored-only (check in this order):**
  1. [`todo.md`](todo.md) §0/§3c → [`deployment-tasks.md`](deployment-tasks.md) — the ⏳ deploy-gated
     verification checklist per phase (checkbox + date when done).
  2. Owning-service docs (`docs/services-*.md`, hardware docs) ✅ status lines + `git log` on them —
     the dated live-verified evidence.
  3. Doc status banners (`🟢 IaC done, not yet live — ⏳ deploy-gated`) are **hints, not proof** —
     trust the owning-doc ✅ lines + deployment-tasks ticks over banners until the docs catch up.
- **Hosts:** single namespace `kogler.si` → `oldsrv`, `nas`, `pi`, `router`, `switch`, `vps`.
  Canonical list + naming/IP conventions: `docs/index.md` → Conventions.
- **Recommended next tasks:** see the latest `prompt-*.md` handoff (date-stamped) — it names the
  current most-valuable, laptop-doable items. **HD-312 3-SSID WiFi + per-MAC cloud-IoT WAN is LIVE
  (2026-09-03)** — the cloud-IoT appliances (LG/Bosch/HAP) regain WAN as leases turn over; the phantom
  **VLAN 21 (IoT-Internet) DELETED + live-cleanup applied (HD-325 + HD-328, 2026-09-04)** — cloud-IoT
  moved to VLAN 20 with a per-device `wan_allow` flag (SSOT = live). **HD-328 (2026-09-04): the NVIDIA
  Shield (Media VLAN 50) no-internet root cause FIXED + LIVE** — the CRS328 had **no untagged access
  membership for VLAN 50**, so ether14/ether20 frames were dropped at ingress (empty ARP, no DHCP/WAN);
  every `switch_port_map` access port is now an untagged member of its role VLAN in
  `crs328_converge.rsc.j2` + the switch role, applied + verified → Shield online (ARP reachable, lease
  bound). **Kids device set DEFINED (HD-326, 2026-09-04)** =
  `tablet-valentina` + `tablet-ipad` — per-MAC kids controls (bedtime/DoT/DNS-filter) are the next
  implement item. Remaining tails (kids-* controls, n8n firmware automation) are in
  [`todo.md`](todo.md) HD-312/HD-326. **HD-317 Technitium DNS-primary on the VPS is LIVE** (3-instance DNS
  HA); the split-horizon A-record **seed is DONE + LIVE on the VPS primary** (HD-324, 2026-09-03 —
  VPS admin recreated to the 1P value via the documented API; the seed role now idempotent).
  **The `dns-pi` (Pi tertiary) 5380 web-UI publish is LIVE (2026-09-04, HD-317)** — `technitium-pi`
  now publishes `5380:5380/tcp` (the 502 root cause — no listener — is gone; `pi:5380` answers HTTP 200);
  the **Pi tertiary's A-record seed is still BLOCKED** on its admin being rotated from the default
  `admin`/`admin` to the 1P `technitium_login` value (**HD-330**, same class as the VPS HD-324 fix) — its
  zone is empty until then; oldsrv secondary seeds once its Phase-3 admin is up. **HD-315 (UPS exporter)
  pinned to `v3.3.0` (2026-09-04)** — replaces the `@latest`→`(devel)` drift on nas.
  **Edge model DECIDED (Option A, 2026-09-04, HD-331):** one **public edge** (WAN-only, public apps) + one
  **internal all-app edge** (every app, public + internal) over Headscale tailnet + WG-S2S; the DNS stays the
  settled 3-instance Technitium (VPS-primary) split-horizon. Implement via HD-332 (catalog `public:` flag +
  internal-edge growth), HD-333 (WG + tailnet reach + ACL), HD-334 (per-device DNS via Pi-first VLAN-10 +
  seed `vpn`/`home`/`dns` records).
  Detail: [`todo.md`](todo.md) HD-317 / HD-330.

---

## 3. Non-negotiables (repo contract for agents)

- **Validate before finishing:** run **`bash scripts/validate-all.sh`** — must end green.
  Fail-closed linters (`check_doc_map.py`) break validation on a stale map link.
- **SSOT direction:** values live in IaC (`group_vars/*.yml`, `host_vars/*.yml`,
  `rack-connections.json`). Generated `*-generated.md` docs are render views — **never hand-edit**
  them, and scripts never parse generated MD.
- **Secrets:** never literal in docs / group_vars / templates — always 1Password `Homelab-ansible` vault
  refs (or the Private SA vault per HD-140). **Fail-loud**: no `default('')`.
- **Language / links:** English (technical); Slovenian only for `docs/manual/` (family). Relative
  `.md` links. Every doc starts with `> **Role:**` / `> **Linked from:**`.
- **Planning-phase styling:** substantive, content-level edits only — **no** cosmetic/visual tweaks
  (ASCII alignment, spacing, wording polish).
- **IaC / doc consistency:** verify any edit touches the right SSOT; regenerate rendered docs
  if the change affects one.

---

## 4. Task workflow (default)

1. `read README.md`
2. read mandatory context §2 (in order)
3. state your environment (`platform-env`) per the global `AGENTS.md`
4. open the owning doc via `docs/index.md`
5. update `todo.md` (pick/register an HD-XX; open a new HD if none exists)
6. implement → `bash scripts/validate-all.sh` green → update `todo.md` + owning `docs/*.md` per
   lifecycle (close-out lives in the owning doc + commit; the frozen changelog/journal are archived)
   → commit signed (if `Couldn't find key in agent`: `ssh-add ~/.ssh/github_signing ~/.ssh/github_auth`, then commit; CONVENTIONS §6)
7. if it's a planned / multi-step / multi-host / live-deploy change → use the **orchestrator pattern**: a single parent session co-ordinates subagents/parallel lanes with an explicit lane map (see pi-subagents skill), and records the runbook in the owning `docs/*.md` — no separate `plan/` ceremony required

---

## 5. Ask-if-unsure checklist (gate)

- Is this a **planned change** worth the orchestrator pattern? (concurrency, multi-host, live-deploy,
  unprovisioned host, irreversibility) — if so, co-ordinate via subagent lanes (pi-subagents) and
  record the runbook in the owning doc, not a throwaway `plan/` folder
- **Deploy-gated** item? Hosts not provisioned yet — verify vs `deployment-tasks.md` before running.
- Re-deciding something? **Check the owning doc + `<domain>-rejected.md` first** (and `git log` on them).
- Unsure which doc owns the area? Ask via `docs/index.md` map.

---

## 6. Context quick-refs

`CONVENTIONS.md` (root) · `docs/index.md` · `IaC/README.md` · [`scripts/README.md`](scripts/README.md) (validators, renderers, vault-seeding utilities) · `todo.md` · archive: `reports/changelog.md`, `reports/deployment-journal.md` (frozen)

---

## 7. For humans / family

> This is the **agent** README. The family-friendly guide lives in **[`readme-humans.md`](readme-humans.md)**
> (Slovenian, `docs/manual/`), and the family launchpad is `kogler.si`.