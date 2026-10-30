# prompt-secrets.md — the leak-debt lane: the four tools that stop the next leak, and the debts a rotation is the only close for

> **Role:** the runbook for the secrets-hygiene residue: the four tools that keep a vault value out of a
> capture (HD-1216 · HD-1217 · HD-1218 · HD-1219), the row hygiene that keeps the debt register readable,
> and the owner-side acts that are the ONLY thing that closes a `run-capture` debt (HD-1170 · HD-1181).
> It is a lane brief, not a second backlog: every act below is a box on a row that already exists.
> **Rows it carries:** **1181** · **1170** · **1216** · **1217** · **1218** · **1219** — re-derive
> this list from [`todo.md`](todo.md) at the commit this file is edited (CONVENTIONS §4: an id is not stable
> prose). **Cited, not carried:** the kopia connect-line scrub (`prompt-storage-backup.md`'s cell), the rendered
> seat token (`prompt-seat-cockpit-grants.md`), the app-side rotations (`prompt-media-arrs.md` and
> `prompt-litellm-consumers.md`), and the Win11 seat-parity class every new script inherits (§7) — the ids those
> lanes hold are in §10, and none of them is this lane's to run.
> **Linked from:** [`todo-table.md`](todo-table.md) §B0 — the dispatch cell for the ids above.
> **Mechanics it does NOT restate:** the rotation mechanism (far end → vault → propagate → both-directions
> proof) is [prompt-update.md](prompt-update.md) §5a and
> [docs/deployment-secrets.md](docs/deployment-secrets.md) §Creation & Rotation Workflow. Read those before
> touching a value; this brief only says which acts are left and what is owed in the tree.

---

## 0. How to run this file

- **The list is read, never remembered.** One command (§2) produces the whole actionable set, ids and titles
  only. A register re-typed into a brief, a row or a doc is the defect CONVENTIONS §2 names — and this corpus
  has carried one.
- A box is ticked on **its own proof**, not on a plausible-looking run. Every proof here prints ids, counts,
  `sha256[:12]` or a verdict word — **never a value, never a length, never a captured line** (CONVENTIONS §6).
- **A green leak-gate is a statement about the seat it was taken on**, not about the fleet. Name the seat with
  every verdict; the honest partial form is `--no-captures`, which prints `NOT SCANNED run-capture` and marks
  the run `PARTIAL`.
- `todo.md` is updated **once per phase**, after that phase's last box. ⛔ No `HD-` id is minted for anything
  in this file; the rows above are the whole queue.
- Lane contract: [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) — ≤2 children, the parent's model,
  one writer per worktree.
- **This file dies with its rows** (O7): the last commit that closes the last of them deletes it.

## 1. State this brief was written against

- **The gate's verdict is seat-local, and on this seat it is green — which is not the same as clean.**
  `python3 scripts/gate/check_secret_leak.py` exits `0` here and prints a `KNOWN-EXPOSED` block: that block **is
  the register** — every pair in it is a live value sitting where a capture can be read, listed so the gate
  reddens on a *new* one instead of going blind. A run on another seat reads that seat's store and may redden
  on hits this one cannot see, so the seat travels with the verdict. `scripts/gate/secret_leak_ledger.txt`
  is a debt register, not a mute button, and a line whose hit is gone prints `STALE` on every run until it is
  removed by hand.
- **A register line is a debt, not an assignment to a human.** Most of what the register names is rotatable by a
  lane through its far end; the lines that genuinely wait for a person are the no-channel and human-vault ones
  (§4a), and the fourth shape — credentials outside our scope — never closes, it only gets contained.
- **Nothing in the tree can un-leak a value.** `~/.pi/agent/sessions/**/*.jsonl` and the `/tmp/pi-subagents-*/`
  scratch live outside the repo and grow for the life of a session, so a rotated value stops being a finding while
  an unrotated one is never closed by deleting, shredding or `git rm`-ing a transcript
  ([docs/deployment-secrets.md](docs/deployment-secrets.md) §Creation & Rotation Workflow item 7). Ruled, and
  recorded as a rejection: transcript redaction as *remediation*
  ([docs/deployment-rejected.md](docs/deployment-rejected.md)).
- **The four tools the rows name are tasks, not references** — each is named again where it is owed:
  `pi-agent/extensions/vault-mask.ts` is enabled and deployed on every seat (the plane owns
  `pi-agent/extensions/**`, so placement there is the switch — an owner act),
  `scripts/gate/secret_debt_register.txt` and `scripts/gate/check_secret_debt.py` are both committed and
  wired into `validate-all.sh`,
  `scripts/secrets/contain-leaked-values.py` is committed and its `CONTAINED` leg is in the eye,
  and `scripts/git/install-hooks.sh` is committed with the `git-hooks` seat plane.
  What is still owed by all four is the **owner-side half**, never a second version of the tool.
- **The instrument the tools hang off is finished and honest.** `check_secret_leak.py` matches by **content**
  (`MIN_VALUE_LEN = 8` is the containment floor it will not go under), names the stores it read per class,
  prints `NOT JUDGED` for a class it did not read, `PARTIAL` on an incomplete sweep, and exits `2` on a vault
  it cannot read rather than `0`. Its `--self-test` is the pattern each new tool copies.
- **The token story is settled and is not this lane's work.** The seat's read-scoped integration answers
  read-only, the write item is the read+write one, there is no CI holder for either, and the host installs are
  listed in [docs/1password.md](docs/1password.md) §Where a token is installed — so nothing here waits on a
  re-seat, and a `403` with a freshly written token file is the running shell beating the file, not a bad
  install (§Proving which service account an install holds).
- **This seat is the WSL Debian clone on the laptop**, served by spark — so the spark-served dispatch filter binds
  the whole run: no child against the spark engine brief, and no converge that is not provably engine-safe
  ([docs/orchestration.md](docs/orchestration.md) §4). HD-1170's rotation is neither — it recreates the engine to move
  its `--api-key` argv — so every rotation that needs the spark window is parked here, and parking it is the correct
  outcome, not a stall. ⛔ Rule 0 is the *timed-number* rule and HD-1170's row says the tree carries no
  `PI_PROVIDER=spark` guard: argue the park from this filter and from the row's own preflight, never from a guard that
  does not exist.

## 2. The register read — the only list this brief uses

```bash
python3 scripts/gate/check_secret_leak.py                     # this seat, all three classes
python3 scripts/gate/check_secret_leak.py --update-ledger --class run-capture
    # after a rotation, on a signed-in seat that HAS the store
python3 scripts/lib/vault_read.py --list                      # titles + ids + VERSION numbers, ONE request
```

- Run it on **each seat that has a store** (`win11`, `wsl`, `oldsrv`); the rotation list is the **union**, and a
  seat that was not read answers nothing either way.
- It costs a batched whole-vault read and **prints** the cost (`requests=…`). The ceiling that binds is the
  **account's** 1000 requests / 24 h across every service account on it, not a per-token hourly one
  ([docs/1password.md](docs/1password.md) §What a gate run costs the vault). Never read the vault twice in one
  process, and never write a leg that fans out `op item get`.
- Self-tests and fixtures must read **zero** requests: aim `HL_VAULT_READ_FIXTURE` at a minted JSON file
  ([`scripts/lib/vault_read.py`](../scripts/lib/vault_read.py)). A gate whose `--self-test` needs the vault is
  a gate that cannot run on a seat that is offline.

## 3. The four tools — the order is a dependency, not a preference

**HD-1217 → HD-1219 → HD-1216 → HD-1218.** The book comes first because containment derives its scope from it
and the masker's acceptance is read out of it; the push gate is independent and cheap, so it lands second and
starts protecting the commits the other three are made of.

### 3a. HD-1217 — the debt book that says who acts, on which seat, and whether it rotated

- **Files:** `scripts/gate/secret_debt_register.txt` (data) and `scripts/gate/check_secret_debt.py`
  (verdicts) — both committed, both gated. A **companion** book, deliberately: columns on the ledger
  itself were weighed and declined, because `--update-ledger` rewrites that file's body and a fourth
  column dies at the next run.
- **The exit classification is a ruling, and the checker prints it on every run:** `REFUSED` and
  `UNLEDGERED` are RED, `NOT ROTATED` and `CANDIDATE` are REMINDERS that name the actor from the `path:`
  column, and `CLOSED`/`GONE`/`NOT JUDGED` are STATE. The reminder half exists because a `path: none`
  line is a credential no act can move, so a red on that word is true forever — and a permanently-red
  gate is the mute CONVENTIONS.md §6.4 exists to prevent. ⛔ It mutes no CURRENT value: that red is
  `check_secret_leak.py`'s, and `UNLEDGERED` exists so the book agrees with it instead of tabling it.
- **Key:** `(item-id-prefix, class, seat)`, carrying the vault **`version` at leak time** and the owning doc's
  rotation link. The version is what makes "rotated?" a *fact* rather than a memory: `--list` answers versions
  for one request, version unchanged ⇒ provably `NOT ROTATED`, version moved ⇒ `CANDIDATE — prove with
  check_secret_leak.py`, hit gone ⇒ `CLOSED — remove the line`.
- ⛔ **Never hash values for this check.** On credentials this short, a hash is an offline guess-check, and the
  fleet's rule is that a hash proves a *holder*, not a history.
- **Seat locality:** a seat that read no store prints `NOT JUDGED` for **its own** lines and may never close
  another seat's. That is the same rule `check_secret_leak.py` already enforces per class — read its `--class`
  refusal and copy the shape.
- **Order inside the box:** re-derive the ledger first (`--update-ledger --class run-capture`), or the register
  inherits every stale line the book still carries.
- **Cheap test that proves it:** point the checker at a fixture vault whose version for one listed item is
  bumped in the fixture only. The verdict must move `NOT ROTATED → CANDIDATE` without any other line changing.

### 3b. HD-1219 — the thing that stands between a commit and the remote

- **File:** `scripts/git/install-hooks.sh` (to be written), installing a `pre-push` hook that runs
  `python3 scripts/gate/check_secret_leak.py --tree-only --no-history` and refuses the push when it reddens.
- **Why a push and not a commit:** a commit loop pays a vault read per commit; pushes land at phase boundaries,
  so the same coverage costs a fraction of the shared account budget. The per-commit form is declined in
  [docs/deployment-rejected.md](docs/deployment-rejected.md) — do not re-litigate it.
- ⚠ **Hooks live in the COMMON git dir, not the worktree's.** In a linked worktree `git rev-parse
  --git-path hooks` resolves to the primary clone's `.git/hooks` (read both paths from a linked worktree before
  writing the installer), so the installer must write there and **one install covers every worktree of that
  clone** — and an installer that writes into a worktree's own `.git` installs nothing at all. Resolve with
  `git rev-parse --git-common-dir`, never with `$(dirname "$(git rev-parse --git-dir)")`.
- **Declare it as a seat plane** in [`scripts/lib/seat-planes.yml`](../scripts/lib/seat-planes.yml): `harness:
  all`, `owner: install-hooks.sh`, `seats: win11 wsl oldsrv`, `check: --check --strict`, `push: --push`. The
  driver then *reports* a seat with no hook instead of assuming one. A seat that runs no converge must still
  get checked — the plane set is the only place a seat's state is declared.
- **The hook speaks only for `repo-tree`.** It must print `run-capture NOT JUDGED` and `git-history NOT
  JUDGED`; the flag pair already does exactly that and marks the line `PARTIAL`, so the leg is a wrapper, not a
  new verdict — and a green that implies the captures were read is the precise failure this family documents.
- **Self-test arms:** a canary value planted in the tree reddens the hook; a clean tree passes; a seat with no
  reachable vault **SKIPs with a printed reason** (the checker's exit `2` boundary), never silently. A `SKIP`
  that reads as a pass is the shape CONVENTIONS §6 calls a green that cannot fail.

### 3c. HD-1216 — the masker at the earliest seam where a value can be stopped

- **File:** `pi-agent/extensions/vault-mask.ts` — **enabled; the arms stay in `pi-agent/proposed/`.** The
  `extensions` plane owns `pi-agent/extensions/**` as a directory glob, so a file committed there is live on
  every seat; a hook that transforms tool output is a fleet-wide harness change, so placement in that
  directory is the owner's act and `proposed/` is where a written-but-unaccepted hook waits.
- **The hook is `tool_result`.** It is *chained* — each handler sees what earlier handlers returned — and a
  handler that redacts `content` **must replace `structuredContent` too**, or replacing only `content` drops
  it. That is the one integration detail that decides whether the tool works — the pi package's own
  extension guide states the `tool_result` contract; read it before writing the handler.
- **Match by value, never by key name.** The rendered `KEY: "value"` shape is what has walked past every
  shape-based filter here; the same `MIN_VALUE_LEN = 8` floor applies, so a short value reports `unmasked`
  rather than pretending, and each masked hit prints a marker naming the **item prefix** so a human can go and
  read it deliberately.
- **Values come from one batched read** through [`scripts/lib/vault_read.py`](../scripts/lib/vault_read.py),
  held in memory only, with the request count printed like every other leg. Every child session is its own
  process, so a busy lane pays that cost per child against the shared account bucket: read once per process,
  print the count, never read twice.
- **A rotation leg needs a bypass**, because a masker that rewrites the value a rotate is about to write
  breaks the act. Make the bypass loud — an env var plus a printed line — never a silent setting, and never a
  bypass that survives into the next command.
- **Acceptance is not "it loaded":** the item that recurs across unrelated sessions must stop appearing on the
  next `check_secret_leak.py` run. ⛔ Prevention closes nothing already captured — no box in this section
  reduces the register by one line.

### 3d. HD-1218 — containment, for the values this fleet cannot rotate

- **File:** `scripts/secrets/contain-leaked-values.py` (committed) — **manual invocation only**, never a
  `validate-all.sh` item, never an automatic sweep. `--dry-run` is the default; `--apply` is the act.
- ⚠ **Two lists, one misleading name.** `NOT_AUTO_ROTATABLE` in
  [`scripts/secrets/provision-secrets.py`](../scripts/secrets/provision-secrets.py) is the **auto-rotation
  guard**: it asserts one narrow thing — *a vault-only `--rotate` write here would leave the far end running the
  old value* — so `--rotate` refuses the item and `--rotate-all` reports `skip (coupled)`. Most of its members are
  rotatable by a **lane**, because the far end is a host command, an app's config file, a device API, or the
  converge itself (§4). Containment is for the set with **no rotation path at all** — a human act (a provider or
  1Password console, where `op_api`'s re-issue sits, or a write into the **human** vault), or a credential outside
  our scope (`pppoe_login`, the Soulseek network account). The two sets overlap and neither contains the other,
  so containment derives from the register's `path: none` half and never from the guard.
- **Where the fact lives — ruled.** Two places, and the checker holds them equal. HD-1217's register carries the
  per-debt `path:` column — `lane` / `lane+converge` / `human` / `none` — and
  [`scripts/secrets/provision-secrets.py`](../scripts/secrets/provision-secrets.py) states a `NOT_ROTATABLE` set
  that names the same ruling at the item level, beside — and deliberately distinct from — the
  `NOT_AUTO_ROTATABLE` guard. Containment derives `path: none` ∩ the register and cross-checks it against
  `NOT_ROTATABLE`; an arm reddens when the two disagree, because two copies of one ruling is the twin every gate
  in this repo exists to catch. ⛔ Neither repurpose nor rename `NOT_AUTO_ROTATABLE`: its meaning belongs to the
  auto-provision path, and renaming it moves a decision every rotate leg depends on.
  Cheap test: print the derived scope and count it — non-empty, holding every register line whose far end has no
  machine channel, and holding nothing `--rotate` would accept today.
- **Replace by value, never by shape**; refuse git objects, IaC and rendered live config, and the invoking
  session's own `SESSION_DIR` (the tool editing the file the harness is appending to is the fourth leak);
  `--dry-run` by default; print item ids and counts only.
- **It writes a 0600 append-only receipt** `(item-id, class, seat, paths changed, vault version, timestamp)`,
  and `check_secret_leak.py` reads that receipt so a contained pair prints **`CONTAINED`** — never `STALE`,
  never `OK`. Without that leg a redaction reads as a rotation, which is the one thing the ledger's own header
  forbids; the verdict word is therefore part of the tool, not a follow-up.
- Proving a mask landed is the scanner's hit count before and after, which prints no value.

## 4. The residue — four shapes, and only two of them wait for a human

⚠ **A register line is not automatically a human's job** — read `NOT_AUTO_ROTATABLE` as the auto-rotation guard
it is (§3d), never as "cannot be rotated". Most secrets here are **AI-rotatable**: where a lane has a channel to
the far end, the rotation IS lane work — far end first, then the vault write, then the converge that propagates
it. The mechanism and the write-scoped-token form are [prompt-update.md](prompt-update.md) §5a/§5b and the per-item
far ends live there, not here; what this section adds is only the **shape** of each remaining line, which is the
fact no machine holds.

| shape | who acts | what closes the line |
|---|---|---|
| the far end answers a lane's channel — a host command, an app's config file, a device API, the converge itself | **AI** | rotate, propagate, then `--update-ledger --class run-capture` and delete the `STALE` lines |
| the far end answers, but the propagation costs a restart inside someone's window | **AI, in that window** | the same act, run when that slot is free (engine argv, a router WG write) |
| no machine channel exists, or the write target is the **human** vault | **owner** (O4) | the act itself; until then the line stays and the register says `human` |
| outside our scope — an ISP credential, a network account whose reset mail never arrives | **nobody** | containment only (§3d), and the line stays open by design |

**4a. The current lines, by shape** — derive the lines from the ledger file, never from this prose; what is
stated here is the channel each one closes through:

- **lane, needs the router slot:** the WireGuard pair (`wg genkey` on both ends, both items written, the converge
  renders the private key) and the device SNMP community (`/snmp community` on both MikroTiks plus the exporter
  render — the exporter and the device must not sit on different communities).
- **lane, needs a converge:** `kopia-server_fingerprint` — ⚠ its current value is a cert **fingerprint**, so the
  line stays even after the cert moves (ruling S7); a rotated-out fingerprint is a dead value, not a closed debt.
- **lane, inside the spark window:** `spark-llm_api` with `litellm-engine_api` riding it — see §4b.
- **lane + owner split:** `spark_login` — `passwd` on the box is a lane act, the vault write is not, because the
  item lives in the human vault. Prove the fresh SSH in a second session before anyone reboots.
- **owner:** `immich_oidc` (an owner call — ruling S4), `pgvector_db`, which closes when the owner deletes the
  item **with** the retired paths it guards (a vault write there is the divergence the guard names), and the item the
  ledger titles `slskd slskd@kogler.si` — a value **no IaC file reads**, so the close is the owner rotating it or
  retiring the item, never a re-render.
- **nobody:** the `pppoe_login` and Soulseek-account lines — containment is the only act available, it lowers the
  copy count, and it closes nothing.

**4b. HD-1170 — the published bearer.** ⏳ Rotate `spark-llm_api` (with `litellm-engine_api` riding it) in one
spark window; `git rm` stops the ongoing exposure at HEAD and touches no history, and a history rewrite buys
tidy history, not containment. It is parked on the owner's word, unscheduled — **do not re-surface it as a
blocked lane**, and do not treat the gate's `git-history` lines as a repo defect.
**4c. HD-1181 — the row itself.** It is the largest row in the backlog and it carries the register's
per-pair narration, which is what `secret_leak_ledger.txt` and the owning doc own. ⏳ Move that half to
[docs/deployment-secrets.md](docs/deployment-secrets.md) §Creation & Rotation Workflow, leave the row stating
what is missing plus the commands, and keep the ⏳ legs (1) — the owner rotations and the book re-derive that
follows them. Clearing this is **not** a trim: it is the state-only rule (CONVENTIONS §4), and
`check_backlog_prose.py` prints the size reminder until it happens.

## 5. The phases

### Phase 0 — the seat, and the read

- [ ] `python3 scripts/gate/check_secret_leak.py` from this seat; record the verdict word and the **seat name**
      with it. If the vault is unreadable, `python3 scripts/lib/vault_read.py --install-sdk` and re-run — the
      fallback fan-out spends orders of magnitude more of the shared bucket.
- [ ] The other two seats' reads, if their owners are reachable; the union is the rotation list, and a seat that
      was not read is stated as unread rather than assumed clean.
- [ ] `bash scripts/validate-all.sh` from the worktree, green; name every SKIP by reason.
- [ ] `todo.md` — one line in each row this brief rides; no new ids.

### Phase 1 — the book (HD-1217)

- [ ] Re-derive the ledger first: `--update-ledger --class run-capture`, delete the `STALE` lines by hand.
      ⛔ not while a live un-rotated finding still hits — Phase 5 states the mute-button rule.
- [x] `scripts/gate/secret_debt_register.txt` and `scripts/gate/check_secret_debt.py`, with the
      fixture-only `--self-test` and the version-bump test in §3a.
- [x] A registry row in [`scripts/README.md`](scripts/README.md) for each new file — `check_script_layout.py`
      reddens a script the registry does not carry, and the row states what the tool refuses.
- [ ] `todo.md` — HD-1217's tail.

### Phase 2 — the push gate (HD-1219)

- [ ] Write `scripts/git/install-hooks.sh` (not committed yet): the common-dir install, the `--check`/`--push`
      pair, and the `SKIP` arm.
- [ ] The `git-hooks` plane in `scripts/lib/seat-planes.yml`; `pi-seat-sync.sh --check` reports the seats.
- [ ] One real `git push` with a canary in the tree, in a throwaway commit that never lands: the hook must
      refuse it. Then remove the canary and prove a clean push still passes.
- [ ] `todo.md` — HD-1219's tail.

### Phase 3 — the masker (HD-1216)

- [x] `pi-agent/extensions/vault-mask.ts`: the chained `tool_result` handler, `structuredContent` and
      `details` included, one batched read per process asked for from the eye's own needle map, the loud
      rotation bypass. Arms: `bun pi-agent/proposed/vault-mask.selftest.ts` (9 arms, zero vault requests —
      the child env is passed explicitly, since the fixture seam is otherwise seat-dependent).
- [x] Enabled: the file sits in `pi-agent/extensions/`, `sync-extensions.sh --push` ran on every seat and
      `--check --strict` is green on each.
- [ ] The acceptance read: the recurring item stops appearing on the next run.
- [ ] `todo.md` — HD-1216's tail.

### Phase 4 — containment (HD-1218)

- [ ] Land the two halves of the ruling: `NOT_ROTATABLE` in `provision-secrets.py` and the register's `path:`
      column (§3d), plus the arm that reddens when they disagree.
- [x] `scripts/secrets/contain-leaked-values.py` and the `CONTAINED` verdict in `check_secret_leak.py`, both
      halves covered by arms that read no vault (13 arms + one mutation arm in the eye).
- [x] One `--dry-run` over the stores on this seat: 3 items in scope, 526 files read, `2 occurrence(s) across
      1 file(s)`, and a shared-value refusal that found something (the row's tail names it: `spark_login` carries the
      Soulseek bytes).
- [ ] ⏳ **OWNER:** `--apply` — it rewrites past captures irreversibly for two copies and closes nothing.
- [ ] `todo.md` — HD-1218's tail, and the register lines that now read `CONTAINED` stay open.

### Phase 5 — the rotations, by shape

- [ ] The **lane** lines, driven in the lane that owns the item and the slot it needs (§4a): far end → vault →
      propagate → new-accepted / superseded-refused. ⛔ never the vault first, and never a `--rotate` on a name
      the guard refuses as coupled.
- [ ] The **owner** lines, when the owner takes them; the ones with **no path** stay open and go to §3d instead.
- [ ] After any rotation: `--update-ledger --class run-capture` on a signed-in seat **that has the store**, and
      the `STALE` lines deleted in the same commit — that commit is what makes the gate honest again. ⚠ **Only when
      the run's remaining hits are all ledger-worthy:** the re-derive derives from THIS run's hits, so with a live
      un-rotated finding still hitting it would mint a ledger line for a CURRENT value — the mute button §7 names.
      When the residue includes one, skip the rewrite; the register line and the leak gate's red are the record.
- [ ] `todo.md` — the register rows shrink here; the rows whose ⏳ list empties are **deleted**, their record
      being the owning doc and the commit.

### Phase 6 — the documentation pass, then this file dies

- [ ] §4c's row hygiene, once.
- [ ] [`prompt.md`](prompt.md) and [`todo-table.md`](todo-table.md) §B0 re-derived for the ids that closed;
      `check_brief_coverage.py` clean.
- [ ] `bash scripts/validate-all.sh` green (or red only on a named, dated exception).
- [ ] Commit, merge, push; delete this brief in the commit that closes the last of its rows.

## 6. File ownership

| area | this brief's files | owned by someone else |
|---|---|---|
| new tooling | the four tools of §3, each named by its own subsection, plus `scripts/gate/check_secret_leak.py` (the `CONTAINED` verdict), `scripts/lib/seat-planes.yml` (one plane), `scripts/README.md` (registry rows) | `scripts/harness/**` beyond that plane's declaration stays the seat lane's |
| the book | `scripts/gate/secret_leak_ledger.txt` (re-derive + delete `STALE` only) | `scripts/secrets/provision-secrets.py`'s CATALOG / `NOT_AUTO_ROTATABLE` — touched only by an item's owning lane |
| docs | `docs/deployment-secrets.md` (the register narration, §4c), `docs/1password.md` only if a token install changes | `docs/backup.md` (HD-1174's kopia mechanics) |
| IaC | **none** — this brief converges nothing of its own | every rotation's converge belongs to the host lane that issues the value |

⛔ Never `--diff` a converge to "see" a secret, never `cat` a rendered config, never `env` / `set` /
`printenv` / `/proc/<pid>/environ` into a session: a diagnostic that lists "interesting" variables is the leak
class this brief exists to close. The answer to "was this process started with the token?" is a **count** or a
12-hex hash, and [docs/deployment-secrets.md](docs/deployment-secrets.md) item 7 carries both forms.

## 7. Traps

- **A store-less checkout prints a false green.** The `run-capture` class is judged per **store**; `/tmp` scratch
  can make the corpus non-empty while `$HOME` holds nothing. If a run does not name `pi-transcripts` among the
  stores it read, its silence about a persistent-store debt is `NOT JUDGED`, not `OK`.
- **A ledger line for a live value that a re-derive mints is a mute button.** `--update-ledger` may drop lines;
  it must never be run to make a red gate quiet. A live value the ledger does not name **reddens** the run, and that
  red is the design; a ledger that carries the debt by name is what makes the same run green and honest.
- **`--self-test` must cost nothing.** Any new leg that reaches the vault from a fixture arm is a gate that
  fails on an offline seat and spends the shared account budget for a test.
- **Seat parity.** Every new leg runs on the Win11 Git-Bash seat too: pin stdout/stderr to UTF-8 the way the
  sibling checkers do, never rely on `$( )` to preserve a CR, and make an environment boundary print `SKIP`
  rather than a pass (the HD-1202 class).
- **A mask is not a close.** Nothing in §3 lowers the register by one line; only §5 Phase 5 does, and only for
  items that CAN rotate. If a box in this file seems to make a debt vanish without a rotation, the box is wrong.
- **Two lanes, one file.** `check_secret_leak.py` is a live lane's tool as often as this one's; re-read it
  before editing and keep the change to the verdict word.

## 8. Verify before closing

```bash
python3 scripts/gate/check_secret_leak.py            # the register, all classes, this seat named
python3 scripts/gate/check_secret_leak.py --self-test
python3 scripts/gate/check_secret_debt.py            # the book: who acts, where, rotated yet
python3 scripts/gate/check_secret_debt.py --self-test
python3 scripts/gate/check_brief_coverage.py         # the row→brief map this brief joins
bash scripts/validate-all.sh                         # from the worktree
```

The debt checker prints its own exit classification, so a run states which verdicts reddened it and
which only reminded (§3a) — read that line before calling a red a defect.

Plus, per tool, the cheap test that only passes because of the fix: the version-bump arm (§3a), the canary push
(§3b), the recurring item absent from the next register read (§3c), and the before/after hit count of a
`--dry-run` versus its real run (§3d).

## 9. Rulings — do not re-decide

- **Containment is exposure reduction, never closure**; rotation stays the only close, and the debt line
  survives a redaction ([docs/deployment-rejected.md](docs/deployment-rejected.md), HD-1181's owner override of
  the no-transcript-edit half).
- **No transcript is deleted or edited to make a check green**, and no checker is edited to quiet a live value.
- **A leak check runs at a push, not at a commit** — the per-commit form costs the vault and is declined.
- **The register is a companion book, not ledger columns** — `--update-ledger` rewrites the ledger body.
- **Prevention and remediation never share a verdict word**: `CONTAINED` is neither `STALE` nor `OK`.
- **`NOT_AUTO_ROTATABLE` is the auto-rotation ordering guard, not a list of the unrotatable.** Membership means
  "a vault-only write leaves the far end behind", and the lane rotates those items through their far end. The
  no-path ruling lives in TWO places and they are held equal by a checker arm: the register's `path:` column and
  `NOT_ROTATABLE` in `scripts/secrets/provision-secrets.py`. The guard is neither, and is not renamed to say so.

## 10. Held out on purpose

The rotations themselves — each driven by the lane that owns the item and the slot it needs (§4a), never from
this brief · every spark-window act, including HD-1170's close, which the spark-served dispatch filter (not Rule 0)
keeps off this seat · the router-slot legs the WireGuard pair and the device SNMP community wait on · HD-1174's
kopia connect-line scrub, which is `prompt-storage-backup.md`'s cell · HD-442's rendered seat token, owned by
`prompt-seat-cockpit-grants.md` · the app-side rotations HD-384 and HD-1091, owned by the litellm-consumers and
media lanes · the Win11 seat-parity class HD-1202, which every new script here inherits but no lane closes
from this brief · any second scanner, any automatic scrubber, and any `NOPASSWD` or bypass added to make a
verification loop quiet.
