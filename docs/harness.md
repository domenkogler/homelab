---
title: Harness — Coding-Agent Seats (domain hub)
role: index
domain: harness
status: active
tags: [harness, pi, agent-harness, seats, tmux, llm]
---
# Harness — Coding-Agent Seats

> **Role:** Index — the **`harness` domain hub**: the coding-agent harness the operator actually works
> *in*, on the operator seats. The domain's host-class is **operator seats**, not a service host — what
> deploys together here is a **plane set** ([`../scripts/lib/seat-planes.yml`](../scripts/lib/seat-planes.yml)),
> never a `docker_services` catalog. This page decides **placement** (which doc owns which harness
> subject) and the naming rule that keeps the host `pi` and the harness `pi.dev` apart; every number,
> mechanism and measurement stays in the docs it is owned by, linked below.
> **Links to:** `harness-pi-engines.md`, `harness-pi-models.md`, `harness-pi-seats.md`,
> `harness-pi-seat-identity.md`, `harness-pi-terminal.md`, `harness-review.md`, `harness-rejected.md`,
> `hardware-spark.md`, `spark-llm-profiles.md`, `hardware-workstation.md`, `services-ai.md`,
> [`../scripts/README.md`](../scripts/README.md)
> **Linked from:** `index.md`, `harness-pi-engines.md`, `services.md`

---

## What this domain is — and what it is not

- **The harness is the client side of the AI stack**: the agent, its model contract, its settings, its
  seat planes and the terminal it runs in. The **engine** it calls is a different domain — vLLM args,
  KV-pool governance and profile certification are owned by [`hardware-spark.md`](hardware-spark.md) and
  [`spark-llm-profiles.md`](spark-llm-profiles.md). Direction of truth is **engine → harness, never the
  reverse** ([`harness-pi-engines.md`](harness-pi-engines.md) §1).
- **A coding harness is not a service.** Harnesses reach the engine **directly** at the spark name edge —
  the consumption boundary is decision #26 in [`services-ai.md`](services-ai.md) §9, and the parked
  `dsh` / `pi-dev` catalog entries (`enabled: false`, kept so the port contract survives a re-onboarding)
  are recorded there. Nothing in this domain is Ansible-converged as a container: the seat planes are
  converged by [`../scripts/harness/pi-seat-sync.sh`](../scripts/harness/pi-seat-sync.sh), from each seat's
  own clone.
- **Domain, not a cross-cutting doc.** [`../CONVENTIONS.md`](../CONVENTIONS.md) §8.4 would allow an
  unprefixed concern doc (`security.md`, `backup.md` shape); the domain wins because harness candidates
  already carry a reject history, which a cross-cutting doc has no decision log of its own to hold. The
  host-class wording that licenses a seat-class domain is the **seat-class domain** bullet in
  [`../CONVENTIONS.md`](../CONVENTIONS.md) §8.1.

---

## Seats — the host-class

| Seat | What it is | How it is converged |
|------|-----------|--------------------|
| `win11` — "Win11 workstation seat" | The Windows half of the admin laptop: the leg that **draws** the glyphs and runs the terminal the operator looks at | The driver's `win11` leg is this shell on the Windows workstation; its font leg is [`../scripts/harness/win/install-nerd-font.ps1`](../scripts/harness/win/install-nerd-font.ps1), and the tmux plane does not apply — the terminal is Windows' own |
| `wsl` — "Debian-on-WSL seat" | The WSL Debian clone on the same machine: retained, rarely used, still named by the fan-out so it reports `UNREACHABLE`/drift honestly instead of vanishing | [`../scripts/harness/install-pi-wsl.sh`](../scripts/harness/install-pi-wsl.sh) from zero; the driver reaches it through `wsl.exe` |
| `oldsrv` — "oldsrv cockpit seat" (account `domen`) | A Debian seat that renders the model contract locally and serves the harness's own web front-end | [`../scripts/harness/install-pi-debian.sh`](../scripts/harness/install-pi-debian.sh) (`--cockpit` adds the cockpit package); the driver's `oldsrv` leg uses the seat-local `oldsrv-domen` alias, which exists in the workstation's ssh config |

Three seats, two in daily use; which one is which, why the WSL seat stays in the list, and why a run **on**
oldsrv reports every leg `UNREACHABLE` by design: [`harness-pi-seat-identity.md`](harness-pi-seat-identity.md) §5a. One command fans
every plane out to every seat and **fails** on an unreachable one — the driver, its plane registry and its
verdict vocabulary are registered in [`../scripts/README.md`](../scripts/README.md) §`scripts/harness/`.

**Planes**, not hosts, are the unit of deployment. The set is declared ONCE in
[`../scripts/lib/seat-planes.yml`](../scripts/lib/seat-planes.yml) and read by all three seat readers;
each record also carries a `harness:` axis (`pi` for pi-only planes, `all` for the ones that hold for any
harness) so the next harness is a row there and not a restructure here.

---

## Placement map — where each harness subject is owned

| Subject | Owning doc / SSOT |
|---|---|
| Seat × plane matrix, the fan-out driver, the from-zero installers | [`harness-pi-engines.md`](harness-pi-engines.md) §1 · [`../scripts/lib/seat-planes.yml`](../scripts/lib/seat-planes.yml) · [`../scripts/README.md`](../scripts/README.md) §`scripts/harness/` |
| The **model contract** — `models.json`, context window, thinking control, timeouts, the second vendor's block | [`harness-pi-models.md`](harness-pi-models.md) §4 · SSOT [`../scripts/harness/pi/models-spec.yml`](../scripts/harness/pi/models-spec.yml), rendered by [`../scripts/harness/render-pi-config.py`](../scripts/harness/render-pi-config.py) |
| The **settings plane** — harness keys + the package set composed from the pins | [`harness-pi-seats.md`](harness-pi-seats.md) §5 · SSOT [`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json), pins in [`../IaC/ansible/group_vars/all/versions.yml`](../IaC/ansible/group_vars/all/versions.yml) |
| **Seat identity** — what the footer names, the TUI key, the Nerd Font the icons come from | [`harness-pi-seat-identity.md`](harness-pi-seat-identity.md) §5a |
| The **terminal harness** — tmux mouse, OSC 52 clipboard, and why a byte-identical config can still be inert | [`harness-pi-terminal.md`](harness-pi-terminal.md) §5b (harness-**independent**: it is the terminal, not pi, that owns the mouse and the clipboard) |
| Subagent concurrency — how many children the shared engine can actually serve | [`harness-pi-engines.md`](harness-pi-engines.md) §6 + [`orchestration.md`](orchestration.md) §4 (O10–O11) |
| The **engine** behind the harness (vLLM args, KV pool, profile switching, incidents) | [`hardware-spark.md`](hardware-spark.md), [`spark-llm-profiles.md`](spark-llm-profiles.md), [`spark-incidents.md`](spark-incidents.md) |
| The workstation's **client-side legs** (FIM autocomplete, visual judgment) | [`hardware-workstation.md`](hardware-workstation.md) + decision #28 in [`services-ai.md`](services-ai.md) §9 |
| The seat's **ssh alias plane** (lives in `scripts/harness/`, owned elsewhere) | [`network-vpn.md`](network-vpn.md) §The laptop alias contract + [`../ssh/aliases.tmpl`](../ssh/aliases.tmpl) |
| Harness **candidates and rejections** | [`harness-review.md`](harness-review.md) (queue), [`harness-rejected.md`](harness-rejected.md) (decision log, with the seed pointers into the older logs) |

The split above is a **placement decision, now carried by the four split docs**: every harness detail named in the
table is owned by `harness-pi-engines.md` / `harness-pi-models.md` / `harness-pi-seats.md` /
`harness-pi-seat-identity.md` / `harness-pi-terminal.md` (HD-1119a split, 2026-10-18).

---

## The `pi` overload — the naming rule

Two different things in this fleet are called **pi**, and the collision is what makes harness text read
as if it were about a machine:

| Name | It is | Owned by |
|---|---|---|
| **`pi` / `pi.kogler.si`** | the **Raspberry Pi 4 host** — Home Assistant primary, Technitium tertiary, `traefik-ha` edge | [`hardware.md`](hardware.md), [`smart-home.md`](smart-home.md), [`deployment-pi-provision.md`](deployment-pi-provision.md) |
| **`pi.dev` / "the harness"** | the **coding-agent harness** this domain documents | [`harness-pi-engines.md`](harness-pi-engines.md) + the four split docs, this hub |

So: say **`pi.dev`** or **the harness** for the toolchain, **`pi`** only for the host, and never
`pi` + `harness` collapsed into one bare word where a reader could take it for the Raspberry Pi.
`deployment-pi-provision.md` next to a harness doc means the **host** — the name is not ambiguous here,
the prose was.

---

## Related

- [`index.md`](index.md) — the document map and the AI dispatcher this hub is registered in.
- [`harness-pi-engines.md`](harness-pi-engines.md) — the domain's engine-side detail doc (§1/§1b/§2/§3/§6/§7/§8).
- [`harness-pi-models.md`](harness-pi-models.md) — the rendered model contract (§4/§4b).
- [`harness-pi-seats.md`](harness-pi-seats.md) — the settings plane (§5).
- [`harness-pi-seat-identity.md`](harness-pi-seat-identity.md) — seat identity (§5a).
- [`harness-pi-terminal.md`](harness-pi-terminal.md) — the terminal harness (§5b).
- [`harness-review.md`](harness-review.md) / [`harness-rejected.md`](harness-rejected.md) — the
  [`../CONVENTIONS.md`](../CONVENTIONS.md) §8.3 pair.
- [`../CONVENTIONS.md`](../CONVENTIONS.md) §8.1 — the domain/host-class rule that admits a seat-class domain.
