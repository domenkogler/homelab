# prompt-next.md — the answer plane's last two repo halves, and the seat that keeps its fix

> **Rows it carries:** none. This brief sequences acts whose rows keep their own owners and their own
> briefs — [prompt-dns-transport.md](prompt-dns-transport.md) for the transport legs,
> [prompt-smart-home.md](prompt-smart-home.md) for the standby legs,
> [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md) for the seat plane. The ids named below
> are **ridden, not carried**; no ownership moves here and no row is minted for an act.
> **Role:** the ordered runbook for ONE session that lands the two repo halves the MagicDNS answer plane
> still needs, runs the read-only pre-flight the unattended ruling allows, and closes the seat-side
> durability gap — then **stops at the owner-present converge**, which is a different sitting days away.
> **Linked from:** nothing yet — the owner's entry point for this wave.

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11). It overrides README §4 and
CONVENTIONS §6 at the items it numbers; this file restates none of them. Worktree before any edit, ≤2 children,
`async: true`, this session's own model, validate in the worktree → merge green → push.

---

## 1. Ground truth to re-prove, not read

Nothing below is trusted from a handoff. Run these four and let the tree answer:

```bash
python3 scripts/gate/check_zone_kogler_si_parity.py --self-test   # the case list is its own output
python3 scripts/ansible/zone_kogler_si_render.py --render-records | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))'
grep -n "headscale_extra_records_path:" IaC/ansible/group_vars/vps.yml
grep -rn "tailnet_pi_ip" IaC/ansible/templates/docker_services/headscale/ | head
```

What they establish, in order: the records file is a **JSON array** and the gate parses it the consumer's way
in both key shapes; the render emits one row per name per namespace; the inline `dns.extra_records` block is
the shape in force, so **live is unchanged**; and **`dual` renders a second `.ts` row at `tailnet_pi_ip` in
both record shapes** — the render half of Act 1 is landed, so what Act 1 still owes is the FIELD, and the field
is §6's diff.

---

## 2. Act 1 — author the `dual` render (repo only, ⛔ no host, no flag flip)

**HD-435**'s publish half. `ha.ts.kogler.si` answers with one node address, so an oldsrv node death
black-holes the away path that is supposed to survive it ([docs/network-vpn.md](docs/network-vpn.md)
§Tailnet boundary, [docs/smart-home-failover.md](docs/smart-home-failover.md) §Away access). The class default
for `node`/`dual` is `tailnet_oldsrv_ip`; the second home node is `tailnet_pi_ip` (both in
`IaC/ansible/group_vars/all/main.yml`, never re-typed into a template).

| file | the change |
|---|---|
| `IaC/ansible/templates/docker_services/headscale/config.yaml.j2` | the inline loop emits a SECOND `.ts` `A` row (`type: A`, value `tailnet_pi_ip`) for an entry whose `tailnet:` is `dual` |
| `IaC/ansible/templates/docker_services/headscale/extra_records.json.j2` | the same second row, same position in the document order — the gate compares the two shapes row by row, so a shape that renders it in a different place is RED here, not in the netmap |
| `IaC/ansible/group_vars/all/main.yml` | the `tailnet:` field contract: replace the sentence Act-1's grep finds with what `dual` now does, and say plainly that a second address renders only when that node's address is set |
| `scripts/testdata/zone_kogler_si_golden.json` | **no row moves in this act**: the fixture is a snapshot of the ANSWERS, and an act that changes the render while no entry carries the field leaves it byte-identical. When a field does flip, the move is by hand — `capture_zone_kogler_si_golden.py` refuses to re-capture a derived zone — and it lands in the same commit as the flip, with the reason in the message |
| `scripts/gate/check_zone_kogler_si_parity.py` | one self-test case: a `dual` entry must yield BOTH `.ts` rows in BOTH shapes, and the canary is the second row going missing |
| `docs/network-vpn.md`, `docs/smart-home-failover.md`, `docs/network-dns.md` | the answer survives either home box; the SERVICE surviving either box is a different claim (§7) |
| `todo.md` **HD-435** | the AI tail says the answer goes to "oldsrv's (dead) node address". "(dead)" is an unproven live claim inside a row: make it a state sentence — the answer is one address, and when that node is not answering, the away path is `pi.ts.kogler.si` — and keep the outage claim in its owning doc if it has evidence there |

⛔ **Do not set `tailnet: dual` on `ha.kogler.si`, and do not set `headscale_extra_records_path`, in this act.**
Both are the window's diff (§6): landing them here would make `main` disagree with live until the converge, and
this wave ends before that converge.

**Acceptance:** `APPROVE`-shaped — the parity gate green with the fixture moved (its print names the counts,
quote them, never re-type), `--self-test` +1 case passing, `bash scripts/validate-all.sh` green, and the two
record shapes rendering byte-comparable row sets. A claim with no command output behind it counts as not run.

---

## 3. Act 2 — the read-only pre-flight (VPS, writes nothing) — LANDED

The dry-diff is the ONLY thing an unattended window runs on this plane. Its reads were run and their results
are **state in the owning docs**, not in this brief: one record key and the inline shape in force,
the live set equal to the derived render **both directions**, `tailnet_oldsrv_ip` / `tailnet_pi_ip` equal to
the addresses `headscale nodes list` assigns, and `ha-ts` answering TCP/443 under `ha.ts.kogler.si` on **both**
home boxes behind the VIP — see [docs/network-dns.md](docs/network-dns.md) §The MagicDNS records FILE and
[docs/network-vpn.md](docs/network-vpn.md) §Tailnet boundary. The `dual` flag is therefore a fix, not a lie,
and §7 still bounds what it buys.

Two reads change §6's diff, and both are in the row and the doc:

* **The flip is not `group_vars`-only.** Live still binds `./extra_records.yaml` and has no
  `/opt/headscale/extra_records.json`, so the run that sets `headscale_extra_records_path` must be the run that
  re-renders this service's compose — bind move plus the `retired_artifacts` removal, same run.
* **`/api/http/routers` answers 404 on both home edges** (neither `traefik-internal` nor `traefik-ha` passes an
  `api:` flag), so the router read there is the rendered `dynamic/routes.yml` + `ss -ltnp` + one `curl --resolve`
  SNI probe — stated in [docs/services-traefik.md](docs/services-traefik.md).

The window RE-runs the diff before it converges: the point of the artifact is that it is fresh, and
[docs/network-dns.md](docs/network-dns.md) §The MagicDNS records FILE carries the commands. A Pi node whose
address differs from `tailnet_pi_ip` is a finding for the **SSOT**, fixed before the window, never by editing a
template; a missing Pi node is not this wave's failure, because the render degrades to one address (gate-proven).

**Acceptance:** the diff, empty in both directions, written into the session report as the artifact + the node
list read. That artifact is what the owner walks into for §6.

---

## 4. Act 3 — make the seat's resolver family repo-owned

**HD-1176** tail: the per-link resolver claim (`resolvectl dns`/`domain`), the `resolved.conf.d` uplink drop-in,
and the re-assert unit pair live on one WSL seat as unversioned state. A reimaged box comes back with the
NXDOMAIN leak. The sibling already shows the shape: `scripts/harness/seat-llm-path-timer.sh` owns the pin's
unit pair and names this family as its own — read it before writing anything.

* New owner in `scripts/harness/` + one `plane:` record in `scripts/lib/seat-planes.yml`; the registry, not a
  hand-maintained list, is what makes `pi-seat-sync.sh --plane <name> --check` able to say a seat is short.
* ⛔ These are **seat** artifacts: the push leg runs FROM the seat, because a seat plane converges from its own
  clone and the station cannot speak for a seat's PATH
  ([docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a), and a host on the session's own
  model path is off-limits to a converge act ([docs/orchestration.md](docs/orchestration.md) §3 item 9).
* ⛔ Not the answer plane: no zone row, no netmap record, no `hosts` line, and the zone-wide "ask the home
  resolver at home" switch stays rejected for everything but the one inference name
  ([docs/network-dns.md](docs/network-dns.md) §Host-side resolver).
* Idempotence is the whole design: flush, write, re-read, and log the read-back — `resolvectl` exits `0` even
  when `resolved` refuses, and `RemainAfterExit=yes` once made every timer fire a silent no-op.

**Acceptance:** the plane `--check` distinguishes a seat that has the family from one that does not; the
installer is idempotent on a second run; the row's tail loses the "no repo owner" clause and nothing else.

---

## 5. Act 4 — turn one open question into an answerable one

The headscale-side question **HD-1176** carries — should MagicDNS forward the parent zone instead of
`SERVFAIL`ing the names outside the netmap — has no `Options` section, so today it is an argument.
Mint it in [docs/network-dns.md](docs/network-dns.md) to CONVENTIONS §8.3's shape. `check_open_questions.py`
is the authority and it prints the **derived next id** — read it instead of typing one — and it enforces the
rest: an `Options` heading at level 2 or 3 naming the id, the header exactly
`| Option | For | Against | Cost | Cheap test |`, **two or more** option rows, every `Cheap test` cell
non-empty, and no recommend/decided/decision wording anywhere inside the section. Make the cheap test one
that could actually settle it: a resolver probe for a netmap name and a non-netmap name, run from a device ON
the tailnet, since a home Technitium instance cannot see this plane at all. No recommendation in the section —
the answer is the owner's act, and when it lands it becomes state prose, plus a `network-rejected.md` row if an
alternative dies.

---

## 6. The stop line — the converge that is NOT this session's

Owner-present, days away, **VPS** slot, one run, contents prepared by Acts 1–2 and committed at the window:

* `headscale_extra_records_path` → the container path of the records bind, and
* `ha.kogler.si` → `tailnet: dual`, so **HD-435**'s publish rides the same bounce, and
* the records bind's rename + the retired-artifact removal ride it too — that bounce happens on any
  headscale-scoped converge regardless, which is precisely why the flip travels with it instead of after it.

Guardrails, from [docs/network-dns.md](docs/network-dns.md) and the guarded-converge entry in
[scripts/README.md](scripts/README.md): rehearse the app probe on the target by hand and SEE it succeed; arm
the watchdog before the service is touched; sample liveness (`Running` true, `RestartCount` flat across
samples, probe `0` every sample) — ⛔ `configtest` is not a verdict, it never opens the records file, and it
also accepts a config carrying both record keys; ⛔ never `--diff` on `docker_services`; run detached, never
behind a timeout; do not share the wave with another VPS lane. Rollback is one detached, scoped run with the
path forced back to empty — the inline block is authored, complete, and ready.

Read-back after GREEN: one key on the host, the parsed delta empty both directions, the retired file gone, and
the two `dig`s from a tailnet-attached device unchanged (a home Technitium instance proves nothing about this
plane). Then **HD-436**'s other owner leg — `playbooks/dns.yml` from the home control plane, expected: no
record change — and the row closes.

## 7. What this wave must not claim

Publishing two addresses makes the **answer** survive either home box. The **service** surviving either box
needs the VIP to have a second advertiser, and until the oldsrv standby is cold-created it has one: the Pi
([docs/smart-home-failover.md](docs/smart-home-failover.md)). So a dual-A publish does not close **HD-435**,
and it gives **HD-418**'s standby proof and **HD-434**'s standby tunnel no new subject — those wait on
**HD-1109**'s cold create, an oldsrv act on its own owner-scheduled window. Write the answer half as done and
the drill half as owed, or the next reader inherits a false "failover works".

## 8. Out of scope

`playbooks/dns.yml` until §6's converge is GREEN · the standby and its drills · the router's global slot
(**HD-1160**) and **HD-1152**'s first real prune apply · the `llm.kogler.si` answer flip, ruled to
tailnet-edge and closed in its row · any `--tags network` / lockout-class apply on **oldsrv** while it is the
controller · every parked owner act in [prompt.md](prompt.md).

## 9. Session close-out

`bash scripts/validate-all.sh` green in the worktree → merge to `main` → validate at the station → push →
remove the worktree. Then: the dry-diff artifact named, the window's diff prepared but **not** merged, and
this file deleted or rewritten by whoever runs §6 — a wave brief dies with its wave (O7). `deployment-manual.md`
stays untouched unless a step was performed that a from-scratch rebuild would need.
