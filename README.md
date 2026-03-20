## Validity Sensor `138a:0090` and `138a:0097` support

This repository contains the `vfs0090` `libfprint` driver and a reproducible Linux runtime workflow for older Validity sensors found in some ThinkPad systems.

The main supported workflows are:

* `138a:0090`: Linux runtime use with `python-validity`, `open-fprintd`, `fprintd`, and PAM once the sensor's paired state is known
* `138a:0090`: one-time Windows-based pairing recovery or paired-state discovery when needed
* `138a:0097`: match-on-sensor enrollment and verification on Linux

If you are using the Linux hardware-matching flow for `138a:0090`, start with [docs/vfs0090-arch-hardware-matching.md](docs/vfs0090-arch-hardware-matching.md).

## What Works

* `138a:0090`: verification, LED control, `fprintd` CLI integration, and PAM-backed authentication once pairing identity and SID mapping are configured
* `138a:0097`: Linux enrollment, verification, LED control, and standard `fprintd` integration

## Important Constraints

* `138a:0097` supports match-on-sensor enrollment directly on Linux.
* `138a:0090` uses a paired-state workflow. Linux does not recreate the Windows pairing from scratch.
* A Windows install, or a Windows VM with USB passthrough, is only needed for pairing-state discovery or recovery. It is not part of the normal day-to-day Linux auth path.
* The machine-specific pairing identity and SID mapping belong in local `/etc` configuration, not in the repository.

## Device Initialization

[`validity-sensors-tools`](https://snapcraft.io/validity-sensors-tools/) can still be useful as a recovery or initialization tool, but it is not part of the normal `138a:0090` day-to-day runtime path once the paired state is already working.

One distribution route for that tool is Snap:

```bash
sudo snap install validity-sensors-tools
sudo snap connect validity-sensors-tools:raw-usb
sudo snap connect validity-sensors-tools:hardware-observe
sudo validity-sensors-tools.initializer
```

Some distros package the same tool differently or do not use Snap. Treat the commands above as one packaging example, not as a universal installation method.

For `138a:0097`, you can also enroll directly in the sensor database:

```bash
sudo validity-sensors-tools.enroll --finger-id [0-9]
```

## Installation Paths

### Arch and CachyOS

This repository ships a replayable local package and helper scripts for the paired-state `138a:0090` hardware-matching flow. Start with [docs/vfs0090-arch-hardware-matching.md](docs/vfs0090-arch-hardware-matching.md).

### Ubuntu and derivatives

Older Ubuntu-based setups used a `tod` driver path. The pairing and sensor behavior described here still apply, but this repository does not currently ship a ready-made Debian or Ubuntu package for the replayable `python-validity` patch flow.

### Other distros

The driver logic is distro-agnostic. What changes is how you package the Python service, where you persist the pairing identity, how you manage the SID mapping, and how you wire PAM.

## Testing

Use `fprintd-list` and `fprintd-verify` after the service is configured. For PAM testing, verify a terminal flow first, then test your display manager or lock screen. For a fingerprint-backed root shell, prefer `sudo -i`; `su -l` is a separate root-auth policy decision.

## Caveats

* This project is not a generic fix for every Validity sensor.
* The `138a:0090` runtime fix depends on the paired-state workflow being configured correctly.
* Package upgrades can overwrite patched Python modules unless you have a replayable install path.
* The repository intentionally avoids storing real pairing identities, SID mappings, or host-specific overrides in tracked files.

## Background

The implementation originally grew out of work by [nmikhailov](https://github.com/nmikhailov/Validity90/) and [uunicorn](https://github.com/uunicorn/python-validity). The current focus of this repository is to keep the `vfs0090` driver usable in a reproducible way on Linux.
