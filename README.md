# Kogler Homelab — AI Bootstrap

> **Role:** AI session bootstrap. Read at the start of EVERY coding/agent task. Absolute map to the
> mandatory context + the repo's working contract for agents.
> **Linked from:** `readme-humans.md` (the human/family guide) & `AGENTS.md` guidance.
> **Scope note:** a `prompt-*.md` handoff may supersede this by naming its own context — this file is
> the base, handoff files extend it.

---

## 0. How to use this file

A new task starts with: **"read README.md, then <task>"**. This file is the bootstrapper; it points to
the mandatory context that carries all background so the task needs no extra briefing.
Read §1 below, then §2 mandatory context **in order**. After §2, use `docs/index.md` → "Which Document
to Read First" for task-specific dispatch. Do **not** bulk-read the repo.

---

## 1. Mandatory context (read every session, in this order)

| # | File | Role | Read when |
|---|------|------|-----------|
| 1 | [`CONVENTIONS.md`](CONVENTIONS.md) | Cross-cutting rules index — naming, secrets, SSOT, IaC, lifecycle, service-onboarding (§5) | always — every rule is binding |
| 2 | [`docs/index.md`](docs/index.md) | AI dispatcher / document map — which owning doc to open for your task | always |
| 3 | [`IaC/README.md`](IaC/README.md) | Ansible implementation spec — roles, templates, layout, build order, status | any IaC / compose / template work |
| 4 | [`todo.md`](todo.md) | Backlog + open decisions; §0 lifecycle (HD-XX); pick up or register work | always, before every task |
| 5 | [`changelog.md`](changelog.md) | Decision log + done work — decision-log SSOT | before re-deciding / re-implementing anything |

> A resolved/dropped decision lives in `changelog.md` **only** — never re-decide without checking it
> (`todo.md` §1 is the compact open-decisions pointer).

---

## 2. State of the world (as of 2026-08-20)

- **Planning phase — nothing is deployed live yet.** VPS bought + provisioned; home hosts
  (`oldsrv`, `nas`, `pi`) unprovisioned. Do **not** assume live behavior; treat every deploy as
  *deploy-gated*. Verify against `deployment-tasks.md` before any "run".
- **Hosts:** single namespace `kogler.si` → `oldsrv`, `nas`, `pi`, `router`, `switch`, `vps`.
  Canonical list + naming/IP conventions: `docs/index.md` → Conventions.
- **Recommended next tasks:** see the latest `prompt-*.md` handoff (date-stamped) — it names the
  current most-valuable, laptop-doable items.

---

## 3. Non-negotiables (repo contract for agents)

- **Validate before finishing:** run **`bash scripts/validate-all.sh`** — must end green.
  Fail-closed linters (`check_doc_map.py`) break validation on a stale map link.
- **SSOT direction:** values live in IaC (`group_vars/*.yml`, `host_vars/*.yml`,
  `rack-connections.json`). Generated `*-generated.md` docs are render views — **never hand-edit**
  them, and scripts never parse generated MD.
- **Secrets:** never literal in docs / group_vars / templates — always 1Password `Homelab` vault
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
6. implement → `bash scripts/validate-all.sh` green → update `todo.md` / `changelog.md` per lifecycle
7. if it's a planned / multi-step / multi-host / live-deploy change → produce a `plan/` (plan-task)
   and honor its `## Environment` note

---

## 5. Ask-if-unsure checklist (gate)

- Is this a **planned change** worth `plan-task`? (concurrency, multi-host, live-deploy,
  unprovisioned host, irreversibility)
- **Deploy-gated** item? Hosts not provisioned yet — verify vs `deployment-tasks.md` before running.
- Re-deciding something? **Read `changelog.md` first.**
- Unsure which doc owns the area? Ask via `docs/index.md` map.

---

## 6. Context quick-refs

`CONVENTIONS.md` (root) · `docs/index.md` · `IaC/README.md` · `todo.md` · `changelog.md`

---

## 7. For humans / family

> This is the **agent** README. The family-friendly guide lives in **[`readme-humans.md`](readme-humans.md)**
> (Slovenian, `docs/manual/`), and the family launchpad is `kogler.si`.