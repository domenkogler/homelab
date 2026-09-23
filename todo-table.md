# Todo Split — Decided State, AI-Runnable Work, Owner Residue (planning view)

> **Role:** hand-curated planning view of [`todo.md`](todo.md) — the whole open backlog seen as **what to do next**.
> §A is now a **decision record**, not a queue: it states what the owner already answered and where each answer is
> logged, so no later session re-asks it (§A1), plus the small residue that is genuinely still theirs (§A2).
> **`todo.md` stays the registry SSOT** (CONVENTIONS §4(a): a fully-done row is deleted from the registry; this table
> is a view, not a second record) and **must be re-synced whenever the backlog changes**.
> **Linked from:** [`todo.md`](todo.md) · [`prompt.md`](prompt.md) · [`README.md`](README.md) · [`scripts/README.md`](scripts/README.md)
>
> **Re-synced 2026-09-22, third pass — the done-item sweep.** What moved:
> - **If a commit says it is finished, it now leaves the views** (CONVENTIONS §4(a)). **HD-375 is deleted on the
>   owner's call** — both spark host-memory OOM rules are live in the ruler and the Grafana-UI + n8n confirmation is
>   taken, record [observability.md](docs/observability.md) §Alerting. Also gone from `todo.md`: the **duplicated
>   struck HD-181** row (done + superseded, and the two copies were byte-identical — the exact table-corruption
>   class HD-417 registers), **HD-382** (its only tails were HD-383 and HD-384, which have their own rows),
>   **HD-385** (both premises failed, every item closed by measurement or shipped with the pinned-AI lane — the
>   research record is [services-ai.md](docs/services-ai.md) §9c and its two non-actions are
>   [hardware-gpu.md](docs/hardware-gpu.md) §CWSR), the **closed 2026-09-04 network packages A/B/C/D/F** (every row
>   they folded is deleted) and the five closed owner items in §2.1b. §A2/§D lost the phone re-measure row — it
>   RAN, and so did the 60-second discriminator — and **HD-412 moved from §B to §D**: its server is LIVE, only the
>   two enrolment sessions wait on a human at each end.
> - **The question queue emptied.** §A became a record of 17 decisions (cockpit surface and seat, the exit node,
>   the scoped-consumer grant, the git-credential shape, the OWUI split, the resolver chain, and more), each pointing
>   at its `*-rejected.md` row. §A2 is what is actually left of the owner: logins, a sideload, and physical windows.
> - **2026-09-23 (the runner/cockpit lane closeout, performed by the lane itself because no orchestrator existed).** Seven
>   rows leave the registry as delivered: the oldsrv control node, the Technitium `--check` gate, the SSH-grant auditor, the
>   parked-pair converge, the rendered client config, the browser cockpit, and the LAN-gateway confirmation whose only tail
>   was that converge. The lane **deleted its own brief** and re-synced both views, so §B0/§B/§D point at rows rather than
>   at a brief that is gone. **The gates the lane hit became rows** — 442 deleted op service account,
>   443 three SSH-grant verdicts keeping the new gate red, 444 the phone has never driven the cockpit, 445 no role owns
>   the cockpit's unit files, 446 no bare-Debian pi installer, 447 Metabase Authentik objects plus a dormant item, 448 the
>   VPS has no working IPv6, 449 pull-only promise plus a leftover key backup — and one defect was minted by measurement
>   rather than design (440: every `docker_services` converge restarts a healthy service). Nothing here re-decides
>   anything; each row names the gate that produced it.

> - **§0 Repo state:** the two empty session worktrees (the HD-395 and HD-399 lanes, both 0 commits) and all twelve
>   stale `session/*` branches are gone; `main` is the only checkout, clean, `validate-all.sh` green.
> - **Registry** (re-derive any count from `todo.md`; never type one) — HD-408 deleted as decided, **HD-418 / HD-419**
>   registered out of the two fault-notes that lived only in [network-vpn.md](docs/network-vpn.md) prose.
>   **2026-09-22 (the HD-414 lane):** **HD-419** deleted (shipped + verified), **HD-301** deleted (hardening floor
>   measured on the live device), **HD-09** deleted as **void** — its ask contradicts [docs/hardware-ups.md](docs/hardware-ups.md)
>   and the rule never existed despite "IaC done"; it is now a row in [docs/network-rejected.md](docs/network-rejected.md).
>   **2026-09-22, second pass (the discriminator):** **HD-410** and **HD-414** deleted as **done** — the scoped
>   IPv6 shipped and folded into the converge, and the post-IPv6 phone re-measure plus a log-only discriminator
>   came back **still relayed, with nothing at all arriving from the phone on either family**. The DERP posture is
>   therefore **decided** (no self-hosted relay) and both inbound remedies are retired. Durable content is in
>   [docs/network-vlans.md](docs/network-vlans.md) §IPv6 + [docs/network-vpn.md](docs/network-vpn.md); the two
>   side-findings that have no registry row are recorded as owner residue in §A2.
> - **§B** gained the rows the decision round converted from owner-gated to pure AI.
> - **Watch-list** now also catches the false claims a decision round creates by itself — "`§A` is done" (decided is
>   not shipped), "Forgejo is the remote" (it holds no copy), "oldsrv will push" (it is pull-only until HD-409).

---

## 0. Repo state (one screen)

| Fact | State (measured 2026-09-22) |
|---|---|
| Primary checkout `/home/domen/source/homelab` | `main`, working tree **clean** — a merge station, not an edit site |
| `bash scripts/validate-all.sh` | **GREEN** |
| Session worktrees | **transient by design** — a lane worktree (`../homelab-wt-<YYYYMMDD>-<HHMM>`) exists only while its lane runs, and the parent removes it after the merge. **Swept 2026-09-22:** the five finished-lane worktrees (`1359` OV probe, `1403` HD-412, `1440` HD-394, `2259` agentmemory probe, `0100` HD-312 close) and the HD-414 lane worktree (`20260922-0200`) were merged and removed by name with `git worktree remove` — the station held **one** worktree before this sweep and none of them was mid-flight. ⚠ A worktree existing has twice meant *nobody was in it* — check `git log` on the branch, not the directory |
| **Lane briefs = the dispatch unit** | **one `prompt-<HD>.md` brief = one session = one worktree = one branch.** Each brief carries the rows it owns, the files it owns and the converge host it holds; the row index per brief is §B0 below. Waves, pairing and the merge/cleanup contract are in [prompt.md](prompt.md) **§4**, whose rules deliberately DIFFER from README §4 and CONVENTIONS §6 (items O1–O8 there) — §4 is silent nowhere this table depends on |
| **Who writes `prompt.md` / `todo-table.md`** | **The orchestrator only** (§4 O2). Lane sessions edit their own `todo.md` rows and their own `deployment-tasks.md` lines, and never touch these two views — `check_todo_done.py` couples `prompt.md` to `todo.md`, so two writers on the views means a red gate by construction |
| Stale session branches | deleted with `git branch -d`, which refuses an unmerged branch — so the sweep itself proves nothing was stranded (12 at the 2026-09-21 sync; the merged lane branches again on 2026-09-22) |
| Registry size | **derived, never typed** — the row count and the next-free id (max + 1) are read out of [todo.md](todo.md) (`grep -c` on its `HD-` rows, `sort` for the max); this sweep deleted rows, so re-derive rather than trusting any number quoted in prose (a literal pipe would break this cell — see [todo.md](todo.md) HD-417) |

### What is live vs authored-only

- **Live:** VPS edge (Phase 1), nas (Phase 2), Pi (Phase 4), oldsrv (Phase 3, full `docker_services` healthy),
  Victoria* observability, 3-instance DNS HA, the home `traefik-internal` edge, `lan-litellm` on oldsrv, the three
  pinned-AI Vulkan legs on the RX 7600, spark as the generation tier with the **16 GiB KV pool certified**, and
  **oldsrv as a headscale node** (`tag:dev:443`, `ha.ts.kogler.si` from its own edge).
- **Open, and now fully AI-owned:** everything in §B. The owner answer round of 2026-09-21 removed every remaining
  hand from the top of the backlog (§A1) — what is left on the owner's side is §A2.
- **The live reality that reorders the transport lane — measured twice, and now settled.** The first real away
  session to the home node came back **`Relayed (FRA)`, 60–90 ms**, killing "static public IPv4 ⇒ direct" for
  cellular clients here. HD-414 then shipped the scoped /56 (2026-09-22, **VLAN 10 only**, accept-before-drop
  proved load-bearing on the device) and the re-measure came back **still relayed in both directions**; a
  log-only discriminator (no hole opened) showed **zero packets from the phone arriving on either family**,
  while v4 internet scans hit the WAN constantly. Both rows left the registry as **done**: **HD-414** (shipped,
  folded into the converge, all four invariants re-proven) and **HD-410** (DERP posture **decided** — no
  self-hosted relay; the cost lives on the phone↔FRA/NUE leg). What that leaves: the planned `UDP 41641` accept
  is **retired** (its destination receives nothing), **HD-406 has nothing left to wait for and is now the more
  credible path** (phone-initiated WireGuard survives carrier NAT because the UE's own NAT state carries the
  reply), and **inbound-over-v6 from home is unavailable** — no unsolicited inbound v6 reaches the delegated
  prefix, so an `AAAA` pointing at a home service would be unreachable. Numbers and method:
  [docs/network-vpn.md](docs/network-vpn.md).
- **Proof order for any live claim:** `todo.md` §3c → [`deployment-tasks.md`](deployment-tasks.md) checkboxes → the
  owning doc's ✅ lines. Doc banners are hints, not proof.

---

## A. Decided 2026-09-21 — and what is actually left on your side

The question round is closed: every item below is recorded in `todo.md` **and** in its domain decision log, so no
later session re-asks it. Rows marked ✅ are now pure AI in §B.

### A1. Decisions recorded (nothing further from you)

| HD | The decision, as it now stands | Recorded in |
|----|------------------------------|-------------|
| **HD-347** ✅ | Alerts go to the **whole "Homelab Alerts" group**; the value in SSOT is the **group ID signal-cli reports** — not the invite link (that blob is an encrypted join payload, not a recipient). **AI sources it itself**, read-only, from the linked daemon | [observability.md](docs/observability.md) §Alerting |
| **HD-354** ✅ | **No music exists on local disks** (the family listens from the cloud) → the Box-library and admin-user halves are **void**; do not mint an admin for an empty library. Tail = the Subsonic/ExtAuth verify | `todo.md` row |
| **HD-361** ✅ | Break-glass identity = **one password-bearing `maint` per cockpit host** — today `nas` + `oldsrv`, the only two hosts with the `cockpit` role. Vault items `nas-cockpit_login` / `oldsrv-cockpit_login`, password **generated by the AI**, `sudo` group, **no NOPASSWD**, no SSH keys, excluded from `AllowUsers`. ⚠ `cockpit` is in the HD-413 lockout set → converge from the laptop | [services-traefik.md](docs/services-traefik.md) §Cockpit Routes |
| **HD-383** ✅ | Remediate the stale `dsh` secret **now** (owner authorized the write path): clear the credential, delete the `dsh` alias in the LAN Admin UI, drop the item's doc row — one change | `todo.md` row |
| **HD-384** ✅ | Scoped consumers get the **`spark/qwen3.8-flash-next` row only**, never a `spark/*` wildcard. **`max_budget` dropped** (owned devices, no metered cost); **`rpm` caps stay** — they are contention protection on the one 262k KV pool, not a bill. Plus a separate client credential for the `llm` router so `spark-llm_api` stops being triple-used | [services-rejected.md](docs/services-rejected.md) 2026-09-21 |
| **HD-406** ✅ **(re-decided 2026-09-22)** | The admin path will be **MikroTik Back To Home** — WireGuard with MikroTik relay fallback, TILE-capable so the RB4011 qualifies — **explicitly not now**, and it does not restore the family road-warrior surface. Two things to clear first: BTH writes router config **outside `roles/router`**, which the device-wide converge rebuilds, and it can put a **vendor relay** in the path, whose cost is the shape just measured on cellular. | `todo.md` row |
| **HD-407** ✅ | Seeding is **AI-runnable and authorized**. Pull with the **read-only** `github-homelab-deploy_api` over HTTPS via a 0600 credential store (never in the remote URL); **GitHub is the live remote** — Forgejo on the VPS holds no copy of this repo; the vault **signing** key is reused, so commits on oldsrv are signed and attributed to you; `github_auth` (push) stays off the box. **Consequence: oldsrv is PULL-ONLY until HD-409** adds a repo-scoped write key | [deployment-rejected.md](docs/deployment-rejected.md) 2026-09-21 |
| **HD-408** ✅ | **Exit node stays on the Pi** — the row is deleted. Weighed: an exit node adds no SD-card wear worth naming (tailscaled logs no per-flow data, nft masquerade is silent), so the real tradeoff was oldsrv's better pipe against widening the tailnet boundary — and the boundary won. Re-open trigger: the HD-406 full-tunnel profile proving geo-egress with no exit node at all | [network-rejected.md](docs/network-rejected.md) 2026-09-21 |
| **HD-409** ✅ | Surface = **`@ygncode/pi-web`**, running under your **`domen`** seat on oldsrv (accepted deviation from the non-human-workspace precedent — measured: `domen` there holds neither the `op` token nor the fleet key); `ansible-admin` stays runner-only; **break-glass is now `<host>-cockpit_login`**, not `domen` | [deployment-rejected.md](docs/deployment-rejected.md) 2026-09-21 |
| **HD-411** | Paseo runs **simultaneously with HD-409**, one comparison window, two surfaces (own `*_port` var each, both tailnet-bound, relay off). **Your hand: sideload + pair + 2-week verdict** | `todo.md` row · 📋 closed runner/cockpit lane (2026-09-23; brief deleted) |
| **HD-412** ✅ (live 2026-09-21) | Family machines **join the tailnet** where they can (direct-IP, no relay); hbbs + hbbr still land on the **VPS** for the rest, **relay bandwidth-capped** to the VPS quota | `todo.md` row |
| **HD-415** ✅ | Neither "leave it" nor "trim it": make the resolver **reachable from wherever the device is**. The chain becomes **oldsrv's tailnet node address** (direct-over-LAN at home with the WAN pulled; reachable away while the home link is up) **+ the VPS public instance as fallback**, and the two LAN-address entries go. Case (d) — away while the **home** WAN is down — is accepted as unresolvable: your words, *"it is ok that I will not get dns for whole domain, because it is not reachable from the internet."* Folded into the HD-414 lane · **✅ shipped 2026-09-22** — the chain is live and answers over the tailnet; ✅ the three-case drill ran 2026-09-22 with the owner present: (a) home ✅, (c) WAN pulled ✅ (media loaded, direct links, `ts-forward` counters moved), (b) re-scoped as a *different* problem, (d) refused | [network-dns.md](docs/network-dns.md) §The answer-plane model + [network-rejected.md](docs/network-rejected.md) 2026-09-21/22 |
| **HD-415 · second call** ✅ | **Include `udp 53`** — the 2026-09-20 "443 ONLY" freeze is lifted **for DNS only**, written `udp:`-scoped to the resolver node rather than to `tag:dev`; no LAN bridge, no advertised routes, no exit node, no Tailscale SSH. The headscale stop/start is **authorized with a hard safety condition: if the driving session drops, headscale must come back on by itself** (prove the auto-re-enable before the first stop) — **both delivered 2026-09-22**: `scripts/restart-watchdog.sh` + `scripts/guarded-converge.sh`, proved live (one stop, self-recovered in 19 s) before the single authorized restart. Case (b) of that row's drill is what surfaced `override_local_dns`'s advisory behaviour, recorded in the docs rather than left in a closed row | [docs/network-dns.md](docs/network-dns.md) §The resolution requirement |
| **HD-432** ✅ | **Do not split the zone — refused, and the question was the wrong one.** Splitting `kogler.si` to a tailnet resolver would answer `media` with a LAN address to a phone on cellular: correct, unreachable, and with **no fallback**, because a split domain is never retried against the OS resolver. What is needed is *reachable answers*, which MagicDNS `extra_records` already give from the client's own netmap with no resolver dependency. Measured while deciding it: with `override_local_dns: false` the delivered chain is **advisory** — the laptop asked the LAN resolver with the tailnet connected, the phone asked its carrier — so no design may assume a client was told to use the chain. · [docs/network-dns.md](docs/network-dns.md) §The answer-plane model, [docs/network-rejected.md](docs/network-rejected.md) |
| **HD-433** ✅ | **One URL, and it is the plain `ha.kogler.si`.** Decided with the owner rather than by me, because the deciding fact was his: the HA Companion app stores exactly one URL, so a design where the tailnet URL differs from the home URL breaks the app. Publishing the plain name as an extra_record gives one string in all three cases — home without the tailnet (LAN zone → VIP), home with it (node answer, direct over the LAN), away (node path) — and `ha.ts.kogler.si` stays as a free alias. Follow-up **HD-435**: the Pi joins the tailnet so the name carries two A records and survives either box. **Flagged unmeasured:** multi-A fall-over on a real client needs a plug-pull, and the expected symptom is a timeout before the second answer, not an instant switch. · [docs/network-vpn.md](docs/network-vpn.md) §Tailnet boundary |
| **HD-248** ✅ | **No second OWUI instance now** — the row is now just "correct the stale `x2 live` banner"; the split stays planned until a real second audience exists | [services-rejected.md](docs/services-rejected.md) 2026-09-21 |
| **HD-435** ⏳ | **The tailnet's HA answer must survive either home box** — join the Pi to the tailnet, bind its edge to a tailnet listener, publish `ha.kogler.si` with **two** A records. Owner approves the new node + ACL grant first; acceptance proves MagicDNS returns both records and that HA stays reachable with one box powered off. · [todo.md HD-435](todo.md) |
| **HD-436** ⏳ | **`zone_kogler_si` — the namespace as one derived list**, replacing the seed's inline records, headscale's two subdomain lists, the public Cloudflare set and a workstation hosts file that cites two scripts which have never existed in git. Derived from the `docker_services` entries (`name`/`subdomain`/`public`/`enabled`) plus `internal` / `tailnet: none|edge|node|dual` / `ts_router`, rendered into all four consumers, with validators for the mismatch classes already measured (`music` has no name, `sec` keeps one after being disabled, `stats`/`logs`/`csui` hand LAN clients a tailnet address). Aliases for admin boxes are **generated or not at all**. · [todo.md HD-436](todo.md) |
| **HD-336b** | CrewAI **stays parked** — you are evaluating alternatives (incl. Hermes); no pilot until you rule | `todo.md` row |

| **HD-434** ⏳ | **Standby KNX: retest, don't re-theorise.** My GIRA-router conclusion was built on unauthenticated probes — the router expects the integration's `user_id`, so those packets would go unanswered from the healthy primary too, which makes them worthless as evidence. The bug actually found was ours (**HD-438**). Needs one owner-present takeover with the primary as a known-good reference. · [todo.md HD-434](todo.md) |


| **HD-438** ✅ | **Half-open KNX tunnel: outbound worked, inbound did not, for three days.** The reply leg lived only on `established/related` conntrack; an idle UDP tunnel that outlives it keeps switching devices while every state read is dropped and xknx never notices. Reload restored it; a `src-port=3671 → trusted-ha` reverse accept closes the recurrence, proven by deleting the conntrack entry under live traffic. My two earlier diagnoses (GIRA router, `trusted-ha`) are withdrawn — the second was measured with ICMP and TCP against a UDP path. Left: the generator's ~36 phantom state GAs, and no detection for this failure mode. · [docs/network-vlans.md](docs/network-vlans.md) |
### A2. What still needs you — the honest residue
| **HD-439** ⏳ | **KNX leftovers:** the generator emits ~36 state group addresses the old working config never used and that never answer (they will keep timing out on every sync, and were the noise that hid a three-day outage), and nothing in the stack detects a half-open tunnel — the reload cadence or an alert on outgoing-telegram-error growth is the missing instrument. · [todo.md HD-439](todo.md) |

| What | HD | Note |
|---|---|---|
| **Browser logins** matrix / claw / cloud / foto / immich (+ register on Forgejo) | HD-147 + HD-141 tail | You know. The click-by-click with the five URLs comes with the next session's task list. One embedded choice: **Forgejo primary + GitHub mirror** vs GitHub-only — note Forgejo is **empty today**, so "primary" is currently a plan, not a fact |
| **Mint a current read+write 1Password service account** (`op-write_api`) | HD-442 | the oldsrv write token is a deleted SA, so nothing on that box can write to the vault and the cockpit token has nowhere to live |
| **Three SSH-grant verdicts** | HD-443 | sanction or remove: `ansible-admin_ssh` under `admin` (NOPASSWD:ALL) on the Pi · `ai_ssh` on oldsrv · `laptop-domen_ssh` on spark. The gate stays red until each is answered |
| **Drive the oldsrv cockpit from the phone once** | HD-444 / HD-411 | the tailnet path the whole remote-dev thread exists for is unproven; Paseo pairing rides the same session |
| **Rule on the leftovers of a retired service** | HD-447 | delete the Metabase Authentik objects + `metabase_oidc` + `sec.kogler.si` + `/opt/metabase`, or write down why they stay |
| **Decide whether oldsrv may push** | HD-449 | a repo-scoped write key, or pull-only becomes the answer and the promise gets deleted |
| **Sideload the Paseo APK + pair + a 2-week verdict** | HD-411 | Runs in parallel with HD-409 now |
| **Check your Jellyfin login at seerrng** | HD-353 | 30 seconds |
| **A spark bench window** | HD-400 · 376 · 359 · 367 | Detached; never with an agent session attached, never from a spark-backed session |
| **A WAN-pulled drill at home** | HD-415 | The new resolver design's whole load-bearing assumption is that a phone at home reaches the node **direct over the LAN with the WAN pulled**. That is proven by a drill you are present for, not by a `dig` from the laptop |
| **One visual pass** | HD-316 · 315 · 343 · 377 · 319 | Launchpad, host-overview (disk-work + temps), Network Clients, `homelab-llm`, the three rekuperator GAs — the spark memory rules left this list when HD-375 closed 2026-09-22 |
| **Be on-site once** | HD-397 tail | The LAN matrix + the `Mgmt99` vNIC half |
| **Physical windows** | HD-06 · 288 · 194 · 34/191 | UPS pull → WoL · a router/switch/AP reset · gaming + Moonlight · one edge login/callback · the yearly restore drill (also where HD-207 and HD-230 get decided) — HD-301 left the registry when its floor was verified on the device |
| *(optional)* | HD-409 | If you want oldsrv to **push**, mint a repo-scoped **write-capable** deploy key when HD-409 lands. Until then oldsrv pulls only and commits wait there |
| **Three memory-plane calls** (OQ-12/13/14) | *(no HD row yet)* | **Measured, waiting on you** — is `agentmemory` the ONE central memory plane, where does Hermes' memory live, and does memory need the `bge-m3` leg at all? One line each in [services-ai.md](docs/services-ai.md) §9b, full evidence in [`reports/probe-agentmemory-20260921.md`](reports/probe-agentmemory-20260921.md). The blocker to accept or reject: a *central* instance on 0.9.29 is loopback-only with **one shared bearer and no per-user isolation**, so it needs a proxy. Nothing was installed and nothing blocks AI work meanwhile |

---

## B. Table AI — doable now (no owner step in front)

⏳ = the exact next action, not a restatement of the row. Goal = what "done" means.

### B0. Lane briefs — which brief carries which row

Every row below that has a brief is dispatched **from the brief**, not from this table: the brief adds the file
ownership, the converge host and the lane contract. Rows with **no brief** stay exactly where they are — that is not
lost work, it is unassigned work. Waves, pairing, the owner-gate "park and continue" rule and the merge/cleanup
sequence are [prompt.md](prompt.md) **§4** (orchestrator mode), which **overrides** parts of README §4 and
CONVENTIONS §6 at items O1–O8; this table is a row→brief index only and keeps no second copy of those rules.

| Brief | Wave | Rows it carries (lead · merged-in) | Converge host |
|---|---|---|---|
| `prompt-407.md` runner + cockpit — **CLOSED 2026-09-23, brief deleted** | **1** | closed as delivered: 407 · 409 · 399 · 386 · 416 · 388 · 356. Open residue: **411** (parked) + **442–449** | oldsrv + one full VPS `docker_services` |
| [prompt-420.md](prompt-420.md) metric cadence | **1** | HD-420 · **395 · 377(b) · 342 · 345** | spark + VPS (`--tags monitoring`) — **the spark half landed 2026-09-23** (hot/cold + 5 s sidecar + acceptance); the engine-restart residue is [`prompt-spark-external.md`](prompt-spark-external.md) |
| [prompt-414.md](prompt-414.md) transport — **re-dispatch card only: closed 2026-09-22 for its AI half** (scoped IPv6 shipped, the phone matrix and the punch discriminator both RAN) | **2** | **HD-415 · 406** (+159 with a stated window); the rows it also carried (**414 · 410 · 405 tail · 419 · 09 · 301**) are closed and left the registry | router slot **now free** + oldsrv |
| [prompt-384.md](prompt-384.md) LiteLLM consumer chain | **3** | HD-383 · **384** · 403 · 387 · 373 · 249 | oldsrv + VPS `docker_services` |
| [prompt-376.md](prompt-376.md) spark engine + bench | **3** | HD-376 · 400 · 359 · 367 · 380 (absorbs the stale `prompt-next.md`, now deleted) | spark, **owner bench window** |
| [prompt-357.md](prompt-357.md) launchpad + home edge — **its old gate fell 2026-09-22** (HD-419 shipped, so the jellyfin tile has an endpoint) | **4** | HD-357 · 17 · 217 · 358 · 418 (window-gated) | oldsrv |
| [prompt-417.md](prompt-417.md) gates + doc hygiene | **5, alone** | HD-417 · 404 · 248 · 396 | none (repo-only) |

> **Briefs deleted at the 2026-09-22 sweep** (job done, links fixed in the same commit): `prompt-412` (HD-412
> shipped live), `prompt-394`, `prompt-405` (closed banner), `prompt-next` (the 2026-09-15 spark handoff, absorbed
> by `prompt-376`), `prompt-OV` and `prompt-agentmemory` (both probe lanes closed). **Unbriefed but still open —
> not lost, just unassigned:** HD-360 · 402 · 103 · 238 · 421 (the HD-394 lane's residue), **HD-450** (a cert
> consumer can age out unalerted — found closing HD-350), and HD-412's two
> enrolment sessions, which need a human at both ends and therefore live in §D.


### 🔥 Active lanes

| HD | P | Goal | ⏳ Next action | Why nothing blocks it |
|----|---|------|----------------|------------------------|
| **HD-395** | 2 | the watchdog stops restarting a healthy spark engine | fix is authored + self-tested (4/4, 7/7 mutants killed) in `session/395-watchdog-*` — baseline only after `/health` 200 **and** a settle window, committing the **max** of N samples, with the boot floor and the margin verdict emitted as their own `status` fields; ⏳ **the live half** = the scoped `--tags watchdog` converge + the “a unit restart must not recycle” check + one intentional recycle with in-flight 0 — that leg is [`prompt-spark-external.md`](prompt-spark-external.md) J1 | measured defect, still firing: `enforce.log` shows **three** recycles on 2026-09-23 (`03:41`, `04:15`, `04:50`Z), every one reading `92343 MiB > baseline 71911 + 8 GiB` — the guard was permanently armed against a healthy engine — it either restarts a healthy engine or goes silent. The live half must be driven from the laptop **by a session whose own model is not spark** · 📋 [`prompt-spark-external.md`](prompt-spark-external.md) J1 |
| **HD-417** | 3 | the validators can see a broken table | cell-count check for markdown tables in the docs validator (split on unescaped pipes, compare to the header, fail with file + line) + an escape convention + a one-time legacy sweep | a swallowed newline merged two registry rows and an `/etc/x`-style description added nine stray cells to a 3-column row on 2026-09-21 — both passed every gate. Cheap guard for a failure that is invisible today. · [CONVENTIONS.md](CONVENTIONS.md) §6 · 📋 [`prompt-417.md`](prompt-417.md) |
| **HD-387** | 2 | know whether thinking is actually OFF through the gateway | run the written probe protocol against the LAN instance (baseline → toggle → budget pair → `top_k` → the proxy's own dropped-params log) | a recorded live measurement and the pinned source contradict each other, and the failure mode is silent thinking-ON at HTTP 200. Master-key path, no client change; the harness route does not move either way (decision #26) · 📋 [`prompt-384.md`](prompt-384.md) |
| **HD-396** | 2 | the retired `op_api` secret thread ends with a fact | repo-archaeology, one question: does the Forgejo CI runner still exist, and does it still hold the pre-2026-09-19 secret? renew it, or delete the stale Phase 0/5 prerequisite lines in [deployment-tasks.md](deployment-tasks.md) | the leak itself is closed (record: [deployment-ai-stack-secrets.md](docs/deployment-ai-stack-secrets.md) §4a); no IaC references `op_api` any more, so only the Forgejo side can answer it · 📋 [`prompt-417.md`](prompt-417.md) |
| **HD-393** | 1 | the `amdgpu init_user_pages: -1` burst is explained or accepted | attribute the **one** bounded episode (dmesg 774,316 s → 780,804 s) per-process — journal vs container restarts in that window — then fix or record as noise | re-measured: 1,296 lines, all inside ~1.8 h, **0 hang/reset** anywhere, none new since. ⚠ `dmesg` needs `sudo` on oldsrv; `rocm-smi` lives **inside** `immich-ml`/`ollama`, not on the host |
| **HD-369** | 2 | voice points at the tiers that are actually live | **(d)** Whisper → the live whisper.cpp **Vulkan** leg on oldsrv (not Ollama), Piper → CPU, LLM → spark; then **(e)** the Sunshine priority glue (pause/unpause pinned-AI + immich-ML) | the tier has been live since 2026-09-19, so (d) has something to point at. ⚠ **(c) is SUPERSEDED — do not recreate the ollama catalog, do not bump the `:rocm` pin**; (f) is done |
| **HD-402** | 2 | the OCR engine is chosen by measurement, not by hope (⛔ **HD-421 first**) | confirm the Docling `RapidOcrOptions` adapter exposes the PP-OCR `latin` rec model → convert the **same Slovenian scan** with EasyOCR and RapidOCR-ONNX → keep only if quality ≥ EasyOCR → record the speed delta | CPU bench on the VPS, no host risk. Language was never the blocker (`latin` includes `sl`); the risks are the script-grouped model on `č ć š ž` and the adapter wiring. Closes on the **HD-103** scan gate. Free lever regardless: `do_ocr=False` for born-digital PDFs. Measured 2026-09-21: `rapidocr` is NOT in the pinned image (the adapter is fine, the PP-OCR weights are baked), and **no model can be fetched at runtime until HD-421** — see [services-ai.md](docs/services-ai.md) |
| **HD-421** | 3 | any Docling model change is actually installable | give the model cache a writable owner (`bind_owner_uid: "1001"` on the registry entry, or repoint `HF_HOME` / `DOCLING_SERVE_ARTIFACTS_PATH` at the bind) and **prove** a runtime fetch lands on the bind | `/models` is empty + root-owned while the container runs as uid 1001 ⇒ a fetch dies `PermissionError: /models/hub`; the served pipeline works today only because its weights are baked into the pinned image (871 MB) — so **HD-402 and any pin bump are dead on arrival until this lands**. [services-ai.md](docs/services-ai.md) §Where the model weights actually live |
| **HD-401** | 2 | the workstation provably carries FIM + visual judgment locally | clear the four pre-flight gates in [hardware-workstation.md](docs/hardware-workstation.md): pick + record the ROCm/`gfx1151` stack, prove the VL `mmproj` runs on the iGPU (measure `--image` prefill), measure FIM latency on the real Continue prompt shape, check the iGPU carve-out/GTT | **the stack install on this box is authorized (owner, 2026-09-21)** and three of the four gates are measurable right here. ⚠ every platform figure in that doc is owner-stated/community, **unmeasured here** |
| **HD-376** | 2 | agentic max-context is proven, and lanes get a smaller window | promote the `spark-lane` 64k profile; run the 262k needle test; measure parent-vs-lane KV contention | engine + harness config are live; the lane profile is paper-only. ⚠ needs the bench window (A3) — same window as HD-359/367 + HD-400, never an attached agent session · 📋 [`prompt-376.md`](prompt-376.md) |

### 🆕 Remote-dev plane (three file-disjoint lanes — run one per session)

Briefs: [prompt-414.md](prompt-414.md) (transport; it absorbed the closed `prompt-405`) ·
`prompt-407.md` (runner + cockpit) is **closed and deleted** — its residue is the 442–449 cluster below, not a brief.
and the follow-on lanes [prompt-384.md](prompt-384.md)
(LiteLLM consumer chain), [prompt-357.md](prompt-357.md) (launchpad + home edge),
[prompt-376.md](prompt-376.md) (spark engine + bench) and
[prompt-417.md](prompt-417.md) (gates + doc hygiene). The remote-desktop (`prompt-412`) and VPS-hygiene
(`prompt-394`) briefs are **closed and deleted** — HD-412's two enrolment sessions are in §D, and the open VPS
rows (HD-360 · 402 · 103 · 238 · 421) are unbriefed. Run one brief per session — [prompt.md](prompt.md) §4.
Decisions are already in the `network` / `deployment` / `services` decision logs — start from the briefs, do not
re-open the direction. Two standing decisions were **scoped, not repealed**: the tailnet permits exactly one home host
with **no advertised routes**, and the VLAN-99 seal (HD-398 A) is untouched.

| HD | P | Goal | ⏳ Next action | Gate / note |
|----|---|------|----------------|-------------|
| **HD-406** | 2 | a dev path that depends on neither the VPS nor headscale | ⏸ **owner-timed, not now** — and the shape changed: **MikroTik Back To Home** replaces the hand-rendered `roles/router` WG peer (BTH creates its own WireGuard interface + peers, and a standard WG client can import its config) | **re-decided 2026-09-22.** Clear two things first: BTH's artifacts live **outside `roles/router`** while the converge rebuilds filter rules device-wide, and BTH may use a **MikroTik relay** rather than the direct path. The old "AI mints the keypair" plan is superseded — BTH manages its own keys · 📋 [`prompt-414.md`](prompt-414.md) |
| **HD-411** | 3 | a native Android path to the same harness, without a third-party relay | AI: the daemon (systemd or a scoped container), tailnet bind + password + hostname allowlist, **relay off**, one 1P item | **sequence changed: runs simultaneously with HD-409**, one comparison window. Owner hand: sideload + pair + the 2-week verdict. The browser cockpit stays **primary** — an app someone else maintains cannot be a dependency, a URL can · 📋 closed runner/cockpit lane (2026-09-23; brief deleted) |
| **HD-415** | 3 | one tailnet resolver that works **wherever the device is** | **✅ SHIPPED 2026-09-22 (AI half complete):** `udp 53` in the headscale ACL scoped to the resolver node's address (not `tag:dev`), the node address as the tailnet nameserver, the VPS instance kept as the fallback, the two LAN-address entries gone; converged behind the proven auto-re-enable net and measured over the tailnet. ⚠ **acceptance = the three-case drill** (LAN / cellular / **home with the WAN pulled**) — procedure deployment-manual.md §1.4e · [network-dns.md](docs/network-dns.md) §The resolution requirement · 📋 [`prompt-414.md`](prompt-414.md) |
| hygiene | — | the last debt the transport lane named | expire the **retired headscale preauth keys 4 (`tag:pi-dev`) + 5 (`tag:dsh`)** — live, reusable, non-expiring for services that no longer exist; report ids only, never values | one `headscale preauthkeys expire` each; the tombstones in [deployment-secrets.md](docs/deployment-secrets.md) do not revoke them — headscale does |

### 🔒 Residuals of the closed runner/cockpit lane (442–449) — the gates it hit, not work it abandoned

| HD | P | What is actually left | Owner step in front? |
|---|---|---|---|
| **HD-442** | 1 | oldsrv `/etc/op/provision-token` is a **deleted** service account (`403 Service Account Deleted`) — re-mint, update `op-write_api`, re-run the pre-pass, then mint `cockpit-pi-web_api` with the value already on the box, and audit what silently never wrote | **Yes** — minting the SA is yours |
| **HD-443** | 1 | the new grant gate is **red** until three placements are sanctioned in the doc or removed (Pi `admin` + NOPASSWD, `ai_ssh` on oldsrv, `laptop-domen_ssh` on spark); close the HA-guests coverage hole in the same pass | **Yes** — three verdicts |
| **HD-444** | 2 | the cockpit is live and tailnet-bound, but no real peer has ever crossed the ACL to it — prove it from the phone with the laptop shut | **Yes** — presence |
| **HD-445** | 2 | no role owns the cockpit user units / drop-in / env file, so the port vars are reservations nobody reads and a rebuild loses the surface | no |
| **HD-446** | 3 | `scripts/install-pi-debian.sh` does not exist; apt Node 20 cannot run pi (needs >= 22.19.0) — sibling of the WSL installer, not a fork | no |
| **HD-447** | 3 | Metabase is retired via the registry switch (and the egress glue now honours it), but its live Authentik provider/app/edges, the dormant `metabase_oidc` item, `sec.kogler.si` and `/opt/metabase` remain | **Yes** — delete or justify |
| **HD-448** | 2 | the VPS nft `input` chain has no `icmpv6`, so NDP drops and IPv6 is dead in both directions — which also makes the Cloudflare VPS /64 entry decoration | no (transport lane owns the file) |
| **HD-449** | 2 | oldsrv is pull-only unless you mint a repo-scoped write key — and the docs still promised that ends when the cockpit lands, which it did; plus an unverified pre-restore runner key backup sits on the box | **Yes** — decide |


### AI / Office

| HD | P | Goal | ⏳ Next action | Note |
|----|---|------|----------------|------|
| HD-268 / HD-337 / HD-335 | 1–2 | RAG + memory + office stack live | Qdrant embed/rerank + **re-index** after the bge-m3/1024 cutover, OKF wiki skeletons (**268a**), then **268b = implement `rag-mcp`**, Mem0 + OpenHands | ⚠ the Vulkan embed move does **not** trigger the re-index (same dims, cosine 0.9996). ⚠ `rag-mcp`'s compose is a TODO comment block with **no `services:` section** — its `enabled: false` is not a flag to flip; until 268b lands the reranker leg stays dormant (~327 MiB) |
| HD-360 | 2 | Samba auth rides Authentik over LDAP | declare the provider + `svc_samba` in the Blueprint → mint a fresh bind token → redeploy the outpost → **then** flip `storage_samba_passdb: ldapsam` + converge nas | ⚠ order is safety-critical: smbd fails hard if the flip lands first (that outpost is Up **unhealthy** = expired token; re-probed 2026-09-21: Authentik also has **no LDAP provider/source/outpost object**, so token minting alone is not enough — [deployment-compose.md](docs/deployment-compose.md) §HD-132) · 📋 prompt-394.md — brief deleted |
| **HD-403** | 2 | voice has an LLM to call | mint a `home-assistant` scoped key vault-first, render `LITELLM_BASE_URL` + key into the compose env, point the Assist pipeline at it | HA ships only `TZ` in its env today; **HD-384 is decided**, so this is now plain work · [smart-home-voice.md](docs/smart-home-voice.md) · 📋 [`prompt-384.md`](prompt-384.md) |
| **HD-404** | 3 | the last stale IaC strings stop teaching agents the wrong truth | text-only PR over the enumerated list (Victoria headers, the Pi "primary DNS" comment, the `llm-backend` purpose string that feeds a generated doc, `amd_rocm`'s `OLLAMA_KEEP_ALIVE`, `first-boot-config.sh`'s wording) | the docs stopped repeating these; the comments are now the last place an agent reads a wrong truth · [deployment-ansible.md](docs/deployment-ansible.md) · 📋 [`prompt-417.md`](prompt-417.md) |
| HD-336 | 2 | agent memory per project | agent-memory.dev on oldsrv + ZeroClaw runner | spec in [services-ai.md](docs/services-ai.md) §9b; does not wait on HD-336b |
| HD-248 | 2 | the OWUI story matches the box | correct the stale "x2 live" banner in [services-ai.md](docs/services-ai.md); stop there | **decided 2026-09-21: no second instance.** The split stays planned until a second audience exists — building it today duplicates a service that does not run · 📋 [`prompt-417.md`](prompt-417.md) |
| HD-104 (+ HD-160) | 2 | OpenClaw is actually configured | `openclaw onboard` → `openclaw.json`, then the OpenCloud WebDAV round-trip | container Up/healthy; only onboarding + verify remain |
| HD-103 | 2 | Docling converts a real Slovenian scan | convert a real Slovenian scan end-to-end **through the served API** (the in-container CLI cannot run: unwritable `/models` bind) | Docling is Up on the VPS; **HD-402** closes on this same gate. Premise corrected 2026-09-21: there is no HF download to trigger (weights baked into the image; the `/models` bind is decorative — HD-421) |
| HD-111 | 2 | office MCP tools reachable from the UI | `ppt-mcp` first, register MCP servers in OWUI | nothing gates it now — the OWUI split question is deferred, not open |
| HD-249 | 3 | n8n workflows spend a budgeted key | audit external webhook deps + `WEBHOOK_URL`, then mint a budget-capped LiteLLM key for the AI nodes | n8n live behind the tailnet edge; its key is an HD-384 consumer once the allow-list exists · 📋 [`prompt-384.md`](prompt-384.md) |
| HD-251 | 3 | the admin surfaces move to tailscale-first | roll out the tiers (Headplane, Dozzle, Metabase, Grafana, Traefik-dash) | the policy/doc half landed 2026-08-26 |
| HD-373 | 2 | the LiteLLM admin UI deep-link works | pick (a) nginx SPA fallback / Traefik `PathPrefix(/ui/)` rewrite, or (b) route-scoped forward-auth on `/ui/*` | the `/fallback/login` workaround works, so this is a real fix, not a fire · 📋 [`prompt-384.md`](prompt-384.md) |
| HD-380 | 2 | spark memory growth is watched, with the cache question answered | passive: watch `samples.csv` for a curve growing > 2 GiB/h under traffic that does not return at idle — that, and only that, re-arms C3 — plus the never-measured prefix-cache/preemption check across the 16 GiB raise | certified state is stable; this row is a standing watch + one cheap measurement · 📋 [`prompt-376.md`](prompt-376.md) |

### Network / platform / security

| HD | P | Goal | ⏳ Next action | Note |
|----|---|------|----------------|------|
| HD-357 | 2 | the launchpad tiles are alive | wire Homepage tiles/widgets to the verified endpoints (home edge + VPS edge), then hand the visual check to the owner | endpoints and route tables are final; bug #6 is wiring · 📋 [`prompt-357.md`](prompt-357.md) |
| HD-358 | 2 | Seerr can talk to the *arrs without a human | record the Seerr→\*arr API-key + URL hand-off as a runbook step (and consider automating it in IaC) | home edge is up; bug #7 · 📋 [`prompt-357.md`](prompt-357.md) |
| HD-122 | 2 | Matrix profile auth proven | verify it now — the servers have been live since 2026-08-22 | the row used to wait on a deploy that already happened |
| HD-47 | 3 | Matrix is federated | publish `matrix`/`chat` + `_matrix` well-known/SRV, then prove inbound federation from an external server | servers live; the records are the only missing piece (also a prerequisite inside HD-147) |
| HD-112 | 2 | Zipline is usable, not just up | post-up seeding: local admin → OIDC login (one owner browser step) → flip `bypass-local-login` → create `guestbin` + `dropzone` → round-trip + 6 h sweep verify | deployed; the remainder is seeding |
| HD-159 | 2 | the tunnel-down alert is proven | run the deliberate `wg down` test and confirm `wg-s2s-down` fires (short planned window) | rule + scrape deployed, never proven · 📋 [`prompt-414.md`](prompt-414.md) |
| HD-287 | 2 | immich-ml runs with minimal caps | encode `cap_drop: ALL` + the ROCm-init `cap_add` set → converge → verify ML inference still works | its gate (the ML leg being live) is met; rides the HD-386 converge |
| HD-318(b) | 1 | the *arr quality profiles actually sync | confirm the recyclarr @daily sync landed (after the 2026-09-15 `bind_owner_uid` fix) | stacks are up; observation only |
| HD-280 | 2 | brute force actually gets banned | observation: confirm a repeated 401/403 produces a ban | jail is live; waits on natural traffic |
| HD-14 | 2 | HA entities reach the metrics store | enable the HA Prometheus exporter and export the entity list | the observability gate is gone (Victoria + Alloy live); feeds the HA dashboard |
| HD-17 + HD-217 | 2 | one failover button on the launchpad | render the **IP-only** button (`homepage_failover_button`; the RFUSB path is obsolete — HD-18 rejected) | `ha-failover-api` is active on oldsrv since 2026-09-08; only the render remains |
| HD-04 (tail b) | 1 | the HA standby is a standby again | restore oldsrv's keepalived conf to the **BACKUP 100** variant (the drill left the 120 failover variant) — before the next standby cold boot | a one-file revert the drill left behind; the rest of HD-04 is your failover test |

### Observability

Lane brief for the cadence row: [prompt-420.md](prompt-420.md) — **Wave 1**, and it now also carries
HD-395 (the spark watchdog), HD-377(b), HD-342 and HD-345, because they share `roles/monitoring/**` or the
spark converge. The rest of this section is independent of it and of each other.

| HD | P | Goal | ⏳ Next action | Note |
|----|---|------|----------------|------|
| **HD-420** | 2 | the nine spark panels the owner named show 5-second data — the OOM gauge included — without paying for 1,745 series | author the hot/cold `prometheus.scrape` split in `roles/monitoring/templates/alloy.river.j2` (gated to spark, **disjoint** `keep`/`drop` sets), then `DCGM_EXPORTER_INTERVAL` 30000→5000, then `jsonData.timeInterval: "5s"` on the `prometheus` datasource, then the `[5m]`-gauge panel fix | measured, not guessed: spark = **1,774 samples/scrape**, VM ≈ **0.33 B/sample**, so **50 hot series @ 5 s = +9.2 rows/s / ≈ +95 MB/yr** and blanket 5 s = +125 rows/s / ≈ 3.4 GB. ⛔ age-tiering is **out** (community VM has no `-downsampling.period`/`-retentionFilter`, O2's is enterprise) and a **second store was declined by the owner** — do not re-open either. ⛔ never restart the engine; the DCGM sidecar needs a CPU + anon-RSS pre-flight against its `mem_limit: 256M` first. · [prompt-420.md](prompt-420.md) |
| HD-344 | 3 | AI can query metrics/logs through MCP from its own tools | register the MCP endpoints in pi / Open WebUI / OpenClaw — **ports are `mcp_metrics_port` 8083 / `mcp_logs_port` 8084**, not :8080/:8081 | servers live on oldsrv; registration is the whole remaining row. ⚠ use the vars, never a literal port |
| HD-345 | 2 | the last `DatasourceNoData` class goes away | find why the SNMP `ifOperStatus` walk still yields 0 series (rules on, SNMP enabled) | the only one left · 📋 [`prompt-420.md`](prompt-420.md) |
| HD-342 | 2 | the observability data itself is backed up | Kopia client wiring for the Victoria data dirs | the Victoria cutover is live; this is its backup tail · 📋 [`prompt-420.md`](prompt-420.md) |

### Docs / policy (no host risk)

| HD | P | Goal | ⏳ Next action |
|----|---|------|----------------|
| HD-238 | 3 | a DR path that does not assume the GPU | ✅ runbook + yearly drill procedure WRITTEN 2026-09-21 ([backup.md](docs/backup.md) §Runbook / §Restore drill); the drill itself is owner-scheduled |
| HD-191 | 2 | a restore is a rehearsed act, not a hope — and **every store actually reaches the repo** | run the Kopia restore drill from a snapshot + verify the volume-name pin (you confirm the target); ⏳ **folded in 2026-09-21:** stand up the missing backup clients — there is **no client on the VPS** (so no `/srv/docker/*` and no SQL dump is off-site) and **no `db-backup` job on oldsrv** (so `lan-litellm-db` has no dump) — [backup.md](docs/backup.md) §VPS-side coverage gap |
| HD-133 | 3 | renewals stop being surprises | build the subscription SSOT → Homepage/calendar/n8n renewal notify |
| HD-32 | 4 | the family can help themselves | write the Slovenian family guides (`docs/manual/*`) |

---

## C. Standing rules that gate all of the above

1. **HD-397 needs a physical presence for its last half** — the off-LAN matrix is measured + green, the LAN/`Mgmt99`
   half cannot be taken from abroad. It gates nobody's code, only the on-site verification rows. Reachability itself is
   settled: [network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away.
2. **Never benchmark spark, and never run the engine-restart leg, from a session whose own model is
   spark** (incidents #3 + #6). **Narrowed 2026-09-23 by the owner:** such a session MAY converge spark
   when the change provably cannot touch the inference engine — `--tags monitoring`, the `spark-dcgm`
   sidecar, file-provider route edits (`spark-dashboard`, `traefik-tailnet`), `--tags spark,watchdog` —
   provided it records `docker inspect … vllm-qwen-spark` (id + `StartedAt` + `RestartCount`) before and
   after and shows `llm.kogler.si` still 200. Anything that recreates `spark-ai` (engine args, its env,
   the `spark-llm_api` item), the HD-395 live recycle proof and every bench stay outside such a session.
   Live converges run **detached** (`nohup … &` + log + poll), spark via the VPS jump. `--check` is the
   only safe foreground form — and it proves scoping only, because the deploy loop skips in check mode.
3. **Do not merge/converge `main`'s spark values over the certified ones** — the 16 GiB KV pool is the live, certified
   config, and `--enforce-eager` (C3) stays off on measurement, not on deferral.
4. **One writer per file family** — narrowed for parallel lanes by [prompt.md](prompt.md) §4 **O3**:
   `docs/services-ai*.md` stays one-lane-at-a-time (lane 407 while it lives), `templates/docker_services/**` is
   **one writer per service directory**, and there is **one converge in flight per host** (oldsrv / VPS / spark /
   router — the router slot is global because its converge is a device-wide `/import`). `roles/router/**` belongs to
   the HD-414 lane — **closed 2026-09-22, so `roles/router/**` and the router's converge slot are free again** (the IPv6
   section is folded into the converge template; the phone matrix RAN and the one-port exception was retired by measurement, so nothing reopens it). Check `git worktree list` + `git log` on the file before editing it.
5. **The runbook has no owning lane — ownership follows the action** (README §4.8): if a session did something a human
   would repeat by hand, `deployment-manual.md` gains the imperative line **in that same change**.
6. **Never print a secret value** — lengths, prefixes, item ids and hashes only.
7. **A test that cannot fail is not evidence** (CONVENTIONS §6): prefer the gate that carries its own self-test over
   prose that asserts coverage.

---

## D. Table Human — 🚧 what is genuinely left

The decision round closed most of this table; the residue below is **hands and eyes**, not questions. Every row is
also in §A2 with the reasoning.

| HD | P | Your move | AI then |
|----|---|-----------|---------|
| HD-147 (+ HD-141 tail) | 1 | browser logins: matrix / claw / cloud / foto / immich, + register on Forgejo — and settle **Forgejo-primary vs GitHub-only** while you are in there (note: the VPS Forgejo holds **no copy of this repo** yet, so "primary" is a plan today) | re-render the inventory + close the OIDC epic tail |
| HD-411 | 3 | sideload the APK, pair, 2-week verdict | the deployment + the §9b verdict either way · 📋 closed runner/cockpit lane (2026-09-23; brief deleted) |
| HD-353 | 2 | check your own Jellyfin login at seerrng (30 s) | fix whatever it reveals |
| HD-400 · 376 · 359 · 367 | 1–2 | one spark bench window | run the ladder detached, report the numbers |
| HD-412 | 2 | **two enrolment sessions** — the server itself has been LIVE on the VPS since 2026-09-21: enrol one Path-B family machine, then run one relayed session (phone on mobile data) and one Path-A tailnet direct-IP session with the relay provably uninvolved | the log read-back + the row close-out · ⛔ never on oldsrv: a rescue tool behind the thing it rescues is not a rescue (the `prompt-412.md` brief is deleted) |
| ⚠ **unrowed** | 1 | **fix the VPS tailscale listener** — `tailscale-sidecar` shares a container netns with `ports=map[]` and binds ephemeral sockets, so that node is permanently relayed and every path through it pays a hop | mint the row; pinning + publishing the port (or running the node on the host net) is the cheapest latency win left |
| ⚠ **unrowed** | 2 | **remove the router's non-default `/system logging` rule `ssh → memory`** — it floods ~1000 packet-dump lines per 3 min, saturating the memory log (it silently rotated away a window under measurement) and writing handshake bytes into it | mint the row; nothing in repo-managed config creates it |
| ⚠ **unrowed** | 3 | **decide whether inbound IPv6 from the ISP is worth chasing** — no unsolicited inbound v6 reaches the delegated prefix, so no home service can be published over v6 at any firewall cost | mint a row, or record the acceptance in [docs/network-rejected.md](docs/network-rejected.md) |
| **HD-415** | 3 | **a WAN-pulled drill at home** — the new resolver design is only as good as "the phone reaches the node direct over the LAN with the WAN pulled" | the chain is shipped — now prove all three cases in that drill (procedure: deployment-manual.md §1.4e) · 📋 [`prompt-414.md`](prompt-414.md) |
| HD-316 · 315 · 343 · 377 · 319 | 1–2 | the one visual pass (launchpad, host-overview, Network Clients, `homelab-llm`, the three KNX GAs) | fix what the eyeball catches; retire the three superseded dashboards |
| HD-397 (tail) | 2 | be on-site: the LAN matrix + the `Mgmt99` vNIC linked | close the row |
| HD-06 · 288 · 194 · 34 / 191 | 1–4 | physical windows: UPS pull → WoL · a router/switch/AP reset · gaming + Moonlight · one edge login/callback · the yearly restore drill | verify state after each; run the pin + Kopia GUI-vs-CLI assessment during the drill |
| HD-230 · HD-207 | 1 | decide at the drill: which sources get backed up · media rename vs personal-files | the surgical converge + the landing-zone mechanics |
| HD-362 · HD-57 | 2–3 | the music-pillar 1P values + Lidarr clients · bank tokens (and see HD-354: there is **no local music**, so the pillar's premise is now "if we ever have some") | the last mile on each |
| HD-366 | 2 | **still deliberately untouched by your instruction** — the JupyterLab LAN edge | nothing, unless you ask |
| OQ-12 · 13 · 14 | 2 | the memory-plane call (central `agentmemory` vs per-seat, Hermes' store, is the embedding leg needed) — the agentmemory probe answered all three on 2026-09-21/22 and decided none of them | a new HD row + the compose/seat work only after your word |

---

## ⚠ Watch-list — reads as done, is not

Checked 2026-09-21 against the registry + live SSOT. Each of these has already fooled one document.

| Claim you might believe | Reality |
|---|---|
| "A worktree existing means work is in flight" | It has meant the opposite twice. The 2026-09-22 sweep found **five finished lanes sitting unmerged** and, a day earlier, two lanes (HD-395, HD-399) opened and never started. Read `git log main..<branch>` and `git status` in the worktree — never the directory name |
| "The memory plane is decided / agentmemory is live" | **No.** The 2026-09-21 probe measured it and decided nothing: **OQ-12/13/14 are open owner calls**, nothing was installed, and the shape the question assumed (LAN bind + per-client tokens + per-user isolation) **does not exist in 0.9.29** — loopback-forced REST, one shared bearer, `TEAM_*` inert in the search path. And the durable negative: **LLM memory compression scored R5 0/5** — it rewrites identifiers out of existence. Facts: [services-ai.md](docs/services-ai.md) §9b |
| "HD-407 is blocked on a foreign key" | **Was.** The `oldsrv-rsync` key was retired 2026-09-21 (neutralized on nas, proven inert); `restore-runner-key.sh` now finds an empty path. What is in front of it now is AI work: land the clone for `ansible-admin`, pipe the token, prove `--check` from oldsrv — and delete both key halves after one green backup night |
| "Signal alerting is closed" | Device linked ✅, workflow live ✅ — but `signal_alert_recipients` is still **empty** in SSOT, so nothing reaches the group. **The value is the group ID signal-cli reports — not the group's invite link** (that blob is an encrypted join payload; HD-347 reads it from the linked daemon) |
| "Open WebUI ×2 is live" (`services-ai.md` banner) | The VPS runs **one** `open-webui` at `ai.kogler.si`; `chat` is **element-web**. **decided 2026-09-21: no second instance** — HD-248 is now just correcting that banner |
| "The pinned-AI tier runs on Ollama" | Not since 2026-09-19: STT = `whisper.cpp` Vulkan, rerank **and** embed = `llama.cpp` Vulkan on the RX 7600. `ollama/bge-m3` survives only as the embed **fallback rung** — and it is a *rung*, not a LiteLLM row (`/model/info` on both gateways returns one row each: `spark/qwen3.8-flash-next`). Plan of record: [services-ai.md](docs/services-ai.md) §3a + the §4a catalog runbook |
| "The reranker has a consumer" | It ships **dormant** (~327 MiB idle): `rag-mcp` is the HD-268b compose STUB with no `services:` block. It was verified with a LiteLLM probe + a synthetic consumer, **not** live RAG traffic |
| "Making spark text-only buys throughput" | Decision #28 says the opposite: no image tokens ⇒ the tower never executes ⇒ decode is expected **flat**. It buys memory on the boot-bound side (≈32.2k KV tokens per GiB). HD-400 |
| "Vision can be split: laptop ViT → spark" | **Rejected as unbuildable**, not merely expensive — vLLM's only pre-computed-vision seam is multimodal *embeddings*, which must live in the target model's own visual-token space. Vision lives on the workstation as a **text cascade** · [services-ai.md](docs/services-ai.md) §9 #28 + [hardware-workstation.md](docs/hardware-workstation.md) |
| "HD-383's stale-secret abort is a live blocker" | The glue is `bootstrap_keys: false` and the scoped-key list is empty — the abort is **unreachable**, and the stale 1P value is still standing in the vault. **authorized 2026-09-21** to clear it before HD-384 re-arms the glue |
| "Navidrome never deployed" | Deployed: container Up, the Box music dir mounted ro, scanner ran. **there is no local music at all** (the family listens from the cloud — owner fact 2026-09-21), so HD-354's library and admin halves are void; do not mint an admin for an empty library |
| "Matrix waits on unprovisioned hosts" | Tuwunel + Element have been live since 2026-08-22; HD-47/122 are verifies now (DNS records + profile auth) |
| "Zipline's first deploy is human-gated and pending" | `zipline` + `zipline-db` are Up/healthy — only post-up seeding is left (HD-112) |
| "The watchdog's idle recycle is a safe background detail" | It restarted the engine twice 35 min apart on a healthy box; its baseline is boot-timing-dependent (HD-395) |
| "oldsrv SSH / the Mgmt plane is broken" | Closed 2026-09-19: HD-392 and HD-398 are deleted rows. The VPS jump rides in `group_vars` (no `-e` needed), `ssh oldsrv` = the **Home** leg, VLAN 99 stays sealed by owner decision **A** |
| "The §A decisions are done" | **Recorded, not shipped** — though three have since shipped (HD-399, HD-416, HD-350), which is why this line is re-checked, not trusted. The table changed what is *asked*, not what is *built*. The first wins left are HD-347, HD-383→HD-384→HD-403, HD-417 |
| "Forgejo is the repo's primary remote" | **The VPS Forgejo holds no copy of this repo** — `origin` is GitHub. The "Forgejo primary + GitHub mirror" line in [deployment-secrets.md](docs/deployment-secrets.md) is a plan, and HD-147's Forgejo registration is where you decide whether it stays one |
| "oldsrv will pull and push like the laptop" | **Pull-only, and now for keeps unless you say otherwise** (`HD-449`): the deploy token is read-only and that is proven by a 403 on push, so commits made there wait for a laptop session. The old promise that this ends "when the cockpit lands" pointed at a closed row and is gone |
| "Cockpit runs on every node, so break-glass is a fleet-wide problem" | The `cockpit` role runs on **two** hosts — `nas` + `oldsrv`. Pi, spark and the VPS have no cockpit, and spark's management surface is deliberately a separate question |
| "The tailnet resolver chain just needs tidying" | Trimming the "unreachable" home resolvers sells the WAN-out case. The decided fix is reachability: a resolver on **oldsrv's tailnet address**, with the VPS as fallback (HD-415) |
| "The exit-node question is still open" | **Decided 2026-09-21: it stays on the Pi**, row deleted. The re-open trigger is HD-406's full-tunnel profile, which removes the need for an exit node at all |
| "A static public IPv4 means phone→oldsrv is direct" | **Measured false here:** the first away session came back `Relayed (FRA)`, 60–90 ms. Hence HD-414 gating HD-410/406/412 |
| "HD-386's parked tailnet names are an open decision" | Settled in code + [network-vpn.md](docs/network-vpn.md): `dsh`/`pi-dev` answers **502 by design**. The row's only tail is the `failed=0` converge log |

---

## Park / moot

| HD | P | Status |
|----|---|--------|
| HD-45 | 3 | Homelable + network dashboard — a parallel lane owns implementation; do not re-plan |
| HD-264 | 2 | Renovate sandbox `domen/test` — parked, owner steps (external re-launch mechanism, real manifest, then flip `RENOVATE_REPOSITORIES`) |
| HD-250 | 3 | DSH onboarding — **parked with the service** (`enabled: false`, HD-386) and moot under decision #26 |
| HD-28 | 3 | Office AI stack — not parked but **not startable**: its Ollama half is superseded twice over and its MCP half waits on HD-111 |

---

## Bottom line

- **The owner-side backlog is three sentences long:** do the browser logins (HD-147), be present for the
  windows in §A2, and answer the three **memory-plane** calls (OQ-12/13/14 — measured, one page, nothing blocks
  AI work while they wait). Everything that used to sit in front of the AI work has a decision attached to it.
- **Decided ≠ shipped — that is the honest state of this table.** Cheapest first, in order: **HD-347** (one value,
  alerting stops being blind) → **HD-383 → HD-384 → HD-403**
  (one vault-and-registry change that finally gives voice and the simple queriers a route)
  → **HD-417** (the last cheap gate for a failure class no validator can see today). Shipped since this line was
  written, and off it: **HD-399** (oldsrv `--check` works), **HD-416** (the grant gate), **HD-350** (the cert-pull
  leg — and it was not "one pubkey": the grant had been in place for eight days, see
  [docs/services-traefik.md](docs/services-traefik.md) §Certification).
- **Then the sequenced chain:** HD-414 (scoped IPv6) was the hinge — it shipped and measured, closing itself and HD-410, which unblocks
  HD-415 resolver redesign: HD-406 now runs and is the surviving transport shape, while HD-415 shipped on 2026-09-22 and now waits on a measurement only — the three-case drill (HD-412 shipped 2026-09-21 without waiting). HD-407 is unblocked and mechanical now, and HD-409 rides it.
- **Independent of every chain, and already specced:** **HD-420** (spark metric cadence) — the measurement is done,
  the design is written in [docs/observability.md](docs/observability.md) §Scrape cadence and
  [prompt-420.md](prompt-420.md), and it touches only `roles/monitoring/**` + the dcgm sidecar, so it can run in
  any spare session without colliding with a lane.
- **One thing is still wrong with the repo and has a row:** the standby HA edge cannot proxy (**HD-418**). The other
  fault-note of that pair, `media.kogler.si` answering 502 (**HD-419**), was fixed and verified 2026-09-22 — and fixing it
  exposed that the same `502` shape covers `seerr`/`sonarr` and the rest of the home-hosted route group, which has **no row
  yet** (recorded in [docs/services-traefik.md](docs/services-traefik.md) so it can be minted with the evidence attached).
- **Oldsrv reachability is not a blocker:** off-LAN it is the Home leg through the VPS jump, carried in `group_vars`
  since 2026-09-19 — `bash scripts/ansible-run.sh playbooks/home_servers.yml --limit oldsrv.kogler.si --check …`
  needs no `-e`. The only things presence still buys are the on-site half of HD-397, the `*99` aliases and the
  HD-415 WAN-pulled drill.
