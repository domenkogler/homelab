# `strata_draft.md` — draft brief: `strata-iq4xs`, the GGUF engine on the existing spark

> **Role:** the brief a **certification window** picks up if and when the arm this file describes can
> boot. It records the rulings being executed, the facts as they were **verified against primary
> sources** (each with the read that produced it), the arithmetic, what the authored profile can and
> cannot do today, the stop conditions, and what is owed before a window may open. It is a **draft
> plan, not a decision log**.
> **Linked from:** [`docs/spark-llm-profiles.md`](docs/spark-llm-profiles.md) (the `strata-iq4xs` catalogue
> row and its nomenclature row) — the queue row this lane owes does not exist yet (see §8).
> **Authority: none.** `docs/spark-llm-profiles.md` owns the catalogue and the arithmetic;
> `spark/llm-profiles/README.md` owns the gate ladder; `docs/hardware-spark.md` owns the memory budget;
> `CONVENTIONS.md` §7 owns what a pin is. Where this page disagrees with one of them, that page is
> right and this one is the defect.

---

## 0. The rulings this draft executes

| # | Ruling | Where it lands permanently |
|---|---|---|
| S1 | **A new profile is authored on the EXISTING spark hardware.** No second box, no added memory, no part swap. The arm competes with the live `fast` lane for the same 121.63 GiB unified pool and can never co-run with it | `IaC/ansible/group_vars/spark.yml` `spark_llm_profiles.strata-iq4xs` |
| S2 | **An empty pin on a catalogue key IS the refusal** (owner, this window): the arm lands as a real, reviewed, **gated** profile rather than as a draft with no key, because in this repo a key that renders honestly and cannot boot is the correct state (`bz-v33-*` is the precedent) | `IaC/ansible/group_vars/all/versions.yml` `spark_strata_image: ""` + the arm's `uncertified_reason` |
| S3 | **The aarch64 RELEASE TARBALL route is documented, not taken.** The vendor's `strata` Terminal installs and supervises an engine component and writes a data dir; running it is a host-install serving shape this repo does not have. Inventing one is a bigger decision than this window owns | this file, §3 and §6 |
| S4 | **The served id is DISTINCT** — `spark/qwen3.8-flash-next-strata` — on the `sg-*` precedent. Keeping the certified lane's id would need an authored `aliases` run-settings file, and the canonical id is exactly what a certified engine must keep unambiguous | the profile's `served_name` + `uncertified_reason` (c) |
| S5 | **Default quant: UD-IQ4_XS-v31 at revision `d9620119`.** Justified from the memory arithmetic in §4, not from taste | the profile's `model_subdir` / `strata_model` / `fixed_cost_bytes`; `spark_strata_weights_revision` |
| S6 | **The container contract is written to the vendor's own documentation** and is marked **validated-only-offline** — it has never executed on any hardware and there is no image to execute it against | the compose template's `strata` branch + the arm's `uncertified_reason` (d) |
| S7 | **No `HD-` id is minted by this draft.** If a queue row is wanted, the row and its id are owed to the owner (§8) | — |

---

## 1. The headline, and it is one upstream fact

**There is no aarch64 image, so this arm cannot boot, and no configuration change can alter that.**

Read on the registry itself (`ghcr.io/niko1221/strata`, anonymous pull token, then
`GET /v2/niko1221/strata/manifests/<tag>` with the OCI/`docker-content-digest` headers):

* `v0.2.11-cuda13` resolves to the single manifest
  `sha256:871e1e79c063b240184b08075ba0676b6cd2585eac11f76a9d179f4739d2c857` — 9 layers,
  858,779,762 B, **no manifest list**;
* its config blob says `architecture: amd64`, `os: linux`, label
  `com.strata.engine=0.1.57-linux-x86_64-cuda-cuda13`;
* **all 46 tags on that repository are single `amd64/linux` manifests** — `0.2.1` → `0.2.11`, every
  flavor (`cuda12`, `cuda13`, `rocm-gfx120x`, `rocm-gfx110x`, `rocm-gfx1151`, `sycl`), plus the
  `latest-*` aliases.

spark is aarch64. A pin is therefore **not available**, and `spark_strata_image` is `""` with the
reading recorded in its comment — which is the designed refusal (CONVENTIONS §7), not an unfinished
pin. The moment an `arm64` manifest exists, the fill is one read plus one digest:

```
docker buildx imagetools inspect ghcr.io/niko1221/strata:<version>-cuda13   # on the box, read-only
```

…and the `linux/arm64` digest it prints is the pin, with the version + the reading recorded in the same
change. ⚠ The x86_64 digest above must never be pinned: a pulling host would take an amd64 image and the
container would exit at the entrypoint, not at the gate.

---

## 2. What Strata is, verified

| fact | value | how it was read |
|---|---|---|
| repository / licence | `Niko1221/Strata`, **MIT** | `api.github.com/repos/Niko1221/Strata` (`license.spdx_id`) |
| release | **`v0.2.11`**, published `2026-11-05T12:49:59Z` | `/releases` (first non-draft entry) |
| release commit | `v0.2.11` → tag object `4a4160162e4a…`; the tree read below is at `c3b3f5035506` | `/git/ref/tags/v0.2.11` + `/tags` |
| engine component in the image | `0.1.57-linux-x86_64-cuda-cuda13` | the image config's `com.strata.engine` label |
| aarch64 artifact that DOES exist | `strata-engine-0.1.57-linux-aarch64-cuda-cuda13.tar.gz`, 659,232,889 B, `sha256:b871dac15d161696e23625c70026a7f360533751d1dd43be0198ef078679ef8e`; control `strata-control-0.1.57-linux-aarch64.tar.gz`, 83,864,826 B, `sha256:5b4d75b6bc23749fe8140e82db80167d65d17c25a1b42e4f80edd1ee3828fc67` | `/releases` asset digests |
| API surface | `POST /v1/chat/completions`, `/v1/messages` (Anthropic), `/v1/responses`, `/v1/messages/count_tokens`; `GET /v1/models` + `/models`, `/props`, `/slots`, `/metrics`, `/metrics/prometheus`, `/v1/status`, `/health`; `POST /v1/load`, `/v1/unload`, `/v1/vram`, `/v1/images/generations` | `serve/server.py` at `c3b3f5035506` (the module docstring, the `do_GET`/`do_POST` dispatch) |
| default port | **8080** (`Env PORT=8080`, `EXPOSE 8080`, `EXPOSE 8080` in the Dockerfile) | the image config blob + `docker/Dockerfile` |
| bearer handling | `Authorization: Bearer <key>` **or** `x-api-key`; `_authorized()` is consulted on every read path **except** `/health` | `serve/server.py` `_authorized()` / the `/health` branch |
| served id | `svc.model` plus a config-file `aliases` list (`set_aliases`); the entrypoint passes **no** alias flag | `serve/server.py` `model_for`/`model_names`/`set_aliases`; `docker/entrypoint.sh` |
| container contract | `tini` PID 1 → `/opt/strata/entrypoint.sh` → `strata launch --no-tui`; `VOLUME ["/data"]`; `STOPSIGNAL SIGTERM`; `HEALTHCHECK … --start-period=2h` polling `/v1/models` WITH the key | `docker/Dockerfile`, `docker/entrypoint.sh`, `docker/healthcheck.sh` |
| settings vocabulary | `MODEL`, `FAMILY`, `MODEL_PATH`, `CONTEXT`, `PARALLEL`, `KV`, `VISION`, `PORT`, `PRESET`, `GPU`/`GPUS`, `TUNE`, `API_KEY`/`API_KEY_FILE`, `STRATA_SET` | the vendor's `DOCKER.md`, the Settings table (all environment variables) |
| layout constraint | `MODEL_PATH` must name **the folder holding one set's shards**, not a parent — the launcher then stops and says which sub-folder to name | `docker/entrypoint.sh` (the `MODEL_PATH` guard) |
| launcher defaults that matter | context defaults to **131,072** and warns above **262,144** ("more than the model was trained on (256K)"); `TUNE` defaults to `skip` | `strata_control/default_context.py` (`DEFAULT_CONTEXT = 131072`), `strata_cli/launch/settings.py` `check_context` |
| what the image does NOT ship | **no `curl`** — only `tini ca-certificates libgomp1 libatomic1 libnuma1 zlib1g` plus its own bundled CPython at `/opt/strata/terminal/python/bin/python3` | `docker/Dockerfile` (the `apt-get install` list) |
| memory planning | the launcher sizes the pool from the whole machine (`gpu_fit.py`: `DENSE_GB 5.0`, `SYSTEM_ROOM_GB 10.0`; `default_context.py`), and its own docs say "Do not put a memory limit on the container" | `strata_control/gpu_fit.py`, `strata_control/default_context.py`, the vendor's `DOCKER.md`, Troubleshooting |

The 0.2.11 release notes are also where the weights claim comes from: *"On 11-04 Unsloth re-uploaded its
Qwen3.8-Flash-Next GGUFs ("Dynamic v3.1") … Each file is checked by size and SHA-256 against Unsloth's
revision **d9620119**"* — and they name the sets Strata downloads/prepares: UD-IQ1_M, UD-Q2_0, UD-IQ2_XS,
UD-Q2_K_XL, UD-IQ3_XXS, UD-Q3_K_XL, **UD-IQ4_XS-v31**, while UD-Q4_K_XL / UD-Q5_K_XL / UD-Q6_K_XL / Q8_0
keep the 09-30 files (the 11-04 UD-Q4_K_XL split is also accepted).

---

## 3. The weights, verified per file

Read from the Hugging Face tree API at the revision, not from a table:
`/api/models/unsloth/Qwen3.8-Flash-Next-GGUF/tree/<rev>?recursive=1`.

**The v3.1 set is `d96201194f103c906994f283f504209dc8d2a10c`** (2026-11-04, "Better UD 3.1 quants"),
which is the revision the vendor's own notes name. The other candidate from the search results,
`38bb39ee9782…`, is the 2026-09-02 revision and still carries the **pre-v3.1** UD-Q4_K_XL split — 4
files / 111,251,309,184 B, against 4 files / 111,334,654,778 B at `d9620119`. **Different bytes**, so the
revision is load-bearing and `d9620119` is the one pinned (`spark_strata_weights_revision`).

| set | files | bytes | GB | last file |
|---|---|---|---|---|
| **UD-IQ4_XS-v31** | 4 | **93,672,359,738** | 93.7 | 28,800,138,432 |
| UD-Q4_K_XL | 4 | 111,334,654,778 | 111.3 | 28,800,138,432 |
| UD-Q5_K_XL | 6 | 158,286,406,650 | 158.3 | 3,320,101,792 |
| UD-Q6_K_XL | 6 | 169,165,382,688 | 169.2 | 14,838,313,984 |
| Q8_0 | 6 | 188,225,033,248 | 188.2 | 34,015,618,784 |
| BF16 (reference) | 8 | 354,029,930,496 | 354.0 | 47,426,022,016 |

These agree with the vendor's own download column to ±0.3 GB, which is the cross-check that the set
names map one-to-one.

**The per-token table is the set's LAST file**, not a separate download: 28,800,138,432 B (28.8 GB),
shared between sets (UD-IQ1_M + UD-IQ2_XS share one; UD-IQ3_XXS + UD-IQ4_XS-v31 share the other).

**The MTP draft head is separate and shared:**

| file | bytes | GB |
|---|---|---|
| `MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf` | 2,786,568,256 | 2.79 |
| `MTP/mtp-Qwen3.8-Flash-Next-shared-BF16.gguf` | 5,227,963,456 | 5.23 |

The arm stages the Q8_0 shared head (`spark_strata_mtp_shared_q8_0_bytes`).

### The documented alternative: the aarch64 tarball route (S3)

The release also publishes `strata-engine-0.1.57-linux-aarch64-cuda-cuda13.tar.gz` and a matching
`strata-control-0.1.57-linux-aarch64.tar.gz`. Those are consumed by the **`strata` Terminal**: it installs
the engine component, writes a data dir (`/data`: `Strata-data/`, `state/`, `install/`, `home/`) and
supervises the engine. Serving that way means running the Terminal **on the host**, outside a container —
a serving shape this repository has never had (every engine it serves is a container with a pinned
image and a rendered argv). Taking that route is a decision about adding a host-install profile shape, not
a pin, and it is the owner's to make. It is recorded here so the next session does not rediscover it as an
easy win.

---

## 4. Why UD-IQ4_XS-v31, and what it costs

Two constraints, and only one of them binds.

### Disk — satisfied by every candidate

Read live from the box (`ssh spark 'df -P -B1 / /mnt/spark_nvme'`):

| mount | free bytes | note |
|---|---|---|
| `/` (`/dev/nvme0n1p2`) | **110,094,852,096** | the container store and the built images live here; the arm stages nothing here |
| `/mnt/spark_nvme` (XFS, `nvme0n1p3`) | **394,994,212,864** | where a `models_root: xfs` profile stages |

The profile stages on **XFS**: 93.67 GB (UD-IQ4_XS-v31) + 2.79 GB (shared MTP Q8_0) = **96.46 GB**, leaving
~298 GB. UD-Q4_K_XL's 111.3 + 2.79 = 114.1 GB would also fit. **Disk does not choose the quant**, so no
candidate is excluded on disk and `/`'s 110 GB is not a term in the decision — it only has to survive the
*image pull*, which is not part of this arm's staging and is not possible anyway (§1).

### Memory — this is what chooses it

The launcher plans from the whole machine: nothing sizes a KV pool from our side, so the budget term is the
**resident** set — the experts it holds in RAM plus dense weights, session state, the draft layer and the
prompt buffers. The vendor publishes that column ("RAM for all experts") per set:

| set | download | experts | RAM for all experts | same top token as Q8_0 |
|---|---|---|---|---|
| **UD-IQ4_XS** | 94 GB | 55 GiB | **~72 GB** | 88.9 % |
| UD-Q4_K_XL | 111 GB | 72 GiB | ~88 GB | 93.1 % |
| UD-Q5_K_XL | 158 GB | 92 GiB | ~108 GB | 94.6 % |
| UD-Q6_K_XL | 169 GB | 102 GiB | ~118 GB | 94.6 % |
| Q8_0 | 188 GB | 120 GiB | ~136 GB | 100 % |

On a unified pool this is the whole argument, and it is a **ceiling** argument rather than a taste one.
`MemTotal` reads **130,594,004,992 B (121.63 GiB)**. The box's recorded rest floor is **11.73 GiB**
(`docs/hardware-spark.md` §The fixed cost, MEASURED), and the global host-floor ceiling built from it is
`spark_llm_device_hold_ceiling_bytes = 113,000,000,000 B`. Adding the launcher's own constants
(`DENSE_GB 5.0`, `SYSTEM_ROOM_GB 10.0`) and the draft head:

| set | resident ≈ | + 5 GB dense | + 10 GB room | + 2.79 GB draft | fits 113.0e9? |
|---|---|---|---|---|---|
| **UD-IQ4_XS-v31** | ~72 | 77 | 87 | 89.8 | **yes — 23.2 GB spare** |
| UD-Q4_K_XL | ~88 | 93 | 103 | 105.8 | yes — but only **7.2 GB** spare |
| UD-Q5_K_XL | ~108 | 113 | 123 | 125.8 | **no** |
| Q8_0 | ~136 | 141 | 151 | 153.8 | **no** (and larger than MemTotal) |

**UD-IQ4_XS-v31 is the largest set whose resident cost leaves the recorded 11.73 GiB rest floor intact with
room to spare**; UD-Q4_K_XL technically fits the ceiling but spends all but 7.2 GB of the margin, on a box
whose whole incident history is global-OOM under a scheme that looked affordable on paper. The declared
`fixed_cost_bytes: 109000000000` is the vendor's ~72 GB column + `DENSE_GB` + `SYSTEM_ROOM_GB` + the draft
head, rounded up — a **DERIVED** figure, labelled as such, and a boot's own plan line is what replaces it.

⚠ Two things this arithmetic does **not** price, stated so nobody reads the margin as free:
* page cache for the 93.7 GB of mmapped GGUF (reclaimable, therefore not held — but it is also why the
  rest floor, not free memory, is the term that matters);
* the 28.8 GB per-token table, which the engine reads per token. It is inside the set's 93.7 GB, and how
  much of it is resident is a **boot-log** fact, not a published one.

---

## 5. What the authored profile can and cannot do today

**Can:** render. It passes the offline gate, the render matrix and the compose validator; it appears in
`spark_llm_profiles` beside every other arm; every render-matrix arm that existed before it is
**byte-identical** to before; it is skipped by every `_`-prefix consumer; and its artifacts (96.46 GB on
XFS) are declared in `spark_artifact_sets.strata-gguf` as **two revision-pinned `files` sets** rather than
one `weights` download, because the repo carries every quant set at once (BF16 alone is 354 GB).

**Cannot:** boot. There is no aarch64 image (§1). The arm's `certified: false` additionally refuses it
without `spark_llm_allow_uncertified: true`, and the empty pin refuses it *before* that — the render prints
`IMAGE-PIN-EMPTY(gated)`, the same shape `bz-v33-*` prints.

**Is marked honestly:** `uncertified_reason` names the empty pin as the whole story, the never-run contract,
the two unresolved contract terms, and the offline-only validation. `certified_evidence: ""`.

### What the container branch does, and what it does not prove

Rendered to the vendor's own documented contract: `tini` → `/opt/strata/entrypoint.sh`; `PORT` from
`spark_engine_port` (NOT the vendor's 8080 — the engine-port indirection is the client contract, and one
number is what keeps the healthcheck, the loopback publish and the edge route agreeing); `FAMILY=unsloth`,
`MODEL=UD-IQ4_XS`, `MODEL_PATH=/model`, `CONTEXT`, `PARALLEL`; `API_KEY` from the **same**
`spark-llm_api` credential the certified lane holds; `/model:ro` (the staged set) and
`<xfs>/strata_data:/data` (the vendor's single writable root); `stop_grace_period: 2m`; and **no
`command:`** — that absence is correct, because the image's own CMD is `run`, which its entrypoint converts
into `strata launch`, and a compose `command:` would replace it.

Three deliberate departures from a copy of the vendor's example, each for a repo invariant:

1. **A `memory_limit: 105G` cage IS declared**, against the vendor's advice. A container able to claim the
   whole 121.63 GiB pool is the incident class the cage exists for. ⚠ The first boot leg of any window
   must test it: on this engine the cgroup kill would be `OOMKilled: true` (host-RSS mmap pages ARE
   charged, unlike GPU pages), which is the one OOM this box reports honestly.
2. **The healthcheck does not use `curl`.** The image ships none (§2), so a `curl` test would report
   `unhealthy` forever on a working engine — the failure mode that gets a real check muted. It uses the
   image's own bundled CPython against `/health`, which answers without a key. That also means the check
   proves the server is UP, not that the model loaded.
3. **The shared MTP head is staged but NOT bind-mounted.** The vendor documents no variable pointing the
   launcher at a draft layer outside `/data` (its own prepared layer lives at
   `/data/Strata-data/mtp/rt`). A bind would name a path nothing upstream reads, so wiring it is an **owed
   act** (§7), not a guess.

None of this has executed. There is no image to execute it against.

---

## 6. Stop conditions

Stop and report — do not work around — on any of these:

1. **`spark_vllm_fast_v33_image` / `spark_vllm_fast_v33_tag` need an edit.** That lane is another
   worker's; this change touches neither, and a change that would need to is a collision, not a fix.
2. **Any edit under `roles/spark-profile-fast-v33/**`.** Same reason.
3. **`spark_llm_profile` moving off `fast`.** The active profile is `fast` and stays `fast`; this arm is
   gated and nothing in this change flips anything.
4. **`/` dropping under ~80 GB.** A sibling lane's v33 rebuild moves `/`; the arm stages on XFS so its own
   artifacts are safe, but the image store lives on `/`. Below ~80 GB the read is not "tight", it is the
   state where a pull stops being arithmetic.
5. **Any memory floor lowered or ceiling raised.** `spark_llm_pool_ceiling_bytes` (16 GiB),
   `spark_llm_device_hold_ceiling_bytes` (113.000e9) and `spark_llm_os_min_free_bytes` (150e9) are
   certifications, not knobs. This arm declares its own `fixed_cost_basis` and nothing else moves.
6. **A prune of any staged set.** `spark-artifacts` only writes; a set another profile names is not spare
   bytes.
7. **Converging, building, booting, restarting anything.** IT IS OUT OF SCOPE for this change and stays out
   of scope until an image exists. Read-only `ssh` is the whole of the permitted box contact.
8. **Inventing a digest, a pin, an alias config, or an `HD-` id.** Each of those is a claim nobody measured
   (§7 lists the real ones).

---

## 7. What is owed before a certification window

In cost order, because the cheapest first is the only order that survives contact with a queue:

1. **An aarch64 image from upstream** — the single blocker. Nothing else in this list can be tested
   without it. Track it against `ghcr.io/niko1221/strata`; when an `arm64/linux` manifest appears, fill
   `spark_strata_image` with that digest (never the x86_64 one) and say in the same change how it was read.
2. **The served id decision** — either accept `spark/qwen3.8-flash-next-strata` as the arm's permanent id,
   or author an `aliases` run-settings file under `/data` so the engine answers the canonical
   `spark/qwen3.8-flash-next`. The second is new rendered config (a run-settings file the launcher reads),
   not a flag, and it belongs to whoever owns the client contract.
3. **The window question** — our client contract promises 262,144; the launcher warns above 256K and
   defaults to 131,072. The arm declares 262,144 and renders `CONTEXT=262144` so a boot would **measure**
   the disagreement. Someone must decide whether 262,144 is served (and defended with a real read) or the
   client window moves — and moving the certified lane's window is not an option.
4. **The MTP wiring** — the head is staged; the route that makes it the launcher's draft layer is not
   authored (§5.3). It may simply be "let the launcher prepare its own under `/data`", in which case the
   staged artifact is evidence rather than input — a decision, then one line.
5. **Gates 0–7 of `spark/llm-profiles/README.md`** — all of them, unrun. No number in this draft is a
   measurement of this engine on this box, and gate 7 is what falsifies the DERIVED `fixed_cost_bytes`.
6. **A `todo.md` row + its `HD-` id.** This draft mints none (§8).

The offline gate's `strata_verdicts()` in `scripts/gate/check_spark_llm_gate.py` is **unexercised by a
real boot**: it carries canaries for every invariant it grades, but nothing in it has ever seen a running
engine — the arm gates on the empty pin before any of it matters. Its canaries are the only evidence it
has, and they are evidence about the function, not about the engine.

Not owed, and worth stating because it looks owed: a `-rejected.md` row. Nothing here is a rejected
alternative — the arm is gated on an upstream artifact, not refused by a decision.

---

## 8. The queue row and its id are owed

This draft carries **no `HD-` id**, deliberately (S7). Minting one here would be a draft that invents a
pointer: `CONVENTIONS.md` §4 makes the next id `max(HD)+1` **in `todo.md` at the commit that writes the
row**, and a number typed into a brief is the exact shape that goes stale (the reason
`fast_v33_draft.md` §9 states the rule). What a row would say, if the owner wants one:

> spark: the GGUF engine (`strata-iq4xs`) is authored and gated on one upstream fact — the vendor
> publishes no aarch64 image. ⏳ Fill `spark_strata_image` when an arm64 manifest exists; then settle the
> served id + the 262,144 window, wire (or drop) the staged MTP head, and run gates 0–7.

The row is the owner's to create. Until it exists, the arm's state is the
`docs/spark-llm-profiles.md` catalogue row plus the IaC comments that rendered it, and this file is the
working detail behind them — `CONVENTIONS.md` §4's housekeeping rule does not bind a file that carries no row.

---

## 9. What this draft deliberately does not do

* It does not restate the gate ladder, the memory-budget arithmetic or the client contract — those are
  `spark/llm-profiles/README.md`, `docs/hardware-spark.md` and `docs/spark-llm-profiles.md`, and a re-typed
  copy is a second source.
* It does not re-derive any ruled question: the `sg-*` grid, the `fast-v33-*` pair, the never-evict pin and
  the fp8-KV lineage list all stay where their rulings live.
* It does not open an `Options` section. The arm has no open design question — it has one upstream blocker
  and a list of owed acts.
* It states no dated event. The dates in §2 are artifact identities (a release timestamp, a commit date),
  which is why they are facts and not history.
