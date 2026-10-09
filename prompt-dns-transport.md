# `prompt-dns-transport.md` — Lane brief · the answer plane, DNS policy, and the v6 tails

> **Role:** dispatch note for **one** lane session on the DNS / transport plane. **The rows are the authority** for what is
> missing and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-436 · HD-435 · HD-480 · HD-481 · HD-482 · HD-483 · HD-477 · HD-488 · HD-487 · HD-461 · HD-460 ·
> HD-448 · HD-1095 · HD-1097** (row ids as of `9e661845` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O9) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge hosts + slots (O3):** **oldsrv** (Technitium seed + the network-manager leg), **VPS** (headscale + traefik + the
Cloudflare API), the **Pi** tertiary, and the **router** — whose slot is **global**, so holding it blocks every other router
change in the fleet. ⛔ **Do not share a wave with another oldsrv or VPS lane**, and never bundle a router converge with any
other host's. The HD-480/481/482/483/488 resolver work is **one writer** on `roles/docker_services/tasks/technitium-seed.yml`
plus one `group_vars` block, converging `dns-pi` **once**.

**Read first:** [docs/network-dns.md](docs/network-dns.md) §`zone_kogler_si` + §Per-Subnet DNS Policy + §Host-side resolver
→ [docs/network-vpn.md](docs/network-vpn.md) §Tailnet boundary / §Reaching LAN nodes when away →
[docs/network-ops.md](docs/network-ops.md) §Central log shipping + §IPv6 → [docs/services-vps.md](docs/services-vps.md).

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-436** | Switch the two consumers that still hand-author their lists — `group_vars/vps.yml`'s `tailnet_subdomains` / `tailnet_ts_only_subdomains` and `roles/cloudflare_dns/vars/main.yml`'s `cloudflare_dns_records` — onto the derived `zone_kogler_si` list | **Unattended window = the dry-diff only** (owner ruling 2026-10-08, [docs/network-dns.md](docs/network-dns.md) §`zone_kogler_si`): write the diff into the report as the artifact and leave both converges for an owner-present window — this re-renders live edge routing |
| 2 | **HD-436** | Step 2: the `extra_records_path` swap, with HD-435's publish riding the **same** headscale converge | ⛔ `dns.extra_records` and `dns.extra_records_path` are mutually exclusive on the pinned headscale (`versions.yml:47`) and a fatal config still reports `Running` → use the guarded converge's **sampled** liveness probe, never a one-shot inspect. Re-verify the exclusion on the pin: the row's wording predates the bump |
| 3 | **HD-435** | Make `ha.ts.kogler.si` answer with the **live** home box via the list's `tailnet: dual`, then run the reciprocal fall-over drill and hand the per-device Companion App repoint to the owner | Deliberately **not** a `tailnet_subdomains` bolt-on — that answers the PLAIN name for a phone standing at home. One direction was already hit by accident: it is a proxy, not the drill; measure the delay before the second answer |
| 4 | **HD-480** | Build the client groups + per-group upstreams as declarative API steps in `technitium-seed.yml` behind one `group_vars` list, and set `enableBlocking: false` on every tier that carries no list | A block list on the Home/Guest tier is **superseded** — do not build one. `enableBlocking: true` with `blockListUrls = null` is the silent-failure shape. Never via the web UI: a hand-set list is live state no role owns |
| 5 | **HD-481** | The Kids half: the VLAN-40 group with Cloudflare Families **as the upstream**, and the per-MAC `:53` dst-nat for the two Home-VLAN tablets landing on that group | The NAT is live and the policy it lands on is not. Acceptance is an **unsupervised device on each path** getting `NXDOMAIN` for a filtered name while `kogler.si` still resolves — not a `dig` |
| 6 | **HD-482** | `logQueries` on the **Pi tertiary only**, with the 14-day retention rendered into the config, plus the IoT→Quad9 upstream on HD-480's mechanism | Until this closes no doc may cite per-device visibility as achieved. Retention is a rendered value, not Technitium's default |
| 7 | **HD-483** | Move the resolver tuning (`resolverTimeout`/`resolverRetries`, `maxConcurrentResolutionsPerCore`, `cacheMaximumEntries`, `dnssecValidation`, `qnameMinimization`, `serveStale`, `logQueries`) into one SSOT dict + one declarative step with an asserted read-back | This is drift-proofing, not speed. Coordinate `logQueries` with HD-482 — two rows writing one key to different values is exactly this row's drift class |
| 8 | **HD-477** | Re-render the VLAN-10 DHCP resolver offer to `[ha_vip, dns_primary_ip, dns_secondary_ip]` and close its three gates (fail-over on resolver *unhealth*, the oldsrv secondary answering `:53` **on the VIP**, `→ VIP:53` reachability) | RouterOS silently drops a **4th** address — still exactly 3. Run this **after** HD-480/481 exist: one changes what DHCP offers, the others what the resolver answers, and both at once makes a failure unattributable. The IoT `:53` dst-nat keeps targeting `dns_tertiary_ip` |
| 9 | **HD-487** | oldsrv: delete the dead networkd renders + `netd_phys_name`, render the NetworkManager profile from SSOT, and fix the role's guard to ask the **host** rather than a role var | Lockout class — it writes the leg the converge rides: off-box path, console-reachable plan, owner-present window, and **run it alone** in that window. Do not "align" `nm_oldsrv_profile` with `netd_phys_name`. `scripts/probe-net-manager.sh` is the read-only verdict; `is-active` alone lies |
| 10 | **HD-488** | The spark host-resolver pair (`host_resolver_dns` = `dns_secondary_ip`,`dns_tertiary_ip`) on the next **spark-slot** converge; for `nas`, find the uplink's owner by measurement **first** | Do not apply the Pi template to `nas`: its resolver list carries the VPS between two home rungs and no manager owns the uplink (HD-487's `nas` question). A spark converge here contends with the spark slot — never inside a bench window |
| 11 | **HD-461** | Delete the router's non-default `/system logging` rule (`ssh` → `memory`), re-converge, then re-print the rule count and the `memory` buffer depth | ⛔ Never also delete the four managed forwarding rows — that stops `centralsyslog` and blinds VictoriaLogs. One router converge at a time (global slot). **PARKED on reachability:** the VLAN-99 address timed out from the laptop and the `ssh -J oldsrv.kogler.si router` jump has not been re-measured — treat an on-site / LAN-attached runner as the reliable form |
| 12 | **HD-448** | Nothing until the owner re-authorises; when they do, re-take the inbound v6 read from a **proven** v6 source and read the routers' counters, never route presence | ⏸ Deferred by owner 2026-10-08 **including** the `meta nfproto ipv4` scope half — do not re-scope the accepts. A `curl -6` "Could not connect" from a host with no v6 route is the same string as a real failure: prove the source with `api6.ipify.org` in the same reading |
| 13 | **HD-460** | Nothing — the VPS v6 half stays a **parked owner edge-networking decision**, not an open task | The edge netns has no global IPv6 at all. If pin/publish is ever touched it is **one** change on the netns owner (`traefik-tailnet`, not the `network_mode: service:` dependent), and `Relayed` afterwards means the pin did not take |
| 14 | **HD-1095** | Close the device acceptance: the Home-VLAN (10) regression and the away path **without** Tailscale, on a real device, for `media` / `seerr` / `seerrng` | If a name fails, read the edge's `/api/http/routers` — the YAML is not the truth. The mechanism already ships; this row is evidence, not new routing |
| 15 | **HD-1097** | Prove the Wi-Fi side on the laptop: `ipconfig /renew` → the DNS suffix appears, `nas.kogler.si` → the `nas` Home address, and `\\nas\media` mounts **on Wi-Fi**; one family machine on each link | ⚠ Any added name turns `check_zone_kogler_si_parity.py` RED and `capture_zone_kogler_si_golden.py` refuses to re-capture a derived zone: the fixture moves **by hand, in the same commit**, with the reason in the message |

## ⛔ Traps that cost a round (re-grounded at this `HEAD`)

* **The router's mechanical blocker is gone.** `librouteros` is installed on the runner, added to `bootstrap-runner.sh`, and
  the interpreter is pinned for the `network` group — the run class that used to die on a `PYTHON` import error while both
  devices were healthy now answers. Reads + the four probes that lie: [docs/deployment-ansible.md](docs/deployment-ansible.md)
  §Network devices (router / switch). A router failure from now on is a device or reachability fact, never a missing module.
* **RouterOS 7 has no `domain=`** — `set … domain=` aborts the import. DHCP option 15 rides an `/ip dhcp-server option` row
  referenced by each server's `dhcp-option`, and the hex value must be written **inline** (`:local` + `value=$dom` reports
  success and writes nothing). Read back with `print detail` / `raw-value` or the `:foreach … get` form: a filtered print
  reports *unset* when the value **is** set.
* **The pin, not the prose:** the pinned headscale is what `IaC/ansible/group_vars/all/versions.yml:47` says (bumped since
  the rows were written — they still quote `0.29.3`). Re-read the pin before repeating a version or an exclusivity claim.
  Same rule for Technitium (`versions.yml:129`) and for every image tag here.
* Split-horizon truth: a `zone_kogler_si` validator must be able to say **"retired but deliberately published"** —
  `dsh.ts` and `pi-dev.ts` resolve by documented intent and the edge answers 502 ([docs/network-vpn.md](docs/network-vpn.md)
  §Parked names). Never infer retirement from `enabled:`. Likewise the orphan `localhost` headscale node is known residue, not drift.
* The seat constraint that came with the DNS-tier rulings: `pi-oldsrv.ts.kogler.si` is a headscale **MagicDNS `extra_record`**
  (`tailnet_ts_only_subdomains`), **not** a Technitium record — the seat must still load with Technitium **stopped**, and
  anything that changes the MagicDNS answer set belongs to HD-435/436, not to the resolver rows.
* `tailscale-node` wiring landmines on HD-435's path: the role was wired only into `home_servers.yml`, and the pinned
  `.deb` needs `dpkg --print-architecture`, not the kernel fact.
* Headscale answers and A records are different objects: `ha_vip` appears only in the `ha`/`dns-pi` **A records**, never as a
  client resolver address — that is HD-477's whole defect, so do not "fix" it by publishing the VIP as a record.

## Owns / never touches

**Owns:** `IaC/ansible/group_vars/all/main.yml`'s `zone_kogler_si` block and the `group_vars` resolver-policy dict,
`group_vars/vps.yml`'s two subdomain lists, `roles/cloudflare_dns/**`, `roles/router/**`,
`roles/docker_services/tasks/technitium-seed.yml` + `templates/docker_services/technitium/**`, `roles/network/**` for the
manager legs, `scripts/zone_kogler_si_render.py` / `check_dns_seed_drift.py` / `check_zone_kogler_si_parity.py` /
`capture_zone_kogler_si_golden.py` + the golden fixture, `docs/network*.md`, `docs/services-dns.md`, and your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; traefik `dynamic/routes.yml.j2` hunks **beyond** what the
derived-list switch requires (the VPS edge/identity lane owns those service directories); `docs/services-vps.md` prose other
than the claims your converge falsifies; `roles/monitoring/**`; IaC for smart-home; the frozen archives and generated
`*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: the parity gate green with **all** consumers derived and no doubled plane left (or the dry-diff attached
to the unattended report) · headscale answering through `extra_records_path` with the sampled probe log · `ha.ts.kogler.si`
answering from whichever box is live, drill recorded honestly and the accidental direction labelled a proxy · a real client
getting `NXDOMAIN` only where a list exists, on **all three** instances, and the pi-web seat loading with Technitium stopped ·
`logQueries` proven on the Pi tertiary with the retention rendered · the VLAN-10 offer showing the VIP with all three gates
evidenced · oldsrv's dead netd renders gone with the guard asking the host · the router's stray logging rule gone with the
four forwarding rows intact and the rule count re-printed · the device legs on `HD-1095` / `HD-1097` named by device ·
rows deleted or trimmed to their tails, no history in the row · `bash scripts/validate-all.sh` green **in this worktree** → **stop**.
