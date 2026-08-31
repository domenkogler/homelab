# prompt.md — Deployment Execution Handoff #44 — **wg-s2s bring-up attempt (HD-306 opened) + Phase 1.5 cutover still mid-flight**

> **SESSION #43 (2026-08-31, worktree `homelab-wt-20260831-1607`, branch `session/wg-s2s-20260831-1607`, MERGED + PUSHED):** wg-s2s bring-up attempt after the owner's MikroTik password rotation. Router verified healthy + IaC-aligned steady-state (RouterOS 7.24.1, services lockdown exact, ordered firewall). `wg-s2s` interface key corrected to the shared `wg_password` pubkey (`gwXAk+…`) via `router` role (`ok=32 changed=16`); VPS `wireguard` role live-applied (`ok=13 changed=5`) — interface up on the /30, correct key, listen 51820. 🔴 **BLOCKED — VPS peer never attaches** (new HD-306, research open): `wg show` shows interface only / no peer; `lsmod` refcount 0 → netdev never bound. IaC fixed + committed (Jinja `\n` glue, `.netdev` 0640 + peer location, DDNS endpoint `s.kogler.si`, doc drifts). Full evidence + next steps: journal + [todo.md HD-306](todo.md). **Predecessors #33–#42** are closed history — records in [deployment-journal.md](deployment-journal.md) + [changelog.md](changelog.md); this handoff carries only the live pointers (§2/§3).

> **Role:** entry point for the next session. This handoff is a **pointer index** — every item's owning doc/row holds the detail. Start with README.md §0 (intent routing), then §1 context, then §3 execution order. Read [todo.md](todo.md) for the full row bodies.

> **Linked from:** [README.md](README.md) §0/§2 · [CONVENTIONS.md](CONVENTIONS.md) §4/§6 · [scripts/guard-session.sh](scripts/guard-session.sh) · [changelog.md](changelog.md) · [deployment-journal.md](deployment-journal.md) · [todo.md](todo.md).

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §6 worktree discipline (**MECHANICALLY** enforced by `scripts/guard-session.sh` + validate-all hard-gate), §4 journal loop + close-out items, §2 secret-output hygiene, §5 service-onboarding checklist.
2. [docs/deployment-ansible.md](docs/deployment-ansible.md) — §Tags & surgical runs (`docker_services_scope`, `base` tier) + §Deploy Timing Runbook.
3. [docs/deployment-compose.md](docs/deployment-compose.md) + [docs/deployment-secrets.md](docs/deployment-secrets.md) — compose/secret conventions + fail-loud rule.
4. [docs/network-vpn.md](docs/network-vpn.md) — §Pattern A tailnet sidecars + current tailnet edge state.
5. [changelog.md](changelog.md) — decision log SSOT; read before re-deciding anything.
6. [deployment-journal.md](deployment-journal.md) — append-only as-built record; latest entries = Phase 1.5 (2026-08-31).

## 1. Environment (Windows 11 laptop)

Same as handoff #16 (unchanged): git-bash, forward-slash, `py -3`, UTF-8 no-BOM, LF; Ansible via WSL + 9P gate before every run; Secrets → 1Password item.field only, `>-` for YAML renders. **Self-learned (2026-08-26):** do NOT use multi-line bash heredocs with backslashes/backticks (mangled through `bash -c`) — write patch scripts to a temp file and run them. `wsl.exe` from git-bash mangles `/mnt/...` — prefix `MSYS_NO_PATHCONV=1`. **Signed-commit gotcha (still valid):** keys in `~/.ssh/github_signing`/`github_auth`; `Couldn't find key in agent` → `ssh-add ~/.ssh/github_signing ~/.ssh/github_auth`.

## 2. State snapshot (start of next session)

- **Phase 1 (VPS edge) is LIVE** — full enabled `docker_services` set converges green (`ok=311`); observability + Authentik + headscale + traefik-tailnet all up. See [deployment-journal.md](deployment-journal.md) + [deployment-tasks.md](deployment-tasks.md).
- **Phase 1.5 network redo is MID-CUTOVER (2026-08-31):** switch + APs reset + `.pub`/`.rsc` re-rendered (flash/ fix, HD-304); router on new design after 3 reset attempts (HD-301/303 fixes committed); **switch reachability re-verify + CAPsMAN import (§1.5.4) + wg-s2s handshake (§1.5.5) still pending**; owner MikroTik password rotation DONE.
- **wg-s2s BLOCKED on HD-306** (VPS systemd-networkd peer never binds) — the current #1 next item; research candidates + fallback in [todo.md HD-306](todo.md).
- **Vault state:** all items present under `check-vault-items.sh --strict` (needed 8, in vault 84), except the tailnet-sidecar preauth items `tailscale_dsh_api`/`tailscale_pi_dev_api` which are **MISSING until the HD-268c owner enable-flow runs** (mint preauth keys → seed 1P → flip flags → scoped converge).
- **ID registry:** next free = max(HD)+1 in [todo.md](todo.md) — always re-derived at write time (CONVENTIONS §1/§4); NEVER type a literal.
- **Coordination:** headplane/headscale = SEPARATE lane (D) — coordinate, never fold into other converges.

## 3. Next-session execution order (pointers — row bodies in todo.md)

### 3-N. NEXT (priority order)

1. **HD-306 — VPS wireguard peer-bind research (blocker for wg-s2s).** Root-cause why the netdev doesn't bind (`ip link add` test, `journalctl -b -u systemd-networkd`, kernel quirk, fallback `wg setconf` oneshot); then `--tags wireguard` + verify handshake both sides + ping wg-s2s peer IPs (SSOT `wg-s2s` row). · [todo.md HD-306](todo.md) · [roles/wireguard/](IaC/ansible/roles/wireguard/)
2. **Phase 1.5 cutover remainder (operator + AI):** switch reachability re-verify from the laptop after the converge-.rsc imports; CAPsMAN `/import capsman_steady-state.rsc` (§1.5.4); ride a `router.yml`/`switch.yml` re-converge to confirm the 8 fixes hold; parked `validate-routeros7-syntax` linter stays parked (post-cutover HD). · [deployment-manual.md](deployment-manual.md) §1.5 · [todo.md HD-304](todo.md) · [deployment-tasks.md](deployment-tasks.md) §Phase 1.5
3. **HD-299 — Technitium primary → VPS** (new `dns-servers` overlay, 3-instance DNS HA, split-horizon static A records for plain `*.kogler.si` on tailnet). ⏳ IaC work + owner RB4011 forwarder step. · [todo.md HD-299](todo.md) · [docs/network-dns.md](docs/network-dns.md) line 18/67
4. **HD-296 + HD-297 — tailnet subdomains + traefik-tailnet clean URLs (dsh/pi).** (a) IaC CLOSED; (b) DEPLOY + (c) DEPLOY-VERIFY owner-side (scoped headscale converge, then full vps.yml converge for `tailnet-apps` overlay; `dig`/`curl` checks). · [todo.md HD-296](todo.md) + [todo.md HD-297](todo.md) · [changelog.md](changelog.md) HD-296/297
5. **HD-268c owner enable-flow (tailnet sidecars live).** Mint preauth keys → seed 1P `tailscale_dsh_api`/`tailscale_pi_dev_api` → flip `*_tailnet_sidecar_enabled` → scoped converge → verify UIs. 4-step flow documented in `group_vars/vps.yml`. · [todo.md HD-268](todo.md)
6. **HD-264 Renovate sandbox (owner).** (a) commit versioned manifest + `renovate.json` to `domen/test`; (b) external re-launch timer; (c) verify PR lands; (d) flip `RENOVATE_REPOSITORIES` → `domen/homelab` (LAST). · [todo.md HD-264](todo.md) · [docs/deployment-renovate.md](docs/deployment-renovate.md)
7. **HD-298 — pi-dev `pty.node` crash-loop fix** (remove `--ignore-scripts` from the pi-web-ui line only; verify `wget http://pi-dev:8080/` → 200). Laptop-doable, 1-line template edit. · [todo.md HD-298](todo.md)
8. **Audit-fold owner actions (from the merged audit):** HD-280 fail2ban (add traefik accesslog + filter, or drop http-auth jail) · HD-288/289 sunshine owner-decision + port binding · HD-292 VPS `docker image prune` · HD-294 drop §8.4 refs when HD-263 closes · HD-286 vault-escape template comments. Row bodies carry owning docs. · [todo.md](todo.md) §§2.4/2.8
9. **Metabase gates (PARTIAL DONE):** HD-241 SMTP *Send test email* + invite flow; HD-242 connect both sources + import dashboards + SELECT-only proof. · [todo.md HD-241](todo.md) + [todo.md HD-242](todo.md)
10. **AI stack pre-deploy gates:** HD-105 secrets + OIDC providers (blocks HD-100..104); then HD-101 SSO verify ride-along, HD-102 PGVector db item + extension, HD-103 docling, HD-104 openclaw onboard. · [todo.md HD-100..105](todo.md) · [docs/deployment-ai-stack-secrets.md](docs/deployment-ai-stack-secrets.md)
11. **HD-112 Zipline go-live legs** (first deploy human-gated; post-up seeding runbook in compose header; family drop script). · [todo.md HD-112](todo.md)
12. **HD-252 pending cleanup (owner):** nodes list EMPTY — re-enroll laptop + phone via the now-working OIDC flow under `domen@kogler.si`. · [todo.md HD-252](todo.md)

> **Handoff diff-rule (CONVENTIONS §4):** this handoff is edited from #43's — every prior §2/§3 open item above either appears or is explicitly resolved (closed items moved to changelog/journal only). **Derived-values ban:** next-free HD quoted from todo.md, never typed.

## 4. Working rules (binding)

Fresh worktree per session BEFORE any edit — mechanically enforced (`bash scripts/guard-session.sh`; `validate-all.sh` hard-fails primary+main+DIRTY); merge back only committed+green, ff-only; primary = merge station only. 9P gate before every converge; surgical `--tags docker_services -e docker_services_scope=<svc>`; secrets 1P-item.field only + `>-` for YAML; persisted Authentik tokens always `expiring=False` (HD-216); journal append-only; owning doc + changelog row in same change; English; relative links; Authentik blueprint pin array attrs (HD-231); don't touch headplane/headscale unless asked. No multi-line bash heredocs with backslashes/backticks — write+run temp script files instead.