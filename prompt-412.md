# `prompt-412.md` — Lane brief · remote desktop that helps the family (HD-412)

> **Role:** single-lane handoff for the **remote-desktop** half of the remote-dev-plane thread (owner direction
> 2026-09-20). Start with [README.md](README.md) §0 → §1 mandatory context → this file → the row in
> [todo.md](todo.md) §2.4. Transport is [prompt-405.md](prompt-405.md); runner/cockpit is
> [prompt-407.md](prompt-407.md).
> **Linked from:** [prompt.md](prompt.md) §2 · [todo.md](todo.md) · [todo-table.md](todo-table.md)

## Goal

Self-hosted remote desktop so the owner can help family members' machines, and keep a desktop-rescue path for
the homelab's own GUI surfaces — **without** putting a new public listener on the box that holds the vault token.

The need is about the **family's** machines, not oldsrv: they need an introduction point reachable from wherever
they are, with **outbound-only** access from their side.

## ⛔ The placement is decided — do not re-argue it

Logged in [services-rejected.md](docs/services-rejected.md) (2026-09-20):

* **Server (hbbs rendezvous + hbbr relay) on the VPS.** The reflex objection — "VPS RAM is tight, Docling is off
  now but RAG is coming" — does not apply here: upstream's own floor is *"the minimum configuration of a basic
  cloud server… you can also use a Raspberry Pi"*. What the relay really costs is **bandwidth** when hole-punching
  fails (~30 KB/s–3 MB/s for a 1080p session), so the durable constraint to design against is the **quota**, not
  RAM. Cap it and say so in the doc.
* **Never on oldsrv.** A rescue tool that lives behind the thing it rescues is not a rescue: if the home link or
  oldsrv itself is the broken thing, so is the support path — and making it reachable would need a **public
  listener on the crown-jewel host**.
* **The owner's own machines skip the server entirely:** RustDesk's direct-IP listener + IP whitelist scoped to
  the tailnet range (made possible by HD-405) means no third-party introduction and no relay hop for them.
  Tailscale-and-RustDesk is the documented pairing; verify the direct-IP path on the **pinned** version, because
  upstream has shipped regressions there before.

## Work — CONVENTIONS §5 onboarding, `Stage: 1/10`

This is a service, so the checklist is the ledger (the todo row's `Stage:` is a pointer, not a second ledger):

1. **Exposure & auth** → write it in [services-admin.md](docs/services-admin.md) (this is the owning doc — admin/ops
   tooling, and it already carries the "how do we administer things" answers). Decide and record: ID-access vs
   whitelist-only, the console surface (`:21118`-class web console) behind which middleware tier, and whether
   family machines join the tailnet (then the server is only for non-members) or dial in by ID.
2. **Secrets** → 1P items per convention; the KeyPairs are **externally-coupled** (rotating them orphans enrolled
   clients) → `NOT_AUTO_ROTATABLE` with a stated reason, and they need a backup/restore story (HD-49/HD-191 family).
3. **Compose template** → `templates/docker_services/rustdesk-server/`. `network_mode: host` is the upstream
   recommendation for UDP rendezvous; that is the *justification* CONVENTIONS §3 demands for host networking + host
   ports — write it in-template, not in chat. `cap_drop: ALL`, pinned tag (never a mutable alias, §7), read-only root
   + a writable data dir for the keys.
4. **Registry + catalog row** → `group_vars/vps.yml` + [services.md](docs/services.md).
5. **Edge** → no Traefik route for the rendezvous/relay ports; the **console** is the only HTTP surface and it takes
   the existing admin tier (CrowdSec / tailnet-first per [security.md](docs/security.md) §10).
6. **State & backup** → the key material is the state; put it in the Kopia/db-backup scope.
7. **Observability** → it is infrastructure: uptime/reachability, never a family tile.
8. **Validation** → `bash scripts/validate-all.sh`.
9. **Deploy gate** → human-gated first apply (dry-run → single host).
10. **Docs** → [security.md](docs/security.md) gains the tier row (capability-tiering: an always-on remote-control
    agent is exactly the class §10 governs), [services-admin.md](docs/services-admin.md) holds the how-to, and
    [todo-table.md](todo-table.md) is re-synced.

## Client side — oldsrv's own caveats (record them, they will bite)

* **X11 only.** oldsrv is Xorg/XFCE ([hardware-oldsrv.md](docs/hardware-oldsrv.md)); Wayland is the upstream pain
  source and Docker/Xvfb is the "unsupported display server" trap — do not try to containerise the **client**.
* **It mirrors the current desktop session.** oldsrv is the family desktop with auto-login on the primary family
  account (HD-51), so a support session **takes over the family's screen**. Decide the posture deliberately: service
  vs session-start, unattended password vs one-time consent, and a visible notice. Do not discover this during a
  live family call.
* The iGPU drives the desktop and the dGPU is pinned to the AI tier — nothing here changes that split
  ([hardware-gpu.md](docs/hardware-gpu.md)), but a remote session is the thing a family member will notice.

## Lane rules (concurrent with [prompt-405.md](prompt-405.md) and [prompt-407.md](prompt-407.md))

* **Owns:** `docs/services-admin.md`, `docs/security.md`, `docs/services-vps.md`,
  `IaC/ansible/templates/docker_services/rustdesk-server/`, the `docker_services` + ports region of
  `IaC/ansible/group_vars/vps.yml`, `docs/deployment-secrets.md` **append-only rows for its own items**.
* **Does NOT touch:** `docs/network-vpn.md` / `network-dns.md` / `roles/router/**` (lane 405), `docs/services-ai.md`
  / `docs/pi-harness.md` / `docs/1password.md` / `scripts/**` (lane 407). The reachability answer is *borrowed* from
  lane 405 — if HD-405 has not landed yet, build the VPS server half and leave the tailnet-whitelist half ⏳.
* `group_vars/vps.yml` is shared with lane 405 (it edits `tailnet_subdomains`); stay in your own region and rebase
  rather than hand-merging YAML.
* Owner-gated before anything is exposed: the family-onboarding model and the bandwidth quota are **owner calls**
  listed in the row — ask, do not pick.

## Acceptance

[services-admin.md](docs/services-admin.md) carries the exposure/auth answer + the family onboarding procedure ·
[services-vps.md](docs/services-vps.md) + [services.md](docs/services.md) describe a live service, not a planned one ·
a real support session completed **from the phone to a family machine**, and a **direct-IP tailnet session to
oldsrv** with the relay uninvolved · the bandwidth cap in effect and quoted · the key material in a backup scope and
a restore path named · `bash scripts/validate-all.sh` green · row keeps its ⏳ tail until the live verify
(CONVENTIONS §4(b)).
