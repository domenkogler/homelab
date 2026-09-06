---
name: platform-env
description: |
  Detect the operating system / shell once and apply the correct platform
  assumptions (paths, separators, temp dir, home dir, python launcher, encoding,
  line endings, quoting). Run at session start and when producing/executing
  plans; re-consult ONLY when a command fails with an environment symptom or the
  platform is unknown — never as a gate before every command. Self-learning:
  records newly discovered platform traps back into its own reference docs.
  Works on Windows 11, Debian, or any host.
---

# platform-env — environment awareness

Detect *where you are* and *what shell you speak* once, apply those rules to the
session, and **learn from your mistakes** so the rules get sharper over time.
Windows 11 and Debian are *not* the same default world, and getting them
confused silently breaks commands.

## When to run (and NOT to run)

**Run this skill ONCE, at a defined checkpoint — not before every command:**
- **Session start** (via the global `AGENTS.md` instruction, or `/start`).
- **Producing/executing plans**: at plan scope-check / task startup, so the detected
  environment carries into subagents (plan-task/run-task retired 2026-09-06).

After the checkpoint, the constraints are **established** and applied to every
command *without re-reading the docs*. Do **not** re-load this skill as a
preamble before individual commands — that is overhead with no benefit once the
environment is known.

**Re-consult (only) when** any of these is true:
- A command **already failed** with an environment symptom (bad path separator,
  `ENOENT`, drive-letter/`/` mangling, `UnicodeDecodeError`/cp1252, CRLF/LF
  mismatch, `&&` error on PowerShell 5.1, `python`/`which` not found).
- The platform/shell is **genuinely unknown** (e.g. a new host).
- You are about to make a change that **crosses hosts** (e.g. remote Debian box
  from a local Windows shell).

## Workflow (one-time detection)

1. **Detect** the platform and shell — `references/detect.md`.
2. **Load** the matching doc — `references/windows11.md` or `references/debian.md`.
3. **Surface** a short, concrete environment note (platform, shell flavor, and
   the 3–5 constraints that actually bite in this session) before acting.
4. **Apply** those constraints to every command you run from then on.

When you produce **plans**, you additionally **emit an
`## Environment` section into the plan** (index + a one-line note in each task's
executor prompt) so subagents inherit the same assumptions.

## Self-learning (observe a failure → record the lesson)

Windows/Debian subtleties are discovered mainly by **hitting them**. When a
command fails and the root cause is environmental, turn that failure into a
durable rule:

1. **Confirm it is environmental**, not a task-logic failure (a wrong
   path/separator, encoding, line ending, shell grammar, or missing interpreter).
2. **Fix the immediate command** using the rules already in the docs.
3. **If the lesson is not already in the matching platform doc** (`windows11.md`
   or `debian.md`), **propose a one-line addition** to the human (symptom + fix),
   get approval, then append it under the relevant section, or under
   `## Self-learned on this host`. **Never change the rules without human sign-off**
   — a wrong auto-edit makes the skill worse for everyone.
4. If the doc is getting long, prune older/duplicate entries when you add.

Full procedure: `references/self-learn.md`.

## The three Windows-11 traps to never forget

1. **Shell flavor decides grammar.** cmd supports `&&`; **Windows PowerShell
   5.1 does NOT** (`&&` is an invalid token — use `;` or separate commands);
   pwsh 7 and git-bash do.
2. **No `/tmp`, no `/home`.** Use `%TEMP%` / `$env:TEMP` and `%USERPROFILE%` /
   `$HOME` (`C:\Users\domen\...`), not `/tmp` and `/home/...`.
3. **Python is `py -3`, not `python`.** Plain `python` may be the Microsoft
   Store alias; `python3` is usually absent. Always write files as **UTF-8**
   (cp1252 is the Windows default and breaks tools that read UTF-8).

## Integration

- **Session start:** a global `AGENTS.md` instruction tells the agent to run
  this skill first (option: also `/skill:platform-env` on demand).
- **Plans:** the skill is loaded at plan scope-check and records the detected
  environment in the plan's `## Environment` section so workers and subagents
  inherit the correct assumptions instead of re-deriving them (plan-task/run-task
  retired 2026-09-06).

## References

- `references/detect.md` — reliable, shell-agnostic platform + shell detection
- `references/windows11.md` — concrete Windows 11 / cmd / PowerShell rules
- `references/debian.md` — concrete Debian / bash rules (the "assumed" POSIX world)
- `references/self-learn.md` — procedure for turning a resolved env failure into a durable doc entry
