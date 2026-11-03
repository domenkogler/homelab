# `prompt-mcp.md` — Lane brief · the seat's MCP client config, the tool-server carrier, the C# tool leg

> **Role:** dispatch note for **one** lane session on the MCP-config domain: the artifact every other harness
> artifact has and this one does not — a repo-side SSOT for `~/.pi/agent/mcp.json` plus the ruling about which
> entries are fleet. **The row is the authority** for what is missing and how to do it —
> [todo.md](todo.md) **HD-1238** (id as of `6609c73d` — re-derive with `grep -c "^| HD-1238 " todo.md` before
> quoting it). This file carries the contract, the order of work, the traps and the file ownership; nothing else.
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) — read it once. It overrides README §4
and CONVENTIONS §6 at the items it numbers, and this brief restates none of them.

**Rows it carries, and which clauses are yours:** HD-1238 is one row with several legs. The `lsp-binaries` and the
win11 tool-server-carrier legs are closed facts in the row and in
[docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 — **do not re-open them**. The leg that is yours is
`~/.pi/agent/mcp.json`: no plane reads it, `scripts/lib/seat-planes.yml` names an owner for every other harness
artifact and nothing touches an MCP server list, so what an operator writes with `pi mcp add` lives only in that
HOME and no check separates a seat that has an entry from one that lost it.

**Converge hosts + slots (O3):** **none** — this is a seat plane, not a converge. It fans out through
[`scripts/harness/pi-seat-sync.sh`](scripts/harness/pi-seat-sync.sh), which deploys from **each seat's own clone**,
so `git worktree list` and `git -C <seat-clone> log --oneline -1` before you read a seat's verdict: a `STALE-CLONE`
pre-flight means the plane did not run, and it is not a red to chase in IaC.

**Read first:** [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 (the `mcp.json` row and the `mcp-server`
plane row) → [`../scripts/lib/seat-planes.yml`](scripts/lib/seat-planes.yml) (the plane registry — this is where
ownership is declared) → [`scripts/harness/seat-mcp-server.sh`](scripts/harness/seat-mcp-server.sh) (the launcher
half, already owned: it renders a systemd **user** unit, proves it by reading `127.0.0.1:7777` back rather than
trusting `active`, and refuses a unit it did not write) →
[`IaC/ansible/group_vars/all/versions.yml`](IaC/ansible/group_vars/all/versions.yml) (the `scope: fleet` rows the
settings plane composes packages from — the shape your SSOT should copy, not invent).

**Order of work (nothing here needs an owner until step 3):**

1. **Measure the fleet, do not imagine it.** One read per seat of the real `~/.pi/agent/mcp.json` (win11, `wsl`,
   `oldsrv`) plus `pi mcp list` where it exists, and the port read that is the only proof a `url` entry means
   anything. Two live entries differ in **kind**, and that distinction is the whole design question: one is a public
   OAuth endpoint every seat can reach, the other is a `localhost` port that exists only while a desktop process
   holds it.
2. **Build the plane shape the registry already expects** — `check: --check --strict` against a repo file,
   `push: --push` writing it, one row in [`scripts/lib/seat-planes.yml`](scripts/lib/seat-planes.yml), and the leg
   wired into [`scripts/validate-all.sh`](scripts/validate-all.sh) with its `face` and its `subject` globs so
   [`scripts/gate/check-leg-contract.sh`](scripts/gate/check-leg-contract.sh) can grade the declaration. A seat plane
   with no leg is a check nobody runs.
3. **Then the owner gate (O4: park and continue).** Which entries are fleet is a ruling about data egress and about
   what every seat is allowed to be configured to reach — it is the owner's, stated in the session. Finish everything
   that does not need it (the reader, the writer, the drift verdict, the doc rows), write the exact blocked question
   into the row's `⏳` tail, and do not stall the lane waiting for it.
4. **Land the facts in the owner**, not here: the shape and the failure semantics go to
   [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1, a rejected shape to
   [docs/harness-rejected.md](docs/harness-rejected.md). This brief dies with the row (O7).

**Traps, each of which was already paid for once:**

* `pi` only ever **connects** to a `url` entry — it cannot launch one. A config that names an unreachable endpoint
  reads as configured and answers nothing, so the drift check must read the port, never the file.
* An **empty command line** binds port **5000** while `--help` advertises `7777`. Read the rendered unit, not the
  tool's own help.
* A `localhost` entry takes the silent `::1` leg on the WSL seat, where only `127.0.0.1` answers. A check that probes
  one loopback proves nothing about the other.
* The win11 carrier is a per-user **Startup** entry (`schtasks /Create /SC ONLOGON` answers `Access is denied`
  unelevated); on WSL the earliest moment is a login, which is why the boot-time half is still open.
* A fleet copy of a `localhost` entry buys every other seat a server it can never connect to — that is the reason
  step 3 exists and the reason "just ship both entries" is a decision, not a default.
* The C# leg is served **twice** by design and both are live in one session: `pi-lsp`'s `csharp` route and the MCP
  server's solution index. Only `lsp_diagnostics`, `lsp_fix` and `lsp_rename` are `pi-lsp`'s alone; NuGet type lookup
  and decompilation belong to the MCP server. Do not let a config ruling silently remove one of the two.

**Out of scope:** the `lsp-binaries` plane and its pins (owned by HD-1238's closed clauses and
[docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1), every converge, `IaC/`, and the model axis
([prompt-external.md](prompt-external.md)).
