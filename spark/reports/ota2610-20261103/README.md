# ota2610 — the DGX Spark platform update, taken from an externally-served sitting

> **Role:** the evidence directory for one platform act on `spark` (DGX OS OTA "October 2026", `OTA2610`):
> `pre-snapshot.sh`/`pre-snapshot.txt` are the read taken BEFORE the act, and this README carries what the
> vendor update path actually does — read out of the vendor's own scripts on the box, because the update
> door is a button, not a playbook — plus the state it leaves behind, where the package half and the
> firmware half are separate verdicts (§6). It states mechanism, constraints and resulting state; it is
> not a log of the sitting (CONVENTIONS §6, §6.4).
> **Linked from:** [`docs/hardware-spark.md`](../../../docs/hardware-spark.md) §Identity ·
> [`prompt-update.md`](../../../prompt-update.md) Phase 6 · [`todo.md`](../../../todo.md) HD-1206

---

## 1. How the dashboard's "Update Now" button installs

The button is served by `dgx-dashboard-admin` (a root D-Bus service), not by
`nvidia-spark-run-apt-upgrade-once.service`. Its own strings name the mechanism: `apt-get install
--only-upgrade <pkg>`, `RefreshUpdatesCache`, `Auto-upgrading OTA metapackage`, `package upgrade timed out
— no progress for %d seconds`, then the firmware phase (`fwupdmgr refresh` → `fwupdmgr upgrade` → the
`/boot/efi/EFI/UpdateCapsule` directory, 25-minute poll timeout) and finally a reboot.

Three consequences that decide whether the act is safe:

1. **The package set is the box's whole `noble-updates` delta, not the OTA's 149-package metadata list.**
   `apt-get -s install --only-upgrade <every upgradable name>` resolves **284** installs and includes
   `linux-image-7.0.0-1024-nvidia` + `linux-modules-nvidia-580-open-7.0.0-1024-nvidia` from
   `noble-updates`. The promo line ("moves DGX Spark to the 7.0 kernel") describes a box already at 7.0:
   the pre-act kernel was `7.0.0-1019-nvidia`, so what the package half buys is `1019 → 1024` — the value
   §6 records as booted.
2. **The dpkg holds survive it.** The same dry run touches none of `docker-ce*`, `containerd.io`,
   `docker-buildx-plugin`, `docker-compose-plugin` or `alloy`, so the fleet pin set is unmoved and
   Phase 6's `--tags docker` apply stays a separate, later act.
3. **The metapackage upgrades AFTER the packages** (`Auto-upgrading OTA metapackage`), so the two NEW
   packages this box has never carried — `nvidia-spark-grub-kho` (adds `kho=off` to the kernel command
   line) and `nvidia-spark-cloud-init` (NoCloud `OEMDATA` datasource) — land in the same transaction as
   the kernel, and their boot effects appear on the same reboot.

## 2. Constraints the act inherits (each verified on the box, not assumed)

| constraint | read |
|---|---|
| **No LUKS** → the firmware capsule flashes in the clear | `/etc/crypttab` empty, `/dev/mapper` holds only `control`, `lsblk -f` shows no `crypto_LUKS` |
| **The ESP has room for the initrd** | 511 M, 7.4 M used (2 %) — a full ESP is the documented way an ARM upgrade ends unbootable |
| **A stale capsule from the previous OTA was staged before the act** | `/boot/efi/EFI/UpdateCapsule/fwupd-fa5a0e34-….cap`, written 2026-09-14 17:33, and consumed by this act (the directory is empty, §6), while the box has booted 5× since and fwupd history records the EC update as `Success` (2.78.24 → 3.5.8, 2026-09-14 15:32) — the file is spent residue, and `OTA2607`'s highest `torn` item *is* `nvidia-firmware-580-580.159.03` |
| **A failed `kho` boot still boots** | `kho` is disabled by default and the line is additive; `console=ttyS0,921600` is present, so a serial console can intervene — but a PGX has **no BMC**, which makes the owner's presence the actual prerequisite |
| **`multi-user.target` + the headless masks must be re-read, not assumed** | the OTA's `dgx-oobe*` and `dgx-dashboard` packages are graphical-target packages; today the box is `multi-user.target` with the sleep targets masked |
| **Cloud-init can re-take the network** | datasource list already spans `NoCloud` and `/etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg` exists — the new `OEMDATA` datasource is the half to re-read after the boot |
| **The engine is down for the whole act** | reboot + `start_period: 1200s`; `spark-ai`'s compose unit is `enabled`, `docker.service` is `enabled`, so the stack returns on its own. Downstream `litellm`/`lan-litellm` 502 and the pi seats lose their spark lane for the duration |
| **The rollback is the kernel entry, not an image** | the engine image on the box is `sha256:4900c13edab9…` = `spark-rollback:fast`, and both `7.0.0-1019-nvidia` and `6.17.0-1008-nvidia` keep their `/boot` entries |

## 3. `nvidia-spark-run-apt-upgrade-once.service` is NOT this path

That unit runs `apt-get -y full-upgrade` → `reboot` when `linux-modules-nvidia-580-open-nvidia-hwe-24.04`
does not match the running kernel. It cannot fire here: its own latch
`ConditionPathExists=!/var/lib/nvidia-spark-run-apt-upgrade-once/done` is spent (`done` present since
2026-05-24), and the condition was recorded unmet on 2026-09-17. The act removed the condition itself —
packages and booted kernel are both `1024` (§6) — but the unit stays **masked** rather than disarmed by
circumstance: an unattended `full-upgrade` that reboots is exactly what the fleet's pin discipline forbids,
and the next kernel bump recreates the condition (§4).

## 4. The one repo-owned act the button would strand

`docker-compose@dgx-dashboard.service` re-enables on a `dgx-dashboard` package upgrade and crash-loops on
`10.10.1.40:11000`, which `spark-dashboard`'s Traefik already owns. The role masks it
(`roles/spark/tasks/main.yml`, tag `[spark, docker_services]`) precisely because a mask survives a package
upgrade and a `disable` does not. `pre-snapshot.txt` records the unit as `enabled=masked` and
`/opt/dgx-dashboard` still present — the mask, not the directory, is the guard.

## 5. Files

| file | what it is |
|---|---|
| `pre-snapshot.sh` | the read, as a script: identity, cmdline, GPU/driver, the platform package set, the holds, every unit's enabled/active state, containers with their restart counts, listeners, disk, boot images, fwupd devices, markers. Its `--- ota` block is the reason this directory exists: `installed-name` + `torn-score` are what separates an applied platform level from a partially applied one |
| `pre-snapshot.txt` | its output at 2026-11-03 12:28 CET — the **BEFORE** read |

The **AFTER** state is §6 below: that is where the post-act values live, so nothing here has to be diffed
against a capture to be read.

Run it as root on the box, from a seat spark does not serve:
`ssh spark 'sudo -n bash -s' < pre-snapshot.sh > pre-snapshot.txt`

## 6. Post-act state: the package half is at the level, the firmware half is not

The button has two halves and they are not one verdict. The package half reaches the level every time;
the firmware half depends on a feed the OTA's own metadata does not control.

**The package half's post-act state.** Kernel `7.0.0-1024-nvidia`, with `kho=off` on the cmdline — the line
the new `nvidia-spark-grub-kho` (`1.0-1`) adds. `nvidia-spark-cloud-init` (`1.0.2-1`) installed, and
`/etc/cloud/cloud.cfg.d/99-oem-nocloud.cfg` present with `cloud-init status` answering
`disabled-by-generator`, which is the intended state and not a failure. `nvidia-spark-mlnx-firmware-manager`
at `6.0.1-1`, its boot pass done — `inactive dead` with `Result=success` is the correct shape for a
oneshot. `dgx-dashboard` at `0.39.3-5`, listening on `127.0.0.1:11000` and published by `traefik-spark`
on `spark_home_ip:11000` and `:11002`.

**The firmware half's post-act state.** Four components still below what the OTA metadata requires, none
of them flashed:

| component | installed | the OTA metadata requires |
|---|---|---|
| `SOCFW` | `2.155.11` | `2.158.15` |
| `EC` | `3.5.8` | `3.13.7` |
| `EC Unfused` | `3.5.8` | `3.13.7` |
| `USBPD` | `5.22` | `0.5.25` |

**The cause is a vendor-side disagreement, and no local act closes it.** The firmware phase installs
through **LVFS**; `nvidia-spark-ota-check` compares the box against NVIDIA's own required-component list.
LVFS carries none of the four — `fwupdmgr get-updates` answers "No updates available" and names Embedded
Controller `3.5.8` as the newest it has. The phase therefore completes, reports success, and writes no
firmware: §1's mechanism is correct, and this is what it produces when the feed trails the metadata.

**The readings that carry that verdict:**

- `nvidia-spark-ota-check installed-name` answers **`OTA2607`**; `torn` reads **2.6** (it reads `1` in
  `pre-snapshot.txt`); `summary` reports 151/155 checks and `required_satisfied=false`.
- `/boot/efi/EFI/UpdateCapsule/` is **empty** — the stale 2026-09-14 capsule §2 lists is gone from the
  ESP, so that residue no longer exists to be consumed or cleared.
- `/etc/dgx-release` reads `DGX_OTA_VERSION` **7.6.0**. The metapackage level is not the verdict here:
  the firmware checks are, which is why the two disagree.
- Every package-side diff is *newer* than the metadata's requirement (toolkit `1.20.1` over `1.20.0`,
  dashboard `0.39.3-5` over `0.39.3-4`, `libnvidia-egl-wayland1` likewise), so the four firmware rows
  above are the **only** ones that sit behind — a firmware-feed gap, not a package failure.
- UEFI/BIOS is `S0QKT0EA`, release date `2026-07-13`, consistent with an empty capsule directory.

**The boot contract is intact, every check Phase 6 names passing.** `kho=off` in `/proc/cmdline`; the
`nvidia-spark-cloud-init` drop-in present and the generator disabling cloud-init on purpose;
`nvidia-spark-mlnx-firmware-manager` with its boot pass done and exit `0`; `default.target` at
`multi-user.target` with `sleep`, `suspend`, `hibernate` and `hybrid-sleep` all masked;
`spark-gpu-clock-cap.service` active with `Result=success`; `/opt/nvidia/dgx-dashboard-service/
jupyterlab_ports.yaml` still mapping admin → `11002`; `docker-compose@dgx-dashboard.service` still
**masked** — a mask survives the package upgrade, a disable does not (§4);
`nvidia-spark-run-apt-upgrade-once.service` still **masked**, so the skew between the booted kernel and
the installed module packages arms no unattended `full-upgrade`. The dpkg holds are the same set:
`docker` `29.9.2`, compose plugin `v5.7.0`, the containers intact, `/` 162 G and `/mnt/spark_nvme` 184 G
free.

**The QSFP delta is unmoved.** `lspci -nn | grep -ci mellanox` answers `0` at this level, so
§Reality deltas 2 in [`docs/hardware-spark.md`](../../../docs/hardware-spark.md) still holds: the act does
not make the two ports devices.
