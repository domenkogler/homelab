# prompt-secrets.md — the leak-debt lane: the four tools that stop the next leak, and the debts only an owner closes

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
- **Nothing in the tree can un-leak a value.** `~/.pi/agent/sessions/**/*.jsonl` and the `/tmp/pi-subagents-*/`
  scratch are outside the repo and grow for the life of a session: a rotated value stops being a finding, an
  unrotated one is never closed by deleting, shredding or `git rm`-ing a transcript
  ([docs/deployment-secrets.md](docs/deployment-secrets.md) §Creation & Rotation Workflow item 7). Ruled, and
  recorded as a rejection: transcript redaction as *remediation*
  ([docs/deployment-rejected.md](docs/deployment-rejected.md)) — containment lowers the copy count and keeps
  the debt line open.
- **The four tools the rows name are tasks, not references** — each is named again where it is owed:
  `pi-agent/extensions/vault-mask.ts` does not exist yet,
  `scripts/gate/secret_debt_register.txt` does not exist yet,
  `scripts/gate/check_secret_debt.py` does not exist yet,
  `scripts/secrets/contain-leaked-values.py` is not committed yet,
  and `scripts/git/install-hooks.sh` is not committed yet.
- **The instrument the tools hang off is finished and honest.** `check_secret_leak.py` matches by **content**
  (`MIN_VALUE_LEN = 8` is the containment floor it will not go under), names the stores it read per class,
  prints `NOT JUDGED` for a class it did not read, `PARTIAL` on an incomplete sweep, and exits `2` on a vault
  it cannot read rather than `0`. Its `--self-test` is the pattern each new tool copies.
- **The token story is settled and is not this lane's work.** The seat's read-scoped integration answers
  read-only, the write item is the read+write one, there is no CI holder for either, and the host installs are
  listed in [docs/1password.md](docs/1password.md) §Where a token is installed — so nothing here waits on a
  re-seat, and a `403` with a freshly written token file is the running shell beating the file, not a bad
  install (§Proving which service account an install holds).
- **This seat is the WSL Debian clone on the laptop**, served by spark — so Rule 0 binds it: no spark engine
  restart and no `spark-ai` re-render from a session like this one (README §3). Every rotation that needs the
  spark window is therefore parked, and parking it is the correct outcome, not a stall.

## 2. The register read — the only list this brief uses

```bash
python3 scripts/gate/check_secret_leak.py                       # this seat, all three classes
python3 scripts/gate/check_secret_leak.py --update-ledger --class run-capture   # after a rotation, on a
                                                                                 # signed-in seat that HAS the store
python3 scripts/lib/vault_read.py --list                        # titles + ids + VERSION numbers, ONE request,
                                                                                 # no values — the rotation probe
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

- **Files:** `scripts/gate/secret_debt_register.txt` (data — does not exist yet) and
  `scripts/gate/check_secret_debt.py` (verdicts — does not exist yet). A **companion** book, deliberately:
  columns on the ledger itself were weighed and
  declined, because `--update-ledger` rewrites that file's body and a fourth column dies at the next run.
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

- **File:** `pi-agent/extensions/vault-mask.ts` (to be written; the `extensions` plane already deploys and
  drift-checks `pi-agent/extensions/**` on all three seats, so nothing new is installed — the repo IS the
  deployment).
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

- **File:** `scripts/secrets/contain-leaked-values.py` (to be written) — **manual invocation only**, never a
  `validate-all.sh` item, never an automatic sweep.
- ⚠ **The scope derivation the row names does not yet resolve, and that is the first box.** The row derives
  scope from `NOT_AUTO_ROTATABLE` in [`scripts/secrets/provision-secrets.py`](../scripts/secrets/provision-secrets.py)
  ∩ the register — but the items containment is *for* (`pppoe_login`, `slskd_login`, `soulseek_login`) are
  hand-seeded and appear **nowhere** in that file: their "not rotatable" ruling lives as prose in
  [docs/network-rejected.md](docs/network-rejected.md) and [docs/services-rejected.md](docs/services-rejected.md).
  So the intersection as written answers "nothing", and the tool would either do nothing or reach for a
  hand-typed list — which the row itself forbids. **Settle it before writing code:** put the machine-readable
  `not-rotatable` fact in ONE place (HD-1217's register is the natural home, since that book already answers
  "who acts, and did it rotate"), and have both the tool and the gate derive from it. Cheap test: print the
  derived scope and count it — it must be non-empty, must contain the not-rotatable ids the register carries,
  and must contain nothing that `--rotate` would accept.
- **Replace by value, never by shape**; refuse git objects, IaC and rendered live config, and the invoking
  session's own `SESSION_DIR` (the tool editing the file the harness is appending to is the fourth leak);
  `--dry-run` by default; print item ids and counts only.
- **It writes a 0600 append-only receipt** `(item-id, class, seat, paths changed, vault version, timestamp)`,
  and `check_secret_leak.py` reads that receipt so a contained pair prints **`CONTAINED`** — never `STALE`,
  never `OK`. Without that leg a redaction reads as a rotation, which is the one thing the ledger's own header
  forbids; the verdict word is therefore part of the tool, not a follow-up.
- Proving a mask landed is the scanner's hit count before and after, which prints no value.

## 4. The residue that closes only with an owner act

⛔ **No lane rotates, re-issues or deletes a vault item here.** Every act in this section is O4-parked: the
lane's job is to keep the list honest and the tools ready, not to approximate the act.

**4a. What closes each register line** — derive the lines from the ledger file, never from this table; the
table states the *channel* each class of item closes through, which is what no machine holds:

| the line's shape | the channel that closes it | example class |
|---|---|---|
| not rotatable at all (ISP-provisioned, a network account with no reset mail) | nothing — containment lowers the copy count, the line stays | `run-capture` |
| rotatable only where the service issues it (an engine accepted-key list, a device community, a WG keypair) | the far end first, then the vault, then the converge — in a named window, on the slot that service owns | `run-capture`, `git-history` |
| an item with no consumer (a retired service) | the owner deletes the **item** together with the retired paths it still guards — a vault write there is the divergence the guard names | `run-capture` |
| a trust anchor rather than a credential (a certificate fingerprint) | the cert is regenerated, both pinning sides re-render — and the line's meaning changes with it | `run-capture` |
| a credential that lives in the **human** vault | an owner write; a lane's token cannot reach it | `run-capture` |

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
- [ ] Write `scripts/gate/secret_debt_register.txt` and `scripts/gate/check_secret_debt.py` (both do not exist
      yet) with the fixture-only `--self-test` and the version-bump test in §3a.
- [ ] A registry row in [`scripts/README.md`](scripts/README.md) for each new file — `check_script_layout.py`
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

- [ ] `pi-agent/extensions/vault-mask.ts`: the chained `tool_result` handler, `structuredContent` included,
      one batched read per process, the loud rotation bypass.
- [ ] Push the plane on every seat, then `sync-extensions.sh --check --strict` green.
- [ ] The acceptance read: the recurring item stops appearing on the next run. Name the seat.
- [ ] `todo.md` — HD-1216's tail.

### Phase 4 — containment (HD-1218)

- [ ] Settle the scope-derivation question in §3d, in the one place the register owns, with the count printed.
- [ ] Write `scripts/secrets/contain-leaked-values.py` (not committed yet) and the `CONTAINED` verdict in
      `check_secret_leak.py`, both halves covered by `--self-test` arms that read no vault.
- [ ] One `--dry-run` over the stores on this seat: ids and counts only, then the real run, then the scanner's
      before/after hit count as the proof that a mask landed.
- [ ] `todo.md` — HD-1218's tail, and the register lines that now read `CONTAINED` stay open.

### Phase 5 — the owner batch

- [ ] The §4a channels, in the windows their owners choose; each rotation followed by
      `--update-ledger --class run-capture` on a signed-in seat **that has the store**, and the `STALE` lines
      deleted in the same commit.
- [ ] The §4a channels the owner schedules.
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
  it must never be run to make a red gate quiet. The gate is red at the tip **until a rotation lands** — that
  red is the design.
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
python3 scripts/gate/check_brief_coverage.py         # the row→brief map this brief joins
bash scripts/validate-all.sh                         # from the worktree
```

The register's own checker is not written yet, so it is absent from the block above by design — it joins it
when Phase 1 lands.

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

## 10. Held out on purpose

The rotations themselves (owner, §4) · every spark-window act, including HD-1170's close, which a spark-served
session may not run (Rule 0) · the router/switch legs `wg_password` and `network-snmp_api` wait on · HD-1174's
kopia connect-line scrub, which is `prompt-storage-backup.md`'s cell · HD-442's rendered seat token, owned by
`prompt-seat-cockpit-grants.md` · the app-side rotations HD-384 and HD-1091, owned by the litellm-consumers and
media lanes · the Win11 seat-parity class HD-1202, which every new script here inherits but no lane closes
from this brief · any second scanner, any automatic scrubber, and any `NOPASSWD` or bypass added to make a
verification loop quiet.
