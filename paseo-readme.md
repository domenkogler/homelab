# `paseo-readme.md` — running agents with `paseo run` from a seat (dependent, independent, models, workspaces)

> **Role:** the working contract for launching a **pi agent through the Paseo daemon** from a shell on a
> seat: the two launch shapes and what each inherits, how a model/provider is selected and *proved*, how a
> workspace is bound, and the traps that make a launch report something other than what it started. It is
> a `paseo run` reference, not a seat inventory.
> **Linked from:** [`fast_v33_draft.md`](fast_v33_draft.md) (R4 — the build/converge session split),
> [`docs/index.md`](docs/index.md) (dispatch row)
> **Authority: limited.** How a daemon gets installed, bound and reached per seat is owned by
> [`prompt-passeo.md`](prompt-passeo.md) and [`docs/harness-pi-seats.md`](docs/harness-pi-seats.md) §1;
> the model rows and their prices are owned by
> [`scripts/harness/pi/models-spec.yml`](scripts/harness/pi/models-spec.yml) and
> [`docs/harness-pi-models.md`](docs/harness-pi-models.md); whether an external lane may run at all is
> owned by [`README.md`](README.md) §3 and the `sensitivity:` rule in [`CONVENTIONS.md`](CONVENTIONS.md) §8.6.
> Where this page disagrees with one of those, that page is right and this one is the defect.

---

## 1. The three facts that decide everything

1. **The daemon owns the agent, not the shell that launched it.** An agent outlives every client and every
   terminal; `--no-wait` returns the id immediately and nothing stays attached to the caller's process tree.
2. **The caller's environment decides whether the new agent is a child or a stranger.** `PASEO_AGENT_ID`
   says *who is asking*, `PASEO_AGENT_CWD` says *where they work*; a launch that carries them produces a
   **dependent** agent, one that does not produces an **independent** one. They are different tools.
3. **Nothing on the launching side proves the model.** The CLI argument, `paseo inspect`, and the agent's
   own `PI_MODEL` are three different claims — section 4 reads all three.

```bash
paseo status            # localDaemon: running + listen + daemonVersion   (binary: ~/.local/share/pi-node/current/bin/paseo)
paseo provider ls       # which providers this daemon can drive, and their modes
paseo ls -g             # every agent, with PROVIDER / STATUS / CWD / CREATED   (-g includes archived)
```

`paseo` is invisible to a non-login shell: over `ssh host cmd` neither startup file is read, so every
remote leg names `bash -lc` (the trap is written in [`prompt-passeo.md`](prompt-passeo.md)'s seat table).

---

## 2. Dependent launch — a child of the calling agent

```bash
paseo run --no-wait -q --provider pi --model <provider>/<model-id> --title <t> "<prompt>"
```

Run from inside an agent (a lane session, a pi session the daemon already owns), this **inherits the
caller**: `ParentAgentId` is the caller, `Cwd` is the caller's workspace (`--cwd` is *not* honoured when it
conflicts with it), and the caller's opening turns arrive in the child's first message as a
`<paseo-system kind="agent-message" source-agent-id=…>` record.

| use it | never use it |
|---|---|
| a helper whose context should be *this* conversation; a reviewer that must see what the parent just did; anything whose parent survives it | a session that must outlive the parent — **a child of a spark-served session dies when that engine restarts**, which is every converge window; or a session on an external provider, because the injected context is the parent's, and that is the egress question of [`CONVENTIONS.md`](CONVENTIONS.md) §8.6, not a detail |

## 3. Independent launch — the shape for anything that must survive or must not know

```bash
env -u PASEO_AGENT_ID -u PASEO_AGENT_CWD \
    -u PI_SESSION_ID -u PI_SESSION_FILE -u PI_PROVIDER -u PI_MODEL \
  paseo run --no-wait -q --provider pi \
    --model <provider>/<model-id> \
    --env PI_PROVIDER=<provider> --env PI_MODEL=<model-id> \
    --cwd <absolute/path> \
    --title <t> --label <k>=<v> \
    "<self-contained prompt: it inherits nothing, so the prompt is the whole context>"
```

Measured result: `ParentAgentId` = `null`, `--cwd` honoured, and the only project context present is the
one `--cwd` resolves to. Both strips have a reason: `PASEO_*` make it a child, `PI_SESSION_*` make it
*this* conversation's identity. Substituting `--workspace <id>` for `--cwd` keeps the independence —
`ParentAgentId` still answers `null` — and changes only which checkout the session lands in and whose
`AGENTS.md` rides along.

## 4. Models and providers

| claim | where it lives | what it proves |
|---|---|---|
| `--model <provider>/<model-id>` | the CLI | what the daemon was **asked** for; `paseo run --provider pi --model entrim/deepseek-ai/DeepSeek-V4.1-Flash-1017` |
| `Model` / `Provider` in `paseo inspect <id>` | the daemon | what the daemon **attached** to the session |
| `model_change` record in the session file | pi | what the session **ran** |
| `echo $PI_PROVIDER $PI_MODEL` inside the agent | the process env | what **tools inside** the session will read |

The session file is the tie-breaker, named by the cwd-encoded project dir:

```bash
# ~/.pi/agent/sessions/--<cwd with / replaced by ->-/<ts>_<id>.jsonl   e.g. --home-domen-source-homelab--, --tmp--
python3 -c "import json,sys;print([json.loads(l) for l in open(sys.argv[1]) if json.loads(l).get('type')=='model_change'][0])" <file>
# → {'type': 'model_change', 'provider': 'entrim', 'modelId': 'deepseek-ai/DeepSeek-V4.1-Flash-1017', …}
```

**The env row lies unless it is passed.** A model delivered only through `--model` can leave `PI_MODEL`
showing the seat's **default** model (the seat's `agentProfiles`/settings value), so a session actually
running an external row reports the local engine to anything that reads the env — including
[`scripts/gate/check_bench_provenance.py`](scripts/gate/check_bench_provenance.py), whose Rule 0 verdict
is computed from `PI_MODEL`. So `--env PI_PROVIDER=… --env PI_MODEL=…` is not cosmetic: it is the ledger's
truth. Format: `PI_PROVIDER=<provider>`, `PI_MODEL=<model-id>` (**no** provider prefix in `PI_MODEL`).

**Only the first slash separates.** A model id may itself contain one, and the local engine row does: its
`--model` is `spark/spark/qwen3.8-flash-next`, its `PI_MODEL` is `spark/qwen3.8-flash-next`, and `paseo ls`
prints the pair as `pi/spark/spark/qwen3.8-flash-next`. Splitting on the wrong slash yields a provider that
exists and a model that does not, which the daemon reports as a model error rather than a parsing mistake.

Provider rows and their ids come from
[`scripts/harness/pi/models-spec.yml`](scripts/harness/pi/models-spec.yml) rendered into
`~/.pi/agent/models.json`; a hosted row (`providers.entrim`) is run **only when the owner states it in the
session** ([`README.md`](README.md) §3). `--thinking <id>` selects the reasoning effort (`paseo run --help`
lists the ids per provider; `high` is this seat's default profile).

## 5. Workspaces

Workspace records live in `~/.paseo/projects/workspaces.json` (`workspaceId`, `projectId`, `cwd`,
`archivedAt`, `updatedAt`). Binding one is `--workspace <id>` (or `PASEO_WORKSPACE_ID`); the CLI prints
`Using workspace <id>` and, without a binding, tips that it exists.

```bash
python3 - <<'PY'
import json, os
d = json.load(open(os.path.expanduser('~/.paseo/projects/workspaces.json')))
c = [w for w in d if w['cwd'] == '/home/domen/source/homelab' and not w.get('archivedAt')]
c.sort(key=lambda w: w['updatedAt'])          # several live records can carry the SAME cwd
print(c[-1]['workspaceId'])
PY
```

- **The id is derived, never remembered** (§2 discipline): several live records can carry the *same* `cwd` —
  this daemon has held a handful whose `cwd` is the homelab checkout — so a hard-coded id eventually binds a
  stale or archived workspace, and an id built by concatenating every match is refused outright
  (`Workspace not found: wks_…wks_…`). That is exactly why the snippet sorts by `updatedAt` instead of
  guessing.
- **Binding happens at launch, and only at launch.** `paseo workspace` offers `setup`, `create`, `ls`,
  `rename`, `archive` — **no bind or rebind verb**, so a running agent cannot be moved to a different
  workspace afterwards. Nor is `paseo attach` such a verb: it attaches to an agent's **output stream**
  (section 6), which is a different thing wearing the same word.
- **Two agents may share one workspace,** and that is useful (same project context, separate rows in
  `paseo ls`) — but it makes the workspace a *context*, not an isolation boundary. The worktree is the
  boundary, so bind and then open a worktree.
- **`--workspace` beats `--cwd`.** Passed together, the workspace's `cwd` wins: the agent answered `pwd` =
  the workspace path while `--cwd` named another directory. Bind a workspace **or** name a cwd.
- **What proves the binding won.** `paseo inspect` carries **no workspace field** — its keys are `Id`, `Name`,
  `Provider`, `Model`, `Thinking`, `Status`, `Archived`, `Mode`, `Cwd`, `CreatedAt`, `UpdatedAt`, `LastUsage`,
  `Capabilities`, `PendingPermissions`, `Worktree`, `ParentAgentId` — so `inspect` alone cannot tell a bind
  from a cwd. The proof is the launcher's own `Using workspace <id>` line on stdout **and** `Cwd` equal to the
  record's path; that is also why the prompt must carry the worktree act, since `Cwd` names the merge station.
- **A workspace binding loads that project's context** (its `AGENTS.md` and quick-refs land in the prompt
  prefix, mostly as cache reads), which is what lets the kick line stay short — and what makes the
  checkout it points at part of the run. For the primary checkout that is the **merge station**, so the
  prompt must carry the worktree act ([`CONVENTIONS.md`](CONVENTIONS.md) §6) before any edit:
  `git worktree add ../homelab-wt-<date>-<HHMM>`.
- `--new-workspace local|worktree` (with `--worktree-mode`, `--new-branch`, `--base`) makes a managed
  workspace. A session launched that way works in a daemon-owned tree, **not** in the
  `../homelab-wt-*` naming this repo's rule requires — so for repo work, use a repo worktree + a
  `--cwd`/`--workspace` binding and let `git worktree remove` clean it.

## 6. The reads that settle a launch

```bash
paseo wait <id> --json            # status: idle | permission | error | timeout, plus the last activity items
paseo inspect <id>                # Model, Provider, Status, Cwd, Worktree, ParentAgentId, PendingPermissions, LastUsage
paseo send  <id> [prompt] [--prompt-file <f>]    # the next turn of the same session
paseo attach <id>                 # follow its output stream live; no options, and it never binds anything
paseo logs  <id> [-f]  ·  paseo stop <id>  ·  paseo archive <id>  ·  paseo delete <id>
```

**`attach` and `send` are the two verbs people mistake.** `attach` is a *reader*: it prints the agent's
reasoning and tool lines as they happen, takes no flags at all, and leaves the agent untouched — detaching
(or losing the terminal) does not stop the run. It is how you watch a session decide something, and from a
script it wants a bound: `timeout 60 paseo attach <id>`. `send` is a *writer*: it appends a turn to a session,
and an agent that is mid-run takes the message on its next step — which is how a launch that is about to do
something unplanned gets redirected instead of cancelled. The call returns a table naming that turn's status,
not the agent's answer; the answer is in `paseo logs`.

Four checks, in order, before believing a launched session is the session you asked for: `ParentAgentId`
(`null` = independent), `Model`/`Provider`, `Cwd`, and — when the run's numbers depend on it — the
in-agent `env | grep '^PI_'`. `LastUsage` reports what the session consumed, and on a **self-hosted** row
its `CachedTokens` can read `0` while the project prefix is being served, so treat it as a cost line and not
as proof that context came along: for that, read the launcher's `Using workspace <id>` line and `Cwd` (§5).

An agent waiting in `permission` is not hung: `paseo permit ls` / `paseo permit allow <id>`, or start it in
a mode that does not ask (`--mode`, per `paseo provider ls`).

## 7. Traps, each with its symptom

| trap | how it shows | the move |
|---|---|---|
| launched from inside an agent | the new session opens with the parent's text; `ParentAgentId` = the parent | strip `PASEO_AGENT_ID`/`PASEO_AGENT_CWD` (and `PI_SESSION_*`) for anything that must survive or must not see the parent |
| a child of an engine-served session | it dies mid-task the first time that engine restarts | independent launch, on a provider that is not that engine |
| `PI_MODEL` from the seat default | the session says the local engine while `paseo inspect` says a hosted row | pass both `--env` pairs; treat `paseo inspect` + the `model_change` record as the truth |
| `--cwd` with a workspace bound | `pwd` answers the workspace, not the flag | one or the other; verify with `paseo inspect`'s `Cwd` |
| a remembered `workspaceId` | `Workspace not found`, or a silent bind to an archived duplicate | re-derive from `workspaces.json` by `cwd` + `not archivedAt` + max `updatedAt` |
| `attach` read as the workspace verb | attaching to an agent seems like putting it in a workspace, and nothing changes | binding is launch-time only (§5); `attach` only streams output |
| steering a daemon agent with the harness's own child-control verb | `No async run found for <id>` | it is not a subagent child of this session: `paseo send <id> "<instruction>"` |
| a `send` expected to answer inside the call | the call returns a status line with no prose | that status means the turn was accepted; the work shows up in `paseo logs` / `attach` |
| `CachedTokens: 0` read as "no context" | a self-hosted row reports no cached tokens even while serving the project prefix | prove context with the `Using workspace <id>` line and `Cwd`, not with the usage counters |
| a non-login shell | `paseo: command not found`, read as "not installed here" | `bash -lc`, then ask the unit/daemon |
| `paseo wait` as a babysitter | the waiter dies with the launcher and the run looks abandoned | `--no-wait` at launch; `wait`/`inspect` from a survivor, or poll `paseo ls` |

## 8. Delegation from a launched session

A Paseo agent is an ordinary pi session once it starts, so it may **delegate**: bounded subagent children
under [`docs/orchestration.md`](docs/orchestration.md) section 4 — its overrides O1–O11 and the child-lane
contract O10–O11: at most two children concurrently, `model:` never named on a launch (a child inherits the
session's model), a deadline per child rather than a clock-based abort, and silence read as a compaction and
not a hang. The parent launches, reads the evidence and merges; the children read, analyse and write
([`README.md`](README.md) §4 item 7, [`CONVENTIONS.md`](CONVENTIONS.md) §6 — delegation is the default here,
not an escalation). What that contract decides is the lane policy; what this page owns is the launch-side
difference between the two ways a session gets help:

Two mechanisms, and the difference is not cosmetic:

| | pi subagent child | a `paseo run` agent |
|---|---|---|
| lifetime | inside the parent's session; dies with it | daemon-owned; outlives every client, and outlives the parent **only** if launched independent (§3) |
| model | inherits the parent's, always | whatever `--model` names, including a hosted row |
| visibility | inside the parent's timeline | its own agent in the app and on the phone (`paseo ls`) |
| cost of being wrong | a wasted lane | a bill, or context that left the box |

Both carry the same two consequences, checked before launching rather than after:

- **The children of an external-lane session run on that external provider**, because a subagent inherits
  its parent's model and never names another. So the read list of every lane is what
  [`CONVENTIONS.md`](CONVENTIONS.md) §8.6 grades — a lane that must read a `personal` or `secret-bearing`
  doc is not an external-lane lane, whatever the parent runs on.
- **Children of a session served by an engine add load to that engine**
  ([`docs/harness-pi-engines.md`](docs/harness-pi-engines.md) §6's concurrent-sequence budget), which is why
  a window takes its timed legs after the lanes close, never beside them (Rule 0,
  [`docs/orchestration.md`](docs/orchestration.md) section 4).

## 9. What this page does not cover

Seat installation, ports, listeners, relay/password and the per-seat reachability matrix
([`prompt-passeo.md`](prompt-passeo.md), [`docs/harness-pi-seats.md`](docs/harness-pi-seats.md) §1); the
PM-BE relay/launcher family and its review loop (that repository's own `tools/paseo/README.md`, unrelated
to this repo); scheduling, heartbeats and the orchestration skills, none of which a repo session needs;
and any claim that a hosted row is authorized — that is the owner's sentence in the session, never a line
in a file.
