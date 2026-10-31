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
  slashes** for cross-shell safety. Quote any path
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
  There is **no `/tmp`** on cmd/PowerShell — but Git-Bash (MSYS) *does* mount
  `/tmp`, and there `$TEMP`/`$TMP` **are** `/tmp` → the same `…\AppData\Local\Temp`.
  Write logs to `$TEMP/…` and it is correct under every shell on this host.
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
- File edit tools can silently rewrite an LF-only repo file with CRLF endings (git warns "CRLF will be replaced by LF" on add/commit; `.gitattributes eol=lf` keeps the blob LF but the working tree stays CRLF) → after edits, count `\r\n` via `py -3 -c "open(f,'rb').read().count(b'\\r\\n')"` and normalize to LF before committing (when editing repo files on Windows)
- Write/edit tools can emit cp1252-encoded bytes for typographic chars (em-dash written as raw 0x97) into files meant to be UTF-8, breaking parsers (`UnicodeDecodeError`) → keep authored file content ASCII-safe (use `-` not `—`) or byte-verify after editing (when writing file content programmatically on Windows)
- Multi-layer inline quoting through git-bash → wsl.exe → ssh mangles unpredictably (wsl.exe re-splits argv through an intermediate shell; `$`, quotes, backrefs get eaten) → ALWAYS use script-file indirection (`wsl -d Debian -- bash /mnt/.../script.sh`, or feed a remote script via `ssh "sudo bash -s" < local.sh`) for anything non-trivial (when invoking wsl/ssh chains from Windows)
- Windows `.ssh/config` aliases whose IdentityFile points at a `.pub` key + 1Password agent FAIL under MSYS git-bash ssh (`Load key …: error in libcrypto: unsupported` → Permission denied) → drive those hosts via `/c/Windows/System32/OpenSSH/ssh.exe` (same config file, agent handled correctly); also note MSYS `grep -c $'\r'` can report false CRLF counts — verify line endings with awk/xxd instead (when SSH-ing to homelab hosts / checking encodings on Windows)
- Multi-line bash heredocs (<<PYEOF) containing backslashes or backticks get mangled through the host bash -c path on Windows (delimiter mismatch -> escape/quote stripping, <!-- -> SyntaxError) -> for any non-trivial multi-line Python/edit script, write it to a temp file with the write tool and run it (python3 file.py) instead of a here-doc (when authoring generated-text patches on Windows)
- git-bash mangles `/mnt/...` args passed to wsl.exe into `C:/Program Files/Git/mnt/...` (MSYS path conversion) → prefix such invocations with `MSYS_NO_PATHCONV=1`, or keep script-file indirection under /mnt/c (when calling wsl.exe/ssh.exe with POSIX-looking paths from git-bash)
- A repo gate that passes in my shell is red in an agent/child shell, naming `python3`/`python` or a "store" error → git-bash PATH often resolves `python3` to the `WindowsApps` app-execution-alias stub, which exits non-zero without running; gate scripts inherit the caller's PATH, so the same commit validates green from an interactive shell and red from a spawned one → invoke the real interpreter (`python`, `py -3`, or the full path such as `%LOCALAPPDATA%\Programs\Python\Python313\python.exe`) or fix PATH for the child, and never "fix" the code that the stub made look broken (when running validate/gate scripts from subagents or scheduled shells on Windows)
- A bash guard that greps for CR works, but the "faster" fork-free rewrite `s=$(<file)` reports NO CR on a CRLF file (command substitution applies MSYS text-mode translation, the same blindness as plain `grep` without `-U`) -> test bytes with `IFS= read -r line`/`case`/`cmp`, which do NOT translate, and let the existing canary prove the rewrite (when rewriting an encoding/CRLF guard in bash on Windows)
- Timing numbers here swing 5-10x run to run, so a "before" measured in a quiet window beats an "after" measured during a busy one for no reason -> measure the fork+exec cost first (`/bin/true` x100: 16-44 ms quiet, 130-185 ms while another parallel job forks, 0.66 ms in WSL Debian) and A/B ALTERNATING (before/after/before/after), never one run against another (when benchmarking anything on Windows)
- A bare `bash` in PowerShell/cmd is `C:\WINDOWS\system32\bash.exe` — the WSL launcher, which enters the WSL **default** distro (here: `podman-machine-default`, `$HOME=/home/user`) while keeping the Windows cwd as `/mnt/<drive>/...`, so a repo script finds the repo and then reads the wrong box's `$HOME` and node (a Windows `node.exe` over WSL interop cannot open a `/mnt/...` path) → name the build (`C:\Program Files\Git\bin\bash.exe`) or run harness commands from Git-Bash; converged on this seat by `scripts/harness/seat-bash-build.sh` (when running repo `bash scripts/...` commands from a Windows-native shell)
- A `spawnSync`/`execFile` child spawned from a JS script RUN under **bun** on this host never sees a `process.env.X = ...` assignment made inside the script — bun here snapshots the environment block at process start — so a fixture or route seam set in-process is silently IGNORED and the leg reads the live store instead of the fixture (a "zero-request" self-test costs real vault requests, and its arms go red on one runner only) → pass `env: process.env` explicitly on any JS spawn that must honour an env seam, and prove it with the arm that plants the fixture and asserts the fixture was the thing read. Scope it correctly: `pi` and this repo's scripts here run under **node**, where the same in-process assignment DOES reach the child both implicitly and with `env: process.env`, so the lesson is "state `env:` explicitly when spawning from a JS runtime", NOT "the seat/pi behaves this way" (when spawning children from a JS runtime on Windows)
- `setsid: command not found` when detaching a long background run from Git-Bash → that util-linux binary is not shipped with MSYS; use `nohup <cmd> > "$TEMP/x.log" 2>&1 & disown` and poll the log file (when backgrounding a long gate/build from Git-Bash on Windows)
- A `git` command in a `wsl.exe` leg whose cwd is a **linked worktree** (`…/homelab-wt-<date>-<HHMM>`, the inherited Windows cwd) resolves NO repository: that worktree's `.git` is a FILE holding `gitdir: D:/source/...`, and inside WSL that string is a RELATIVE path, so git dies naming its own cwd with the `gitdir:` value appended — `fatal: not a git repository: /mnt/d/.../homelab-wt-<...>/D:/source/.../.git/worktrees/<name>` — and that is true of `init`, `add`, `commit`, `status` and `rev-parse` alike; a leg that reacts by dropping the `cd` instead runs discovery from whatever cwd WSL inherited, where the first repository git CAN read is the parent checkout on `main` → `cd` into the seat's own clone path before ANY git command in a WSL leg (`MSYS_NO_PATHCONV=1 wsl.exe -d Debian -- bash -lc 'cd ~/<clone> && git …'`), and never put `git init` / `git add` / `git commit` in a WSL leg at all: a repo write belongs to the Windows-side lane (when running git through `wsl.exe` from a Windows cwd)
