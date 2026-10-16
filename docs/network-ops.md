---
title: Network Operations — Router Config Storage
role: detail
domain: network
status: active
tags: [network, routeros, ops]
---
# Network Operations — Router Config Storage

> **Role:** Detail — where RouterOS configuration lives, versioning, change workflow.
> **Links to:** `network.md`, `network-vlans.md`
> **Linked from:** `network.md`, `index.md`

---

## Router Config Lifecycle

> **Apply model:** RouterOS config is **authored in Jinja templates (IaC, single SSOT)** and **deployed by
> importing a rendered `.rsc`** — NOT by driving `api_modify` command-by-command for day-to-day changes.
> The API path is used only for **idempotent, order-independent state** (DHCP reservations, firewall lists
> the role owns) and for **verification** (`api_facts`/`api`), never as the primary apply for multi-step changes.
>
> **⚠️ Role ↔ `.rsc` parity:** the `router` Ansible role still contains a handful of `api_modify`
> tasks that mirror converge state (the trunk `interface bridge vlan` task and the port-model
> `interface bridge port` task). These are the **only** places where the role carries day-to-day apply
> logic, and they are a **drift risk**: a role task that silently differs from the template gets
> re-applied on the next role run, or reverted by the next converge — either way the live device state
> depends on which ran last. **Rule: any `api_modify` task that mirrors converge state must stay
> byte-identical to `rb4011_converge.rsc.j2` — edit BOTH or NEITHER.** When in doubt, drop the role task
> and rely on the import. The header of `roles/router/tasks/main.yml` + the two L2 tasks carry this
> warning inline.
>
> **⚠️ Forward-chain ownership:** the role's `Ensure inter-VLAN forward firewall rules` task must
> stay **gated off** (`when: false`). It is an ungated full-reconcile over `chain: forward`, and the
> live per-MAC rows (the `iot-wan-allow` accepts and the `kids-*` tablet bedtime/DoT drops) exist **only**
> in the converge template — a live role run would DELETE them. Related invariant: the apply-of-record
> template (`rb4011_converge.rsc.j2`) must carry the same narrowed scopes as the role SSOT — e.g. the
> Home→IoT new-connection rule is `trusted-ha`, never `trusted-admin`, or a converge silently
> re-broadens it to include `nas`.
>
> **⚠️ srcnat/dstnat ownership:** the role's `Configure NAT masquerade for outbound traffic` task
> reconciles the `srcnat`/`dstnat` table with `handle_absent_entries: remove`, so the table converges
> to exactly the rows both writers list — a NAT row the device carries must be listed on **both**
> sides (the role's `data:` and the converge template) or whichever writer runs last deletes it.

### The three tiers (roles + when each is used)

1. **`*_initial.rsc` — the one-time MANUAL bootstrap** (`rb4011_initial.rsc.j2`, `crs328_initial.rsc.j2`, `ap_initial.rsc.j2`). Factory-reset / first-boot: creates users (incl. the `ansible` SSH identity), uploads SSH keys, binds mgmt services, sets the INPUT firewall floor. **Manual by design** — it hands the device over to automation. After it runs once, you never need it again.
2. **`*_converge.rsc` — the SSOT "full" steady-state** (`rb4011_converge.rsc.j2` → `rendered/rb4011_converge.rsc`). The complete final device state. **Independent of the initial script** (self-sufficient on its own after a reset) and **idempotent** (every `/add` guarded — safe to re-import live at any time). **From the moment initial hands over, converge is the single source of truth / the apply for everything.** A change = edit the converge template → render → import.
3. **`*_delta.rsc` — TRANSIENT only** (`*_delta.rsc.j2` → `rendered/*_delta.rsc`). A **quick patch / debug / test**, or an operator-scoped live fix with a bounded blast radius. **Always a subset of the converge (never divergent truth), and its final state must be folded back into the converge** so the converge stays the SSOT. Deltas may be deleted once folded.

> **Name note:** `converge` is the "full" script — the tier name stays `converge`
> ([network-rejected.md](network-rejected.md) *Converge rsc tier renamed to full*).

### Lifecycle in practice

1. **Factory reset / true baseline** → import the **rendered** `rb4011_initial.rsc` via WinBox (`run-after-reset=` or `/import`). The committed file is the TEMPLATE `rb4011_initial.rsc.j2`; render with `playbooks/render-routeros.yml` (secrets-injected output into the gitignored `rendered/`). **Never import the raw `.j2`.**
2. **Initial hands over → Ansible + converge take over.** All subsequent config = **edit the converge template → render → /import** (the universal apply).
3. **Deltas** are allowed for quick patch/debug/fix, but **final state lands in converge** (fold the delta in, then it's obsolete).
4. **Optional:** export a manual snapshot as `IaC/router/rb4011_live.rsc` for documentation (not yet created).

Source of truth: the **Jinja templates** (`rb4011_{initial,converge}.rsc.j2`; deltas are transient) + the `router` Ansible role. The live export is documentation-only.

### Apply workflow (imports)

- **Render from SSOT:** `bash scripts/ansible/ansible-run.sh playbooks/render-converge.yml` renders `rb4011_converge.rsc` (+ `crs328_converge.rsc`); any `*_delta.rsc.j2` renders to `IaC/router/rendered/` the same way. Rendered files are **gitignored** (they contain live secrets from 1Password).
- **Apply via SSH (ansible identity, pinned host key)** — the sanctioned non-WinBox path. The device host is its **.99 mgmt IP** (the router's `mgmt` row in [`network-addresses-generated.md`](network-addresses-generated.md)). ⚠ **That is an ON-SITE path only** (the Mgmt plane stays sealed from the VPS site-to-site tunnel — [network-rejected.md](network-rejected.md) *Mgmt VLAN 99 reachable over the VPS site-to-site tunnel* — and the `available-from` scoping refuses a tunnel-sourced SSH anyway) and only when the laptop's Mgmt99 vNIC actually has link (`wsl-nat-resolv.ps1 -EnableMgmt99`). **A timeout there is a missing station path, not a dead router**: check `ip -br addr` in WSL for the VLAN-99 route first. **When it is gone, jump through a trusted-admin
host:** confirm the device is alive from inside (`ssh oldsrv` then ping the router's Mgmt address — the `mgmt`
row in [network-addresses-generated.md](network-addresses-generated.md) — it answers in under a millisecond) and
work through it with `ssh -J oldsrv router '<command>'` — auth stays end-to-end on the local key, and old-srv's mgmt leg
satisfies RouterOS's `available-from` ssh binding. (Empty `ssh router` output is this failure's signature.)
Away from home, router/switch work is **deferred, not improvised** — see [network-vpn.md](network-vpn.md) §Reaching LAN nodes when away. **Automated:** `bash scripts/ansible/routeros-apply-delta.sh <router-ip> <delta-file>` performs key pull + parse-verify + host-key pin + SCP + `/import` in one step (see [scripts/README.md](../scripts/README.md)). Manual equivalent (the loop it replaces):
  ```bash
  # pin the router's CURRENT host key (rotated at reset; TOFU):
  ssh-keyscan -T 5 -t ed25519,rsa <router-ip> > /tmp/router_hostkeys.txt
  ssh-keygen -lf /tmp/router_hostkeys.txt   # verify the fingerprint
  # upload + import:
  scp -i <ansible-key> -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/tmp/router_hostkeys.txt \
      IaC/router/rendered/rb4011_pi_delta.rsc ansible@<router-ip>:/rb4011_pi_delta.rsc
  ssh  … ansible@<router-ip> '/import rb4011_pi_delta.rsc'
  ```
  - The `ansible` SSH identity (bootstrap-created, full group) is used; `admin` is password-only (never used for automation).
  - **Host-key pinning is mandatory** (the router rotates keys at every reset) — never `StrictHostKeyChecking=no` on a live edge.
  - **Key extraction:** use `op read` (canonical, clean PEM), NOT `op item get --reveal` piped through shell — the latter emits an inconsistent leading `"`/`\n` wrapper that corrupts the key file and surfaces as OpenSSH's cryptic `error in libcrypto`. `routeros-apply-delta.sh` uses `op read` and verifies the key loads (`ssh-keygen`) before touching the device.
  - **Ansible `copy`-module SCP is NOT RouterOS-safe:** `ansible.builtin.copy` fails with "Destination / not writable" even though raw `scp -i <key> file ansible@<router>:/file` succeeds — the copy module's stat-based writability check is incompatible with RouterOS's pseudo-filesystem (root `/` reports not-writable to stat). **Use `scripts/ansible/routeros-apply-delta.sh` (raw scp) for ANY device file upload/import.**
  - **Delta dedup:** importing the same delta twice leaves duplicate rules. They are behaviorally harmless but reconcile only on a full converge — a `--tags network` role run does NOT own the static `ip firewall filter` table, so it will not dedupe them. Remove duplicates via the API by exact `.id` when cleanliness matters.
  - **Reading back a delta over non-interactive SSH — three probes that lie:**
    `/ip dhcp-server network print where address=<vlan subnet>` and `print as-value` print **nothing** (the
    empty output is the probe failing, not the row missing); a bare `[find …]` resolves against the
    **current menu**, so in `get [find …]` at the root menu it returns nothing and `set [find …]` changes
    nothing without an error; and a `set` of a list attribute that **does** write gets its values
    **re-sorted numerically** (typed `dns_secondary_ip,dns_tertiary_ip,dns_primary_ip` → stored in
    ascending order `dns_tertiary_ip,dns_secondary_ip,dns_primary_ip`), while a `set` whose value already matches is a no-op and leaves
    the historical order standing. The form that reads the truth: `:foreach n in=[/ip dhcp-server network
    find] do={ :put ( [/ip dhcp-server network get $n address] . " -> " . [/ip dhcp-server network get $n
    dns-server]) }` — and it is the only acceptable evidence for "what order do these clients get their
    resolvers in", which is a reachability question, not a cosmetic one (network-dns.md §DNS Flow).
- **Verify live state** afterward via the read-only API (`api_facts`, `mikrotik-read.py`) — never assume the import applied.

### IPv6 on the RB4011 — measured facts, the outside-in probe, the rollback

> **The VPS-side v6 publish is authorized work** (owner ruling), and the family-agnostic accept-parity
> verdict is **given: KEEP THE PARITY** (owner, 2026-10-12). The `:22`, `:443`, `:51820` and RustDesk accepts
> stay family-agnostic in the `inet` table and are **not** scoped `meta nfproto ipv4` — so no session narrows
> the rule set "as a safety improvement", and the family split is decided by what *binds*, not by a filter
> edit. The duty moved from the rule to the **proof**: a real IPv6 client address must be shown reaching a
> ban/attribution log (an address hidden by NAT66 reopens the verdict).
> **Read taken 2026-10-13 on the VPS (read-only):** the host holds a global address
> (`2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5`, `default via fe80::1 dev eth0`), `sshd` listens on `[::]:22`, and
> the journal that fail2ban's `sshd` jail matches (`_SYSTEMD_UNIT=ssh.service`) carries **196** lines from a
> real client address in the advertised home /64 — `Connection from 2a00:ee2:2700:8f00:… on
> 2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5 port 22`, 62 of them `Accepted publickey`, spanning the journal window
> 2026-08-22 → 2026-10-05. So **where a listener binds `[::]`, an inbound v6 address reaches the log
> unpinned** — the `:22` half of the duty is discharged. The `:443` half cannot be discharged yet: the
> published edge is v4-only (`0.0.0.0:80`/`0.0.0.0:443` plus the tunnel-bound `:4443`; no `[::]:443`) and Traefik's
> access log holds **no** v6 client address anywhere in its window (2026-09-03 → 2026-10-13), so the HTTP
> proof is owed with the dual-stack publish — see
> [services-vps.md](services-vps.md) §IPv6 dual-stack on the VPS. RustDesk is the one edge that already
> binds dual-stack (`*:21115`–`*:21119`) and its log does carry v6 peer addresses; `udp 51820` likewise
> listens on `[::]`. No v6 address has ever been *banned* (`fail2ban.log` has none, CrowdSec's live
> decisions are all `Ip:<v4>`) — v6 traffic exists, v6 abuse does not yet, so the ban path over v6 is
> unproven and stays an ⏳ tail.

Plan of record (what is advertised, which VLANs, the filter's rule order, the invariants):
**[network-vlans.md](network-vlans.md) §IPv6.** This section is the *operating* half: how to measure it, how to
prove it is actually filtering, and how to put it back.

**Read the delegation and the advertised state (read-only, safe):**

```bash
ssh router '/ipv6 dhcp-client print detail'        # pool/available + PD_PREFIX (+ bound/ERROR)
ssh router '/ipv6 pool print'                      # the /64 taken from the /56
ssh router '/ipv6 address print'                   # exactly ONE row with ADV=yes (the Home GWA)
ssh router '/ipv6 nd prefix print'                 # ONE *dynamic* row, same prefix, on vlan10-home only
ssh router '/ipv6 firewall filter print stats'     # counters per rule = the real proof
ssh router '/ipv6 route print'                     # the RA-installed default on the router itself
```

**Mechanism facts measured on 7.24.4** (they are not in the RouterOS docs in this shape):
- **`advertise=yes` on the address is what advertises the prefix.** It auto-creates a **dynamic**
  `/ipv6 nd prefix` row (same prefix, `on-link=yes autonomous=yes`, lifetime follows the DHCPv6 lease). You do
  **not** add an `nd prefix` row — and you cannot: 7.24 has no `from-pool`/`template`, and the `prefix` attribute
  wants a concrete prefix, which would hardcode a *leased* value into the converge.
- **A `disabled=yes` `/ipv6 nd` row does not refuse RA.** RouterOS falls back to the default `interface=all` row
  and advertises anyway (add an address on `lo` with a disabled `nd lo` row and `advertise` stays `yes`).
  "No RA on this VLAN" is expressed by **not having an advertised address** there, never by a disabled row.
- `/ipv6 firewall filter` is **first-match-wins** like v4: an accept placed after the drop is unreachable.
  Prove it with a scratch listener plus a scratch accept **below** the drop: connection refused, and a zero
  increment on the accept's counter.
- `/ipv6 dhcp-client` has **no `name=`** (keyed by interface); `/ipv6 nd` takes `advertise-dns` but **not**
  `hop-limit` (a hop limit belongs on the RA's *prefix* or is left default); `protocol=icmpv6` (not `ipv6-icmp`)
  with `icmp-options=` accepting **one integer per rule** — `1-4` and `1,2,3,4` are both rejected, so PMTUD/RS/RA
  coverage costs four rows; `hop-limit` is **not** a matcher in 7.24.
- `from-pool=` on an address works only **after** the pool has bound (an early add → `couldn't get address from
  pool`, rc=1); the converge therefore imports the client before the address.
- ⚠ **`--diff` is forbidden on the router playbook** (`render-converge.yml` runs the `network` role against a
  RouterOS target — the role's per-task diffs dump the whole rendered config, **including the PPPoE password**, a
  500-line context around every change). `ansible-vault view` on `group_vars/router.yml` is the safe way to read
  the file.

**Prove the filter is load-bearing without an outside host (counters, not intent):** traffic that *should* be
blocked and *is* shows up as byte growth on the specific drop rule —
`/ipv6 firewall filter print stats` before/after generating it. The `established` and ICMPv6 RS/RA accepts must
carry real traffic too. Counters reset only at reboot or on the rule's own counter reset.

**The external matrix (the honest acceptance test).** The intended probe is a scratch TCP listener on oldsrv
(`[::]:18099`) plus a *temporary* v6 accept above the WAN drop, then `curl -6` from an off-net v6 host and a
check of the router's byte counters. **The VPS is the probe host and its v6 works.** Its own `input` chain is an
`inet` table: the ICMP accept must be `ip6 nexthdr icmpv6`, because `ip protocol icmp` is the IPv4
upper-protocol field and under `policy drop` it discards the provider router's NA/RA replies, so no v6 nexthop
can ever resolve (`roles/vps-hardening/templates/nftables.conf.j2`). The same v6 root server answers at sub-ms
RTT and TLS over v6 connects.
🔬 **The discriminator is a counter-only rule** (`nft insert rule inet filter input ip6 nexthdr icmpv6
counter`): it carries no verdict, so it cannot change behaviour, and it counts packets that **arrived at our
hook** — compare with `nstat Icmp6InNeighborAdvertisements`, since the netfilter verdict runs *before* the
ICMPv6 handler. Arrive + not delivered ⇒ the drop is ours; nothing arrives ⇒ the block is upstream. ⚠ **A
logger's silence is not evidence until the logger is proved**: the VPS drop-log is rate-limited to 5/minute and
saturates, which is precisely when a counter beats a log.
⛔ **Do not close the home inbound-v6 row on a self-directed probe** — an untested hole is not a
proven-closed hole. The same standard applies to the VPS itself: outbound v6 from it is measured, but no
external v6 peer has connected *to* that box yet, so its inbound half stays open.

🔬 **Two habits that decide any reachability probe:** **(a) probe the transport you
actually use.** A verdict from ICMP or TCP says nothing about a UDP or an ESP path — the live KNX tunnel is
UDP/3671, so a refused TCP/3671 proves nothing about it. **(b) when a probe says NO, run the identical probe
from a host you already know is healthy before you believe it.** Otherwise the control you skipped becomes the
finding — and the finding is the probe, not the path.
⚠ **Say which source produced a v6 read, because a source with no v6 route prints the same words as a filtered
destination** — `Could not connect to server` from a host with no global v6 address is **undetermined, not a
failure**. Prove the source in the same reading (`curl -6 https://api6.ipify.org` must print an address) before
writing anything down about the destination.
DNS is already out of the question: `vps.kogler.si` publishes a DNS-only `AAAA`
(`IaC/ansible/roles/cloudflare_dns/vars/main.yml`) and `matrix.kogler.si` CNAMEs to it.

**Egress direction: a host-side download that fails is a v6 path finding, not a service finding.** Measured on
oldsrv, same host, same URL, same minute:

| probe | result |
|---|---|
| `curl -6 https://www.google.com` | `200` — the box HAS global v6 egress |
| `curl -6` `github.com` · `update.code.visualstudio.com` · `vscode.download.prss.microsoft.com` | connect timeout, no verdict |
| the same three targets over `-4` | `200`/`302` with full bodies |
| `getent hosts update.code.visualstudio.com` | answers **AAAA first** |
| the same URL on the **default** family, same host, same minute | `wget` FAILED · `curl` `200` in 0.42 s, over **v4** (0.09 s when pinned) |
| `wget --no-config` — what the VS Code server installer actually calls | no verdict: the flag drops **every** config file, `~/.wgetrc` included |
| the VS Code **CLI's** own downloader (Go), same host, same wedge | completed — it races both families, so it survives where `wget` does not |

The home v6 egress is **selectively** dead: it reaches some prefixes and not others — and what that costs
depends on whether the downloader races. `wget` has no Happy Eyeballs, so given the AAAA-first answer it dies
on the v6 attempt (FAILED unpinned, `302` pinned, same host same minute). `curl` 8.14 survives the *same* URL
because it tries both families and v4 answers in ~90 ms — 0.42 s unpinned against 0.09 s pinned. So **"curl
works by default" is a race result, not a healthy v6 path**: a downloader without Happy Eyeballs, a longer
race timeout, or a busy link reads this same box as offline. That is why the failure keeps getting misattributed to "this host has no internet" or "the
mirror is down" — a 0-byte artifact left in a download directory is the tell, and the discriminator costs
three commands: `curl -6` a host known to answer v6 (the control, per habit (b) above) and `curl -4` the
failing one. MTU/PMTU is **not** a candidate here: it dies at connect, not mid-transfer, which points at
prefix reachability.

**Seat-local remedy, and the size of it.** `prefer-family = IPv4` in `~/.wgetrc` plus `ipv4` in `~/.curlrc`
(both `0600`, user-scoped) makes a downloader run as that user pick A first — proven both directions on the
real artifact URL: rc-file in effect → `302 Found`, control with the family left default → no verdict. It
reaches `wget`/`curl` for that user and nothing else: a tool that fetches through its own HTTP stack (a Node
binary, an IDE's downloader) ignores both files, so it needs its own client-side download switch instead.

**The case the rc files cannot reach, and what it really turns on.** That switch has its own dead end here: the
Remote-SSH installer calls wget with `--no-config` — its log prints the probe, `Program 'wget' appears to
support flag '--no-config'` — and the flag drops every config file, `~/.wgetrc` included. Measured on the
artifact URL, same minute: rc file in effect → `302`; `wget --no-config` → no verdict. So the split is not
"command-line tools vs an IDE", it is **who races**: `wget` never does (dead), `curl` and the Go CLI both do
(alive). The one lever that reaches a downloader refusing to read its config sits a layer lower, in the
resolver library: `precedence ::ffff:0:0/96 100` in `/etc/gai.conf` makes glibc hand A first to *every*
process. That is the converged form — `roles/common` var `ipv4_first_address_family`, on for `home_servers`
alone (where the asymmetry is measured) and deliberately off on the VPS, where v4-first would mask HD-460's
v6 parity work. It is selectable on its own — `--tags address-family` expands only that write, so a
resolver change never drags apt, docker or the network legs into the same wave.
**State on oldsrv:** the managed block is in `/etc/gai.conf`, `getent ahosts update.code.visualstudio.com`
answers `v4 v6` (it was `v6 v4`), `wget --no-config` on the artifact URL returns `302` (it returned no
verdict), and the control `curl -6 https://www.google.com` still returns `200` — the preference
deprioritizes v6, it does not break it.

⛔ **The durable fix belongs at the router's v6 leg. What the accept-parity verdict at the head of this
section decides is the filter's *family handling*, not this leg — and it is given (KEEP THE PARITY), so it
authorizes nothing here**: no rule change follows from this finding before the prefix read below, so
this is recorded as a measurement plus the probe, never as an edit. What would close it is a prefix-level reachability read from the router itself (`/ipv6 route
print`, then a test per prefix), with the counter-only discriminator above deciding whether the drop is ours
or upstream's **before** anything is touched.
⚠ **Scratch rule hygiene** (this is what `routeros-apply-delta.sh` comments are for): a temporary accept **must
sit above the drop** (below it, it does nothing and the test result is a lie), **must be `dst-port`-scoped**
(otherwise the first packet of a *scan* matches, the conntrack entry then admits the real target, and the matrix
reads "everything answered"), and **must be removed in the same sitting** — the router does not expire it.

**Rollback (two switches; nothing else needs undoing):**

```bash
ssh router '/ipv6 nd set [find where interface=vlan10-home] disabled=yes'   # stop advertising
ssh router '/ipv6 address remove [find where comment~"GWA"]'                # remove the Home GWA
# optional, only to stop the PD client itself:
ssh router '/ipv6 dhcp-client remove [find where interface=pppoe-telekom]'
ssh router '/ipv6 pool remove [find where name=pd-wan6]'
```

The `comment~"GWA"` predicate is the selector, not an identifier: the converge writes one advertised address
per SLAAC VLAN with `GWA` in its comment and writes no other `/ipv6 address` row, so matching on that word
selects exactly the rows the converge owns. `ra-lifetime=30m`, so SLAAC'd addresses age out on their own and
the Home VLAN returns to IPv4-only without touching a single host. To reverse it permanently, revert the
converge's IPv6 section — **do not** leave the device and the plan of record disagreeing.


### Rsc authoring conventions (the rules that make imports safe)

1. **Idempotent by default.** Every `/add` must be guarded so re-import never duplicate-aborts the whole script:
   ```text
   :if ([/interface bridge vlan find where vlan-ids=10 and dynamic=no] = "") do={
       /interface bridge vlan add …
   } else={
       /interface bridge vlan set [find where vlan-ids=10 and dynamic=no] …
   }
   ```
   The guard must target **static** entries (`dynamic=no` for bridge-vlan/lease) — dynamic auto-created entries can't be `set` (`can not change dynamic`).
2. **Never `set` a dynamic object.** DHCP leases and bridge-vlans that the router auto-creates are dynamic; guard static-only, and **add a static reservation** (it takes precedence) rather than mutating the dynamic one.
3. **Order matters.** Import runs top-to-bottom and **aborts at the first error**. Put `/set` (safe, idempotent) before `/add`; put the least-risky, most-reversible changes first; keep the change self-contained so a failure leaves a clear, bounded state.
4. **Converge = the universal apply; delta = transient.** The converge is the full idempotent SSOT — a change goes into the converge template, not a persistent delta. A delta is a quick patch/debug that must be folded back in; don't keep deltas as a parallel long-term truth.
5. **Secrets stay out of the repo.** The rendered `.rsc` (with `mikrotik-admin_login`, `pppoe_login`) is gitignored; the template has Jinja placeholders resolved at render. Never commit/`cat`/grep rendered files.
6. **Every rsc change needs a counterpart in the SSOT** (the template) — the rendered file is a view, never hand-edited.
7. **Which `find` predicates actually match on RouterOS 7:**
   - ✅ `/ip address find where interface=X` — `address=` does **NOT** match the stored CIDR (empty even for an existing row)
   - ✅ `/ip dhcp-server network find where gateway=X` — `address=` does **NOT** match
   - ✅ `/ip firewall address-list find where list=X` (and `list=X and address=Y`)
   - ✅ `/interface bridge port find where interface=X`, `/interface vlan find where name=X`, `/interface bridge vlan find where vlan-ids=N and dynamic=no`, `/ip pool find where name=X`, `/ip dhcp-server find where name=X`, `/ip route find where dst-address=X`, `/interface wireguard peers find where interface=X`, `/user find where name=X`, `/interface bridge find where name=X`
   - ❌ `/ip firewall filter find where dst-address=CIDR` — empty (use `comment=`)
8. **Inline `# comments` inside `:if do={ }` blocks break the parser:** a `asdf # comment` on a guarded `/add`/`/set` line inside an `:if`/`else` block errors with `expected end of command`. Put the comment on its own line above; never inline `#` within a block body.
9. **Bootstrap-only steps must guard on the file existing:** `/user ssh-keys import public-key-file=admin.pub` fails on a steady-state re-import because the bootstrap `.pub` files are gone from `/file` (cleaned after flash bootstrap). Guard `:if ([/file find where name=admin.pub] != "") do={ … }`.
10. **Chain-reset sections are inherently idempotent; address-lists are not.** `/ip firewall nat remove [find chain=…]` / `/ip firewall filter remove [find chain=…]` make NAT/forward/input re-imports land exactly once. But `/ip firewall address-list` has NO reset — a re-import STACKS duplicates, so remove the list members first (`trusted-admin` / `trusted-ha` / `internal_lan`).
11. **A `comment=` is a string on the device, and sometimes it is code.** A ticket id or a date in a `comment=` value — or in any string an import, a rendered template, or a runner script writes onto a host (`~/.bashrc`, a generated config header, a managed-block marker) — states what used to happen rather than what is true, so the [CONVENTIONS.md §3](../CONVENTIONS.md) comment rule applies to it exactly as it does to a `#` line, and [`scripts/gate/check_iac_identifiers.py`](../scripts/gate/check_iac_identifiers.py) refuses the `IaC/` half of it. The one thing that makes such a string **not** editable is a selector: `find where comment="…"`, `comment~`, a `move`/`set` that resolves through the same text, or the role's `api_modify` `comment:` twin. There the id is a key — removing it from one side makes a `remove` stop matching and re-import STACK a duplicate, or makes a guard add a second rule. So the order is always: grep the exact bytes of the string across `IaC/` and `scripts/`, read every hit for a `find`, then change every side in one commit (`check_string_twins.py` reddens a one-sided rename) or none of them. Where the two sides already disagree, the **converge template wins** — it is the apply of record, so the role comment is the side that gets renamed. A folded delta is the exception that frees the text: the id stops being a key when the delta that matched on it is deleted, not before.

   **Retiring a delta that owns a match key — the procedure and the proof order.** This is state, so the
   window is a command sequence and not a re-derivation.

   - **Who writes each rule today.** The converge template is the only writer of record for the whole
     NAT + filter state: it removes both NAT chains
     ([rb4011_converge.rsc.j2](../IaC/router/templates/rb4011_converge.rsc.j2):314, :315) and rewrites the
     `forward` and `input` filter chains in template order (:373, :452), the WAN-egress accepts and the
     Mgmt→Home accept included. The `router` role carries byte-twin `comment:` values for the same rows
     ([roles/router/tasks/main.yml](../IaC/ansible/roles/router/tasks/main.yml):726, :777) but its
     full-reconcile task is **gated off**, so it is a second author of that text, not a second writer of the
     rules. The surviving transient deltas are the only remaining place the same text is used as a
     **selector**: `find where comment="…"` at
     [rb4011_hd307_delta.rsc.j2](../IaC/router/templates/rb4011_hd307_delta.rsc.j2):41 and :51 and
     [rb4011_hd326_fix_delta.rsc.j2](../IaC/router/templates/rb4011_hd326_fix_delta.rsc.j2):56. **No firewall
     state depends on a delta**: delete the delta templates and the next converge still produces the entire
     chain set, in order, from the template.
   - **Prove a delta adds NOTHING before removing it — compare rule attributes, ignore the comment text.**
     Render both scripts, strip the `comment=` field from every `add` line, resolve Jinja, and diff the two
     normalized sets. A delta line that matches a converge line on `chain`, `action`, `src-address`,
     `src-address-list`, `dst-address`, `dst-address-list`, `in-interface`, `out-interface`, `protocol`,
     `src-mac-address`, `connection-state`, `time` and `dst-port` is redundant — an empty diff is the
     evidence, and the comment is excluded from the comparison because it is the field being retired.
     A NAT row whose value comes from a `:local` (e.g. `to-addresses=$vip`) is compared on the resolved
     literal the converge writes, not on the variable name. Then prove **position** on the live device,
     which no text diff can see: `/ip firewall filter print where chain=forward` and check the sequence
     numbers against the order invariants in [network-vlans.md](network-vlans.md) — first-match-wins means a
     rule that exists below the row that already decides the packet is dead weight that reads as working.
   - **Sequence, in the window, in this order:** rename the string on **every** side in ONE commit (converge
     row + role `comment:` twin + every `find where comment=`/`comment~` selector; the twin's own text is
     pinned by [scripts/gate/check_string_twins.py](../scripts/gate/check_string_twins.py) and the
     identifier residue by [scripts/gate/check_iac_identifiers.py](../scripts/gate/check_iac_identifiers.py),
     whose allowlist rows name each twin and which selector matches it) → delete the delta templates in the
     same commit → `bash scripts/ansible/ansible-run.sh IaC/ansible/playbooks/render-converge.yml` →
     `bash scripts/ansible/ansible-run.sh IaC/ansible/playbooks/apply-converge.yml -e converge_rsc=rb4011_converge.rsc`.
     A delta's own rule additions need no separate apply: the converge already writes them, which is what the
     diff above proved. ⛔ Never `--diff` on a router playbook.
   - **Read the device back through the API — the import exit code proves nothing.** `/import` reports success
     for a script whose guards all short-circuited, and a guard whose `find` matched nothing prints nothing
     and changes nothing. So the verdict comes from a read: `api_facts` /
     [mikrotik-read.py](../skills/mikrotik/scripts/mikrotik-read.py), or `ssh router '/ip firewall filter
     print where chain=forward'`. The rename is proven when the NEW text appears exactly once per row, the OLD
     text appears nowhere, and the per-chain row count and order match the template. A row still carrying the
     old text is a row the import never touched — not a row that was renamed.
   - **A comment rename on a row a reconcile selects by exact equality is a delete + add, not an edit.** The
     row is momentarily absent, so the rename belongs inside the window with the accept it touches, never in a
     background run, and the before/after read is taken from the device on both sides of it.
   - **Precondition: a station on-site with WinBox reachable on the Home leg.** This apply is device-wide and
     re-asserts the bridge, which is exactly what the Mgmt-plane caution below refuses unattended — the
     recovery window when the mgmt plane goes dark is WinBox from the laptop / the Home leg, and the `.99`
     mgmt path is itself on-site-only. Away from the house this work is **deferred, not improvised**.
   - **Until the retire lands, the `comment=` match keys stay unedited on every side.** They are keys, not
     prose; cleaning one side (a doc-adjacent tidy-up, an "id-only-here" convenience) is the string-twins
     defect `check_string_twins.py` reddens, and the honest state is that the four strings still carry a
     ticket token because the delta that matches on them is still in the tree.

### Why this model

`community.routeros.api_modify` / `command` are **order- and state-sensitive**: partials, `can not change dynamic`, needs `librouteros` in the exact interpreter, and framings for `/import` are unreliable. A single imported `.rsc` applies many commands as one atomic-ish set — much easier, reproducible, and reviewable (the diff is the template). The **API remains for verification + idempotent state**; the **rsc import is the apply**.

### Ordering pitfall — a new FORWARD accept must sit ABOVE the default-deny

RouterOS evaluates `chain=forward` **top-down**. A rule appended to the END of the forward chain lands
**below** the "Default deny inter-VLAN" row (the repo's forward chain keeps the default-deny mid-list,
before the Comtrend/WAN tail) — so an accept added at the tail is **shadowed**: the deny already dropped
the packet. Fix pattern:

```
/ip firewall filter remove [find where chain=forward and comment="<new-rule>"]   # dedup
/ip firewall filter add chain=forward action=accept … comment="<new-rule>"
:local r [/ip firewall filter find where chain=forward and comment="<new-rule>"]
:local d [/ip firewall filter find where chain=forward and action=drop and comment="Default deny inter-VLAN"]
/ip firewall filter move $r destination=$d     # RouterOS 7 `move … destination=` places BEFORE
```

**Always verify position after a delta apply** (`/ip firewall filter print where chain=forward`) — a rule
that exists but sits below the default-deny is dead weight and *reads* as working.

### Mgmt-plane caution

A **full `router.yml` converge can disturb bridge VLAN memberships on the Management plane**: re-asserting
the bridge can leave VLAN-99's **tagged** memberships missing or flipped-to-untagged on the tagged legs
(router `ether2`/`ether10`), which silently kills the whole tagged-99 plane — every mgmt client goes
ARP-FAILED while the router still answers ICMP on the untagged plane, and because `available-from` is
Mgmt-only the router's own SSH/API become unreachable **from every mgmt client at once**. Rules that follow:

- Prefer **surgical deltas** for mgmt-plane-sensitive changes
  ([network-rejected.md](network-rejected.md) — *Full router.yml converge for mgmt-plane-sensitive changes*).
- Keep `rb4011_pi_delta.rsc.j2` as the canonical **idempotent recovery** — always re-render before use
  (it is SSOT-derived). It re-sets `vlan-99 tagged=bridge-lan,sfp-sfpplus1,ether2,ether10` + the correct
  `pvid` on the Pi's port, matching `router_port_map` / `rb4011_converge.rsc.j2`.
- **A delta import can silently skip a block** (comment/state mismatch inside a guard). After recovery,
  verify the memberships in the live device rather than trusting the import, and re-check every mgmt
  client's ARP before continuing work.
- The recovery window when the mgmt plane is dark is **WinBox from the laptop / the Home leg only**.

---

## Service Binding & INPUT Firewall

> ✅ **Service floor (RB4011, RouterOS 7.24.4):**
> `ftp`, `telnet`, `www`, `api-ssl` and `reverse-proxy` are **disabled**; `ssh` (22), `www-ssl` (443),
> `winbox` (8291) and `api` (8728) are enabled and **every one of them carries
> `available-from=<the Mgmt subnet>`** — no management service listens unbound, and none answers on WAN.
> Re-run this check after any factory reset: `/ip service print detail` and confirm the
> `available-from` on every enabled row.


- **Bootstrap:** in `rb4011_initial.rsc.j2` every management service
  (`api`, `www-ssl`, `ssh`) is **bound to the Management VLAN interface** (`interface=vlan{mgmt}-mgmt`)
  so none listens on WAN or any other VLAN during the bootstrap window. Plain `www` (HTTP) and
  `api-ssl` (no TLS cert yet) are left disabled.
- **Bootstrap-window binding floor (B4):** EVERY bootstrap template (`rb4011`, `crs328`, `ap`) must
  bind management services to the Management interface/bridge **from the first line of device
  uptime** — the rb4011 template above is the canonical pattern; no template may enable an unbound
  management service. The crs328 and ap templates carry the same floor.
- **Steady-state INPUT chain:** the Ansible router role adds `chain: input` rules so
  the management service ports (`22,8728,8729,8291,80,443`) are reachable **only from the Management
  VLAN (99) and `trusted-admin` hosts** (nas/oldsrv/ha-vip); the ports are dropped from every other
  source. Established/related and DHCP input remain accepted so the control plane, clients and the
  WireGuard/VRRP links keep working.
- **Assert-before-mutate:** both the router and switch Ansible roles start with a `community.routeros.api_facts` read of `/system identity` and assert the target matches the per-gear `routeros_expected_identity` from `group_vars/` (fail-loud — a blank identity aborts). This runs **once per role run**, before any `api_modify`, so a wrong-target or swapped-host can never receive config meant for another device.
- **Router API TLS:** `api-ssl` (**:8729**) exists on the device but is **disabled** — every bootstrap and converge template plus the router role's `/ip service` row set `disabled=yes` with `certificate=none` — so the TLS path is **not live** and the management API is the plain `api` (:8728) on the Mgmt VLAN. `routeros_tls` therefore stays **false** — the role default in `roles/router/defaults/main.yml` sets it explicitly and the `routeros_tls: true` line in `group_vars/router.yml` is commented out — until the router is reset with the initial `.rsc` and `api-ssl` is live. Flipping it then keeps `validate_certs: false` — a self-signed device cert on a private Mgmt VLAN, with no public CA and no Let's Encrypt dependency either way. See `rb4011_initial.rsc.j2` / `crs328_initial.rsc.j2`.
- **Shared RouterOS admin credential:** because all management binds to Mgmt-VLAN 99 (above), the **same `mikrotik-admin_login` password is deliberately shared** across RB4011 + CRS328 + APs as an **accepted** risk — it cannot be reached from WAN or any non-Mgmt VLAN. Revisit per-gear items only if a device gains WAN-exposed management or this ACL changes. See [deployment-secrets.md](deployment-secrets.md).
- **Rotating the shared admin password:** the rotation follows the repo-native **render → `/import`** flow, NOT a manual device-by-device SSH script. Procedure: (1) update `mikrotik-admin_login` in 1Password — set **`old-password`** = current live value, **`password`** = new value (vault = SSOT; every converge/`initial` template reads `password`). (2) Re-render `render-converge.yml` + `render-routeros.yml` so every `IaC/router/rendered/*.rsc` embeds the NEW password; **delete any stale rendered `ap_initial.rsc`** (legacy universal AP script — per-AP `ap_initial-<name>.rsc` are current) and any converge `.rsc` left on a device after a partial `/import`. (3) Apply the converge (or a `user set admin password` delta) per device via `scripts/ansible/routeros-apply-delta.sh` / `apply-converge.yml` (SSH `ansible` identity, pinned host key; the API `/import` step needs `librouteros` in the runner — if missing use the SSH-import path). (4) **Verify from a Mgmt-sourced API path**: old password must FAIL, new must authenticate — testing from a non-Mgmt source (e.g. a Home IP) is INPUT-dropped and reads as a **false lockout**. (5) At the **next bootstrap reset**, re-upload the re-rendered `initial` `.rsc` files (`rb4011_initial.rsc` / `crs328_initial.rsc` / `ap_initial-<name>.rsc`) to each device's `flash/` so a flash-bootstrap sets the NEW password. `ansible` is a key-only automation user (`group=full`, password unused) and is unaffected by the rotation.

---

## Central log shipping — RouterOS logs → VPS CrowdSec + VictoriaLogs

✅ **LIVE end-to-end.** The RB4011 forwards its logs as **RFC5424 syslog over the `wg-s2s` tunnel** to the
VPS; CrowdSec parses them for failed-login + port-scan detection and the same stream is available to
VictoriaLogs for central search.

- **RouterOS side (router role, `router-logging` tag):** `/system logging action centralsyslog`
  (`target=remote`, `remote=<vps wg-s2s address>:514` — SSOT `wg_s2s_vps.remote_ip`,
  `src-address=wg-s2s`) plus `/system logging` rules forwarding topics `error` (login/API failures — the
  `a1ad` parser requires it), `firewall` (drops → port-scan scenario), `critical`, `warning` →
  `centralsyslog`. RouterOS 7 action-name rule: **letters+numbers only** — `central-syslog` is rejected by
  the device. `src-address` ties the source to the wg-s2s interface (Mgmt-plane only; never WAN).
  Fail-loud: any missing SSOT value aborts the render.
- ⛔ **A foreign `/system logging` rule destroys the log window every measurement needs — live defect.**
  The device carries the `ssh` topic routed to the **`memory`** action, and **no repo-managed
  config creates it**: the `router-logging` task owns exactly the `error` / `firewall` / `critical` /
  `warning` rows that forward to `centralsyslog`, and this is not one of them. Consequence: **~1000
  packet-dump lines per 3 min against a 1000-line memory buffer**, so the buffer is *always* rotating and
  silently rotates away whatever window a measurement is reading, and the dumps write handshake/packet bytes
  into the stream that this section then ships to the centre. Read the table instead of trusting the config:
  `ssh router '/system logging print'`. Removing it is only half the work — the deletion has to be proved
  to **stay** gone across the next router converge (that converge's own `path: system logging` task is the
  suspect for restoring it).
- **WireGuard AllowedIPs gotcha (the reason this class of failure is invisible):** WireGuard **silently
  drops any inner packet whose source IP is not in the peer's `AllowedIPs`**. The syslog packets are
  sourced from the **router's own tunnel address** (`wg_s2s_vps.router_ip`), so that /32 MUST be in
  `wg_s2s_vps.allowed_ips` (`group_vars/all/`, the single SSOT consumed by both tunnel sides) — otherwise the tunnel looks perfectly healthy (handshake + big transfer counters, all `10.10.*`
  traffic flowing) while every log packet dies inside the tunnel. **Re-render the VPS `wg-s2s.conf` and
  re-run the `wg-ensure-s2s-peer` oneshot whenever that list changes.** Diagnosing this class needs a
  synchronized test: router-side `/tool sniffer quick interface=wg-s2s ip-protocol=udp port=514` **and** a
  listener on the VPS wg address — packets visible on one side only localizes the drop.
- **Scoped `logpipe` API user (r/o, `read` group):** created by the role with the `mikrotik-logpipe_api`
  1Password credential; only the Mgmt plane reaches it. A dedicated `n8n` scoped read-only user
  (`mikrotik-n8n_api` item) follows the same pattern and stays provisioned for admin use (the
  n8n firmware workflow is superseded — [network-vlans.md](network-vlans.md) §CAPsMAN).
- **Receiver (monitoring role, `routeros-syslog` tag, VPS only):** `rsyslog` UDP/514 on the **wg-s2s VPS
  address** (SSOT `wg_s2s_vps.local_ip`) accepts RFC5424 from the router peer only and writes
  `/var/log/remote-syslog/routeros.log`. Notes: the **netcup minimal image does NOT ship rsyslog** (the
  monitoring role installs it); the VPS default-deny nftables input needs an explicit
  `iifname "wg-s2s" ip saddr <router wg address> udp dport 514 accept`, otherwise rsyslog binds the
  address and the input policy silently drops every syslog packet.
- **CrowdSec (docker_services `crowdsec` service):** compose binds `/var/log/remote-syslog` (ro); the
  `acquis-routeros.yml` (monitoring role → `config/acquis.d/`, VPS-only) tells CrowdSec to tail the file as
  `type: mikrotik`. `crowdsec_collections` carries **`a1ad/mikrotik`** (parser + `mikrotik-bf` +
  `mikrotik-scan-multi_ports` scenarios) — the upstream-blessed remote-syslog pattern.
  ⚠ The acquis must live in the **config mount's `acquis.d/`** (`/etc/crowdsec/acquis.d/` in-container) —
  a compose-dir extra-template copy is never read by CrowdSec.
- **VictoriaLogs (search surface):** the VPS Alloy tails `/var/log/remote-syslog/routeros.log`
  (`loki.source.file "routeros_syslog"` + `loki.process.routeros`, `job=routeros-syslog`) → VictoriaLogs (90d);
  Grafana is the query surface — no second log backend.
- **Role/runner gotcha:** the router/switch roles' `routeros_api_password` `set_fact` must stay tagged
  `always` — otherwise any surgical `--tags router`/`--tags switch` converge fails on an undefined
  password (the assert-before-mutate identity check is `always`).
- **Retained safety net:** a `/system script` + startup scheduler (`fixsyslog`) on the RB4011 re-applies the
  `centralsyslog` action target 10s post-boot (toggle remote → back). Harmless, self-healing insurance if
  RouterOS ever fails to (re)init the action on boot; the converge template folds it in.
- **Switch/AP log forwarding is not enabled:** the CRS328 has no wg tunnel and the rsyslog receiver
  accepts only the router's wg peer; a routed path (receiver LAN-source allow or a switch-side tunnel) is
  needed before enabling them. See [observability.md](observability.md) and
  [services-traefik.md](services-traefik.md) §CrowdSec.

---

## CAPsMAN steady-state contract (`wifi-qcom-ac`)

> The imperative apply procedure lives in [deployment-manual.md](../deployment-manual.md) §1.5.4; this is the
> **why**, so a change here does not have to be re-derived from a broken WLAN.

1. **The manager has to be enabled.** `/interface wifi capsman set enabled=yes` is the FIRST line of the rendered
   steady-state. Config objects existing is not enough: with the manager at `enabled=no` no AP ever provisions, and
   the symptom is "APs not functioning" with a clean-looking config.
2. **wifi-qcom-ac CAPs cannot honour `datapath vlan-id`.** Configs use a named datapath `DP_AC` (bridge-lan, **no**
   vlan-id). The per-SSID VLAN rides the CAP's **bridge** instead: pvid on the provisioned slave interface + the
   uplink `ether1` tagged.
3. **Radios must be told to be CAPs.** Each radio needs `configuration.manager=capsman` + `disabled=no`, and the CAP
   needs `slaves-static=yes` (carried by `ap_initial.rsc.j2`). A bare `cap set enabled=yes` leaves the radio a
   locally-configured master that never joins — the `MBX` state.
4. **AP identities are descriptive and rendered per AP** (`ap-spalnica`, `ap-dnevna`, `ap-spare`) via
   `ap_initial-<name>.rsc`; do not hand-name them on the device.
5. **Three SSIDs, band-split by provisioning rule**: `Kogler` (both bands), `Kogler IOT`
   (**2.4 GHz only**), `Kogler guest` (**5 GHz only**) — expressed as `band:` per SSID in the
   `routeros_capsman_ssids` SSOT. There are no per-purpose SSIDs — no extra configs, no extra security
   profiles; kids control is firewall MAC rules — [network-vlans.md](network-vlans.md) §CAPsMAN.
6. **The switch must carry the wifi VLANs tagged on the AP ports.** An AP port that is only an untagged VLAN-99
   access drops the CAP's per-SSID tagged frames at switch ingress: clients associate, never get DHCP ("phone
   disconnects"). Encoded in `wifi_ports` (`group_vars/switch.yml`) + the converge rsc — ether11/ether12 carry
   10+20+30 tagged.
7. **A new slave SSID does not materialize on a provisioning change alone.** After adding a slave to a rule, kick
   the manager (`enabled=no` then `=yes`) so each CAP re-pulls and creates the slave interface, then add the bridge
   VLAN entry (`/interface bridge vlan add vlan-ids=<v> tagged=ether1 untagged=<slave>`) and the port pvid. See
   `ap_guest_delta.rsc.j2` for the guarded, idempotent form.
8. **Flash persistence:** the `.pub` files and anything else that must survive a reboot go under `flash/` on the
   switch and the APs — files written at device root are wiped on reboot. RB4011 root is fine.

VLAN landing per SSID: `Kogler` → 10, `Kogler IOT` → 20, `Kogler guest` → 30.
