# Self-learning: turning an env failure into a durable rule

The platform docs (`windows11.md`, `debian.md`) are **living reference**.
When a resolved environment failure teaches something not already recorded, it
belongs in the doc so future sessions don't repeat it. This is how the skill
improves itself — with human sign-off.

## When a failure qualifies

An environment symptom looks like (exit != 0 plus) one of:
- Path: `ENOENT`/`not found` on a path that should exist; wrong `\` vs `/`;
  git-bash mangling a leading `/` or a `D:\` drive; missing extension.
- Separator/quoting: drive-letter `:` misread as a URI; spaces unquoted.
- Shell grammar: `&&` invalid on Windows PowerShell 5.1; `%VAR%` vs `$env:VAR`;
  `where` used where `which` expected (or vice versa).
- Interpreter: `python` (Store alias) or `python3` absent on the wrong OS;
  `py` not available on Debian.
- Encoding: `UnicodeDecodeError`, `SyntaxError: Non-UTF-8`, cp1252 garbage.
- Line endings: CRLF where LF expected (or diff/validator flakiness).

## Confirm it is environmental (not task logic)

Ask: *would this have failed the same way on any OS, given the same task?* If
yes it's a task/validation problem — **do not** record it here. Only record
when the fix was a platform-specific adjustment (a different path form, an
interpreter, an encoding read, a shell construct).

## Procedure

1. **Diagnose** the failure; identify the platform rule that, if followed,
   would have avoided it.
2. **Fix the immediate command** per the existing rules (don't invent anything).
3. **Check the matching doc** (`windows11.md` / `debian.md`). If the rule is
   already there, you're done (and note that the failure was a *failure to
   apply*, which is a prompt problem, not a doc gap).
4. If the rule is **missing or underspecified**, **propose** a one-line edit to
   the human: the concrete symptom + the fix, and the section to place it in.
   - Format: `- <symptom> → <fix> (when <condition>)`.
   - Place it in the relevant section; if it doesn't fit a section, append under
     `## Self-learned on this host`.
5. **On approval**, apply the edit. If rejected, don't apply.
6. **Prune**: when adding, drop older entries that are now covered by the rest
   of the doc, so the file doesn't bloat with repeated lessons.

## Guardrails

- **Never auto-edit the docs without human sign-off.** A wrong platform rule is
  worse than no rule — it will be followed authoritatively and silently.
- Keep entries **one line** each. Verbose paragraphs gather dust.
- Distinguish *local* (this Windows laptop) vs *remote* (a Debian host you SSH
  to): a lesson about a remote host belongs in `debian.md` with the host named,
  only if it's a general Debian rule and not a one-off misconfig.
- Do not turn a single typo into a permanent doc rule. Only durable, general
  traps qualify.
