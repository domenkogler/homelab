# Windows 11 environment — concrete rules

Assume **nothing** about the POSIX world. Everything below is a common trap that
breaks agent runs on this OS.

## Shell flavor first

Your command tool may be cmd, Windows PowerShell 5.1, pwsh 7, or git-bash. Detect
it (`references/detect.md`) because grammar differs:

- **`&&`**: valid in cmd, pwsh 7, git-bash. **INVALID in Windows PowerShell 5.1**
  (parses as an error). Chained commands in PS 5.1 → use `;` or separate steps.
- Variables: cmd `%VAR%` / `$VAR`? PowerShell uses `$env:VAR`. git-bash uses `$VAR`.
- `which` → cmd/PS use `where`. git-bash uses `which`.

## Paths

- **Separator:** both `\` and `/` work in most Windows APIs, but **use forward
  slashes** (`plan/2026-08-06-reorg/T1.md`) for cross-shell safety. Quote any path
  that might contain spaces (e.g. `C:\Users\Domen Kogler\...`).
- **git-bash mangles leading-`/` paths** (treats `/foo` as a root path) and can
  rewrite `D:\...`. Prefer **relative forward-slash paths from the repo root**,
  or absolute `D:/source/domenkogler/homelab/...` (forward slashes), always quoted.
- **Drive letters** have a colon (`D:\`). In git-bash a bare `D:\x` can be
  misread as a URI scheme; spell it `D:/x`.
- **Working directory is never guaranteed** for a fresh subagent. Pin it before
  running commands: `cd /d D:\source\domenkogler\homelab` (cmd) or
  `Set-Location D:/source/domenkogler/homelab` (PowerShell).

## Temp dir / home dir → NOT `/tmp` and NOT `/home`

- Temp: `%TEMP%` = `C:\Users\domen\AppData\Local\Temp` (PowerShell `$env:TEMP`).
  There is **no `/tmp`**.
- Home: `%USERPROFILE%` / `$HOME` = `C:\Users\domen`. **No `/home/domen`**.
  `~` expands to the user profile on cmd/PowerShell, but may differ under git-bash.

## Python

- **Use `py -3`** (Windows Python launcher). Plain `python` may be the Microsoft
  Store alias (opens the Store / no-op), and `python3` is usually **not** on
  PATH.
- Verify before relying on it: `py -3 --version`.
- Windows console output defaults to **cp1252**; when output is captured/parsed,
  non-ASCII (`· → — ≤`) can garble. Prefer UTF-8 (see Encoding).

## Encoding & line endings

- **Files must be written UTF-8 (no BOM).** The cp1252 default breaks tools that
  read `encoding="utf-8"` (e.g. `validate-plan.py`), which then FAIL a valid plan.
- **Line endings:** git `core.autocrlf` on this repo is `false` → files are LF.
  Do not introduce CRLF where LF is expected (or vice versa) when editing; match
  the existing file. Inconsistent line endings make diffs and regex validators
  flaky.
- When writing a file that mixes non-ASCII and must be parsed by a tool, force
  UTF-8 explicitly in the write.

## Commands & tools

- `which` → use `where` in cmd/PowerShell.
- No `chmod`/root/`sudo` semantics on the local machine (files owned by you).
- `robocopy` exit codes **0–7 are SUCCESS**; only ≥8 is a real failure (do not
  treat a return of 1 as an error).
- Copy via `copy` / `robocopy`, not `cp`.
- Process listing: `tasklist`; kill: `taskkill //PID <n> //F` (double slash under git-bash).

## Case-insensitive filesystem

- The NTFS volume is case-insensitive: `readme.md` and `README.md` are the same
  file. Don't rely on case to disambiguate; a rename that only changes case needs
  an explicit two-step to work on some tooling.

## Summary "surface note" (use as your environment note)

```
Windows 11 · shell: <cmd|powershell-5.1|pwsh7|git-bash>
temp  : %TEMP% (C:\Users\domen\AppData\Local\Temp) — no /tmp
home  : %USERPROFILE% = C:\Users\domen — no /home
python: use py -3 (NOT python / python3)
prefer: forward-slash relative paths from repo root; pin CWD before commands
coding: write UTF-8 (no BOM); keep LF line endings; `&&` invalid on PS 5.1
```

## Self-learned on this host (Windows 11)

Append durable discoveries here when a resolved environment failure reveals a
gap not covered above (procedure: `references/self-learn.md`). One line each,
`symptom → fix (when …)`. Prune duplicates as the file grows.

- `py -3` printing non-ASCII to stdout (✓/✗) → `UnicodeEncodeError: 'charmap' codec … cp1252` → keep script output ASCII-only, or run with `PYTHONUTF8=1` / reconfigure stdout to UTF-8 (when a Python script prints to the Windows console)
