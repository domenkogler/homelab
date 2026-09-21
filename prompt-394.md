# `prompt-394.md` — Lane brief · VPS hygiene, the Samba auth order, and the two backup/DR docs (HD-394 · HD-360 · HD-402 + HD-103 · HD-49 · HD-238)

> **Role:** one lane for the **VPS-side residue**: containers no converge owns, the Samba↔Authentik-as-LDAP flip whose
> order is safety-critical, the OCR engine decision that must be made by measurement, and the two docs that describe a
> recovery nobody has written. **Wave 4.** Start with [README.md](README.md) §0 → §1 mandatory context →
> [prompt.md](prompt.md) **§4 (orchestrator mode)** → this file → the rows in [todo.md](todo.md) §2.
> **Linked from:** [prompt.md](prompt.md) §2 + §4 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
>
> **Lane contract (orchestrator mode — the authority is [prompt.md](prompt.md) §4, which OVERRIDES parts of
> README §4 and CONVENTIONS §6 at items O1–O8; where §4 is silent, README + CONVENTIONS stand and outrank this
> brief).** One session, one worktree, one branch; the parent creates them (`../homelab-wt-<YYYYMMDD>-<HHMM>` /
> `session/394-vps-<YYYYMMDD>-<HHMM>`). **You hold the VPS converge slot** (O3), plus the **nas** change for row 2's
> flip: one converge in flight per host, detached, **never `--diff`**. Owner gate → **park and continue** (O4): the
> removal verdict and the yearly restore drill are the owner's. Close-out = owning docs + row tails + signed commit +
> `bash scripts/validate-all.sh` green **in this worktree** → **stop**.

## Rows

| # | HD | Action | Gate / note |
|---|----|--------|-------------|
| 1 | **HD-394** | **Container census**: list every running container **without a compose project label**, name what it is, propose removal, and record the verdict table in [docs/services-vps.md](docs/services-vps.md) | Known today: `confident_shamir` (a hand-run `traefik:v3.7.11`, Up since 2026-08-24, no networks/ports/labels) and **`pgvector`** (Up/healthy although Qdrant superseded it). ⛔ **Owner OK before deleting anything** — the row is the census + verdict, the deletion is a separate act. The third sighting (`authentik-ldap`, Up **unhealthy**) is row 2's, not a removal |
| 2 | **HD-360** | Samba auth rides Authentik over LDAP — **the order is the safety property**: declare the provider + `svc_samba` in the Blueprint → mint a fresh `authentik-ldap_bind` token → redeploy the outpost → **then** flip `storage_samba_passdb: ldapsam` on nas → converge → family-drive verify | ⛔ **Never flip before the provider/outpost/token are live** — `smbd` fails hard, and the family drives go with it. Its outpost is also row 1's unhealthy `authentik-ldap` (expired token) — fix them as one story · [deployment-compose.md](deployment-compose.md) §Samba↔Authentik-as-LDAP, [services-authentik.md](docs/services-authentik.md) |
| 3 | **HD-402 + HD-103** | Docling OCR engine, **bench before applying**: confirm the `RapidOcrOptions` adapter actually exposes the PP-OCR `latin` rec model → convert the **same Slovenian scan** with EasyOCR and RapidOCR-ONNX → keep RapidOCR only if quality is ≥ EasyOCR → record the speed delta. That same scan closes HD-103's first-run gate | Language was never the blocker (`latin` includes `sl`); the risks are the **script-grouped** model (~40 languages) regressing on `č ć š ž` vs EasyOCR's dedicated `sl`, and the adapter wiring. CPU bench, no host risk. ⚠ Docling's accelerator set is `auto\|cpu\|cuda\|mps\|xpu` — **no Vulkan/ROCm**, so the RX 7600 is not an option for it. Free lever regardless: `do_ocr=False` for born-digital PDFs |
| 4 | **HD-49** | Add the **Matrix identity/signing + media keys** to the backup policy scope — signing keys are the class where a restore without them means reissue | [backup.md](docs/backup.md); rides row 5's DR framing. Live verify belongs to the owner's drill (HD-191) → **park** it |
| 5 | **HD-238** | Write the **oldsrv → VPS DR runbook for the non-GPU services** into [backup.md](docs/backup.md) as imperative procedure | Runbook = imperative only: no ✅/⏳, no dated narrative, no inlined knowledge — link the owning doc from the step (`check_runbook_purity.py` gates it) |

## ⛔ No-re-decide list

* **Qdrant superseded pgvector** — row 1 documents the survivor, it does not re-open the choice.
* **The OCR question is a bench question** (HD-402), and the decision record for the AI tier is
  [services-ai.md](docs/services-ai.md) §9 + [services-rejected.md](docs/services-rejected.md).
* **`docling` is already Up on the VPS** — this is a model/quality decision, not a deployment.
* **Secrets:** fresh tokens mint into 1P items only, `>-` renders, **never** a printed value (CONVENTIONS §6). The
  blueprint shape is validator-gated (`scripts/validate_blueprints.py`) — change the blueprint and keep it green.

## First action

Do the census **read-only** and completely before proposing anything: `docker ps` with the compose project label
empty, then for each survivor ask *what would break* — that table is the deliverable, and it is also the cheapest
protection against the failure this repo has seen repeatedly (a running thing no converge owns).

## Lane rules (Wave 4 — pair with [`prompt-357.md`](prompt-357.md) only)

* **Owns:** `IaC/ansible/group_vars/vps.yml` **in the docker_services/ports regions you touch**, the **nas** key
  `storage_samba_passdb` and its `group_vars`/`host_vars` region, `IaC/ansible/templates/docker_services/{authentik,docling,navidrome,forgejo}/**`,
  the Authentik **blueprint** files, `scripts/validate_blueprints.py` **if the blueprint shape moves**,
  `docs/{services-vps.md,services-authentik.md,backup.md,services-matrix.md,services-downloads.md,deployment-compose.md}`,
  and **your own `todo.md` rows**.
* **Never touches:** `prompt.md` / `todo-table.md` (O2); `docs/services-admin.md` + `docs/security.md` +
  `templates/docker_services/rustdesk-server/` + **the ports/registry region of `group_vars/vps.yml`**
  ([`prompt-412.md`](prompt-412.md)) — ⛔ **never the same wave as 412**, both want that file and that doc;
  `templates/docker_services/{lan-litellm,litellm,n8n}/**` + `docs/services-ai*.md`
  ([`prompt-384.md`](prompt-384.md)) — ⛔ **never the same wave as 384** either (both converge the VPS);
  `roles/monitoring/**` + `vps.yml --tags monitoring` ([`prompt-420.md`](prompt-420.md)); `roles/router/**` (414);
  the frozen archives and generated `*-generated.md`.
* If a line is genuinely owed in a file you do not own, write it into your row's tail and **name the lane**.

## Acceptance

A census table naming every unlabeled running container with a verdict and (where removal is proposed) the owner's
word attached · the Samba flip landed **in order**, with the outpost healthy *before* the flip and a family-drive
verify after — or the row parked one step short with the exact next command · an OCR verdict with the two conversions
of the **same** scan side by side and the speed delta · the Matrix key scope in the backup policy · the DR runbook
readable as imperative procedure and `check_runbook_purity.py` green · closed rows deleted, others trimmed ·
`bash scripts/validate-all.sh` green **in this worktree** → **stop** ([prompt.md](prompt.md) §4).
