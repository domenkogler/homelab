> **Role:** single-lane handoff for **HD-398 — the management VLAN (99) does not accept traffic from the site-to-site tunnel.** The mechanism is already proven; what is left is a narrow piece of router evidence and **one owner decision**. This file is self-contained.
> **Linked from:** [`prompt.md`](prompt.md) §2 · [todo.md](todo.md) HD-398 · siblings [`prompt-397.md`](prompt-397.md) (the away-path work this row gates) and [`prompt-391.md`](prompt-391.md) (the lane that needs a reliable oldsrv converge path).
> **Baseline:** authored on `main` at `47a71c7`, 2026-09-19. Row Exec class is **AI + gate** — the last step is not yours.

---

## 0. Start here

1. **Fresh session worktree before any edit:** `git worktree add ../homelab-wt-$(date +%Y%m%d-%H%M)` (CONVENTIONS §6).
2. **On-site prerequisite for the remaining evidence:** `router` and `switch` aliases target mgmt-leg addresses with **no jump** — they are reachable only when the Windows **`Mgmt99` vNIC has link** (`wsl-nat-resolv.ps1 -EnableMgmt99`; it was **Disconnected** on 2026-09-19) or when you are physically on the LAN. Verify link first: `ip -br addr` in WSL must show a VLAN-99 route, not just `eth0`. If you have no mgmt access, **you cannot finish this row** — do the desk work in §3/§4 and hand the owner the decision.
3. Ansible through `bash scripts/ansible-run.sh …`; `--check` is the only safe foreground converge form; real converges detached; **never `--diff` on `docker_services`**; never print a secret value.
4. `bash scripts/validate-all.sh` green before finishing; signed commits (`ssh-add ~/.ssh/github_signing ~/.ssh/github_auth` if the agent has no key).

**Do not re-derive:** everything in §2 was measured twice by two sessions on 2026-09-19. **Do not re-decide:** LAN hosts do not join the tailnet (decided 2026-09-10) — it is the tempting wrong answer to this row.

---

## 1. Mission + definition of done

**Mission:** settle whether VLAN 99 being unreachable from the VPS tunnel is intentional or a fault, and make the repo say so out loud — either by recording the seal as policy and routing all off-LAN admin to the Home leg (HD-397), or by widening the two boundaries deliberately.

**Done when:**

- [ ] The owner has answered, in writing, one of: **(A) the seal stays** (mgmt plane is same-site only) or **(B) widen it** (with a stated security delta accepted).
- [ ] The router/switch evidence in §3 is either collected (if the answer is B, or if the owner wants it on record) or explicitly waived.
- [ ] [docs/network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away states the settled rule (it currently ends with "Whether the seal is intentional or a fault is HD-398").
- [ ] Whichever answer lands, `IaC/ansible/host_vars/oldsrv.kogler.si.yml` (`ansible_host`), the ssh alias contract and [docs/network-vpn.md](docs/network-vpn.md) agree with it — **no silent edit of any of the three**.
- [ ] HD-392 and HD-398 are closed out per lifecycle (done rows are deleted from [todo.md](todo.md); the record is the owning doc + git).

---

## 2. Already proven (do not repeat; commands are for re-verification)

**Symptom.** From the VPS over `wg-s2s`: ICMP to the VLAN-99 gateway answers; TCP/22 to the router's own mgmt address, to the Pi's mgmt leg and to oldsrv's mgmt leg all stall into banner-exchange timeout; a Home-VLAN host (`10.10.1.10:22`) answers fine. On oldsrv everything is healthy: `enp0s31f6.99` **UP** with the right address, source-forced ICMP from that address to the VLAN-99 gateway succeeds, up 9 d 21 h, 34 containers running, 0 unhealthy. *(The "up 12 days" figure in the first draft of this row was not reproducible — the conclusion is unaffected.)*

**Two independent mechanisms, both intentional:**

1. **The VPS has no route to the mgmt address at all.** `ip route get <oldsrv mgmt>` on the VPS resolves **`via <vps default gw> dev eth0`** — out to the internet — while `ip route get <VLAN-99 gateway>` resolves **`dev wg-s2s`**. Cause: `wg_s2s_vps.allowed_ips` in `IaC/ansible/group_vars/all/main.yml` is an explicit **/32 least-access allow-list** (router + switch mgmt + the five VLAN-10 node addresses + the `wg-vps-services` range) with **no oldsrv mgmt entry**, and systemd-networkd installs routes only for what AllowedIPs names. Live `sudo wg show` agrees; the netdev file's **mtime is 2026-09-03**, so nothing changed today.
2. **Even the allowed mgmt addresses refuse tunnel-sourced SSH.** `IaC/router/templates/rb4011_converge.rsc.j2:442` sets `/ip service set ssh … available-from={{ router_services_available_from }}`, and that var (`IaC/ansible/group_vars/router.yml`) is **the VLAN-99 subnet and nothing else** — a tunnel-sourced connection (src `10.255.40.2`) is refused by design (tagged 99 = admin plane; Home→Mgmt forward is dropped).

**Re-verify in 60 seconds:**

```bash
ssh vps 'ip route get 10.10.99.30; ip route get 10.10.99.1; sudo wg show wg-s2s | sed -n "/allowed ips/p"; ls -l --time-style=+%F /etc/systemd/network/wg-s2s.netdev'
grep -n -A9 "allowed_ips:" IaC/ansible/group_vars/all/main.yml | head -20
grep -n -B3 -A2 "router_services_available_from:" IaC/ansible/group_vars/router.yml
```

**The datum that pointed at a live fault was wrong.** "It worked ~10:44Z and died by ~12:26Z, so something changed mid-day" is **workstation-side**: `~/.ssh/config.bak-20260918-103530` shows `Host oldsrv` direct and **jump-less**, and `ProxyJump vps` was added to it on 2026-09-19. Combined with the 2026-09-03 netdev mtime, no network-side change is needed to explain anything.

---

## 3. The remaining evidence (narrow)

For the **router's own** mgmt services nothing is missing: `available-from` already explains it. What is not yet read is the path **through** the router to another host's mgmt address, i.e. would adding the /32 even work:

1. **Forward + return path:** `ssh router '/ip firewall filter print where chain=forward'` — is there a rule dropping `in-interface=wg-s2s` toward the VLAN-99 bridge? And `/ip route print | grep 10.255.40` (return route for the S2S /30).
2. **Neighbour/ARP for the mgmt address from the router:** `ssh router '/ip arp print where address=10.10.99.30'` plus `/interface vlan print` (VLAN 99 interface present, correct `interfast-vlan99`-style member list).
3. **Switch trunk** (only matters for host-to-host VLAN-99 traffic, not for the router's own services): confirm the oldsrv uplink port (`ether11` per the switch port map SSOT) still tags 99, and that the router's trunk to it does too.
4. **Service scope on the switch** (`/ip service print`) — same class as the router's `available-from`.
5. Optional decisive experiment (owner-approved, revertible): temporarily add the /32 to the VPS peer **only** (`wg set`), then re-test. It answers "route or filter?" without touching the repo. Revert immediately; do not leave a live WG peer out of sync with IaC.

If you cannot reach the router (§0.2), stop here and take the decision below — options A works without any of it.

---

## 4. The decision to put in front of the owner

| | **A — seal stays (mgmt = same-site only)** | **B — widen deliberately** |
|---|---|---|
| Meaning | VLAN 99 admin is a physical-presence plane; off-LAN admin is always the Home leg | A compromised VPS gains admin-plane reach toward router/switch/oldsrv mgmt |
| Repo changes | none on the tunnel; `host_vars/oldsrv.kogler.si.yml` + ssh alias + docs move to the Home leg (HD-397 carries it); record the rule in [docs/network-vpn.md](docs/network-vpn.md) | add the derived `/32` to `wg_s2s_vps.allowed_ips` (**never a literal**), converge the wireguard role, likely also extend the router's `available-from` list, verify from the VPS |
| Security delta | zero | **material** — this is the HD-155 least-access boundary + the HD-310 admin-plane boundary; both exist on purpose |
| Cost | HD-397 must land | router ACL surgery + a standing exception |

**Recommendation to present: A.** It is the current behaviour, it is what `pi`/`spark` already rely on, and B spends two deliberate boundaries to fix a symptom that the Home leg already solves. If the owner picks B, the `available-from` change must be an explicit, separately-reviewed edit — not smuggled in with the AllowedIPs line.

---

## 5. Do-not-do list

- ⛔ Do **not** "fix" it by adding a /32 to `wg_s2s_vps.allowed_ips` on your own initiative: it widens two intentional boundaries **and** is insufficient by itself (the `available-from` wall remains).
- ⛔ Do **not** join LAN hosts to the tailnet (decided 2026-09-10).
- ⛔ Do **not** flip `host_vars/oldsrv.kogler.si.yml` `ansible_host` to the Home leg as a convenience while the owner question is open — that is the decision, not a workaround.
- ⛔ Do **not** leave `wg set` experiments live; the repo is the SSOT and drift here is how "worked earlier" stories get invented.
- ⚠ Read the failure correctly: **banner-exchange timeout = dead next-hop**, and a **dead address is not a dead host**.
- ⚠ There is no `tailscale` CLI on the VPS host (sidecar owns it) — `tailscale status` there is the wrong instrument.

---

## 6. Close-out

1. Record the settled rule + the evidence in [docs/network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away (replace the open "whether the seal is intentional" sentence) and, if B, the WG/allow-list change in `IaC/README.md` status + [docs/network-ops.md](docs/network-ops.md).
2. Update [todo.md](todo.md): close HD-398 and HD-392 (delete done rows per CONVENTIONS §4(a)); if A, HD-397 becomes the only open row in this lane and should say so.
3. If any generated doc's input changed, re-render (`scripts/render_all.py`); never hand-edit `*-generated.md`.
4. `bash scripts/validate-all.sh` green → signed commit on the session branch → fast-forward into `main`.
