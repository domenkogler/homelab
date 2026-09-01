# HD-306 — VPS systemd-networkd WireGuard peer never binds (wg-s2s)

> **Role:** Research + durable-fix plan for the VPS-side wg-s2s peer that systemd-257
> networkd creates but never applies. Live-research done 2026-09-01; fix is a secret-free
> `wg set` oneshot that surfaces the peer after networkd init (the documented HD-306 fallback).
> **Environment:** Debian 13 (vps, kernel 6.12.101+deb13-amd64, systemd 257).

## 0. Root cause (live-verified)

On the VPS, the wireguard role renders a correct `/etc/systemd/network/wg-s2s.netdev`
(peer in `[WireGuardPeer]`). **systemd 257 networkd parses the netdev as `netdev ready` /
`Link UP` but never applies the `[WireGuardPeer]` block to the kernel** — `wg show wg-s2s`
shows the interface (key/address/listen) with **no peer**.

Proof chain (2026-09-01, live):
1. On-disk `.netdev` is correct; networkd even generated the runtime `wg-peer.conf` (peer +
   endpoint) — yet no peer in the kernel.
2. A control interface created via `ip link add wgtest0 type wireguard` + `wg set peer`
   attaches the peer **fine** (same netns, same kernel, same perms).
3. On the networkd-owned `wg-s2s`, `wg set`/`wg setconf` **do** attach the peer (rc=0, peer
   appears and persists across `networkctl reconfigure`). So raw WireGuard works; only
   **networkd's own peer-application** is the bug — matching the documented systemd-networkd
   WireGuard issues (GH #25547/#38196 family), not a kernel/namespace/config problem.

## 1. Fix (durable, secret-free)

Add a **systemd oneshot `wg-ensure-s2s-peer.service`** to the `wireguard` role that runs
after networkd brings up the interface and idempotently issues:

```bash
wg set wg-s2s peer <PUBKEY> allowed-ips <allowed_ips> endpoint <endpoint>:<port>
```

- Runs `After=systemd-networkd-wait-online.service` (wait-online is enabled on the VPS) so the
  interface exists before the `wg set`.
- **No private key needed** — `wg set` peer-add only uses the peer public key + allowed IPs +
  endpoint (all non-secret SSOT values), so we neither duplicate `wg_password` nor open a
  second secret file. The private key stays in `.netdev` (0640).
- Idempotent: `wg set` re-adding an existing peer is a no-op; peer survives networkd reconfig.
- `RemainAfterExit=yes` one-shot; `Restart=on-failure`.
- Endpoint resolved at runtime so a home WAN IP change does not need a re-render (matches the
  existing `.netdev` DDNS-token design).

## 2. Files

- `IaC/ansible/roles/wireguard/templates/wg-ensure-s2s-peer@.service.j2` (static unit) —
  actually a plain `.service` since wg-s2s is single-instance.
- `IaC/ansible/roles/wireguard/templates/wg-ensure-s2s-peer.sh.j2` (renders `wg set` line from
  SSOT `wg_s2s_vps`; endpoint resolved at runtime).
- `IaC/ansible/roles/wireguard/tasks/main.yml` — render `.service` + `.sh`, `systemctl enable --now`,
  template `notify` none (no networkd restart needed; unit applied directly).
- `deployment-manual.md` §1.5.5 — update the stale HD-306 blocker note → resolved + new verify.
- `todo.md` HD-306 + `docs/network-vpn.md` — close-out / record.

## 3. Verify (after converge)

```bash
systemctl status wg-ensure-s2s-peer          # active (exited)
sudo wg show wg-s2s                          # peer present (+ handshake once router side is up)
sudo systemctl restart systemd-networkd; sleep 2; systemctl start wg-ensure-s2s-peer
sudo wg show wg-s2s                          # peer re-attached after networkd restart (boot-path proof)
```

Handshake (`latest-handshakes` nonzero) requires the **router side** (HD-285 / Phase 1.5) — out
of HD-306 VPS scope, noted in close-out.
