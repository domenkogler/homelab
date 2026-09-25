# `prompt-417.md` — Lane brief · two cheap gates for failure classes no validator can see (HD-417 · HD-404 · HD-248 · HD-396)

> **Role:** the **repo-hygiene lane**: a markdown-table integrity gate, the last stale IaC strings, one false banner,
> and one repo-archaeology question. No host risk, no converge. **Wave 5 — it runs alone**, with no other lane live.
> Start with [README.md](README.md) §0 → §1 mandatory context → [prompt.md](prompt.md) **§4 (orchestrator mode)** →
> this file → the rows in [todo.md](todo.md) §2.
> **Linked from:** [prompt.md](prompt.md) §2 + §4 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
>
> **Lane contract (orchestrator mode — the authority is [prompt.md](prompt.md) §4, which OVERRIDES parts of
> README §4 and CONVENTIONS §6 at items O1–O8; where §4 is silent, README + CONVENTIONS stand and outrank this
> brief).** One session, one worktree, one branch; the parent creates them (`../homelab-wt-<YYYYMMDD>-<HHMM>` /
> `session/417-gates-<YYYYMMDD>-<HHMM>`). **You converge nothing.** Owner gate → park and continue (O4).
> **The one O2 exception, stated because this row's own deliverable needs it:** the HD-417 sweep may reformat table
> **cells** in `todo-table.md` and `prompt.md` (a `|` inside a cell is the bug), but it changes **no dispatch state,
> no row list, no wave table, no link target** in those two files — the content stays the orchestrator's (O2). That
> is why this lane is **alone**: if any other lane is live, do not start this brief.

## Rows

| # | HD | Action | Gate / note |
|---|----|--------|-------------|
| 1 | **HD-417** | A **markdown table-integrity gate**: split cells on unescaped pipes, compare the count against the header row, fail with file + line — plus the **escape convention** (`\|` in cells) and the **one-time legacy sweep** that makes the gate green on day one | Two real misses in one session, both passing every gate: a swallowed newline merged two registry rows, and a `a\|b\|c` description widened a 3-cell row to 12. ⚠ legacy rows quote pipes **legitimately** — the sweep is the work, not the check. Add the gate to `validate-all.sh` and give it a **self-test fixture** (a test that cannot fail is not evidence, CONVENTIONS §6) |
| 2 | **HD-404** | The enumerated text-only pass over six stale IaC strings/comments: Victoria-vs-Prometheus headers, the Pi "primary DNS" comment, the `llm-backend` purpose string **that feeds a generated doc**, `amd_rocm`'s `OLLAMA_KEEP_ALIVE`, the Pi image wording in `first-boot-config.sh`, the `tailnet-apps` overlay comment | No converge risk, but the `llm-backend` purpose string **feeds `network-addresses-generated.md`** → edit the vars/purpose strings and **re-render**, never the generated file (the HD-404 rule). The docs stopped repeating these; the comments are the last place an agent reads a wrong truth · [deployment-ansible.md](docs/deployment-ansible.md) |
| 3 | **HD-248** | Correct the stale **"Open WebUI ×2 live"** banner in [services-ai.md](docs/services-ai.md) and **stop there** | **Decided 2026-09-21: no second instance.** The split stays planned until a second audience exists — building it today duplicates a service that does not run |
| 4 | **HD-396** | ✅ **answered 2026-09-25 by the parent while the brief was idle — the runner does not exist**, so the Phase 0/5 prerequisite lines were rewritten to say the phase must build a runner before it can hold a secret | Five measurements are in [deployment-tasks.md](deployment-tasks.md) §Vault inventory + Phase 5 and the consumer map in [docs/deployment-ai-stack-secrets.md](docs/deployment-ai-stack-secrets.md) §4a |

## ⛔ No-re-decide list

* **The OWUI split is decided-off** (2026-09-21, [services-rejected.md](docs/services-rejected.md)) — row 3 is a
  wording fix, not an architecture task.
* **`docs/` is wished-state only** and `deployment-manual.md` is imperative procedure only — the two doc-role
  contracts are gated (`check_runbook_purity.py`, `check_doc_map.py`). Do not "fix" a stale string by adding dated
  narrative next to it.
* **The generated docs stay generated**; the vault is `Homelab-ansible` only.

## First action

Write the failing case **first**: a fixture row with an unescaped `|` in a cell and a swallowed-newline row merge, then
the checker that catches both, then the sweep. A gate added after the sweep cannot be proven to have worked.

## Lane rules (Wave 5 — **alone**, no sibling)

* **Owns:** `scripts/check_*.py`, `scripts/validate-all.sh`, `scripts/testdata/**` (fixtures), `CONVENTIONS.md` §6
  (the escape convention), the six named IaC strings/comments, `deployment-tasks.md` **only** for HD-396's stale
  prerequisite lines, `docs/**` **for the sweep only**, and **your own `todo.md` rows**.
* **Never touches:** dispatch content in `prompt.md` / `todo-table.md` (the exception above), any `IaC` **behaviour**
  (no vars that change a rendered service — this lane is strings and gates), `roles/**` task logic, live hosts.
* ⛔ **Alone.** Its sweep edits every doc, so it conflicts with any live lane **by construction**. If the parent has
  another lane open, this brief does not launch.

## Acceptance

The new gate **fails on purpose-built bad tables and passes on the swept repo** (show both, plus the self-test wired
into `validate-all.sh`) · the six strings are gone and any generated doc they feed is re-rendered · the banner matches
the box · HD-396 has a fact and the ledger reflects it · closed rows deleted · `bash scripts/validate-all.sh` green
**in this worktree** → **stop** ([prompt.md](prompt.md) §4).
