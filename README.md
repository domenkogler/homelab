# Kogler Homelab — AI Bootstrap

> **Role:** AI session bootstrap. Read at the start of EVERY coding/agent task. Absolute map to the
> mandatory context + the repo's working contract for agents.
> **Linked from:** `readme-humans.md` (the human/family guide) & `AGENTS.md` guidance.
> **Scope note:** a `prompt-*.md` handoff may supersede this by naming its own context — this file is
> the base, handoff files extend it.

---

## 0. How every session starts (intent-routed)

The human ALWAYS starts a session with the universal phrase **"read README.md"** followed by ONE
free-form intent sentence (e.g. *"read README.md — zipline uploads stopped working"*). This file
is the bootstrapper; it carries all background so the intent sentence needs no extra briefing.
The agent then routes the intent — there is NO keyword routing table:

1. **Step-0 ritual, UNCONDITIONAL, in this order:**
   1. **Conventions map — the FIRST command of the session, before any file is opened:**
      `grep -n "^#\|^## \|^### " CONVENTIONS.md | head -40`
      Every rule in this repo is cited by section number (§5 onboarding, §6 worktrees, §8.3
      rejected-check), so without the printed outline a citation is not actionable and the file
      gets bulk-read to find what §N means. Read the cited section in full, then all of
      `CONVENTIONS.md` (§1 row 1) — the map is the entry point, never a substitute for the rules.
      It is cheap and it is mandatory on every task, however trivial (depth markers in 3 below
      trim analysis verbosity, never the safety ritual).
   2. `git status` sanity check + fresh session worktree (`../homelab-wt-<date>-<HHMM>`,
      CONVENTIONS §6) BEFORE any edit — enforced mechanically by
      [`scripts/gate/guard-session.sh`](scripts/gate/guard-session.sh) + a hard gate inside
      [`scripts/validate-all.sh`](scripts/validate-all.sh).
2. **Semantic prior-art sweep:** search todo.md / docs/ — including the `<domain>-rejected.md`
   decision logs, `<domain>-review.md` and `brainstorming/` — plus `git log -S 'HD-XX'` / `git log`
   on the owning doc, and REPORT the prior art found BEFORE proposing any new HD row (side-effect:
   enforces the §8.3 rejected-check and the decision-log re-decide ban; the frozen
   `reports/changelog.md`/`reports/deployment-journal.md` are archive-only).
3. **Depth markers** ("quickly", "just do X") reduce ANALYSIS verbosity only — NEVER safety ritual
   (worktree, validate-all, owning-doc/lifecycle discipline always applies).
4. **Ambiguous intent → ask exactly ONE clarifying question**, then proceed.

Routing changes ORDER/emphasis only — it never eliminates context. Read the §1 mandatory context
table **in order**. After it, use `docs/index.md` → "Which Document to Read First" for
task-specific dispatch. Do **not** bulk-read the repo.

---

## 1. Mandatory context (read every session, in this order)

| # | File | Role | Read when |
|---|------|------|-----------|
| 1 | [`CONVENTIONS.md`](CONVENTIONS.md) | Cross-cutting rules index — naming, secrets, SSOT, IaC, lifecycle, service-onboarding (§5) | always — every rule is binding; enter it with the §0 step-1 outline grep, then read in full |
| 2 | [`docs/index.md`](docs/index.md) | AI dispatcher / document map — which owning doc to open for your task | always |
| 3 | [`IaC/README.md`](IaC/README.md) | Ansible implementation spec — roles, templates, layout, build order, status | any IaC / compose / template work |
| 4 | [`todo.md`](todo.md) | Backlog + open decisions; §0 lifecycle (HD-XX); pick up or register work. **Rows hold what is missing + how to do it; durable knowledge lives in the owning doc the row links; a finished row is deleted** | always, before every task |
| 5 | [`scripts/README.md`](scripts/README.md) | tools and scripts | always, before every task |

> **Decisions** live in the owning doc + the `<domain>-rejected.md` decision log (append-only, per
> domain) — never re-decide without checking those + `git log -S 'HD-…'`. Historical rows live in
> the frozen `reports/changelog.md` (archive-only).

---

## 2. State of the world (as of the `todo.md` rows — verify against [`deployment-tasks.md`](deployment-tasks.md))

> **This section is not a status log.** It states the phase verdict and points at the evidence; it does
> not accumulate dated per-HD narration. A session that verifies live state edits the owning doc's ✅
> status line and ticks the [`deployment-tasks.md`](deployment-tasks.md) checkbox — never this file
> (CONVENTIONS §4: as-built evidence is the owning doc + the commit, progress is the ledger).

- **Phase verdicts — every phase is live.** **Phase 1 (VPS edge)** runs its full enabled
  `docker_services` set — Traefik, Authentik, the observability backend, Technitium DNS primary, etc.
  **Phase 2 (nas)** and **Phase 4 (Pi)** are provisioned + live; **Phase 3 (oldsrv)** is complete +
  live. Evidence, in this order: the owning-service docs' ✅ status lines + the
  [`deployment-tasks.md`](deployment-tasks.md) checkbox dates + the git commit messages; the as-built
  journal and changelog were frozen 2026-09-01 (`reports/`, archive-only). Anything still owed is
  owner-manual or already a `todo.md` row; verify live-state evidence against
  [`deployment-tasks.md`](deployment-tasks.md) before any "run".
- **How to check what is live vs authored-only (check in this order):**
  1. [`todo.md`](todo.md) §0/§3c → [`deployment-tasks.md`](deployment-tasks.md) — the ⏳ deploy-gated
     verification checklist per phase (checkbox + date when done).
  2. Owning-service docs (`docs/services-*.md`, hardware docs) ✅ status lines + `git log` on them —
     the dated live-verified evidence.
  3. Doc status banners (`🟢 IaC done, not yet live — ⏳ deploy-gated`) are **hints, not proof** —
     trust the owning-doc ✅ lines + deployment-tasks ticks over banners until the docs catch up.
- **Hosts:** single namespace `kogler.si` → `oldsrv`, `spark`, `nas`, `pi`, `router`, `switch`, `vps`.
  Canonical list + naming/IP conventions: `docs/index.md` → Conventions. **All of them are provisioned**,
  including the last arrival: the Lenovo ThinkStation PGX (`spark.kogler.si`), the headless NVIDIA GB10
  inference node that replaced the old Phase-2 Ryzen/Proxmox plan, is a **live first-class IaC host** beside
  `nas`/`oldsrv`/`vps`/`pi` — state and evidence in [`docs/hardware-spark.md`](docs/hardware-spark.md) and the
  [`deployment-tasks.md`](deployment-tasks.md) Phase 4b ticks; the legs still open on it are row HD-335.
- **Recommended next tasks:** see the latest date-stamped `prompt-*.md` handoff — it names the current
  most-valuable, laptop-doable items. **Handoff family:** `prompt.md` is the standing handoff;
  `prompt-<domain>.md` files are **single-lane briefs** (one lane session each, named for the domain +
  host, never for an HD id — CONVENTIONS §6), referenced from their `todo.md` rows and indexed in the
  [`todo-table.md`](todo-table.md) §B0 lane map; a brief dies with its lane (O7) and any small residue
  folds back into the rows — read those. The ruled network items stay as facts, not as dated results:
  the Wi-Fi model is **3 SSIDs with per-device cloud-IoT WAN egress**
  ([`docs/network-vlans.md`](docs/network-vlans.md) §CAPsMAN SSID-to-VLAN Mapping) and the DNS tier is
  **three live seeded instances**, whose public `:53` publish is source-restricted at the nftables
  FORWARD chain ([`docs/network-dns.md`](docs/network-dns.md) §Recursion + exposure controls).

---

## 3. Non-negotiables (repo contract for agents)

- **Validate before finishing:** run **`bash scripts/validate-all.sh`** — must end green.
  Fail-closed linters (`check_doc_map.py`) break validation on a stale map link.
- **SSOT direction:** values live in IaC (`group_vars/*.yml`, `host_vars/*.yml`,
  `rack-connections.json`). Generated `*-generated.md` docs are render views — **never hand-edit**
  them, and scripts never parse generated MD.
- **Secrets:** never literal in docs / group_vars / templates — always 1Password `Homelab-ansible` vault
  refs (or the `Private` vault — [docs/1password.md](docs/1password.md)). **Fail-loud**: no `default('')`.
- **Language / links:** English (technical); Slovenian only for `docs/manual/` (family). Relative
  `.md` links. Every doc starts with `> **Role:**` / `> **Linked from:**`.
- **Planning-phase styling:** substantive, content-level edits only — **no** cosmetic/visual tweaks
  (ASCII alignment, spacing, wording polish).
- **IaC / doc consistency:** verify any edit touches the right SSOT; regenerate rendered docs
  if the change affects one.

---

## 4. Task workflow (default)

1. `read README.md` — run the §0 step-1 conventions-map grep first
2. read mandatory context §1 (in order)
3. state your environment (`platform-env`) per the global `AGENTS.md`
4. open the owning doc via `docs/index.md`
5. update `todo.md` (pick/register an HD-XX; open a new HD if none exists)
6. implement → `bash scripts/validate-all.sh` green → update `todo.md` + owning `docs/*.md` per
   lifecycle (the finding/✅ goes to the doc, the row keeps only the remaining `⏳` items and shrinks;
   close-out record = owning doc + commit; the frozen changelog/journal are archived)
   → commit — **plain `git commit`, signing is retired (HD-1116, 2026-10-08): `commit.gpgsign=false`, never
     `git commit -s` (that adds a `Signed-off-by` trailer, it signs nothing), and `%G?` → `N` is the expected
     value, not a failure; CONVENTIONS §6**

> **Live converges run DETACHED:** a full `docker_services` converge
> takes **10–30+ min** and must be launched with `nohup … &` + a log file, then polled — a foreground
> run behind an outer timeout gets killed **mid-restart**, leaving sibling containers `Exited` and the
> next run's restart guard failing (`cannot join network namespace of a non running container`, live
> evidence: VPS `tailscale-sidecar Exited (128)` after a `timeout 600` kill). Re-running the same
> playbook is idempotent (the guard restarts the stack cleanly once siblings are up). `--check` is the
> only safe foreground form. See `scripts/README.md` Notes & conventions for the exact incantation.
7. if it's a planned / multi-step / multi-host / live-deploy change → use the **orchestrator pattern**: a single parent session co-ordinates subagents/parallel lanes with an explicit lane map (see pi-subagents skill), and records the runbook in the owning `docs/*.md` — no separate `plan/` ceremony required. **Delegation is the default here, not an escalation** (CONVENTIONS §6, [docs/orchestration.md](docs/orchestration.md) §4 O10): the parent launches, reads evidence, merges and validates; the children read, analyse and write.
8. **the runbook is for what the AI cannot do — everything else belongs to its owning doc.** `deployment-manual.md` carries the steps a human must perform and a from-scratch rebuild cannot recover without: first accounts on devices and services, physical console/reseat/label work, and anything gated on a human-held credential. **If the AI can do it, it does not go in the runbook** — automated behaviour lives in IaC, and repeatable procedure + failure semantics live in the owning `docs/*.md`. A session that *ran* a check writes those lines where they are read, not into the runbook: "this session performed it" is not what makes a step runbook material (HD-450, 2026-09-23: a cert-pull health check the session ran over SSH was briefly added here for exactly that wrong reason). Ownership still follows the action for the human-only steps: the imperative line is written **in the same change, by the session that did it** (the lane briefs assign files to avoid two writers, and that root file was assigned to nobody — which is how owed procedure quietly belongs to everybody). The runbook is procedure, not a diary (CONVENTIONS §6.4)

### Orchestrator + reviewer discipline (lane hygiene)

> **Two different things, one word.** Everything in this section is about **subagent children inside one session**.
> Running **independent lane sessions** — one [`prompt-<domain>.md`](prompt.md) brief per session, each with its own
> worktree and branch, then merged and cleaned up by a parent — is governed by
> [docs/orchestration.md](docs/orchestration.md) **§4 (Orchestrator mode)** (moved out of `prompt.md`
> 2026-09-28), whose rules **deliberately differ from README §4 and
> CONVENTIONS §6** at the items it numbers O1–O11 (fast-forward vs rebase, who may write `prompt.md` /
> `todo-table.md`, per-directory converge slots, park-instead-of-stop on owner gates, who deletes a brief, and
> the child-lane contract O10–O11). Where §4 is silent, this README and CONVENTIONS stand and outrank any brief.

When co-ordinating subagent lanes (item 7), keep children **bounded and focused** — an over-scoped,
verbose child is worse than none. Live lesson (2026-09-08): a `reviewer` handed two full IaC branches
+ the whole render pipeline + todo claims, on a thinking-heavy model, ran 35+ min and never produced
a verdict — the parent had already verified the final state itself. Rules:

- **Scope each child to ONE deliverable** with an explicit acceptance micro-format. For a reviewer:
  `APPROVE / REQUEST_CHANGES` + a bounded list (`blocking` / `non-blocking`), file:line where useful.
  Say what is **out of scope** (e.g. "do not re-audit the render pipeline — it is known-good").
- **Give the reviewer the parent's verification notes**: the parent holds authority; a pre-merge review
  is a second opinion, not a fresh audit. State "the parent has already verified X, Y, Z — confirm or
  flag only what contradicts."
- **Silence is not a hang, and the parent does not race the child** — the retired clock-based
  steer-or-abort timer is wrong on a locally-served model, where a child compacts for minutes at ~11 tok/s. Run ≤2 children
  concurrently, async, on a 2 h deadline, on the parent's own model: the numbers, the reasoning and where each
  is set are [docs/orchestration.md](docs/orchestration.md) §4's child-lane contract (O10–O11). Steer on a
  needs-attention notice or a repeated tool failure — never on quiet.
- **Prefer fresh-context single-purpose children** over broad multi-commit audits; if a review is big,
  split it per commit/branch and run them in parallel.
- Keep the parent as arbiter: children implement/review within their lane; the parent merges,
  runs `validate-all.sh`, records the runbook, and owns final acceptance — and by default it does **not**
  perform the implementation or the analysis itself (O10). A parent that investigates the tree to decide what
  to delegate has paid for the work twice.

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

>
> **Away from home (mobile hotspot / public Wi-Fi)?** SSH to LAN nodes goes through the VPS jump; service
> traffic goes through the tailnet edge. The measured per-node matrix, what is broken today (`nas`,
> oldsrv's management leg) and the three traps: [docs/network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away.
`CONVENTIONS.md` (root) · `docs/index.md` · `IaC/README.md` · [`scripts/README.md`](scripts/README.md) (validators, renderers, vault-seeding utilities) · `todo.md` · archive: `reports/changelog.md`, `reports/deployment-journal.md` (frozen)

**Ansible questions — answer them without bulk-reading the tree.** §0 says *do not bulk-read the
repo*; [`scripts/ansible/ansible_query.py`](scripts/ansible/ansible_query.py) is how that is done for Ansible. Read-only,
bounded digest over `IaC/ansible` (`--root spark` for the other tree), needs `~/ansible-venv`:

| Question | Command |
|---|---|
| Where is this variable set, and does anything read it? | `--var <name>` — definitions in **precedence order** with the winner marked, incl. **bare** Jinja in `when:` / `assert: that:` and `{% %}` inside `.j2` |
| Which roles/tasks use a module, or what does a role contain? | `--module <name>` · `--role <role>` |
| Does every `notify:` reach a handler? | `--handlers --unresolved` (exit 1 when one does not) |
| Which 1Password items does IaC read? | `--vault` — item/field **names** + file:line only, never a value (§6) |
| Search Jinja expressions only (no YAML noise) | `--jinja '<regex>'` · discovery: `--list-vars`, `--context` |

---

## 7. For humans / family

> This is the **agent** README. The family-friendly guide lives in **[`readme-humans.md`](readme-humans.md)**
> (Slovenian, `docs/manual/`), and the family launchpad is `kogler.si`.