# prompt-journal — standing handoff: human input → deployment-journal entry

> **Role:** Standing feed file for [`deployment-journal.md`](deployment-journal.md). The human pastes raw
> notes into the **DATA** block below; the AI session converts them into a proper append-only journal entry,
> ticks the plan, closes any gates the step satisfies, validates, commits, and clears this DATA block.
> Never delete this file (unlike task `prompt-hd*.md` handoffs) — it is reused for every deploy action.
> **Linked from:** [deployment-journal.md](deployment-journal.md), [deployment-tasks.md](deployment-tasks.md)

---

## AI instructions (execute top-to-bottom when this file's DATA block is non-empty)

1. Read `deployment-journal.md` **Rules** first — they define entry format, ordering, secret policy.
2. Determine the **Phase + step** from the DATA (Phase numbering = `deployment-tasks.md`). If ambiguous,
   pick the most likely and say so in the commit message rather than blocking.
3. Append a **new `###` entry at the bottom of that phase's section** in `deployment-journal.md`
   (chronological order — never insert above older entries):
   - title `### YYYY-MM-DD — Phase X.Y · <short what>` (today's date; add `[MANUAL]` if human-executed);
   - **commands as run** verbatim in fenced ```bash blocks (clean up shell prompts, keep flags);
   - **settings chosen** as bullet values; **secrets** by `<item>.<field>` name ONLY, never values;
   - **verification evidence**: short output snippets the DATA contains (`zpool status`, `sshd -T`, HTTP codes…);
   - **deviations** from `deployment-tasks.md` / owning docs, each ending with `(doc updated: <file>)` if you
     fixed the doc in this same change (promotion loop — required when the divergence is permanent).
4. Tick the matching checkbox in `deployment-tasks.md` (`- [x]` + date; add `**[MANUAL]**` if missing).
   If the plan step isn't checkbox-formatted yet, convert that step to `- [x]` form while ticking.
5. If the step closes a deploy-gated item: trim/update the todo.md `⏳` tail and the owning-doc status
   block (🔴→🟢→✅) in the same change.
6. Run `bash scripts/validate-all.sh` — must end green.
7. Commit everything as one change: `journal: Phase X.Y · <slug>` (+ co-updated files listed).
8. **Clear the DATA block** back to the empty placeholder below, then commit that reset separately
   (`journal-feed: data consumed`) — git history preserves the raw input via the journal entry itself.

If the DATA is too vague to journal safely: make the best-effort entry, mark unknowns `⚠ not captured`,
and list your open questions at the top of the commit message for the human to answer in the next feed.

---

## DATA (human fills — raw notes, pasted outputs, half-sentences; any format goes)

<!-- Fill between the markers, then tell the AI session: "read prompt-journal.md".
     Useful things to dump: what you did, terminal output, panel settings, dates,
     what broke, what you decided differently than the docs say. Secrets: names only! -->

<!-- end of data -->

