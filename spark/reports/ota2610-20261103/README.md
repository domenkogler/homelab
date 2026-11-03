# ota2610 — the DGX Spark platform update, taken from an externally-served sitting

> **Role:** the evidence directory for one platform act on `spark` (DGX OS OTA "October 2026", `OTA2610`):
> `pre-snapshot.sh`/`pre-snapshot.txt` are the read taken BEFORE the act, and this README carries what the
> vendor update path actually does — read out of the vendor's own scripts on the box, because the update
> door is a button, not a playbook. It states the mechanism and its constraints; it is not a log of the
> sitting (CONVENTIONS §6, §6.4).
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
   `noble-updates`. The promo line ("moves DGX Spark to the 7.0 kernel") is already true here: the box
   runs `7.0.0-1019-nvidia`. What the act really buys is `1019 → 1024`.
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
| **A stale capsule from the previous OTA is still staged** | `/boot/efi/EFI/UpdateCapsule/fwupd-fa5a0e34-….cap`, written 2026-09-14 17:33, while the box has booted 5× since and fwupd history records the EC update as `Success` (2.78.24 → 3.5.8, 2026-09-14 15:32) — the file is spent residue, and `OTA2607`'s highest `torn` item *is* `nvidia-firmware-580-580.159.03` |
| **A failed `kho` boot still boots** | `kho` is disabled by default and the line is additive; `console=ttyS0,921600` is present, so a serial console can intervene — but a PGX has **no BMC**, which makes the owner's presence the actual prerequisite |
| **`multi-user.target` + the headless masks must be re-read, not assumed** | the OTA's `dgx-oobe*` and `dgx-dashboard` packages are graphical-target packages; today the box is `multi-user.target` with the sleep targets masked |
| **Cloud-init can re-take the network** | datasource list already spans `NoCloud` and `/etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg` exists — the new `OEMDATA` datasource is the half to re-read after the boot |
| **The engine is down for the whole act** | reboot + `start_period: 1200s`; `spark-ai`'s compose unit is `enabled`, `docker.service` is `enabled`, so the stack returns on its own. Downstream `litellm`/`lan-litellm` 502 and the pi seats lose their spark lane for the duration |
| **The rollback is the kernel entry, not an image** | the engine image on the box is `sha256:4900c13edab9…` = `spark-rollback:fast`, and both `7.0.0-1019-nvidia` and `6.17.0-1008-nvidia` keep their `/boot` entries |

## 3. `nvidia-spark-run-apt-upgrade-once.service` is NOT this path

That unit runs `apt-get -y full-upgrade` → `reboot` when `linux-modules-nvidia-580-open-nvidia-hwe-24.04`
does not match the running kernel. It cannot fire here: its own latch
`ConditionPathExists=!/var/lib/nvidia-spark-run-apt-upgrade-once/done` is spent (`done` present since
2026-05-24), and the condition was last recorded unmet on 2026-09-17. It is still a **latent** trigger after
this act, because the packages version `1024` while the booted kernel is `1019` — but an unattended
`full-upgrade` that reboots is exactly what the fleet's pin discipline forbids, so the unit is masked rather
than left armed (§4).

## 4. The one repo-owned act the button would strand

`docker-compose@dgx-dashboard.service` re-enables on a `dgx-dashboard` package upgrade and crash-loops on
`10.10.1.40:11000`, which `spark-dashboard`'s Traefik already owns. The role masks it
(`roles/spark/tasks/main.yml`, tag `[spark, docker_services]`) precisely because a mask survives a package
upgrade and a `disable` does not. `pre-snapshot.txt` records the unit as `enabled=masked` and
`/opt/dgx-dashboard` still present — the mask, not the directory, is the guard.

## 5. Files

| file | what it is |
|---|---|
| `pre-snapshot.sh` | the read, as a script: identity, cmdline, GPU/driver, the platform package set, the holds, every unit's enabled/active state, containers with their restart counts, listeners, disk, boot images, fwupd devices, markers |
| `pre-snapshot.txt` | its output at 2026-11-03 12:28 CET, before the act |

Run it as root on the box, from a seat spark does not serve:
`ssh spark 'sudo -n bash -s' < pre-snapshot.sh > pre-snapshot.txt`
