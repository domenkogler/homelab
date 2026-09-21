# Todo Split — Open Questions, AI-Runnable Work, Human Gates (planning view)

> **Role:** hand-curated planning view of [`todo.md`](todo.md) — the whole open backlog seen as **what to do next**,
> front-loaded with the **owner questions that unblock AI work** (§A, each with a recommended default you can just
> accept). **`todo.md` stays the registry SSOT** (CONVENTIONS §4(a): a fully-done row is deleted from the registry;
> this table is a view, not a second record) and **must be re-synced whenever the backlog changes**.
> **Linked from:** [`todo.md`](todo.md) · [`prompt.md`](prompt.md) · [`README.md`](README.md) · [`scripts/README.md`](scripts/README.md)
>
> **Re-synced 2026-09-21** from `todo.md` + [`prompt.md`](prompt.md) at `674ad61`. Changes since the 2026-09-20 build:
> - **§0 Repo state added** — branch/commit, the validator verdict, and the **worktree sweep**: two session worktrees
>   are open and **both hold nothing** (0 commits ahead, clean, no stash) — the HD-395 and HD-399 lanes were opened
>   and never started. All 13 `session/*` branches are merged into `main`; nothing is stranded.
> - **§A Open questions added** — every open owner decision in one numbered place, each with a **recommended default**
>   and the lane it unblocks, so "accept defaults" is a one-line answer. Two owner calls that lived only in
>   [network-vpn.md](docs/network-vpn.md) prose (the `ha_trusted_proxies` 400 and the `media.` 502) are surfaced here
>   as **unregistered** — they need HD rows (next free id = **HD-418**).
> - **Goal column added to every AI row** — what "done" means, in one clause. Descriptions stay in `todo.md` and the
>   `prompt-*.md` briefs; this table is dispatch, not prose.
> - **HD-407's blocker is gone:** the foreign `oldsrv-rsync` key was retired 2026-09-21, so `restore-runner-key.sh`
>   now finds an empty path — the row is down to **one owner seed** (Q3).
> - Rows re-checked against the registry (101 open HDs), the owning-doc ✅ lines and the live SSOT values — not against
>   the previous version of this table.

---

## 0. Repo state (one screen)

| Fact | State (measured 2026-09-21) |
|---|---|
| Primary checkout `/home/domen/source/homelab` | `main` @ `674ad61`, working tree **clean** — a merge station, not an edit site |
| `bash scripts/validate-all.sh` | **GREEN** (every validator passed, incl. ansible `--syntax-check`) |
| `session/*` branches not merged into `main` | **none** — all thirteen report `ahead=0`; nothing to rebase, nothing to salvage |
| Stashes / uncommitted edits anywhere | **none** |
| Registry size | 101 open HD rows in `todo.md`; every one is represented in this table |

### Open worktrees — what each actually holds

| Worktree | Branch | Ahead of `main` | Contents | Verdict |
|---|---|---|---|---|
| `../homelab-wt-20260921-0105` | `session/spark-recycle-kv-ssot-20260921-0105` | 0 (6 behind) | clean, 0 commits, no stash | **the HD-395 lane, never started** — an empty shell |
| `../homelab-wt-20260921-0218-hd399` | `session/hd399-checksafe-20260921-0218` | 0 | clean, 0 commits, no stash | **the HD-399 lane, never started** — an empty shell |
| `../homelab-wt-20260921-0758-table-sync` | `session/todo-table-sync-20260921-0758` | this re-sync | this file | the session that rewrote this table |

⚠ CONVENTIONS §6: a worktree is retired only by its own session, only via `git worktree remove`, never `rm`. Both
empty lanes belong to other (finished) sessions — **left in place deliberately**; say "retire the two empty lanes"
and they go. Practical consequence either way: **HD-399 and HD-395 have no work in progress and can be started fresh.**

### What is live vs authored-only

- **Live:** VPS edge (Phase 1), nas (Phase 2), Pi (Phase 4), oldsrv (Phase 3, full `docker_services` healthy),
  Victoria* observability stack, 3-instance DNS HA, the home `traefik-internal` edge, `lan-litellm` on oldsrv, the
  three pinned-AI Vulkan legs on the RX 7600, spark as the generation tier with the **16 GiB KV pool certified**,
  and — since 2026-09-20 — **oldsrv as a headscale node** (`tag:dev:443`, `ha.ts.kogler.si` from its own edge).
- **Not live / open:** everything in §B. The single most recent reality check: the first real away session to that
  node came back **`Relayed (FRA)`, 60–90 ms**, so the "static public IPv4 ⇒ direct" premise is **false for cellular
  clients here** — which is why HD-414 (scoped IPv6) now gates HD-406, HD-410 and HD-412.
- **Proof order for any live claim:** `todo.md` §3c → [`deployment-tasks.md`](deployment-tasks.md) checkboxes → the
  owning doc's ✅ lines. Doc banners are hints, not proof.

---

## A. Open questions — answer these and the AI lanes unblock

**Reply `defaults` (or `defaults 1-19`, or a list of numbers to override) and each accepted row becomes a green-lit
lane.** Nothing in §B needs a question answered — §A is what turns the *gated* rows into AI work, and Q1–Q3 alone
change what the next three sessions can finish.

### A1. Your hand, not a decision (minutes each, no thinking required)

| # | HD | Your move | Default | AI then |
|---|----|-----------|---------|---------|
| **Q1** | **HD-347** | Capture the **"Homelab Alerts" Signal group UUID** into `signal_alert_recipients` (`group_vars/all/main.yml`, non-secret). The device is linked, the value is empty | **Do it now — highest value per keystroke in the repo** | re-converge n8n + prove delivery; without it every alert lane below (HD-375, HD-377, HD-280, HD-159) is provable but **blind** |
| **Q2** | **HD-350** | Authorize oldsrv's `/root/.ssh/traefik-cert-sync.pub` on the VPS (the cert pull 401s until then) | **Yes, authorize** | verify the wildcard pair + the LAN routes it feeds |
| **Q3** | **HD-407** | Seed the `op` read-scope token + host keys on oldsrv: the one-liner is in [prompt.md](prompt.md) §2 / [prompt-407.md](prompt-407.md) (repo lands first, token on stdin) | **Yes** — and delete the retired `oldsrv-rsync` key halves after one green backup night | bootstrap the runner, prove `--check` green **from oldsrv** per inventory group, then flip the "laptop only" wording in [1password.md](docs/1password.md); laptop stays as rescue until that log exists |
| **Q4** | **HD-361** | Create the `nas_maint_login` 1P item + pick the break-glass password — `cockpit-nas.kogler.si` has **no working login today** | **Yes**: `maint` in `sudo`, **no** NOPASSWD, no SSH keys, excluded from `AllowUsers` | add the PAM identity + a `pamtester` verify path; decide spark's management surface separately |
| **Q5** | **HD-147** (+ HD-141 tail) | Browser logins: matrix / claw / cloud / foto / immich (+ Forgejo register) | **One sitting** | re-render inventory, close the OIDC epic tail |
| **Q6** | **HD-354 / HD-353** | Put music on the Storage Box, create the Navidrome admin user, check your own Jellyfin login at seerrng | **One sitting** | Subsonic/ExtAuth verify at the pin; closes the music pillar's last mile |

### A2. Decisions — each with the default I would run

| # | HD | Question | **Recommended default** | Why this default | Unblocks |
|---|----|----------|-------------------------|------------------|-----------|
| **Q7** | **HD-384** (P1) | Which simple querier may call what, at what budget — and does the `llm` router keep borrowing the engine's own bearer? | Grant **HA + Docling + OWUI** the `spark/qwen3.8-flash-next` row **only** (not a `spark/*` wildcard), one scoped key each with an `rpm` cap and a `max_budget`; embed/STT stay on the `ollama/*` + pinned rows; flip `bootstrap_keys: true` **in the same change**; mint a **separate client credential for the `llm` router** so `spark-llm_api` stops being triple-used | the consumer set is built from **zero** (the LAN list is empty), so there is nothing to trim; a named-row + per-key cap is the cheapest way to keep one 262k-context session from eating 56 % of the pool (incident #6) | HD-403 (voice LLM leg), HD-356's tail, HD-409's spark-edge credential, HD-249's key, HD-383 (Q16) |
| **Q8** | **HD-409** (P1) | Which phone cockpit is primary — `@ygncode/pi-web` or `pi-web-ui`? | **`@ygncode/pi-web`**, installed **natively on glibc** under a dedicated non-human account; browser cockpit stays primary; TUI-in-tmux stays the floor | it reads session JSONL + SSE, so a killed mobile tab loses nothing (the phone is the flakiest client); `pi-web-ui` is the one HD-298 hurt, and all four of those root causes were container-caused — a native host install sidesteps them by construction | the coding plane moving to oldsrv; [pi-harness.md](docs/pi-harness.md) §1 ownership stops saying laptop-only |
| **Q9** | **HD-411** | Run the Paseo (native Android) trial now or later? | **After HD-409 lands**, 2-week trial, daemon tailnet-bound + password + hostname allowlist, **relay off** | a comparison needs a baseline; and its posture-safe mode is exactly the mode its own docs recommend for VPN use | a verdict for [services-ai.md](docs/services-ai.md) §9b either way |
| **Q10** | **HD-412** | Family support: family machines **join the tailnet**, or dial into the VPS RustDesk rendezvous by ID? + the relay bandwidth quota | **Join the tailnet** (direct-IP, no relay at all) for machines that can; hbbs+hbbr still land on the **VPS** for the rest, with the relay **bandwidth-capped** to your plan's quota | measured today: hole-punching **fails** from cellular (relayed via FRA), so a relay-first family path means every support session transits someone else's relay until HD-414 lands | the VPS server half is buildable now regardless; the tailnet-whitelist half rides HD-405 |
| **Q11** | **HD-408** | Exit node: keep the Pi or move it to oldsrv? | **Keep the Pi** | the reason on record (the exit node must be up exactly when you travel) survived the premise change; oldsrv has the better pipe but is now the box you are building your dev plane on — and Android scopes an exit node per-app anyway, so geo-egress ≠ all-traffic-through-home | nothing else — this row blocks only itself |
| **Q12** | **HD-406** | Router WG road-warrior peer — build, or not? | **Decide after HD-414 is measured; build nothing now** | with a static /56 the direct path exists without a second public listener; if v6 does not produce `DIRECT`, the case gets stronger and you decide with a number in hand | (a second path that depends on neither the VPS nor headscale) |
| **Q13** | **HD-415** | Tailnet resolver chain — leave, reorder/trim, or split per source? | **Leave it** | the "unreachable from cellular" resolvers are exactly what keeps `*.kogler.si` resolvable at home **with the WAN down**; the cost is timeouts on a phone that is away. Revisit with per-source split DNS only if away-resolution latency keeps costing you — do **not** delete the home resolvers | a P3 wart stops re-appearing as a "bug" in future sessions |
| **Q14** | **HD-401** | Approve installing a ROCm / `gfx1151` stack on the admin laptop (+ check the BIOS iGPU carve-out / GTT)? | **Yes** | the workstation is the only place the two client-side legs (FIM autocomplete + visual judgment) can run, and losing local FIM latency is the real hidden cost of moving the dev plane to oldsrv — three of the four pre-flight gates are unmeasurable without it | the three measurable gates in [hardware-workstation.md](docs/hardware-workstation.md); then a config worth rendering |
| **Q15** | **HD-248** | Do you still want the **OWUI two-instance split** (`ai.` internal + `chat.` public)? | **No second instance for now** — AI corrects the false "x2 live" banner, verifies SSO on the **one** instance, and the split stays planned until a second audience actually exists | the box runs one OWUI at `ai.kogler.si`; `chat` is element-web. Building the split today duplicates a service that does not exist and burns the Authentik blueprint work for nobody | HD-101 (SSO round-trip), HD-111 (`ppt-mcp` + MCP registration), the `chat.`→`msg.` rename decision |
| **Q16** | **HD-383** | Remediate the parked `dsh` stale secret now, or leave the landmine armed? | **Remediate now**: clear the 1P credential + delete the `dsh` alias in the LAN Admin UI (manual, documented), glue stays `false` | it is unreachable today only because the consumer is parked — clearing it costs one Admin-UI pass and removes a fail-closed abort from the path of HD-384's flip | a clean runway for Q7 |
| **Q17** | **HD-336b** | CrewAI pilot — run the 2-week slice, later, or never? | **Later (park)** — no run now | the AI lane's own open tails (HD-268b `rag-mcp`, HD-384, HD-388, HD-403) are prerequisites for anything an orchestrator would orchestrate; a pilot now would measure the stack, not the tool | nothing (HD-336 agent-memory is already unblocked) |
| **Q18** | *(unregistered → **HD-418**)* | `ha_trusted_proxies` omits oldsrv's Home IP, so **HA answers 400 to anything the standby edge proxies** — the standby `ha` router has never worked. Fix = add it, which **restarts the smart-home controller** | **Yes, in a planned window** (a few seconds of HA restart), and register the row | it is the only known-broken piece of the HA failover story; the tailnet router only sidesteps it by stripping XFF | a standby edge that would actually work in a takeover · [network-vpn.md](docs/network-vpn.md) |
| **Q19** | *(unregistered → **HD-419**)* | `media.kogler.si` answers **502** even locally on oldsrv — jellyfin publishes no host port on the Home leg. One line in `group_vars/all/main.yml` | **Yes** — follow the `actual-budget:5006` / `immich-ml:3003` precedent | the home edge cannot serve what does not publish; today the launchpad's media tile is structurally dead off the VPS | mobile/edge media reach, HD-357's tile |

### A3. Windows and eyes — nothing to decide, just your body or your calendar

| HD | What only you can do | Default |
|----|---------------------|---------|
| **HD-400 / 376 / 359 / 367** | One **spark bench window**: text-only engine mode (HD-400, a *memory* change, not a speed change), the 262k needle test + `spark-lane` 64k profile (HD-376), the S2/S3 NVFP4×SGLang ladder | **Book one window covering all of it** — detached, never with an agent session attached, and never from a spark-backed session |
| **HD-405 tail + HD-410** | The **phone-on-cellular** matrix, one pass: node path with headscale **stopped** (restore it in the same breath), IoT + guest unreachable, HA Companion on the `.ts` URL — and capture `DIRECT` vs `relay` + RTT while you are at it | **One pass, both rows**; results decide HD-410 (recommendation already on the table: **do not** self-host DERP on the VPS — it re-inserts the VPS into the path HD-405 exists to remove) |
| **HD-316 / 315 / 343 / 377 / 375** | **One eyeball pass**: launchpad green, host-overview (disk-work + temperature rows) + probe tables, Network Clients panels, the three rekuperator GAs (HD-319), `homelab-llm` on `stats.`, and the two spark host-memory rules in the Grafana UI **and** reaching n8n | **One pass** — it retires three superseded dashboards and closes the alert lane |
| **HD-397 (tail)** | Be **on-site**: re-run the reach matrix from the LAN and with the `Mgmt99` vNIC linked | Next physical visit — it gates only the on-site verification rows, nobody's code |
| **HD-06 · HD-301 · HD-288 · HD-194 · HD-34 / HD-191** | Physical windows: UPS pull → poweroff → WoL · a router/switch/AP reset window · a gaming + Moonlight round-trip · one edge login/callback · the yearly **restore drill** | Fold into the next maintenance window; the drill is also where HD-207 (media vs personal-files rename) and HD-230 (which sources get backed up) get decided |

---

## B. Table AI — doable now (no owner step in front)

⏳ = the exact next action, not a restatement of the row. Goal = what "done" means.

### 🔥 Active lanes

| HD | P | Goal | ⏳ Next action | Why nothing blocks it |
|----|---|------|----------------|------------------------|
| **HD-399** | 2 | every `docker_services --check` on oldsrv runs at all | gate the Technitium login block with `not ansible_check_mode` (`uri` does not run in check mode, so the registered token dies at `technitium-seed.yml:102`) | pure IaC defect, located 2026-09-19; third instance of a catalogued class in [deployment-ansible.md](docs/deployment-ansible.md) §Dry-run Mode. ⛔ no `default()` / `failed_when: false` — fail-loud. Interim green form: `--check --tags common,network`. **A lane was opened for this and never started (§0)** |
| **HD-395** | 2 | the watchdog stops restarting a healthy spark engine | baseline the idle recycle only after `/health` 200 **and** a settle window (or max of N samples), then re-check the +8 GiB margin against the certified peak | measured defect: the first-post-boot floor has been read **71,911 / 86,243 / 92,343 MiB** on one config → it either restarts a healthy engine or goes silent. Drive it from the laptop, never from a spark-backed session. **A lane was opened for this and never started (§0)** |
| **HD-414** | 1 | the phone reaches oldsrv **directly** instead of via a Frankfurt relay | scoped IPv6 on the RB4011: DHCPv6 PD for the /56 → /64s for **Home VLAN 10 only** → RA on VLAN 10 → v6 filter = drop-all-from-WAN with **one** UDP 41641 accept to oldsrv → prove it by probing **from the VPS** | the static /56 exists, the laptop is at home, and it deliberately gates HD-406/410/412. RouterOS 7.21 syntax must be verified before converging; the `.rsc` is generated — never hand-edit, never `system reset`. [prompt-414.md](prompt-414.md) |
| **HD-416** | 2 | every SSH grant on a managed host is named, or it does not exist | read-only `authorized_keys` audit across the managed hosts (fingerprints + comments), diffed against the named set in [deployment-secrets.md](docs/deployment-secrets.md) §Who is authorized where, failing loud on an unknown | triggered by the `oldsrv-rsync` key that authorized `ansible-admin` (NOPASSWD root on nas) from no vault item; four live grants still have none. ⛔ it must **never** edit an `authorized_keys` — the classic failure of an SSH tool is locking yourself out with your own fix |
| **HD-417** | 3 | the validators can see a broken table | cell-count check for markdown tables in the docs validator (split on unescaped pipes, compare to the header, fail with file + line) + an escape convention + a one-time legacy sweep | a swallowed newline merged two registry rows and an `/etc/x`-style description added nine stray cells to a 3-column row on 2026-09-21 — both passed every gate. Cheap guard for a failure that is invisible today. · [CONVENTIONS.md](CONVENTIONS.md) §6 |
| **HD-387** | 2 | know whether thinking is actually OFF through the gateway | run the written probe protocol against the LAN instance (baseline → toggle → budget pair → `top_k` → the proxy's own dropped-params log) | a recorded live measurement and the pinned source contradict each other, and the failure mode is silent thinking-ON at HTTP 200. Master-key path, no client change; the harness route does not move either way (decision #26) |
| **HD-396** | 2 | the retired `op_api` secret thread ends with a fact | repo-archaeology, one question: does the Forgejo CI runner still exist, and does it still hold the pre-2026-09-19 secret? renew it, or delete the stale Phase 0/5 prerequisite lines in [deployment-tasks.md](deployment-tasks.md) | the leak itself is closed (record: [deployment-ai-stack-secrets.md](docs/deployment-ai-stack-secrets.md) §4a); no IaC references `op_api` any more, so only the Forgejo side can answer it |
| **HD-394** | 2 | no container runs that no converge owns | list every running container without a compose project label, propose removal (owner OK before deleting), record in [services-vps.md](docs/services-vps.md) | `confident_shamir` (hand-run traefik, no nets/ports) + `pgvector` (superseded by Qdrant) are invisible to every converge; the third entry (`authentik-ldap`, unhealthy) is HD-360's |
| **HD-386** | 1 | the oldsrv `docker_services` converge is green with the harnesses parked | converge oldsrv `--tags docker_services,lan-litellm` (**both** tags), **detached**, **no `--diff`**; expect the parked pair + the key glue to SKIP, `failed=0` | the park is authored + validated; only the log is missing (a read-only sighting of the end-state exists, it is not the artifact the row asks for) |
| **HD-393** | 1 | the `amdgpu init_user_pages: -1` burst is explained or accepted | attribute the **one** bounded episode (dmesg 774,316 s → 780,804 s) per-process — journal vs container restarts in that window — then fix or record as noise | re-measured: 1,296 lines, all inside ~1.8 h, **0 hang/reset** anywhere, none new since. ⚠ `dmesg` needs `sudo` on oldsrv; `rocm-smi` lives **inside** `immich-ml`/`ollama`, not on the host |
| **HD-369** | 2 | voice points at the tiers that are actually live | **(d)** Whisper → the live whisper.cpp **Vulkan** leg on oldsrv (not Ollama), Piper → CPU, LLM → spark; then **(e)** the Sunshine priority glue (pause/unpause pinned-AI + immich-ML) | the tier has been live since 2026-09-19, so (d) has something to point at. ⚠ **(c) is SUPERSEDED — do not recreate the ollama catalog, do not bump the `:rocm` pin**; (f) is done |
| **HD-402** | 2 | the OCR engine is chosen by measurement, not by hope | confirm the Docling `RapidOcrOptions` adapter exposes the PP-OCR `latin` rec model → convert the **same Slovenian scan** with EasyOCR and RapidOCR-ONNX → keep only if quality ≥ EasyOCR → record the speed delta | CPU bench on the VPS, no host risk. Language was never the blocker (`latin` includes `sl`); the risks are the script-grouped model on `č ć š ž` and the adapter wiring. Closes on the **HD-103** scan gate. Free lever regardless: `do_ocr=False` for born-digital PDFs |
| **HD-401** | 2 | the workstation provably carries FIM + visual judgment locally | clear the four pre-flight gates in [hardware-workstation.md](docs/hardware-workstation.md): pick + record the ROCm/`gfx1151` stack, prove the VL `mmproj` runs on the iGPU (measure `--image` prefill), measure FIM latency on the real Continue prompt shape, check the iGPU carve-out/GTT | three of four are measurable on this very box — Q14 is the only owner piece. ⚠ every platform figure in that doc is owner-stated/community, **unmeasured here** |
| HD-356 | 1 | the LAN gateway is confirmed live after the converge | re-check the LAN instance (live + serving) once HD-386 converges green; the scoped-key glue tail is **not** a fix — it is OFF by design and rides HD-384 | the split is deployed + healthy. ⚠ Its role changed with decision #26: gateway for the **simple queriers**, not the harnesses |
| HD-382 | 2 | (tail only) | the scoped-key allowlist question is **HD-384** (Q7), the stale `dsh` secret is **HD-383** (Q16) | the model entry is live in both LiteLLM DBs + E2E verified |
| **HD-388** | 2 | client model config is rendered from one repo spec, not hand-copied per machine | render `pi` `models.json` + a Continue config from one spec, credential resolved via `op` at render time | pure repo tooling; default shape is a standalone `scripts/render-client-config.py` reusing the `render_all.py` Jinja env — no owner call needed unless you object. ⚠ the template must **not** merge the two `contextWindow` numbers (engine 262,144 vs the LiteLLM row's 245,760 = window − reserve); they differ on purpose |
| **HD-376** | 2 | agentic max-context is proven, and lanes get a smaller window | promote the `spark-lane` 64k profile; run the 262k needle test; measure parent-vs-lane KV contention | engine + harness config are live; the lane profile is paper-only. ⚠ needs the bench window (A3) — same window as HD-359/367 + HD-400, never an attached agent session |

### 🆕 Remote-dev plane (three file-disjoint lanes — run one per session)

Briefs: [prompt-414.md](prompt-414.md) (transport, successor to the merged [prompt-405.md](prompt-405.md)) ·
[prompt-407.md](prompt-407.md) (runner + cockpit) · [prompt-412.md](prompt-412.md) (remote desktop).
Decisions are already in the `network` / `deployment` / `services` decision logs — start from the briefs, do not
re-open the direction. Two standing decisions were **scoped, not repealed**: the tailnet permits exactly one home host
with **no advertised routes**, and the VLAN-99 seal (HD-398 A) is untouched.

| HD | P | Goal | ⏳ Next action | Gate / note |
|----|---|------|----------------|-------------|
| **HD-405** | ✅ live | remote dev whose data path does not cross the VPS | ~~ship the node~~ done (`roles/tailscale-node`, `tag:dev:443`, `ha.ts.kogler.si`) — ⏳ the **phone-on-cellular matrix** (A3) + the HD-410 capture in the same pass | acceptance is a phone, not a 200 OK. Two pre-existing faults it found are Q18/Q19. ⛔ no `:*` ACL widening, VLAN-99 seal stands |
| **HD-407** | 1 | oldsrv = primary control node, laptop demoted to rescue | owner seeds the `op` token + host keys (Q3) → bootstrap the runner → prove `--check` **from oldsrv** per inventory group → only then flip the "laptop only" wording | prep landed; the foreign key that blocked it was retired 2026-09-21. Runner account = `ansible-admin` (`domen` holds neither secret — it is the break-glass identity the self-converge guardrail relies on). ⚠ **nothing syncs the clones** — `git pull --ff-only` is an explicit act. HD-413 (the guardrail) is **closed**: shipped + validator-enforced |
| **HD-409** | 1 | the harness + a phone-first cockpit run on oldsrv | owner picks the surface + seeds the credential (Q8) → then the harness + deployment under a dedicated non-human account | compatible with #26 and with HD-386 — a **dedicated deployment** is what #26 left room for. ⛔ do not re-enable the parked `dsh`/`pi-dev` registry rows: that re-renders a deliberately-empty 1P item and turns the whole oldsrv converge red |
| **HD-412** | 2 | family machines can be helped remotely | owner picks the onboarding model + quota (Q10) → then §5 onboarding (exposure/auth → secrets → compose → registry → backup) | the reflex objection (VPS RAM) is false — the floor is a Raspberry-Pi-class box; the real cost is relay **bandwidth**. ⛔ never on oldsrv: a rescue tool behind the thing it rescues is not a rescue |
| **HD-406** | 2 | a dev path that depends on neither the VPS nor headscale | owner picks the peer credential + full-tunnel vs scoped (Q12) → then the router role/template render + `/import` | the only such path; a full-tunnel peer also answers Slovenian egress with **no exit node**. Family stays on Headscale |
| **HD-410** | 3 | know whether a session is direct or relayed **before** buying a relay | measure `DIRECT` vs `relay` from a phone on mobile data over a few days, then decide | the derp map uses the **public Tailscale** relays, so a failed punch puts a third party in a dev session — but a DERP built on a hypothesis buys a public listener for nothing. Today's reading: relayed is the reality, so HD-414 first |
| **HD-411** | 3 | a native Android path to the same harness, without a third-party relay | owner sideloads the APK + pairs (Q9) → AI: tailnet-bound daemon + password + host allowlist, **relay off** | the browser cockpit stays **primary** — an app someone else maintains cannot be a dependency, a URL can |
| **HD-408** | 2 | the exit node sits where you want it | owner answers Q11 | blocks nothing else; the Pi leg is not retired without your word |
| **HD-415** | 3 | stop re-calling a designed tradeoff a bug | owner answers Q13 | nothing is broken; the away DNS warning is the price of WAN-out survival |
| hygiene | — | close two small debts the transport lane named | expire the **retired headscale preauth keys 4 (`tag:pi-dev`) + 5 (`tag:dsh`)** — live, reusable, non-expiring for services that no longer exist; report ids only, never values | one `headscale preauthkeys expire` each; the tombstones in [deployment-secrets.md](docs/deployment-secrets.md) do not revoke them — headscale does. Also: delete `prompt-405.md` (a closed banner) in the one commit that fixes the two live briefs that still link it — see [prompt-414.md](prompt-414.md) row 8 |

### AI / Office

| HD | P | Goal | ⏳ Next action | Note |
|----|---|------|----------------|------|
| HD-268 / HD-337 / HD-335 | 1–2 | RAG + memory + office stack live | Qdrant embed/rerank + **re-index** after the bge-m3/1024 cutover, OKF wiki skeletons (**268a**), then **268b = implement `rag-mcp`**, Mem0 + OpenHands | ⚠ the Vulkan embed move does **not** trigger the re-index (same dims, cosine 0.9996). ⚠ `rag-mcp`'s compose is a TODO comment block with **no `services:` section** — its `enabled: false` is not a flag to flip; until 268b lands the reranker leg stays dormant (~327 MiB) |
| HD-360 | 2 | Samba auth rides Authentik over LDAP | declare the provider + `svc_samba` in the Blueprint → mint a fresh bind token → redeploy the outpost → **then** flip `storage_samba_passdb: ldapsam` + converge nas | ⚠ order is safety-critical: smbd fails hard if the flip lands first (that outpost is also HD-394's third census entry, Up **unhealthy** = expired token) |
| **HD-403** | 2 | voice has an LLM to call | mint a `home-assistant` scoped key vault-first, render `LITELLM_BASE_URL` + key into the compose env, point the Assist pipeline at it | HA ships only `TZ` in its env, has no consumer in either LiteLLM and no `llm:` config in its role — rides Q7 · [smart-home-voice.md](docs/smart-home-voice.md) |
| **HD-404** | 3 | the last stale IaC strings stop teaching agents the wrong truth | text-only PR over the enumerated list (Victoria headers, the Pi "primary DNS" comment, the `llm-backend` purpose string that feeds a generated doc, `amd_rocm`'s `OLLAMA_KEEP_ALIVE`, `first-boot-config.sh`'s wording) | the docs stopped repeating these; the comments are now the last place an agent reads a wrong truth · [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-336 | 2 | agent memory per project | agent-memory.dev on oldsrv + ZeroClaw runner | spec in [services-ai.md](docs/services-ai.md) §9b; does not wait on Q17 |
| HD-248 | 2 | the OWUI story matches the box, then (maybe) splits | settle Q15 first; if "no second instance": correct the [services-ai.md](docs/services-ai.md) banner and stop; if "split": parametrize the template and deploy the second | today's premise ("x2 live") is false on the box — building on it would duplicate a service that does not exist |
| HD-104 (+ HD-160) | 2 | OpenClaw is actually configured | `openclaw onboard` → `openclaw.json`, then the OpenCloud WebDAV round-trip | container Up/healthy; only onboarding + verify remain |
| HD-103 | 2 | Docling converts a real Slovenian scan | trigger the first HF model download + verify end-to-end | Docling is Up on the VPS; **HD-402** closes on this same gate |
| HD-111 | 2 | office MCP tools reachable from the UI | `ppt-mcp` first, register MCP servers in OWUI | only Q15 gates it |
| HD-249 | 3 | n8n workflows spend a budgeted key | audit external webhook deps + `WEBHOOK_URL`, then mint a budget-capped LiteLLM key for the AI nodes | n8n live behind the tailnet edge; its key is an HD-384 consumer once the allow-list exists |
| HD-251 | 3 | the admin surfaces move to tailscale-first | roll out the tiers (Headplane, Dozzle, Metabase, Grafana, Traefik-dash) | the policy/doc half landed 2026-08-26 |
| HD-373 | 2 | the LiteLLM admin UI deep-link works | pick (a) nginx SPA fallback / Traefik `PathPrefix(/ui/)` rewrite, or (b) route-scoped forward-auth on `/ui/*` | the `/fallback/login` workaround works, so this is a real fix, not a fire |
| HD-380 | 2 | spark memory growth is watched, with the cache question answered | passive: watch `samples.csv` for a curve growing > 2 GiB/h under traffic that does not return at idle — that, and only that, re-arms C3 — plus the never-measured prefix-cache/preemption check across the 16 GiB raise | certified state is stable; this row is a standing watch + one cheap measurement |

### Network / platform / security

| HD | P | Goal | ⏳ Next action | Note |
|----|---|------|----------------|------|
| HD-357 | 2 | the launchpad tiles are alive | wire Homepage tiles/widgets to the verified endpoints (home edge + VPS edge), then hand the visual check to the owner | endpoints and route tables are final; bug #6 is wiring |
| HD-358 | 2 | Seerr can talk to the *arrs without a human | record the Seerr→\*arr API-key + URL hand-off as a runbook step (and consider automating it in IaC) | home edge is up; bug #7 |
| HD-122 | 2 | Matrix profile auth proven | verify it now — the servers have been live since 2026-08-22 | the row used to wait on a deploy that already happened |
| HD-47 | 3 | Matrix is federated | publish `matrix`/`chat` + `_matrix` well-known/SRV, then prove inbound federation from an external server | servers live; the records are the only missing piece (also a prerequisite inside HD-147) |
| HD-112 | 2 | Zipline is usable, not just up | post-up seeding: local admin → OIDC login (one owner browser step) → flip `bypass-local-login` → create `guestbin` + `dropzone` → round-trip + 6 h sweep verify | deployed; the remainder is seeding |
| HD-159 | 2 | the tunnel-down alert is proven | run the deliberate `wg down` test and confirm `wg-s2s-down` fires (short planned window) | rule + scrape deployed, never proven |
| HD-09 | 2 | the UPS web UI is Mgmt-only | ride the next router converge import and confirm the Home→Mgmt 80/443 rule lands | IaC-only so far |
| HD-287 | 2 | immich-ml runs with minimal caps | encode `cap_drop: ALL` + the ROCm-init `cap_add` set → converge → verify ML inference still works | its gate (the ML leg being live) is met; rides the HD-386 converge |
| HD-318(b) | 1 | the *arr quality profiles actually sync | confirm the recyclarr @daily sync landed (after the 2026-09-15 `bind_owner_uid` fix) | stacks are up; observation only |
| HD-280 | 2 | brute force actually gets banned | observation: confirm a repeated 401/403 produces a ban | jail is live; waits on natural traffic |
| HD-14 | 2 | HA entities reach the metrics store | enable the HA Prometheus exporter and export the entity list | the observability gate is gone (Victoria + Alloy live); feeds the HA dashboard |
| HD-17 + HD-217 | 2 | one failover button on the launchpad | render the **IP-only** button (`homepage_failover_button`; the RFUSB path is obsolete — HD-18 rejected) | `ha-failover-api` is active on oldsrv since 2026-09-08; only the render remains |
| HD-04 (tail b) | 1 | the HA standby is a standby again | restore oldsrv's keepalived conf to the **BACKUP 100** variant (the drill left the 120 failover variant) — before the next standby cold boot | a one-file revert the drill left behind; the rest of HD-04 is your failover test |

### Observability

| HD | P | Goal | ⏳ Next action | Note |
|----|---|------|----------------|------|
| HD-344 | 3 | AI can query metrics/logs through MCP from its own tools | register the MCP endpoints in pi / Open WebUI / OpenClaw — **ports are `mcp_metrics_port` 8083 / `mcp_logs_port` 8084**, not :8080/:8081 | servers live on oldsrv; registration is the whole remaining row. ⚠ use the vars, never a literal port |
| HD-345 | 2 | the last `DatasourceNoData` class goes away | find why the SNMP `ifOperStatus` walk still yields 0 series (rules on, SNMP enabled) | the only one left |
| HD-342 | 2 | the observability data itself is backed up | Kopia client wiring for the Victoria data dirs | the Victoria cutover is live; this is its backup tail |

### Docs / policy (no host risk)

| HD | P | Goal | ⏳ Next action |
|----|---|------|----------------|
| HD-238 | 3 | a DR path that does not assume the GPU | write the oldsrv→VPS DR runbook for non-GPU services (backup.md section) |
| HD-49 | 3 | Matrix identity survives a restore | add Matrix identity/media keys to the backup policy |
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
4. **One writer per file family:** `docs/services-ai*.md` + `IaC/ansible/templates/docker_services/**` are
   one-lane-at-a-time; `roles/router/**` belongs to the HD-414 lane. Check `git worktree list` + `git log` on the file
   before editing it.
5. **The runbook has no owning lane — ownership follows the action** (README §4.8): if a session did something a human
   would repeat by hand, `deployment-manual.md` gains the imperative line **in that same change**.
6. **Never print a secret value** — lengths, prefixes, item ids and hashes only.
7. **A test that cannot fail is not evidence** (CONVENTIONS §6): prefer the gate that carries its own self-test over
   prose that asserts coverage.

---

## D. Table Human — 🚧 owner step first

The *decisions and seeds* are in §A with defaults; this is the full owner list, including the physical and browser
work. Columns: what you do → what the AI then closes.

| HD | P | Owner step | AI then | §A |
|----|---|-----------|---------|----|
| HD-347 | 1 | the Signal group UUID into `signal_alert_recipients` | re-converge n8n + prove delivery | Q1 |
| HD-350 | 1 | authorize oldsrv's `traefik-cert-sync.pub` on the VPS | verify the wildcard pair + LAN routes | Q2 |
| HD-407 | 1 | seed the `op` read-scope token + host keys on oldsrv | prove `--check` from oldsrv; flip the laptop-only wording | Q3 |
| HD-361 | 1 | `nas_maint_login` item + break-glass password | add the `maint` PAM identity + verify path | Q4 |
| HD-147 (+ HD-141) | 1 | browser logins: matrix / claw / cloud / foto / immich + Forgejo | re-render inventory, close the epic tail | Q5 |
| HD-354 / HD-353 | 2 | music onto the Storage Box + Navidrome admin (+ Jellyfin login check) | Subsonic/ExtAuth verify at the pin | Q6 |
| HD-384 | 1 | which simple querier gets what, at what budget; `spark-llm_api` hardening | write the scoped records + flip the glue in one change | Q7 |
| HD-409 | 1 | cockpit surface + provider credential | deploy under a dedicated account, verify from the phone | Q8 |
| HD-411 | 3 | sideload + pair + 2-week verdict | the deployment + the §9b verdict | Q9 |
| HD-412 | 2 | family model + relay quota | build the VPS half, then §5 onboarding | Q10 |
| HD-408 | 2 | exit-node host | implement whichever way it lands | Q11 |
| HD-406 | 2 | WG peer credential + scope | render the peer + egress rules, prove both paths | Q12 |
| HD-415 | 3 | resolver-chain tradeoff | apply the choice, record it in [network-dns.md](docs/network-dns.md) | Q13 |
| HD-401 | 2 | approve the ROCm/gfx1151 stack on the laptop + check the BIOS carve-out | run the other three gates, then write config | Q14 |
| HD-248 | 2 | keep or drop the OWUI two-instance split | correct the banner, or parametrize + deploy | Q15 |
| HD-383 | 1 | clear the stale `dsh_api` credential + delete the `dsh` alias | confirm the glue can be re-armed clean | Q16 |
| HD-336b | 2 | CrewAI pilot: run / later / never | run the slice, or leave the spec parked | Q17 |
| *(unregistered)* | — | `ha_trusted_proxies` += oldsrv Home IP (restarts HA) | IaC + converge + prove the standby edge proxies | Q18 |
| *(unregistered)* | — | accept the jellyfin host-port publish | one var + converge, then the 502 is gone | Q19 |
| HD-397 (tail) | 2 | be on-site: the LAN matrix + `Mgmt99` linked | close the row (jump is a no-op for a LAN runner; `*99` answers) | A3 |
| HD-405 tail / HD-410 | 1–3 | the phone-on-cellular matrix + `DIRECT`-vs-`relay` capture | decide HD-410 on the number; close the acceptance | A3 |
| HD-316 / 315 / 343 / 377 / 375 / 319 | 1–2 | the one visual pass (launchpad, host-overview, Network Clients, `homelab-llm`, the memory rules in Grafana + n8n, the three KNX GAs) | fix what the eyeball catches; retire the three superseded dashboards | A3 |
| HD-400 / 376 / 359 / 367 | 1–2 | one spark bench window | run the ladder detached and report | A3 |
| HD-06 | 1 | UPS pull → poweroff → WoL end-to-end | verify state after | A3 |
| HD-301 | 1 | a router/switch/AP reset window | verify firewall + service state after each reset | A3 |
| HD-288 | 3 | a manual gaming window + Moonlight round-trip | pre-verify Sunshine Up/healthy | A3 |
| HD-194 | 3 | one login + one OIDC callback at the edge | close audit S17(a) | A3 |
| HD-101 | 2 | OWUI SSO → Authentik round-trip | verify LiteLLM completion + RAG after | rides Q15 |
| HD-34 / HD-191 | 3–4 | the yearly restore drill | run the pin verify + assess Kopia GUI vs CLI during it | A3 |
| HD-230 | 1 | which data sources get backed up (Kopia wiring) | the surgical converge + wave-2 verifies | A3 (decide at the drill) |
| HD-207 | 1 | media rename vs personal-files call | the landing-zone redistribution mechanics | A3 (decide at the drill) |
| HD-362 | 2 | real values for the music-pillar 1P placeholders + wire Lidarr clients | the music pillar's last mile | with Q6 |
| HD-57 | 3 | bank tokens + Actual Budget / Enable Banking app | WG-scope :5006 + deploy + verify | — |
| HD-312 | 2 | observation: the bedtime window + Kids-Group filtered-DNS binding | close on your first sighting | — |
| HD-366 | 2 | **deliberately untouched since 2026-09-15 by your instruction** — the JupyterLab LAN edge | nothing, unless you ask | — |

---

## ⚠ Watch-list — reads as done, is not

Checked 2026-09-21 against the registry + live SSOT. Each of these has already fooled one document.

| Claim you might believe | Reality |
|---|---|
| "The two open worktrees mean work is in flight" | Both are **empty** — 0 commits ahead of `main`, clean, no stash. The HD-395 and HD-399 lanes were opened and never started; both rows are still fully open |
| "HD-407 is blocked on a foreign key" | **Was.** The `oldsrv-rsync` key was retired 2026-09-21 (neutralized on nas, proven inert); `restore-runner-key.sh` now finds an empty path. The only thing in front of the row is the seed (Q3) + deleting both halves after one green backup night |
| "Signal alerting is closed" | Device linked ✅, workflow live ✅ — but `signal_alert_recipients` is still **empty** in SSOT, so nothing reaches the group (Q1) |
| "Open WebUI ×2 is live" (`services-ai.md` banner) | The VPS runs **one** `open-webui` at `ai.kogler.si`; `chat` is **element-web**. HD-248 starts by correcting that banner (Q15) |
| "The pinned-AI tier runs on Ollama" | Not since 2026-09-19: STT = `whisper.cpp` Vulkan, rerank **and** embed = `llama.cpp` Vulkan on the RX 7600. `ollama/bge-m3` survives only as the embed **fallback rung** — and it is a *rung*, not a LiteLLM row (`/model/info` on both gateways returns one row each: `spark/qwen3.8-flash-next`). Plan of record: [services-ai.md](docs/services-ai.md) §3a + the §4a catalog runbook |
| "The reranker has a consumer" | It ships **dormant** (~327 MiB idle): `rag-mcp` is the HD-268b compose STUB with no `services:` block. It was verified with a LiteLLM probe + a synthetic consumer, **not** live RAG traffic |
| "Making spark text-only buys throughput" | Decision #28 says the opposite: no image tokens ⇒ the tower never executes ⇒ decode is expected **flat**. It buys memory on the boot-bound side (≈32.2k KV tokens per GiB). HD-400 |
| "Vision can be split: laptop ViT → spark" | **Rejected as unbuildable**, not merely expensive — vLLM's only pre-computed-vision seam is multimodal *embeddings*, which must live in the target model's own visual-token space. Vision lives on the workstation as a **text cascade** · [services-ai.md](docs/services-ai.md) §9 #28 + [hardware-workstation.md](docs/hardware-workstation.md) |
| "HD-383's stale-secret abort is a live blocker" | The glue is `bootstrap_keys: false` and the scoped-key list is empty — the abort is **unreachable**, and the stale 1P value is still standing in the vault. It returns with Q7 unless you close it now (Q16) |
| "Navidrome never deployed" | Deployed: container Up, the Box music dir mounted ro, scanner ran. The **library is empty** and no admin user exists (Q6) |
| "Matrix waits on unprovisioned hosts" | Tuwunel + Element have been live since 2026-08-22; HD-47/122 are verifies now (DNS records + profile auth) |
| "Zipline's first deploy is human-gated and pending" | `zipline` + `zipline-db` are Up/healthy — only post-up seeding is left (HD-112) |
| "The watchdog's idle recycle is a safe background detail" | It restarted the engine twice 35 min apart on a healthy box; its baseline is boot-timing-dependent (HD-395) |
| "oldsrv SSH / the Mgmt plane is broken" | Closed 2026-09-19: HD-392 and HD-398 are deleted rows. The VPS jump rides in `group_vars` (no `-e` needed), `ssh oldsrv` = the **Home** leg, VLAN 99 stays sealed by owner decision **A** |
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

- **Answer §A and half the backlog moves.** The three highest-leverage keystrokes are **Q1** (one string — until then
  alerting is blind), **Q2** (one pubkey — it unblocks the home-edge cert chain) and **Q3** (one command — it makes
  oldsrv the control node and demotes the laptop). The highest-leverage *decision* is **Q7/HD-384**, because HA,
  Docling, OWUI, the cockpit's spark credential and n8n's key are all waiting on that one allow-list.
- **Best pure-AI picks right now, no answer needed:** `HD-399` (one `not ansible_check_mode` gate — and its lane is
  already open and empty), `HD-395` (a measured defect that restarts a healthy engine — same), `HD-414` (the
  dual-stack router work that turns a Frankfurt relay hop into a direct session), `HD-416` + `HD-417` (two cheap gates
  for failure classes no validator can see today), `HD-387` (a 20-minute probe that settles a live contradiction),
  `HD-396`, `HD-394`, `HD-402`, `HD-47` + `HD-122`, `HD-357`/`HD-358`, and `HD-386` (one detached converge whose only
  missing artifact is the log).
- **Two things are wrong with the repo, and both need one word from you:** the standby HA edge cannot proxy
  (`ha_trusted_proxies`, Q18) and `media.kogler.si` 502s (one publish, Q19). They are recorded in
  [network-vpn.md](docs/network-vpn.md) but have no HD rows — say "register them" and they become HD-418/HD-419.
- **Oldsrv reachability is not a blocker:** off-LAN it is the Home leg through the VPS jump, carried in `group_vars`
  since 2026-09-19 — `bash scripts/ansible-run.sh playbooks/home_servers.yml --limit oldsrv.kogler.si --check …`
  needs no `-e`. The only thing presence still buys is the on-site half of HD-397 and the `*99` aliases.
