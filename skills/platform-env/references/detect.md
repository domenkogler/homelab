# Detect platform + shell

Do not trust a single tool (a subagent's `bash` tool may be git-bash, cmd, or
PowerShell depending on harness). Run the platform check through **Python** when
available; it gives the same answer everywhere. Then determine the shell flavor,
because it changes command syntax.

## 1. Platform (authoritative, shell-agnostic)

```text
py -3 -c "import platform,sys;print(platform.system(), sys.platform, platform.release())"
```

(If `py` fails, try `python -c "..."` — still POSIX-portable.)

Fast one-liners per commonly available shell:

| Tool | Command | Windows 11 looks like |
|------|---------|------------------------|
| cmd | `ver` | `Microsoft Windows [Version 11.0.xxxx]` |
| PowerShell | `$env:OS` or `[Environment]::OSVersion.Platform` | `Windows_NT` |
| git-bash / Debian | `uname -a` | `MINGW64_NT-10.0-…` (Win) vs `Linux …` (Debian) |
| Python | `platform.system()` | `Windows` vs `Linux` |

Confirm Windows by checking for a drive: `Test-Path C:\` (PowerShell), `if exist C:\` (cmd), or `ls C:/` (git-bash).

## 2. Shell flavor (determines grammar)

| Signal | Shell |
|--------|-------|
| `$PSVersionTable` set | PowerShell (PS 5.1 if `$PSVersionTable.PSVersion.Major -lt 7`) |
| `ver` / `echo %OS%` works, backslash `\` path sep | cmd |
| `uname` prints `MINGW…` / `MSYS…` | git-bash (GNU tools + Windows paths) |
| `uname` prints `Linux` and `$SHELL` is bash | bash on Debian |

Consequences that differ by shell:
- `&&` → OK in cmd, pwsh 7, git-bash; **invalid in Windows PowerShell 5.1** (use `;` or separate steps).
- `$VAR` vs `%VAR%` vs `$env:VAR` syntax.
- `which` (cmd/PS use `where`, git-bash/Debian use `which`).

## 3. Decisions this detector must output

1. Platform: `windows11` | `debian` | `other (investigate)`
2. Shell: `cmd` | `powershell-5.1` | `pwsh7` | `git-bash` | `bash`
3. Temp dir: `%TEMP%` (`C:\Users\domen\AppData\Local\Temp`) vs `/tmp`
4. Home dir: `%USERPROFILE%` / `$HOME` = `C:\Users\domen` vs `/home/domen`
5. Python launcher: `py -3` (Windows) vs `python3` (Debian)
6. Path separator convention to use for this session (forward slashes on both;
   leading-`/` absolute paths are dangerous on git-bash)

Write 1–6 into the environment note you surface, and (for plans) into the
`## Environment` section of `index.md`.
