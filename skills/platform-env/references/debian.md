# Debian environment — concrete rules

This is the "assumed" POSIX world that many plans/subagents default to. On a
real Debian host these are correct — but confirm you are actually on Debian
before assuming them (see `references/detect.md`).

## Shell

- `bash` (usually the login shell). GNU coreutils: `cp`, `mv`, `rm`, `grep`,
  `sed`, `find`, `which` are all present.
- Command chaining with `&&`, `;`, `|`, backticks, and `$()` all work as expected.
- Variables use `$VAR` / `$HOME`.

## Paths

- **Separator is `/`.** Absolute paths start with `/` (e.g. `/tmp`, `/home/domen`).
- Forward slashes only; no drive letters.
- Working directory: `pwd`; `cd ~/path` or `cd /home/domen/path`.

## Temp / home

- Temp: **`/tmp`** exists and is world-writable.
- Home: `~` = `/home/domen` (or `/root` when root). `$HOME` is set.

## Python

- **Use `python3`.** On Debian the `python` command is frequently **not installed**
  (since 2021 it is a package named `python-is-python3`); plain `python` may not
  exist. Verify: `python3 --version`.
- `py` (the Windows launcher) does **not** exist on Debian.
- Default locale is UTF-8 (`C.UTF-8` / `en_US.UTF-8`), so non-ASCII output is safe.

## Encoding & line endings

- Default is **UTF-8**; LF line endings. Writes are naturally UTF-8 — no BOM.
- git `core.autocrlf` is typically unset/input → LF preserved.

## Permissions & privileges

- Local files owned by the user; if a path is owned by root, you need `sudo`.
- Commands that bind low ports (<1024), write to `/etc`, `/var`, or other root
  paths need `sudo`. `chmod`/`chown` apply (case-sensitive, POSIX permissions).
- `apt` is the package manager (`sudo apt update && sudo apt install ...`).

## Case-sensitive filesystem

- ext4 is **case-sensitive**: `readme.md` ≠ `README.md`. Do not assume case is
  normalized; references must match the exact filename.

## Services / daemons (homelab context)

- `systemctl` manages services; on the homelab hosts this is the norm.
- `ssh` to remote hosts (`oldsrv.kogler.si`, `nas.kogler.si`, `ha.kogler.si`).

## Summary "surface note"

```
Debian · shell: bash
temp  : /tmp
home  : /home/domen
python: use python3 (NOT python) — no py launcher
prefer: /-separated absolute or ~-relative paths
coding: UTF-8, LF; case-sensitive FS; sudo for root-owned paths
```

## Self-learned on this host (Debian)

Append durable discoveries here when a resolved environment failure reveals a
gap not covered above (procedure: `references/self-learn.md`). One line each,
`symptom → fix (when …)`. Prune duplicates as the file grows.

- *(active space — add entries as you learn them)*
