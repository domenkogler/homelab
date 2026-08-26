# Proposed process improvements — AI v2 session review (2026-08-26)

> **Role:** Owner-review draft. Three defects surfaced during the 2026-08-26 AI v2 session:
> (1) edits happened on `main` without a session worktree (CONVENTIONS §6 violation, by BOTH
> sessions); (2) `prompt.md` was rewritten from scratch → dropped existing open items (handoff
> regression); (3) three entry points (README.md / prompt.md / prompt-journal.md) were used
> inconsistently → state fragmentation. This file proposes concrete, mechanical fixes.
> **Status:** folded into HD-253 — scheduled for deletion at close-out (owner decisions locked 2026-08-26, see [prompt-workflow.md](prompt-workflow.md); audit-report lifecycle §4).

---

## 1. Make the worktree rule mechanical (CONVENTIONS §6 enforcement)

The rule text is clear ("every session … before touching any file … merge back only committed,
green results, primary checkout untouched"). It is not **enforced**. Two cheap gates:

### 1a. Pre-edit guard — `scripts/guard-session.sh` (new)
Aborts with a clear message when:
- `git rev-parse --abbrev-ref HEAD` == `main` **AND** working tree is dirty, **OR**
- HEAD == `main` and the user is about to edit (fail-closed by default; `--force` override for
  one-off admin fixes with explicit reason).

Wire it into the workflow: run before any edit / first tool call that writes a repo file.
Also add it as the **first step** of the README "How to start a session" sequence.

### 1b. Validation gate — `validate-all.sh` addition
`validate-all.sh` already runs before every commit. Add a **warning** (not a hard fail, to avoid
breaking legitimate single-session cases) when it runs from a **dirty `main`**:
`WARN: running from a dirty main checkout — CONVENTIONS §6 expects a session worktree/branch`.
Hard-fail only when a `--strict` flag is passed (mirrors the check-vault-items `--strict`
pattern, HD-245).

---

## 2. prompt.md handoff — diff, never rewrite (regression fix)

The #17 rewrite dropped open items (`opencloud-collab_password` window, Zipline runbook steps,
HD-246 detail, ride-along checks). Rule to add (CONVENTIONS §"Session close-out" / README):

> **A new prompt.md handoff is produced by EDITING the previous one — never by writing a fresh
> file from scratch.** The previous handoff's §2/§3 open items MUST all appear (or be explicitly
> resolved) in the new §2/§3. A good check: `git diff <prev-handoff> <new-handoff>` should show
> *additions/changes of status*, not *wholesale deletion* of items.

Optionally add a tiny lint (part of `validate-all.sh` or a doc check) that fails if the new
handoff's open-item list shrinks below the previous one's by more than a threshold — but that's
hard to make non-noisy; the diff rule may be enough.

---

## 3. Single session-start sequence — collapse the three entry points

Keep all three files (they each serve a purpose), but **document one canonical order** so the
multiplicity stops being a trap. Proposed addition to README §"How to use this file":

```
HOW A SESSION STARTS (canonical order — READ ONCE, THEN ACT):
  1. `git worktree add ../homelab-wt-<date>-<HHMM>`   (isolation first, CONVENTIONS §6)
  2. Read `prompt.md` (the CURRENT handoff) — NOT README — unless you are starting a brand-new
     topic that supersedes it (then mint a new dated `prompt-<slug>.md` and say so).
  3. Drain `prompt-journal.md` (raw notes) into prompt.md / owning docs / an HD row; clear it.
  4. Claim an HD row in `todo.md` (new work = new HD; never edit todo.md on main).
  5. README.md is the static gate only — re-read §0–§2 for context, never as a task queue.
```

Role split made explicit (mirrors CONVENTIONS):
| File | Role | When touched |
|------|------|--------------|
| README.md | Static bootstrapper / gate | Session start (context), never state |
| prompt.md | **The one live handoff** (latest only, diff-maintained) | Every session close |
| prompt-journal.md | Human raw-notes feed — drained to zero each session | Human quick notes only |

---

## 4. Bonus (optional, low-priority)

- **Branch-per-session as a hard convention** (even if worktree is skipped, branch is mandatory):
  `session/<slug>-<date>`; merge to main only green+committed. The §6 text already implies this
  ("merge back only committed"); make it an explicit checkbox in the close-out checklist.
- If a remote with branch protection ever becomes the norm (Forgejo), main-protect + PR-only
  would be the strongest variant (option D from the earlier review).

---

## 5. Open questions for owner

1. Approve 1a/1b (guard + validate warning)? Prefer strict-fail or warn-only?
2. Approve §2 diff rule? Add the lint or rely on discipline?
3. Approve §3 canonical sequence? Where should it live — README §"How to use", CONVENTIONS, or both?
4. Any of §4 worth taking now?
