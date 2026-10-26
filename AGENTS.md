# AGENTS.md — working contract for this repository

> **Role:** the one-page contract for an AI agent that did not start by reading `README.md`. A mirror, not
> the source: the opening sections of `README.md` are the bootstrap and carry the ritual, `CONVENTIONS.md`
> is the binding rule set and every rule below cites it.
> **Linked from:** `README.md` (context quick-refs), `docs/index.md`

Start with `bash scripts/validate-all.sh` in mind: it is the verdict you must be green against, and some
of its lines are **reminders that never fail the run** (§6.4) — those are yours to clear when your own
change added them.

1. **Docs state facts; commits state what changed.** No changelog entries, no session narrative, no values
   that describe a state that no longer exists. A sentence that reports an **event** — what a session did,
   found or measured, and when — belongs to the commit message, because **git is the only changelog this repo
   keeps**. Dates are kept when the date IS state — expiry, renewal, firmware date, and a `live-verified` /
   as-built marker, where the date is the information. Clear a finding by rewriting the sentence as a fact
   or cutting it, never by deleting a date and keeping the story. → [`CONVENTIONS.md`](CONVENTIONS.md) §6,
   §6.4
2. **A ticket id is a pointer, not provenance.** An `HD-<n>` / `KOPS-<n>` mention may stand in a doc only
   while its `todo.md` row still exists; when the row closes it is deleted, and the mention leaves in the
   same change. → §6, §4
3. **Every session gets its own worktree** named `../homelab-wt-<date>-<HHMM>` before touching a file, and
   the primary checkout is a merge station only — never edit it on `main`. Manage your own worktree with
   `git worktree add` / `remove`, never `rm`/move one. → §6
4. **Values live in IaC.** `group_vars` / `host_vars` / `rack-connections.json` are the SSOT; a
   `*-generated.md` file is a render view — regenerate it, never hand-edit it, and never parse it from a
   script. → §2, §8.2, §8.5
5. **Secrets are 1Password references**, never literals, and a probe prints lengths, prefixes, item ids or
   hashes — never a value. → §3, [`docs/1password.md`](docs/1password.md)
6. **Do not re-decide anything alone.** Read the owning doc and `<domain>-rejected.md`, then
   `git log -S 'HD-…'`, before proposing a decision; an answered question leaves no `Options` section
   behind. → §8.3
7. **Validate before finishing:** `bash scripts/validate-all.sh` green, then commit with a plain
   `git commit` (signing is retired — never `git commit -s`). → §6
8. **Work in a worktree-sized piece.** Delegation to bounded subagent lanes is the default for
   multi-host / multi-step work, ≤2 children at a time, on the parent's own model; a silent child is a
   compacting child, not a hung one. → §6, [`docs/orchestration.md`](docs/orchestration.md) §4 (O1–O11)

`README.md` §0 (session ritual), `CONVENTIONS.md` §5 (service onboarding), `docs/index.md` (which doc owns
your task), `todo.md` (the queue), `deployment-tasks.md` (the ledger — what is actually live).
