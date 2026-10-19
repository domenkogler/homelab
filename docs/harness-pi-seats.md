---
title: pi.dev Harness — Seats & Settings (settings.json harness tuning)
role: detail
domain: harness
status: active
tags: [ai, pi, agent-harness, harness, spark, llm, settings]
---

# pi.dev Harness — Seats & Settings

> **Role:** Detail doc — the **settings plane** and the harness scope + deploy direction: the reference `~/.pi/agent/settings.json` harness block (§5) and §1's scope/deploy map.
> **Linked from:** [`index.md`](index.md) (Document Map + dispatcher) ·
> [`harness.md`](harness.md) (the `harness` domain hub — placement map).

---
## 1. Scope and deploy direction

| Item | Where it lives | Managed by |
|------|----------------|-----------|
| `~/.pi/agent/models.json` | **rendered**, per machine, by [`../scripts/harness/render-pi-config.py`](../scripts/harness/render-pi-config.py) from the SSOT [`../scripts/harness/pi/models-spec.yml`](../scripts/harness/pi/models-spec.yml) | git (the spec) — **not the JSON**; the render carries the bearer key, so it is 0600 and never committed. Rendered on **two** machines: the laptop, and oldsrv's cockpit account `domen` — the harness is therefore not "admin workstation only", and a second machine is contracted through `--out` + scp, not a copied file |
| `~/.pi/agent/auth.json` | **rendered** (vendor `pi-auth`) from the same spec | git — the built-in-provider auth (`openrouter`, `opencode-go`); the client's file is byte-identical to the render |
| `~/.pi/agent/settings.json` | the admin workstation **and** oldsrv's cockpit seat (`domen`) | **§5's harness block is a repo file** — [`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json), merged into each seat's file by [`../scripts/harness/pi-settings-config.sh`](../scripts/harness/pi-settings-config.sh): the merge owns the harness keys and the `packages` list (composed from the `versions.yml` pins, [`harness-pi-engines.md`](harness-pi-engines.md) §7); `externalEditor` / `lastChangelogVersion` / `tuiMode` stay machine-local and [`harness-pi-seats.md`](harness-pi-seats.md) §5 remains the place that says WHY each key is what it is |
| pi packages (`pi install npm:…`), **the pi build itself** + the seat TUI font | every pi.dev seat | git — the pin pairs `pi_host_tui_npm_*` / `pi_host_web_npm_*` / `pi_host_subagents_npm_*` / `pi_host_deepseek_npm_*` / `nerd_fonts_*` in `IaC/ansible/group_vars/all/versions.yml`, installed by the two `install-pi-*.sh` scripts and re-converged by [`../scripts/harness/pi-seat-sync.sh`](../scripts/harness/pi-seat-sync.sh) (the fan-out driver: seat × plane matrix, unreachable seat = failed run, and a seat whose declared planes did not all run fails as `coverage` — a bare `ssh` inside the plane loop eats the loop's stdin) |
| `AGENTS.md`, `prompts/`, `extensions/`, `skills/` | repo `pi-agent/` + `skills/` → deployed by both installers: skills via [`../scripts/harness/sync-skills.sh`](../scripts/harness/sync-skills.sh), `extensions/` via [`../scripts/harness/sync-extensions.sh`](../scripts/harness/sync-extensions.sh) | git (repo → `~/.pi/agent`), drift-gated by `validate-all.sh` items 13 + 27 |
| `~/.pi/agent/extensions/subagent/config.json` — the child-runtime payload (the run deadline and the concurrency ceiling the child-lane contract promises) | every pi.dev seat's HOME, rendered from the `_subagentConfig` block of [`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json) | **the seat × plane matrix.** The plane set [`../scripts/lib/seat-planes.yml`](../scripts/lib/seat-planes.yml) declares and [`../scripts/harness/pi-seat-sync.sh`](../scripts/harness/pi-seat-sync.sh) fans out owns this file — the `subagent` registry record, owner [`../scripts/harness/pi-subagent-config.sh`](../scripts/harness/pi-subagent-config.sh), writes the whole `_subagentConfig` block to `~/.pi/agent/extensions/subagent/config.json` on every seat, one verdict line per seat, the same shape by which the `settings` arm owns `~/.pi/agent/settings.json` and the `tui` arm owns `~/.pi/agent/open-tui.json`. Its `--check` verdict is about the file in THAT seat's HOME: `OK` = **every key the extension reads** equals the SSOT payload; a missing file, an unparseable file (a REFUSAL, bytes left alone), an extra key the SSOT does not carry, or a moved value is drift, so the seat does not read green, and the driver's declared-vs-executed `coverage` rule means an arm that stops running reddens the seat instead of vanishing from the report. **One key sits deliberately outside that comparison: `_note`.** It is documentation the extension never reads, and what it cites are sections of this doc tree — so comparing it byte-for-byte turns a prose-only doc edit into seat drift on every seat not yet pushed, and no offline gate can predict that drift because the bytes it compares live in a seat's HOME. The rule therefore splits the two jobs: the COMPARE ignores `_note`, the WRITE still renders the WHOLE block, note included, so the next `--push` refreshes the prose and `--check` prints the lag on its `OK` line instead of hiding it or accusing the seat. Both halves are canaries in the arm's own `--self-test` — a moved value still reddens under `--strict` and the DRIFT line names the key, and a note-only change does not — because an exclusion that is not narrow is just blindness. The deployed copy is a render, not a string twin: the sentence exists once in the tracked tree, in the SSOT. The arm renders the WHOLE `_subagentConfig` block (never a subset), so a payload key cannot be dropped silently; `scripts/gate/check_subagent_contract.py` R-3 asserts the arm exists (payload present but no registry owner that writes this path is a finding) — the gate proves an arm exists, the arm's own `--check` on each seat's HOME is what stops a seat reading green with the file missing. Not the settings plane — it merges the un-prefixed keys of `~/.pi/agent/settings.json` and nothing else, which is why the payload sits under an underscore |
| `~/.tmux.conf` (the seat's terminal harness) | repo [`../pi-agent/tmux/tmux.conf`](../pi-agent/tmux/tmux.conf) → installed by [`../scripts/harness/install-tmux-conf.sh`](../scripts/harness/install-tmux-conf.sh) | git (the SSOT) — **not** the file in `$HOME`; it carries a `managed-by:` line so an installed copy is nameable, and a foreign `~/.tmux.conf` is a REFUSAL rather than a silent overwrite. Mouse + OSC 52 clipboard: **[`harness-pi-terminal.md`](harness-pi-terminal.md) §5b**. Not yet called by the seat installer |
| spark engine (`--max-model-len`, KV pool) | repo IaC `IaC/ansible/group_vars/spark.yml` | Ansible (SSOT) |

- The harness talks **directly to the spark edge** (`llm.kogler.si`), not through LiteLLM. That
  is a DECIDED boundary (**decision #26**, [services-ai.md](services-ai.md) §9 row 26 +
  the evidence appendix [services-ai.md](services-ai.md) §9d), not an accident of history — see **[`harness-pi-engines.md`](harness-pi-engines.md) §1b**. The LAN/VPS LiteLLM
  instances front the same engine for the **simple-querier tier** (HomeAssistant, Docling,
  Open WebUI) — the model id `spark/qwen3.8-flash-next` is deliberately stable across every path.
- **Secret:** the provider `apiKey` is the `spark-llm_api` credential (1Password `Homelab-ansible`
  vault). Never commit the literal and never print its value (CONVENTIONS §6).
- Reload: `models.json` is re-read every time `/model` is opened in a running session; a new session
  picks it up at start. `settings.json` is read at start → restart pi.
- **Where the pi BINARY lives — two layouts, one PATH.** `npm -g`
  installs it as a symlink at `<pi-node prefix>/bin/pi` next to the pinned node (what
  [`../scripts/harness/install-pi-debian.sh`](../scripts/harness/install-pi-debian.sh) does); pi's own installer writes a
  launcher at `~/.pi/agent/bin/pi` over `~/.pi/agent/install/releases/<ver>/` (`layout: releases-v1`).
  **`pi update` run inside a session migrates the first layout into the second and deletes the
  node-dir symlink** (1.1.0's own CHANGELOG recommends the migration), so a seat can lose `pi` from
  PATH on the day it updates while pi itself runs perfectly — the cockpit then dies with
  `exec: "pi": executable file not found in $PATH`.
  Three places carry **both** dirs: the seat's `.bashrc`/`.profile`
  (`install-pi-debian.sh --path-only` is the repair for a seat whose block predates it), the cockpit
  unit (`roles/seat` → `pi-on-path.conf`, `seat_pi_bin` + `seat_pi_node_bin`, asserted in the live
  unit), and every probe (`pi_bin()` / `pi_candidate()`) — a probe that reads only PATH reports
  "no pi here" for a seat that has one.
  ⚠ **Who WRITES the seat's block (HD-1110, 2026-10-19): the installers, not the operator.**
  `install-pi-wsl.sh` used to print a NOTE asking for a `~/.bashrc` edit, which is a step owned by
  nobody — whether `pi` resolved was then a fact about one hand-written line on one seat rather than
  about the installer. `persist_path()` now writes the node bin dir and pi's entrypoint dir into
  `.bashrc` and `.profile` under the installer's own marks (distinct from `install-pi-debian.sh`'s, so
  each can tell whether IT persisted) and skips a directory this box does not have, and
  `verify_login_path()` asks a **login** shell (`bash -lc 'command -v pi'`, `which -a pi`) and FAILS if
  the winner is a `/mnt/c` copy, reporting the drvfs candidates instead of pretending they are not on
  PATH. Which file answers what, measured: `wsl -- bash <cmd>` is non-interactive AND non-login and reads
  neither file; `bash -l` reads `~/.profile`; an interactive shell reads `~/.bashrc` (which on Debian
  returns early when non-interactive); a systemd USER unit reads neither — that is `roles/seat`'s
  `Environment=PATH` drop-in, not this file. On the WSL seat today the login shell resolves
  `~/.local/share/pi-node/current/bin/pi` first with the Volta `/mnt/c/...` copy last, and the marks are
  **absent** from both files — the correct resolution is currently carried by hand-written lines, one of
  which pins a version directory (`node-v22.23.2-linux-x64`), which is exactly the line this leg exists to
  replace. HD-1118 Stage 2 is the follow-through for the rest of the seat family. `pi update self` installs the LATEST release and takes no version
  flag, so a managed seat off its pin is an **owner** action — move `pi_host_npm_version` +
  `pi_dev_npm_version` to what it reports, or move the seat back to the pinned layout with
  `install-pi-debian.sh --pi-only`; the script refuses to npm-install a second layout underneath it.

---
## 5. Reference `~/.pi/agent/settings.json` (harness tuning)

> **Where these scripts live (2026-10-09, HD-1118):** the seat family moved to
> [`../scripts/README.md`](../scripts/README.md) §`scripts/harness/` — the driver, the plane owners, both
> from-zero installers and `render-pi-config.py`; the shared helpers (`pin()`, the repo-root
> resolver, the plane registry) are in `../scripts/lib/`, and the fleet package set is now rows in
> [`../IaC/ansible/group_vars/all/versions.yml`](../IaC/ansible/group_vars/all/versions.yml).
> Nothing in this section's *content* changed: same pins, same planes, same merge rules. What moved
> is the address, and [`gate/check_script_layout.py`](../scripts/gate/check_script_layout.py) is what
> keeps this paragraph from becoming a lie.

```json
{
  "defaultProvider": "spark",
  "defaultModel": "spark/qwen3.8-flash-next",
  "defaultThinkingLevel": "high",
  "showCacheMissNotices": true,
  "httpIdleTimeoutMs": 900000,
  "retry": {
    "enabled": true,
    "maxRetries": 3,
    "baseDelayMs": 2000,
    "provider": { "timeoutMs": 1800000, "maxRetries": 0, "maxRetryDelayMs": 60000 }
  },
  "compaction": { "enabled": true, "reserveTokens": 16384, "keepRecentTokens": 32768 },
  "thinkingBudgets": { "minimal": 1024, "low": 2048, "medium": 4096, "high": 8192 }
}
```

Other keys in the real file (`lastChangelogVersion`, `externalEditor`, `tuiMode`) are workstation
state, not spec — the block above plus `theme` and `packages` is the part that must match, and that
"must" is enforced rather than asserted: the keys live in
[`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json) and
[`../scripts/harness/pi-settings-config.sh`](../scripts/harness/pi-settings-config.sh) merges them into each seat's
file (owned keys replaced, everything else preserved, timestamped backup, an unparseable file is a
REFUSAL; `packages` is composed from the `versions.yml` pins and a seat-local package the repo does
not name — the cockpit's pi-web — is KEPT and printed, never deleted).

**The owned package set.** The set this plane writes is DISCOVERED from the `pi_pkg_*` inventory in
[`../IaC/ansible/group_vars/all/versions.yml`](../IaC/ansible/group_vars/all/versions.yml) — every `scope: fleet`
row, at its pin — so a row added there reaches every seat on the next plane run and no doc or script carries
a second copy of the list ([`harness-pi-engines.md`](harness-pi-engines.md) §2: a re-typed set drifts silently). `seat-local` is where an unmanaged package
hides: a package named only in an unversioned installer line is classified seat-local and **kept**, which
reads as "fine, nothing to do" while nothing converges it, no version is recorded anywhere, and a seat
carries it only because someone hand-ran `pi install` there. So every package a seat is meant to run is
pinned and owned: the plane fails (`--check --strict`) when a seat is missing one and `--push` restores it at
the pin — an arm of `--self-test` proves that half, and another proves the cockpit's pi-web still survives
the same write. What stays seat-local is exactly the placement a fleet key must not own: the cockpit's
`@ygncode/pi-web` (`--with-package`). A seat-local entry is retired on the seat with `pi remove` — the sync
never deletes one.

**The settings plane converges the declaration, not the bytes.** `--push` writes the package entries into
`settings.json` and runs no installer, so a seat that is already installed and merely gains a fleet row reads
`OK` on the plane with the new name unresolved — pi loads nothing for it. The installer leg is the half that
places code ([`../scripts/harness/install-pi-wsl.sh`](../scripts/harness/install-pi-wsl.sh) runs `pi install` for the
same fleet rows), and the read that tells the two states apart on a live seat is `pi list`: it prints a path
under every package it has resolved and **nothing** under a declaration it has not. The repair is
`pi install <source>@<pin>`; `pi update --extensions` is never the repair, because it moves every package to
whatever the registry calls `latest` and walks a pinned seat off its pins one sync at a time ([`harness-pi-engines.md`](harness-pi-engines.md) §7).

**Which pi build a seat runs is a pinned value too** (`pi_host_npm_version`, and `pi_dev_npm_version` must equal it — both are `1.1.0`, and the reasoning lives in the `versions.yml` pin lines, not in prose). Every other plane compares files, so without a binary plane a seat quietly runs a pi release the repo has not reviewed. [`../scripts/harness/pi-self-update.sh`](../scripts/harness/pi-self-update.sh) is that plane: `BEHIND` and `AHEAD` are both drift, an already-correct seat runs nothing, and `--push` re-probes the binary instead of trusting the installer.

**One rule about that `packages` list:** an
extension package must NOT list a host-provided module in `dependencies`. pi's loader compares each
installed manifest's `dependencies` against `HOST_PROVIDED_EXTENSION_PACKAGES` (`typebox`,
`@sinclair/typebox`, the `pi-ai` / `pi-tui` / `pi-coding-agent` families) and prints on every start:
`Host-provided extension packages must be declared in peerDependencies with a "*" range, not
dependencies`. Not style: an extension that installs its OWN `typebox` gets a second runtime module
beside the host's, bypassing the extension loader — a **pin** problem wearing an extension's clothes.
The fix is the pin, never an edit into someone's `node_modules`, and no pin has to move:
`pi_web_access_version` is `0.36.0`, whose installed manifest declares `peerDependencies.typebox: "*"`
and carries no `typebox` entry in `dependencies` (upstream moved the declaration in 0.32.0,
registry-verified across all 46 published versions). The value of a pin is its `versions.yml` line, not a
number quoted in prose. The predicate is one read of a
manifest, so `pi list` plus a manifest scan proves it, and deleting a hoisted copy is undone by the
next install.

**There is no settings VENDOR in `render-pi-config.py`, and that boundary holds — but [`harness-pi-seats.md`](harness-pi-seats.md) §5 is
not the only source.** `render-pi-config.py --vendor` speaks `pi` / `pi_auth` / `continue` /
`all`; the spec renders the **model contract**, never someone's editor settings
([`../scripts/harness/pi/models-spec.yml`](../scripts/harness/pi/models-spec.yml) says so in its own
comment). The harness keys are a repo file plus a merge script, not a hand-copied doc block — the
re-decision is recorded here, not buried in an edit. `models-spec.yml` names `settings.json` as
machine-local, and the keys it names are machine-local; the harness block is not. "Render
`settings.json` from the spec" names a command that does not exist and must not be revived:
a vendor would rewrite the whole file and delete a seat's own packages. Both carriers today: the laptop, and
oldsrv's seat (the §5 block + `packages`, live).

**`defaultThinkingLevel: high` — thinking ON from the first turn.** What the setting actually does, read off
pi's own resolver and compat code rather than inferred from a UI label: the startup level comes from
**settings.json only**
(`modelThinkingLevels["<provider>/<modelId>"]` → `defaultThinkingLevel` → pi's built-in `medium`) —
**models.json has no default-thinking field**; its `ModelDefinitionSchema` carries `reasoning` /
`thinkingLevelMap` / `samplingParams*`, which decide which levels *exist* and what each *sends*, never
which one starts a session. And because [`harness-pi-models.md`](harness-pi-models.md) §4's `thinkingLevelMap` nulls every level except `off`/`high`,
**`high` is the only ON level this model has** — `medium`/`xhigh` clamp *up* to it — so `high` is the one
correct spelling of "thinking on by default". Cost, in the currencies [`harness-pi-engines.md`](harness-pi-engines.md) §2 measures: every turn sends
`chat_template_kwargs.enable_thinking: true` plus `thinking_token_budget: 8192`
(`thinkingBudgets.high`); the *uncontrolled* template would spend 23–121 hidden reasoning tokens/turn,
thinking-on decode is ~11 tok/s, and reasoning tokens occupy blocks in the shared ~262k KV pool — so a long
turn is minutes and a concurrent lane feels it ([`harness-pi-engines.md`](harness-pi-engines.md) §6). Rows with
`reasoning: false` (the laptop's vision + FIM legs) are untouched; pi clamps them to `off`.
**Seat state:** all three seats read `high`. The `--check` drift gate cannot see this key because
settings.json sits deliberately outside the render — a seat can disagree with §5 in silence, and only a
`pi-settings-config.sh` merge (or a human) proves it. The seat's own file is 0600 `domen`, so the runner key
cannot read it; an owner session on the box can.

**`theme` — why an unset `theme` makes two seats look different.**
pi's default theme is `system`: it queries the terminal's background and 16 ANSI colors and rebuilds its
palette from the answer, so an unset `theme` key means *the terminal decides*. pi's truecolor hint is
`COLORTERM=truecolor|24bit` or `TERM=*-direct` (read off `detectCapabilitiesFromEnvironment` in pi's own
bundle, not inferred from a UI label); the seat's leg is plain SSH with **`COLORTERM` unset** and
`TERM=xterm-256color`, so pi gamut-maps the derived palette down to the 256-color
set — a visibly flatter picture than the laptop's seat in the same session. Set it on a seat with
`"theme": "dark"` (pi's built-in terminal-independent palette; `/reload` to apply).
**The boundary does not move.** `render-pi-config.py --vendor` still has no settings vendor and
`models-spec.yml` still forbids `theme` in the spec, so this stays a hand-written per-machine key with
this section as its source — and the drift gate remains blind to it, the same blindness that lets the
`defaultThinkingLevel` halves divide. **Seat state:** all three seats read `dark` at rest; the laptop half is
owner-REPORTED, not measured. There is no oldsrv→laptop leg (`domenp14s` is a `hosts:`
label for the renderer, not an ssh target), so nothing on this box can read that half, and §5 has no
renderer to check it with either. If they diverge, the only detector is a human running
`grep '"theme"' ~/.pi/agent/settings.json` on each machine — the standing cost of keeping this key outside
the render.

| Setting | Value | Why on this box |
|---------|-------|-----------------|
| `defaultThinkingLevel` | `high` | thinking ON from the first turn: `enable_thinking: true` + the 8192-token `thinkingBudgets.high` cap. `high` is the only ON level the [`harness-pi-models.md`](harness-pi-models.md) §4 map leaves, so any other spelling clamps to this anyway. The ≈20–120 hidden reasoning tokens/turn that `off` would save are a deliberate cost — see the note above |
| `compaction.reserveTokens` | 16384 | pi compacts when context > `contextWindow − reserveTokens` = **245,760**; this is the "use the whole window" dial |
| `compaction.keepRecentTokens` | 32768 (default 20000) | larger verbatim tail survives a compaction — cheaper to keep when the window is 262k |
| `httpIdleTimeoutMs` | 900000 (default 300000) | a cold prefill of a large prompt emits no tokens until the first token; the 5-min default can kill the turn mid-prefill |
| `retry.provider.timeoutMs` | 1800000 | same reason, per-request ceiling (SDK default is far below a 200k cold prefill) |
| `showCacheMissNotices` | `true` | server-side `--enable-prefix-caching` is the only reason a 200k turn is cheap — the notice shows when the harness broke a cached prefix |
| `thinkingBudgets` | 1k/2k/4k/8k | only applied when thinking is ON (needs `thinkingTokenBudgetField`); bounds what "high" can spend |
| `theme` | `dark` | `dark` is terminal-independent, and absence is not neutral: it selects pi's `system` theme, which paints from the terminal's own palette — over the seat's SSH leg (`COLORTERM` unset) that lands on the 256-color approximation, so the cockpit and the laptop do not match. All three seats read `dark`; the laptop half is owner-reported, not measured. Still NOT rendered (§1, `models-spec.yml`) |

---

**Carriers.** No renderer exists for `settings.json` by design ("render settings.json from the spec" names a
command that must not be revived), so §5 is the source and the seat's block is written **from this section**,
not copied off the laptop; a seat's own extra `modelThinkingLevels` / `lastChangelogVersion`-class keys are
workstation state and are preserved by the merge. The host-side bootstrap for a bare Debian seat is
[`../scripts/harness/install-pi-debian.sh`](../scripts/harness/install-pi-debian.sh) — it installs the pinned
Node tarball + the pinned pi and reads its pins from
`IaC/ansible/group_vars/all/versions.yml`, the same `pi_host_*` pins that keep a seat from trailing the
laptop (§1).
