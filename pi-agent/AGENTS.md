# Global instructions (loaded at every session start by pi)

## 1. Environment awareness first (always)

At the **start of every session** (and again only when a command *already* failed
with an environment symptom — path, separator, temp dir, home dir, python
launcher, encoding, line ending, quoting, shell grammar — or when the platform is
unknown), **load the `platform-env` skill and state your environment note**.

**This check is a one-time checkpoint, not a gate before every command.** Do not
re-run it as a preamble before each command once the environment is known. Re-consult
it only when something below actually breaks.

Initial detection:
1. Read `skills/platform-env/SKILL.md`, then `references/detect.md`.
2. Detect the OS and shell.
3. Read the matching doc (`references/windows11.md` or `references/debian.md`).
4. Say, in your first response:
   > `Platform: <windows11 | debian> · shell: <cmd | powershell-5.1 | pwsh7 | git-bash | bash>. I will pin CWD, use <py -3 | python3>, forward-slash relative paths, UTF-8 no-BOM, and <LF | CRLF>; no /tmp or /home assumptions.`
5. Apply those rules to every command this session.

> On this machine, the everyday truth is **Windows 11**. Be careful with
> assumptions about `/` vs `\` in paths, `/tmp`, `~`, `python` vs `py -3`, `&&`
> (invalid on Windows PowerShell 5.1), UTF-8 vs cp1252, and CRLF vs LF.

## 2. Self-learning (improve the skill from failures)

When a command fails and the root cause is **environmental** (not task logic), fix
it per the rules, then — if the lesson is **not already recorded** — follow
`skills/platform-env/references/self-learn.md`: propose a one-line addition to the
human, and only with explicit sign-off append it to the matching platform doc under
`## Self-learned on this host`. Never edit the platform rules without approval.

## 3. When producing or running plans

The `platform-env` environment note is the standard the agent carries into any
plan/execution context; workers inherit the detected environment and do not
re-derive the OS on their own (plan-task/run-task skills retired 2026-09-06).
