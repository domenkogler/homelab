# prompt-workflow.md — Task handoff: execute HD-253 session-discipline enforcement

> **Role:** One-shot execution handoff for HD-253 (process/tooling, local only — no live deploy).
> Read once, execute top-to-bottom, then DELETE this file in the closing change (task-handoff
> lifecycle). NOT a standing feed (that's [prompt-journal.md](prompt-journal.md)).
> **Linked from:** [todo.md](todo.md) HD-253 · [README.md](README.md) §0 · [prompt.md](prompt.md)
> traffic-light header · process-improvements-draft.md (source draft, deleted at close-out)

---

## 0. Owner decisions LOCKED 2026-08-26 (do not re-open without explicit new instruction)

1. **Both gates HARD-FAIL** (no warn-only mode). `guard-session.sh` refuses ANY edit-context while
   the primary checkout sits on `main`; `validate-all.sh` hard-fails when run from primary+main+DIRTY.
   Failure output MUST include the literal remediation command with live timestamp:
   `git worktree add ../homelab-wt-YYYYMMDD-HHMM`
2. **No handoff-shrinkage lint.** The diff-rule + review suffice.
3. **Entry-point model:** user ALWAYS starts a session with *"read README.md"* + one free-form
   intent sentence; the AGENT routes via semantic prior-art sweep over todo/changelog/docs incl.
   `-review`/`-rejected`/ `brainstorming/`. NO keyword routing table. Depth markers ("quickly")
   reduce analysis verbosity, NEVER safety ritual. Ambiguous intent → ask ONE clarifying question.
4. **Branch-per-session** becomes an explicit close-out checkbox.

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: git-bash, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Worktree FIRST (dogfood the rule you're implementing):
  `git worktree add ../homelab-wt-$(date +%Y%m%d-%H%M)` on branch `session/hd253-workflow-enforcement`.
- ansible-playbook syntax gate SKIPs on Windows (WSL/CI-gated) — expected SKIP lines are normal.
- Primary checkout is CLEAN except UNTRACKED process-improvements-draft.md — it has already been
  MOVED into your worktree by this handoff's creation commit; do not edit primary.
- main is ahead origin/main by ≥1 commit; pushing is OWNER's call — do not push unless asked.

## 2. Context (read in order, ~10 min)

1. CONVENTIONS.md §6 (worktree rule being mechanized), §4 rows "Validation gate" + "Session
   close-out" (amendment targets), §1 Backlog IDs (derived-pointer ban you're extending).
2. README.md §0–§2 (bootstrap being rewritten into intent-routed sequence).
3. todo.md HD-252 row (§2.4) — sibling incident doc style; ALSO: headscale/headplane lane remains
   SEPARATE (do not fold HD-253 work into any headscale converge).
4. process-improvements-draft.md (tracked now) — the source proposal you're folding; its §5 open
   questions are RESOLVED (see §0 above).
5. prompt.md current handoff — note compressed open-item detail to restore (step ⑦), and the stale
   derived-pointer lesson ("next free = HD-247" typed into prose — never repeat that pattern).
6. scripts/validate-all.sh + scripts/README.md — insertion points for the gate + script doc row.
7. `git show 6c3de9f:prompt.md` vs `./prompt.md` — the regression evidence motivating the diff-rule
   (§3 shrank 11→8 bullet-ish lines; Zipline runbook 5→1 mentions; ride-alongs 4→1).

## 3. Execution plan (top-to-bottom; single commit at end)

① Create the worktree per §1 if not already in one.

② `scripts/guard-session.sh` (new): implement per §0-1 + todo row spec. Detection: primary ⇔
`git rev-parse --git-dir` equals `git rev-parse --git-common-dir`; branch via `--abbrev-ref HEAD`;
detached HEAD / CI → pass-through. On violation print EXACT remediation command with live
`date +%Y%m%d-%H%M` prefilled + `git status --short` + `git log -1 --format='%h %s'` per dirty file.

③ Self-test fixture (`guard-session.sh --self-test`, or scripts/test/ standalone invoked BY
validate-all.sh): simulate primary-main (expect refuse) and worktree-clean (expect pass). Failures
surface through the standard validate-all gate.

④ validate-all.sh integration: invoke the shared check near the top; hard error with remediation
command when primary+main+dirty; clean-main passes silently (merge-station exemption); worktrees
unaffected (branch ≠ main).

⑤ README.md §0 rewrite per §0-3: universal start phrase + intent routing description + step-0
ritual + depth-marker boundary sentence + prior-art-sweep-before-new-HD requirement. Keep §0–§2
context-mandatory language intact (routing changes ORDER/emphasis, not elimination).

⑥ CONVENTIONS.md amendments per §0-4: §6 mechanical-enforcement sentence + primary-definition;
§4 close-out row gains diff-rule bullet, derived-values ban, branch-per-session checkbox. Surgical
row edits — do not restructure tables.

⑦ prompt.md: restore compressed open-item detail listed in the HD-253 row (Zipline compose-header
runbook steps; converge ride-along checks ①②③); add traffic-light lane-claim header block at top
(format: `> **Active lanes:** <none | lane-name — claimed files — since>`); replace any typed
next-free-HD pointer with the derivation instruction.

⑧ Amend process-improvements-draft.md header status line to "folded into HD-253 — scheduled for
deletion at close-out" (it arrives tracked via this handoff's creation commit).

⑨ `bash scripts/validate-all.sh` — must end green (guard self-test included). Byte-check touched
files (UTF-8 / LF-only).

⑩ Single commit on the session branch:
`feat(hd-253): session-discipline enforcement — worktree guard + validate hard-gate + intent-routed start sequence + handoff diff-rule`
(body lists co-updated files + tracked draft).

⑪ Merge back to primary main (--ff-only); remove YOUR worktree via `git worktree remove`; push
only if owner asks.

⑫ Close-out walk (CONVENTIONS §4 Session close-out): no manual/non-Ansible steps expected →
deployment-manual stays untouched; HD-253 row DELETED from todo.md (fully closed, nothing
deploy-gated → housekeeping pattern (a)); DELETE prompt-workflow.md AND `git rm`
process-improvements-draft.md in the SAME closing commit; rewrite prompt.md to post-state
(next-session pointer = whatever you queue next, derived from todo.md).

## 4. Working rules (binding)

- Fresh worktree per session (you're IN one — stay in it); primary = merge station only.
- No secrets involved in this task; if any probe ever touches one, print lengths/hashes only.
- English prose; relative links; new docs start with `> **Role:**` + `> **Linked from:**`.
- Don't chase cosmetic tweaks beyond the listed targets.
- Coordination: headscale/headplane lane untouched (HD-252 owns that bugfix; separate execution).
  If primary is dirty with foreign WIP when you start: STOP, coordinate, never stash others' work.
