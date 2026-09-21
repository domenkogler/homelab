# Todo Split — Decided State, AI-Runnable Work, Owner Residue (planning view)

> **Role:** hand-curated planning view of [`todo.md`](todo.md) — the whole open backlog seen as **what to do next**.
> §A is now a **decision record**, not a queue: it states what the owner already answered and where each answer is
> logged, so no later session re-asks it (§A1), plus the small residue that is genuinely still theirs (§A2).
> **`todo.md` stays the registry SSOT** (CONVENTIONS §4(a): a fully-done row is deleted from the registry; this table
> is a view, not a second record) and **must be re-synced whenever the backlog changes**.
> **Linked from:** [`todo.md`](todo.md) · [`prompt.md`](prompt.md) · [`README.md`](README.md) · [`scripts/README.md`](scripts/README.md)
>
> **Re-synced 2026-09-21, second pass — after the owner answer round.** What moved in one day:
> - **The question queue emptied.** §A became a record of 17 decisions (cockpit surface and seat, the exit node,
>   the scoped-consumer grant, the git-credential shape, the OWUI split, the resolver chain, and more), each pointing
>   at its `*-rejected.md` row. §A2 is what is actually left of the owner: logins, a sideload, and physical windows.
> - **§0 Repo state:** the two empty session worktrees (the HD-395 and HD-399 lanes, both 0 commits) and all twelve
>   stale `session/*` branches are gone; `main` is the only checkout, clean, `validate-all.sh` green.
> - **Registry: 102 rows** — HD-408 deleted as decided, **HD-418 / HD-419** registered out of the two fault-notes that
>   lived only in [network-vpn.md](docs/network-vpn.md) prose.
> - **§B** gained the rows the decision round converted from owner-gated to pure AI.
> - **Watch-list** now also catches the false claims a decision round creates by itself — "`§A` is done" (decided is
>   not shipped), "Forgejo is the remote" (it holds no copy), "oldsrv will push" (it is pull-only until HD-409).

---

## 0. Repo state (one screen)

| Fact | State (measured 2026-09-21) |
|---|---|
| Primary checkout `/home/domen/source/homelab` | `main`, working tree **clean** — a merge station, not an edit site |
| `bash scripts/validate-all.sh` | **GREEN** |
| Session worktrees | **transient by design** — a lane worktree (`../homelab-wt-<YYYYMMDD>-<HHMM>`) exists only while its lane runs, and the parent removes it after the merge. Two were open at the 2026-09-21 sync (HD-395, HD-399, both 0 commits) and were retired with the owner's word via `git worktree remove`; the HD-420 lane (`homelab-wt-20260921-1125`) was merged and pruned at close-out |
| **Lane briefs = the dispatch unit** | **one `prompt-<HD>.md` brief = one session = one worktree = one branch.** Each brief carries the rows it owns, the files it owns and the converge host it holds; the row index per brief is §B0 below. Waves, pairing and the merge/cleanup contract are in [prompt.md](prompt.md) **§4**, whose rules deliberately DIFFER from README §4 and CONVENTIONS §6 (items O1–O8 there) — §4 is silent nowhere this table depends on |
| **Who writes `prompt.md` / `todo-table.md`** | **The orchestrator only** (§4 O2). Lane sessions edit their own `todo.md` rows and their own `deployment-tasks.md` lines, and never touch these two views — `check_todo_done.py` couples `prompt.md` to `todo.md`, so two writers on the views means a red gate by construction |
| Stale session branches | **all 12 deleted** with `git branch -d`, which refuses an unmerged branch — so the sweep itself proved nothing was stranded |
| Registry size | **derived, not typed** — row count and the next-free id (max + 1) are read out of [todo.md](todo.md) with `grep -c` on its `HD-` rows; 103 at the 2026-09-21 sync, which registered **HD-420** (a literal pipe would break this cell — see [todo.md](todo.md) HD-417) |

### What is live vs authored-only

- **Live:** VPS edge (Phase 1), nas (Phase 2), Pi (Phase 4), oldsrv (Phase 3, full `docker_services` healthy),
  Victoria* observability, 3-instance DNS HA, the home `traefik-internal` edge, `lan-litellm` on oldsrv, the three
  pinned-AI Vulkan legs on the RX 7600, spark as the generation tier with the **16 GiB KV pool certified**, and
  **oldsrv as a headscale node** (`tag:dev:443`, `ha.ts.kogler.si` from its own edge).
- **Open, and now fully AI-owned:** everything in §B. The owner answer round of 2026-09-21 removed every remaining
  hand from the top of the backlog (§A1) — what is left on the owner's side is §A2.
- **The live reality that reorders the transport lane:** the first real away session to the home node came back
  **`Relayed (FRA)`, 60–90 ms**, so "static public IPv4 ⇒ direct" is **false for cellular clients here**. That is why
  HD-414 (scoped IPv6) gates HD-406, HD-410, HD-412 and now the HD-415 resolver work.
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
| **HD-350** ✅ | The AI performs the pubkey append on the VPS itself (back up `authorized_keys` first, then prove the cert pull stops 401ing) | `todo.md` row |
| **HD-354** ✅ | **No music exists on local disks** (the family listens from the cloud) → the Box-library and admin-user halves are **void**; do not mint an admin for an empty library. Tail = the Subsonic/ExtAuth verify | `todo.md` row |
| **HD-361** ✅ | Break-glass identity = **one password-bearing `maint` per cockpit host** — today `nas` + `oldsrv`, the only two hosts with the `cockpit` role. Vault items `nas-cockpit_login` / `oldsrv-cockpit_login`, password **generated by the AI**, `sudo` group, **no NOPASSWD**, no SSH keys, excluded from `AllowUsers`. ⚠ `cockpit` is in the HD-413 lockout set → converge from the laptop | [services-traefik.md](docs/services-traefik.md) §Cockpit Routes |
| **HD-383** ✅ | Remediate the stale `dsh` secret **now** (owner authorized the write path): clear the credential, delete the `dsh` alias in the LAN Admin UI, drop the item's doc row — one change | `todo.md` row |
| **HD-384** ✅ | Scoped consumers get the **`spark/qwen3.8-flash-next` row only**, never a `spark/*` wildcard. **`max_budget` dropped** (owned devices, no metered cost); **`rpm` caps stay** — they are contention protection on the one 262k KV pool, not a bill. Plus a separate client credential for the `llm` router so `spark-llm_api` stops being triple-used | [services-rejected.md](docs/services-rejected.md) 2026-09-21 |
| **HD-406** ✅ | Build **after HD-414 is measured**; the phone peer is **scoped** to one admin device, with **full-tunnel as an optional second allowed-IPs profile** — that profile is what answers Slovenian egress and what makes the Pi's exit node redundant. AI mints the keypair | `todo.md` row |
| **HD-407** ✅ | Seeding is **AI-runnable and authorized**. Pull with the **read-only** `github-homelab-deploy_api` over HTTPS via a 0600 credential store (never in the remote URL); **GitHub is the live remote** — Forgejo on the VPS holds no copy of this repo; the vault **signing** key is reused, so commits on oldsrv are signed and attributed to you; `github_auth` (push) stays off the box. **Consequence: oldsrv is PULL-ONLY until HD-409** adds a repo-scoped write key | [deployment-rejected.md](docs/deployment-rejected.md) 2026-09-21 |
| **HD-408** ✅ | **Exit node stays on the Pi** — the row is deleted. Weighed: an exit node adds no SD-card wear worth naming (tailscaled logs no per-flow data, nft masquerade is silent), so the real tradeoff was oldsrv's better pipe against widening the tailnet boundary — and the boundary won. Re-open trigger: the HD-406 full-tunnel profile proving geo-egress with no exit node at all | [network-rejected.md](docs/network-rejected.md) 2026-09-21 |
| **HD-409** ✅ | Surface = **`@ygncode/pi-web`**, running under your **`domen`** seat on oldsrv (accepted deviation from the non-human-workspace precedent — measured: `domen` there holds neither the `op` token nor the fleet key); `ansible-admin` stays runner-only; **break-glass is now `<host>-cockpit_login`**, not `domen` | [deployment-rejected.md](docs/deployment-rejected.md) 2026-09-21 |
| **HD-411** | Paseo runs **simultaneously with HD-409**, one comparison window, two surfaces (own `*_port` var each, both tailnet-bound, relay off). **Your hand: sideload + pair + 2-week verdict** | `todo.md` row · 📋 [`prompt-407.md`](prompt-407.md) |
| **HD-412** ✅ | Family machines **join the tailnet** where they can (direct-IP, no relay); hbbs + hbbr still land on the **VPS** for the rest, **relay bandwidth-capped** to the VPS quota | `todo.md` row |
| **HD-415** ✅ | Neither "leave it" nor "trim it": make the resolver **reachable from wherever the device is**. The chain becomes **oldsrv's tailnet node address** (direct-over-LAN at home with the WAN pulled; reachable away while the home link is up) **+ the VPS public instance as fallback**, and the two LAN-address entries go. Case (d) — away while the **home** WAN is down — is accepted as unresolvable: your words, *"it is ok that I will not get dns for whole domain, because it is not reachable from the internet."* Folded into the HD-414 lane | [network-dns.md](docs/network-dns.md) §The resolution requirement + [network-rejected.md](docs/network-rejected.md) 2026-09-21 |
| **HD-248** ✅ | **No second OWUI instance now** — the row is now just "correct the stale `x2 live` banner"; the split stays planned until a real second audience exists | [services-rejected.md](docs/services-rejected.md) 2026-09-21 |
| **HD-336b** | CrewAI **stays parked** — you are evaluating alternatives (incl. Hermes); no pilot until you rule | `todo.md` row |
| **HD-418** ✅ | `ha_trusted_proxies` += oldsrv's Home IP, **in a planned window** (restarts the controller) — because the standby HA edge has never actually worked | [smart-home-rejected.md](docs/smart-home-rejected.md) 2026-09-21 |
| **HD-419** ✅ | Publish a jellyfin host port on the Home leg → kills the `media.kogler.si` 502 and feeds HD-357's tile | `todo.md` row |

### A2. What still needs you — the honest residue

| What | HD | Note |
|---|---|---|
| **Browser logins** matrix / claw / cloud / foto / immich (+ register on Forgejo) | HD-147 + HD-141 tail | You know. The click-by-click with the five URLs comes with the next session's task list. One embedded choice: **Forgejo primary + GitHub mirror** vs GitHub-only — note Forgejo is **empty today**, so "primary" is currently a plan, not a fact |
| **Sideload the Paseo APK + pair + a 2-week verdict** | HD-411 | Runs in parallel with HD-409 now |
| **Check your Jellyfin login at seerrng** | HD-353 | 30 seconds |
| **A spark bench window** | HD-400 · 376 · 359 · 367 | Detached; never with an agent session attached, never from a spark-backed session |
| **Re-measure the phone once, after IPv6** | HD-410 · HD-414 | The matrix itself ran ✅ 2026-09-21 (HD-405 closed). One `tailscale ping` from oldsrv to the phone after the /56 lands, plus the app's session-type line: **does it flip to Direct?** |
| **A WAN-pulled drill at home** | HD-415 | The new resolver design's whole load-bearing assumption is that a phone at home reaches the node **direct over the LAN with the WAN pulled**. That is proven by a drill you are present for, not by a `dig` from the laptop |
| **One visual pass** | HD-316 · 315 · 343 · 377 · 375 · 319 | Launchpad, host-overview (disk-work + temps), Network Clients, `homelab-llm`, the two memory rules in Grafana **and** reaching n8n, the three rekuperator GAs |
| **Be on-site once** | HD-397 tail | The LAN matrix + the `Mgmt99` vNIC half |
| **Physical windows** | HD-06 · 301 · 288 · 194 · 34/191 | UPS pull → WoL · a router/switch/AP reset · gaming + Moonlight · one edge login/callback · the yearly restore drill (also where HD-207 and HD-230 get decided) |
| *(optional)* | HD-409 | If you want oldsrv to **push**, mint a repo-scoped **write-capable** deploy key when HD-409 lands. Until then oldsrv pulls only and commits wait there |

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
| [prompt-407.md](prompt-407.md) runner + cockpit | **1** | HD-407 · 409 · 411 · **399 · 386 · 416 · 388 · 356** | oldsrv |
| [prompt-420.md](prompt-420.md) metric cadence | **1** | HD-420 · **395 · 377(b) · 342 · 345** | spark + VPS (`--tags monitoring`) |
| [prompt-414.md](prompt-414.md) scoped IPv6 + transport | **2** | HD-414 · 415 · 406 · 410 · 405 tail · **419 · 09 · 301** (+159 with a window) | router (global slot) + oldsrv |
| [prompt-412.md](prompt-412.md) RustDesk | **2** | HD-412 | VPS |
| [prompt-384.md](prompt-384.md) LiteLLM consumer chain | **3** | HD-383 · **384** · 403 · 387 · 373 · 249 | oldsrv + VPS `docker_services` |
| [prompt-376.md](prompt-376.md) spark engine + bench | **3** | HD-376 · 400 · 359 · 367 · 380 (absorbs the stale `prompt-next.md`) | spark, **owner bench window** |
| [prompt-357.md](prompt-357.md) launchpad + home edge | **4** | HD-357 · 17 · 217 · 358 · 418 (window-gated) | oldsrv |
| [prompt-394.md](prompt-394.md) VPS hygiene + backup/DR | **4** | HD-394 · 360 · 402 · 103 · 49 · 238 | VPS + nas |
| [prompt-417.md](prompt-417.md) gates + doc hygiene | **5, alone** | HD-417 · 404 · 248 · 396 | none (repo-only) |
| [prompt-405.md](prompt-405.md) | — | **CLOSED — no session launches from it;** the parent deletes it in a §4 cleanup commit with its inbound links fixed | — |


### 🔥 Active lanes

| HD | P | Goal | ⏳ Next action | Why nothing blocks it |
|----|---|------|----------------|------------------------|
| **HD-399** | 2 | every `docker_services --check` on oldsrv runs at all | gate the Technitium login block with `not ansible_check_mode` (`uri` does not run in check mode, so the registered token dies at `technitium-seed.yml:102`) | pure IaC defect, located 2026-09-19; third instance of a catalogued class in [deployment-ansible.md](docs/deployment-ansible.md) §Dry-run Mode. ⛔ no `default()` / `failed_when: false` — fail-loud. Interim green form: `--check --tags common,network`. **A lane was opened for this and never started (§0)** · 📋 [`prompt-407.md`](prompt-407.md) |
| **HD-395** | 2 | the watchdog stops restarting a healthy spark engine | baseline the idle recycle only after `/health` 200 **and** a settle window (or max of N samples), then re-check the +8 GiB margin against the certified peak | measured defect: the first-post-boot floor has been read **71,911 / 86,243 / 92,343 MiB** on one config → it either restarts a healthy engine or goes silent. Drive it from the laptop, never from a spark-backed session. **A lane was opened for this and never started (§0)** · 📋 [`prompt-420.md`](prompt-420.md) |
| **HD-414** | 1 | the phone reaches oldsrv **directly** instead of via a Frankfurt relay | scoped IPv6 on the RB4011: DHCPv6 PD for the /56 → /64s for **Home VLAN 10 only** → RA on VLAN 10 → v6 filter = drop-all-from-WAN with **one** UDP 41641 accept to oldsrv → prove it by probing **from the VPS** | the static /56 exists, the laptop is at home, and it deliberately gates HD-406/410/412. RouterOS 7.21 syntax must be verified before converging; the `.rsc` is generated — never hand-edit, never `system reset`. [prompt-414.md](prompt-414.md) |
| **HD-416** | 2 | every SSH grant on a managed host is named, or it does not exist | read-only `authorized_keys` audit across the managed hosts (fingerprints + comments), diffed against the named set in [deployment-secrets.md](docs/deployment-secrets.md) §Who is authorized where, failing loud on an unknown | triggered by the `oldsrv-rsync` key that authorized `ansible-admin` (NOPASSWD root on nas) from no vault item; four live grants still have none. ⛔ it must **never** edit an `authorized_keys` — the classic failure of an SSH tool is locking yourself out with your own fix · 📋 [`prompt-407.md`](prompt-407.md) |
| **HD-417** | 3 | the validators can see a broken table | cell-count check for markdown tables in the docs validator (split on unescaped pipes, compare to the header, fail with file + line) + an escape convention + a one-time legacy sweep | a swallowed newline merged two registry rows and an `/etc/x`-style description added nine stray cells to a 3-column row on 2026-09-21 — both passed every gate. Cheap guard for a failure that is invisible today. · [CONVENTIONS.md](CONVENTIONS.md) §6 · 📋 [`prompt-417.md`](prompt-417.md) |
| **HD-387** | 2 | know whether thinking is actually OFF through the gateway | run the written probe protocol against the LAN instance (baseline → toggle → budget pair → `top_k` → the proxy's own dropped-params log) | a recorded live measurement and the pinned source contradict each other, and the failure mode is silent thinking-ON at HTTP 200. Master-key path, no client change; the harness route does not move either way (decision #26) · 📋 [`prompt-384.md`](prompt-384.md) |
| **HD-396** | 2 | the retired `op_api` secret thread ends with a fact | repo-archaeology, one question: does the Forgejo CI runner still exist, and does it still hold the pre-2026-09-19 secret? renew it, or delete the stale Phase 0/5 prerequisite lines in [deployment-tasks.md](deployment-tasks.md) | the leak itself is closed (record: [deployment-ai-stack-secrets.md](docs/deployment-ai-stack-secrets.md) §4a); no IaC references `op_api` any more, so only the Forgejo side can answer it · 📋 [`prompt-417.md`](prompt-417.md) |
| **HD-394** | 2 | no container runs that no converge owns | list every running container without a compose project label, propose removal (owner OK before deleting), record in [services-vps.md](docs/services-vps.md) | `confident_shamir` (hand-run traefik, no nets/ports) + `pgvector` (superseded by Qdrant) are invisible to every converge; the third entry (`authentik-ldap`, unhealthy) is HD-360's · 📋 [`prompt-394.md`](prompt-394.md) |
| **HD-386** | 1 | the oldsrv `docker_services` converge is green with the harnesses parked | converge oldsrv `--tags docker_services,lan-litellm` (**both** tags), **detached**, **no `--diff`**; expect the parked pair + the key glue to SKIP, `failed=0` | the park is authored + validated; only the log is missing (a read-only sighting of the end-state exists, it is not the artifact the row asks for) · 📋 [`prompt-407.md`](prompt-407.md) |
| **HD-393** | 1 | the `amdgpu init_user_pages: -1` burst is explained or accepted | attribute the **one** bounded episode (dmesg 774,316 s → 780,804 s) per-process — journal vs container restarts in that window — then fix or record as noise | re-measured: 1,296 lines, all inside ~1.8 h, **0 hang/reset** anywhere, none new since. ⚠ `dmesg` needs `sudo` on oldsrv; `rocm-smi` lives **inside** `immich-ml`/`ollama`, not on the host |
| **HD-369** | 2 | voice points at the tiers that are actually live | **(d)** Whisper → the live whisper.cpp **Vulkan** leg on oldsrv (not Ollama), Piper → CPU, LLM → spark; then **(e)** the Sunshine priority glue (pause/unpause pinned-AI + immich-ML) | the tier has been live since 2026-09-19, so (d) has something to point at. ⚠ **(c) is SUPERSEDED — do not recreate the ollama catalog, do not bump the `:rocm` pin**; (f) is done |
| **HD-402** | 2 | the OCR engine is chosen by measurement, not by hope | confirm the Docling `RapidOcrOptions` adapter exposes the PP-OCR `latin` rec model → convert the **same Slovenian scan** with EasyOCR and RapidOCR-ONNX → keep only if quality ≥ EasyOCR → record the speed delta | CPU bench on the VPS, no host risk. Language was never the blocker (`latin` includes `sl`); the risks are the script-grouped model on `č ć š ž` and the adapter wiring. Closes on the **HD-103** scan gate. Free lever regardless: `do_ocr=False` for born-digital PDFs · 📋 [`prompt-394.md`](prompt-394.md) |
| **HD-401** | 2 | the workstation provably carries FIM + visual judgment locally | clear the four pre-flight gates in [hardware-workstation.md](docs/hardware-workstation.md): pick + record the ROCm/`gfx1151` stack, prove the VL `mmproj` runs on the iGPU (measure `--image` prefill), measure FIM latency on the real Continue prompt shape, check the iGPU carve-out/GTT | **the stack install on this box is authorized (owner, 2026-09-21)** and three of the four gates are measurable right here. ⚠ every platform figure in that doc is owner-stated/community, **unmeasured here** |
| HD-356 | 1 | the LAN gateway is confirmed live after the converge | re-check the LAN instance (live + serving) once HD-386 converges green; the scoped-key glue tail is **not** a fix — it is OFF by design and rides HD-384 | the split is deployed + healthy. ⚠ Its role changed with decision #26: gateway for the **simple queriers**, not the harnesses · 📋 [`prompt-407.md`](prompt-407.md) |
| HD-382 | 2 | (tail only) | both tails are decided work now, not questions: the allow-list is **HD-384**, the stale secret is **HD-383** | the model entry is live in both LiteLLM DBs + E2E verified |
| **HD-388** | 2 | client model config is rendered from one repo spec, not hand-copied per machine | render `pi` `models.json` + a Continue config from one spec, credential resolved via `op` at render time | pure repo tooling; default shape is a standalone `scripts/render-client-config.py` reusing the `render_all.py` Jinja env — no owner call needed unless you object. ⚠ the template must **not** merge the two `contextWindow` numbers (engine 262,144 vs the LiteLLM row's 245,760 = window − reserve); they differ on purpose · 📋 [`prompt-407.md`](prompt-407.md) |
| **HD-376** | 2 | agentic max-context is proven, and lanes get a smaller window | promote the `spark-lane` 64k profile; run the 262k needle test; measure parent-vs-lane KV contention | engine + harness config are live; the lane profile is paper-only. ⚠ needs the bench window (A3) — same window as HD-359/367 + HD-400, never an attached agent session · 📋 [`prompt-376.md`](prompt-376.md) |

### 🆕 Remote-dev plane (three file-disjoint lanes — run one per session)

Briefs: [prompt-414.md](prompt-414.md) (transport, successor to the closed [prompt-405.md](prompt-405.md)) ·
[prompt-407.md](prompt-407.md) (runner + cockpit, **Wave 1**, also carrying HD-399 / 386 / 416 / 388) ·
[prompt-412.md](prompt-412.md) (remote desktop) · and the follow-on lanes [prompt-384.md](prompt-384.md)
(LiteLLM consumer chain), [prompt-357.md](prompt-357.md) (launchpad + home edge),
[prompt-376.md](prompt-376.md) (spark engine + bench), [prompt-394.md](prompt-394.md) (VPS hygiene + backup/DR),
[prompt-417.md](prompt-417.md) (gates + doc hygiene). Run one brief per session — [prompt.md](prompt.md) §4.
Decisions are already in the `network` / `deployment` / `services` decision logs — start from the briefs, do not
re-open the direction. Two standing decisions were **scoped, not repealed**: the tailnet permits exactly one home host
with **no advertised routes**, and the VLAN-99 seal (HD-398 A) is untouched.

| HD | P | Goal | ⏳ Next action | Gate / note |
|----|---|------|----------------|-------------|
| **HD-407** | 1 | oldsrv = primary control node, laptop demoted to rescue | **no owner hand remains** — land the clone for `ansible-admin`, pipe the `op` read-scope token, bootstrap, then prove `--check` **from oldsrv** per inventory group | pull path decided: read-only `github-homelab-deploy_api` over HTTPS with a 0600 credential store; **GitHub is the live remote** (the VPS Forgejo holds no copy); the vault signing key is reused; `github_auth` stays off the box → **oldsrv is pull-only until HD-409**. ⚠ nothing syncs the clones — `git pull --ff-only` is an explicit act. HD-413 shipped and is validator-enforced · 📋 [`prompt-407.md`](prompt-407.md) |
| **HD-409** | 1 | the harness + a phone-first cockpit run on oldsrv | install/serve **`@ygncode/pi-web`** under the `domen` seat, mint the `*_port` var, verify from the phone, then move the ownership table in [pi-harness.md](docs/pi-harness.md) §1 + a numbered decision in [services-ai.md](docs/services-ai.md) §9 in the same change | surface + seat **decided** (§A1). ⛔ do not re-enable the parked `dsh`/`pi-dev` registry rows — that re-renders a deliberately-empty 1P item and takes the oldsrv converge red. Needs a reserved port var (not `:8080`/`:8081`) and a Kopia seam over the workspace + `~/.pi`. TUI-in-tmux stays the floor · 📋 [`prompt-407.md`](prompt-407.md) |
| **HD-412** | 2 | family machines can be helped remotely | §5 onboarding (exposure/auth → secrets → compose → registry → backup) — the **VPS half is buildable right now** | model **decided**: family machines join the tailnet where they can, VPS rendezvous + **bandwidth-capped** relay for the rest. ⛔ never on oldsrv: a rescue tool behind the thing it rescues is not a rescue · 📋 [`prompt-412.md`](prompt-412.md) |
| **HD-406** | 2 | a dev path that depends on neither the VPS nor headscale | **after HD-414 is measured:** render a **scoped** WG peer for one admin device in `roles/router`, plus an **optional full-tunnel** allowed-IPs profile, then prove both paths (tunnel up / tunnel down) | **decided 2026-09-21.** The AI mints the keypair — no owner credential hand. The full-tunnel profile is the thing that answers Slovenian egress **and** makes the Pi's exit node redundant · 📋 [`prompt-414.md`](prompt-414.md) |
| **HD-410** | 3 | know whether a session is direct or relayed **before** buying a relay | measure `DIRECT` vs `relay` from a phone on mobile data over a few days, then decide | the derp map uses the **public Tailscale** relays, so a failed punch puts a third party in a dev session — but a DERP built on a hypothesis buys a public listener for nothing. Today's reading: relayed is the reality, so HD-414 first · 📋 [`prompt-414.md`](prompt-414.md) |
| **HD-411** | 3 | a native Android path to the same harness, without a third-party relay | AI: the daemon (systemd or a scoped container), tailnet bind + password + hostname allowlist, **relay off**, one 1P item | **sequence changed: runs simultaneously with HD-409**, one comparison window. Owner hand: sideload + pair + the 2-week verdict. The browser cockpit stays **primary** — an app someone else maintains cannot be a dependency, a URL can · 📋 [`prompt-407.md`](prompt-407.md) |
| **HD-415** | 3 | one tailnet resolver that works **wherever the device is** | bind Technitium to oldsrv's **tailnet node address**, make it the headscale nameserver, keep the VPS instance as the fallback, drop the two LAN-address entries | **decided 2026-09-21** — the away-vs-WAN-out conflict is a reachability problem, not a sort order; runs inside the HD-414 lane. ⚠ acceptance = the three-case drill (LAN / cellular / **home with the WAN pulled**); direct-over-LAN to the node is the load-bearing assumption · [network-dns.md](docs/network-dns.md) §The resolution requirement · 📋 [`prompt-414.md`](prompt-414.md) |
| hygiene | — | close two small debts the transport lane named | expire the **retired headscale preauth keys 4 (`tag:pi-dev`) + 5 (`tag:dsh`)** — live, reusable, non-expiring for services that no longer exist; report ids only, never values | one `headscale preauthkeys expire` each; the tombstones in [deployment-secrets.md](docs/deployment-secrets.md) do not revoke them — headscale does. Also: `prompt-405.md` (a closed banner) is deleted by **the orchestrator** in its [prompt.md](prompt.md) §4 cleanup commit, together with the link fixes in `prompt.md` / `todo.md` / `todo-table.md` — no lane deletes a brief (see [prompt-414.md](prompt-414.md) row 8) |

### AI / Office

| HD | P | Goal | ⏳ Next action | Note |
|----|---|------|----------------|------|
| HD-268 / HD-337 / HD-335 | 1–2 | RAG + memory + office stack live | Qdrant embed/rerank + **re-index** after the bge-m3/1024 cutover, OKF wiki skeletons (**268a**), then **268b = implement `rag-mcp`**, Mem0 + OpenHands | ⚠ the Vulkan embed move does **not** trigger the re-index (same dims, cosine 0.9996). ⚠ `rag-mcp`'s compose is a TODO comment block with **no `services:` section** — its `enabled: false` is not a flag to flip; until 268b lands the reranker leg stays dormant (~327 MiB) |
| HD-360 | 2 | Samba auth rides Authentik over LDAP | declare the provider + `svc_samba` in the Blueprint → mint a fresh bind token → redeploy the outpost → **then** flip `storage_samba_passdb: ldapsam` + converge nas | ⚠ order is safety-critical: smbd fails hard if the flip lands first (that outpost is also HD-394's third census entry, Up **unhealthy** = expired token) · 📋 [`prompt-394.md`](prompt-394.md) |
| **HD-403** | 2 | voice has an LLM to call | mint a `home-assistant` scoped key vault-first, render `LITELLM_BASE_URL` + key into the compose env, point the Assist pipeline at it | HA ships only `TZ` in its env today; **HD-384 is decided**, so this is now plain work · [smart-home-voice.md](docs/smart-home-voice.md) · 📋 [`prompt-384.md`](prompt-384.md) |
| **HD-404** | 3 | the last stale IaC strings stop teaching agents the wrong truth | text-only PR over the enumerated list (Victoria headers, the Pi "primary DNS" comment, the `llm-backend` purpose string that feeds a generated doc, `amd_rocm`'s `OLLAMA_KEEP_ALIVE`, `first-boot-config.sh`'s wording) | the docs stopped repeating these; the comments are now the last place an agent reads a wrong truth · [deployment-ansible.md](docs/deployment-ansible.md) · 📋 [`prompt-417.md`](prompt-417.md) |
| HD-336 | 2 | agent memory per project | agent-memory.dev on oldsrv + ZeroClaw runner | spec in [services-ai.md](docs/services-ai.md) §9b; does not wait on HD-336b |
| HD-248 | 2 | the OWUI story matches the box | correct the stale "x2 live" banner in [services-ai.md](docs/services-ai.md); stop there | **decided 2026-09-21: no second instance.** The split stays planned until a second audience exists — building it today duplicates a service that does not run · 📋 [`prompt-417.md`](prompt-417.md) |
| HD-104 (+ HD-160) | 2 | OpenClaw is actually configured | `openclaw onboard` → `openclaw.json`, then the OpenCloud WebDAV round-trip | container Up/healthy; only onboarding + verify remain |
| HD-103 | 2 | Docling converts a real Slovenian scan | trigger the first HF model download + verify end-to-end | Docling is Up on the VPS; **HD-402** closes on this same gate · 📋 [`prompt-394.md`](prompt-394.md) |
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
| HD-09 | 2 | the UPS web UI is Mgmt-only | ride the next router converge import and confirm the Home→Mgmt 80/443 rule lands | IaC-only so far · 📋 [`prompt-414.md`](prompt-414.md) |
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
| HD-238 | 3 | a DR path that does not assume the GPU | write the oldsrv→VPS DR runbook for non-GPU services (backup.md section) · 📋 [`prompt-394.md`](prompt-394.md) |
| HD-49 | 3 | Matrix identity survives a restore | add Matrix identity/media keys to the backup policy · 📋 [`prompt-394.md`](prompt-394.md) |
| HD-191 | 2 | a restore is a rehearsed act, not a hope | run the Kopia restore drill from a snapshot + verify the volume-name pin (you confirm the target) |
| HD-133 | 3 | renewals stop being surprises | build the subscription SSOT → Homepage/calendar/n8n renewal notify |
| HD-32 | 4 | the family can help themselves | write the Slovenian family guides (`docs/manual/*`) |

---

## C. Standing rules that gate all of the above

1. **HD-397 needs a physical presence for its last half** — the off-LAN matrix is measured + green, the LAN/`Mgmt99`
   half cannot be taken from abroad. It gates nobody's code, only the on-site verification rows. Reachability itself is
   settled: [network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away.
2. **Never benchmark or converge spark from a session whose own model is spark** (incidents #3 + #6). Live converges
   run **detached** (`nohup … &` + log + poll), spark via the VPS jump. `--check` is the only safe foreground form.
3. **Do not merge/converge `main`'s spark values over the certified ones** — the 16 GiB KV pool is the live, certified
   config, and `--enforce-eager` (C3) stays off on measurement, not on deferral.
4. **One writer per file family** — narrowed for parallel lanes by [prompt.md](prompt.md) §4 **O3**:
   `docs/services-ai*.md` stays one-lane-at-a-time (lane 407 while it lives), `templates/docker_services/**` is
   **one writer per service directory**, and there is **one converge in flight per host** (oldsrv / VPS / spark /
   router — the router slot is global because its converge is a device-wide `/import`). `roles/router/**` belongs to
   the HD-414 lane. Check `git worktree list` + `git log` on the file before editing it.
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
| HD-411 | 3 | sideload the APK, pair, 2-week verdict | the deployment + the §9b verdict either way · 📋 [`prompt-407.md`](prompt-407.md) |
| HD-353 | 2 | check your own Jellyfin login at seerrng (30 s) | fix whatever it reveals |
| HD-400 · 376 · 359 · 367 | 1–2 | one spark bench window | run the ladder detached, report the numbers |
| HD-410 | 1 | one re-measure: `DIRECT` vs `relay` **after** HD-414's /56 | the number decides whether a DERP is ever self-hosted — standing recommendation: **do not** |
| **HD-415** | 3 | **a WAN-pulled drill at home** — the new resolver design is only as good as "the phone reaches the node direct over the LAN with the WAN pulled" | rework the chain, then prove all three cases in that drill · 📋 [`prompt-414.md`](prompt-414.md) |
| HD-316 · 315 · 343 · 377 · 375 · 319 | 1–2 | the one visual pass (launchpad, host-overview, Network Clients, `homelab-llm`, the memory rules in Grafana **and** reaching n8n, the three KNX GAs) | fix what the eyeball catches; retire the three superseded dashboards |
| HD-397 (tail) | 2 | be on-site: the LAN matrix + the `Mgmt99` vNIC linked | close the row |
| HD-06 · 301 · 288 · 194 · 34 / 191 | 1–4 | physical windows: UPS pull → WoL · a router/switch/AP reset · gaming + Moonlight · one edge login/callback · the yearly restore drill | verify state after each; run the pin + Kopia GUI-vs-CLI assessment during the drill |
| HD-230 · HD-207 | 1 | decide at the drill: which sources get backed up · media rename vs personal-files | the surgical converge + the landing-zone mechanics |
| HD-362 · HD-57 | 2–3 | the music-pillar 1P values + Lidarr clients · bank tokens (and see HD-354: there is **no local music**, so the pillar's premise is now "if we ever have some") | the last mile on each |
| HD-312 | 2 | observation: the bedtime window + the Kids-Group filtered-DNS binding | close on your first sighting |
| HD-366 | 2 | **still deliberately untouched by your instruction** — the JupyterLab LAN edge | nothing, unless you ask |

---

## ⚠ Watch-list — reads as done, is not

Checked 2026-09-21 against the registry + live SSOT. Each of these has already fooled one document.

| Claim you might believe | Reality |
|---|---|
| "The two open worktrees mean work is in flight" | Both are **empty** — 0 commits ahead of `main`, clean, no stash. The HD-395 and HD-399 lanes were opened and never started; both rows are still fully open |
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
| "The §A decisions are done" | **Recorded, not shipped.** Every row in §A1 still has its code un-written — the table changed what is *asked*, not what is *built*. The first wins are HD-347, HD-399, HD-383→HD-384→HD-403, HD-350 |
| "Forgejo is the repo's primary remote" | **The VPS Forgejo holds no copy of this repo** — `origin` is GitHub. The "Forgejo primary + GitHub mirror" line in [deployment-secrets.md](docs/deployment-secrets.md) is a plan, and HD-147's Forgejo registration is where you decide whether it stays one |
| "oldsrv will pull and push like the laptop" | **Pull-only until HD-409**: the deploy token is read-only and the box holds no push credential. Commits made there wait for a repo-scoped write key |
| "Cockpit runs on every node, so break-glass is a fleet-wide problem" | The `cockpit` role runs on **two** hosts — `nas` + `oldsrv`. Pi, spark and the VPS have no cockpit, and spark's management surface is deliberately a separate question |
| "The tailnet resolver chain just needs tidying" | Trimming the "unreachable" home resolvers sells the WAN-out case. The decided fix is reachability: a resolver on **oldsrv's tailnet address**, with the VPS as fallback (HD-415) |
| "The exit-node question is still open" | **Decided 2026-09-21: it stays on the Pi**, row deleted. The re-open trigger is HD-406's full-tunnel profile, which removes the need for an exit node at all |
| "A static public IPv4 means phone→oldsrv is direct" | **Measured false here:** the first away session came back `Relayed (FRA)`, 60–90 ms. Hence HD-414 gating HD-410/406/412 |
| "HD-386's parked tailnet names are an open decision" | Settled in code + [network-vpn.md](docs/network-vpn.md): `dsh`/`pi-dev` answers **502 by design**. The row's only tail is the `failed=0` converge log |

---

## Park / moot

| HD | P | Status |
|----|---|--------|
| HD-385 | 2 | **Research record, not work.** Both measurement premises failed; items (a)(b)(c)(f) CLOSED by measurement; the implementation shipped 2026-09-19 with the pinned-AI lane. Standing **non-actions**: do NOT set `amdgpu.cwsr_enable=0` up front, do NOT introduce `amdgpu-dkms` on oldsrv ([hardware-gpu.md](docs/hardware-gpu.md) CWSR). Where §9c and [services-ai-bench.md](docs/services-ai-bench.md) disagree, the bench doc wins |
| HD-45 | 3 | Homelable + network dashboard — a parallel lane owns implementation; do not re-plan |
| HD-264 | 2 | Renovate sandbox `domen/test` — parked, owner steps (external re-launch mechanism, real manifest, then flip `RENOVATE_REPOSITORIES`) |
| HD-250 | 3 | DSH onboarding — **parked with the service** (`enabled: false`, HD-386) and moot under decision #26 |
| HD-28 | 3 | Office AI stack — not parked but **not startable**: its Ollama half is superseded twice over and its MCP half waits on HD-111 |

---

## Bottom line

- **The owner-side backlog is now two sentences long:** do the browser logins (HD-147), and be present for the
  windows in §A2. Everything that used to sit in front of the AI work has a decision attached to it.
- **Decided ≠ shipped — that is the honest state of this table.** Every §A1 row is recorded and every one still has
  its code un-written. Cheapest first, in order: **HD-347** (one value, alerting stops being blind) → **HD-399**
  (one `not ansible_check_mode` gate, and every oldsrv `--check` starts working) → **HD-383 → HD-384 → HD-403**
  (one vault-and-registry change that finally gives voice and the simple queriers a route) → **HD-350** (one pubkey)
  → **HD-416 / HD-417** (two cheap gates for failure classes no validator can see today).
- **Then the sequenced chain:** HD-414 (scoped IPv6) is the hinge — HD-406, HD-410, HD-412's relay story and the
  HD-415 resolver redesign all wait on what it measures. HD-407 is unblocked and mechanical now, and HD-409 rides it.
- **Independent of every chain, and already specced:** **HD-420** (spark metric cadence) — the measurement is done,
  the design is written in [docs/observability.md](docs/observability.md) §Scrape cadence and
  [prompt-420.md](prompt-420.md), and it touches only `roles/monitoring/**` + the dcgm sidecar, so it can run in
  any spare session without colliding with a lane.
- **Two things are still wrong with the repo, both now with rows:** the standby HA edge cannot proxy (**HD-418**) and
  `media.kogler.si` answers 502 (**HD-419**). Both decided, both one-change AI work.
- **Oldsrv reachability is not a blocker:** off-LAN it is the Home leg through the VPS jump, carried in `group_vars`
  since 2026-09-19 — `bash scripts/ansible-run.sh playbooks/home_servers.yml --limit oldsrv.kogler.si --check …`
  needs no `-e`. The only things presence still buys are the on-site half of HD-397, the `*99` aliases and the
  HD-415 WAN-pulled drill.
