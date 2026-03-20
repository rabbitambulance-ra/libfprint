## Validity Sensor `138a:0090` and `138a:0097` libfprint driver

This repository contains a `libfprint` driver for older Validity sensors found in some ThinkPad systems.

The main supported workflows are:

* Linux runtime use with `fprintd`
* One-time Windows-based pairing or recovery for `138a:0090`
* Match-on-sensor enrollment for `138a:0097`

If you are using the Linux hardware-matching flow for `138a:0090`, start with [docs/vfs0090-arch-hardware-matching.md](docs/vfs0090-arch-hardware-matching.md).

## What Works

* Enrollment
* Verification
* LED control
* The standard `fprintd` CLI and PAM integration

## Important Constraints

* `138a:0097` supports match-on-sensor enrollment directly on Linux.
* `138a:0090` uses a paired-state workflow. Linux does not recreate the Windows pairing from scratch.
* A Windows install, or a Windows VM with USB passthrough, is only needed for pairing-state discovery or recovery. It is not part of the normal day-to-day Linux auth path.

## Device Initialization

The supported Linux-side initializer is [`validity-sensors-tools`](https://snapcraft.io/validity-sensors-tools/).

```bash
sudo snap install validity-sensors-tools
sudo snap connect validity-sensors-tools:raw-usb
sudo snap connect validity-sensors-tools:hardware-observe
sudo validity-sensors-tools.initializer
```

For `138a:0097`, you can also enroll directly in the sensor database:

```bash
sudo validity-sensors-tools.enroll --finger-id [0-9]
```

## Installation Paths

### Arch and CachyOS

If you are using the local hardware-matching flow for a paired `138a:0090` sensor, follow [docs/vfs0090-arch-hardware-matching.md](docs/vfs0090-arch-hardware-matching.md).

### Ubuntu and derivatives

Older Ubuntu-based setups used a `tod` driver path. The exact packaging differs from the Arch flow, but the pairing and sensor behavior described here still apply.

### Other distros

The driver logic is distro-agnostic. What changes is how you package the Python service, how you persist the pairing identity, and how you wire PAM.

## Testing

Use `fprintd-list` and `fprintd-verify` after the service is configured. For PAM testing, verify the terminal flow first, then test your display manager or lock screen.

## Caveats

* This project is not a generic fix for every Validity sensor.
* The `138a:0090` runtime fix depends on the paired-state workflow being configured correctly.
* Package upgrades can overwrite patched Python modules unless you have a replayable install path.

## Background

The implementation originally grew out of work by [nmikhailov](https://github.com/nmikhailov/Validity90/) and [uunicorn](https://github.com/uunicorn/python-validity). The current focus of this repository is to keep the `vfs0090` driver usable in a reproducible way on Linux.
