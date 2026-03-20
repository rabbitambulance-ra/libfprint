# Validity `138a:0090` and `138a:0097` Linux support

This repository exists for people whose Validity fingerprint reader works poorly, partially, or not at all on Linux, especially:

* `138a:0090` users whose sensor was already paired in Windows and now fails on Linux with initialization, TLS, or runtime auth problems
* `138a:0097` users who need the `vfs0090` driver and Linux-side match-on-sensor support

It contains two things:

* the `vfs0090` `libfprint` driver
* a replayable `python-validity` runtime workflow for `138a:0090`

## Start Here

* `138a:0090`: read [docs/vfs0090-arch-hardware-matching.md](docs/vfs0090-arch-hardware-matching.md)
* `138a:0097`: initialize the device if needed, then enroll and verify through the normal `fprintd` flow

## Why This Exists

`138a:0090` is not just an enrollment problem. On many systems, the real blockers are:

* the sensor is paired against a host identity Linux is not reproducing
* the Linux runtime stack uses the wrong capture path for identify
* upgrades overwrite local fixes unless the deployment is replayable

This repository packages those fixes in a form that can be reused after upgrades and understood by other users hitting the same class of failures.

## Scope

What works here:

* `138a:0090`: verification, LED control, `fprintd` CLI integration, and PAM-backed authentication once pairing identity and SID mapping are configured
* `138a:0097`: Linux enrollment, verification, LED control, and standard `fprintd` integration

What this repository is not:

* a generic fix for every Validity sensor
* a replacement for Windows pairing on `138a:0090`
* a place to store real pairing identities, SIDs, or host-specific overrides

## Windows and VMs

For `138a:0090`, Linux consumes an existing paired state. It does not recreate that pairing from scratch.

Windows, including a Windows VM with USB passthrough, is only useful for:

* recovering a working paired state
* discovering which host identity the sensor was paired against
* confirming that the enrolled sensor state still works

It is not part of the normal day-to-day Linux authentication path once Linux is configured correctly.

## Distro Notes

This repository includes a replayable local package and helper scripts for Arch and CachyOS.

The underlying fix is not Arch-specific. Other distros still need the same core pieces:

* matching pairing identity
* Windows SID mapping for the enrolled prints
* patched `python-validity` runtime behavior for `138a:0090`
* local auth wiring through `open-fprintd`, `fprintd`, and PAM

This repository does not currently ship a Debian or Ubuntu package for that replayable `python-validity` patch flow.

## Initialization

[`validity-sensors-tools`](https://snapcraft.io/validity-sensors-tools/) is still useful as a recovery or initialization tool. It is not part of the normal `138a:0090` runtime path once the paired state is already working.

One packaging route for that tool is Snap:

```bash
sudo snap install validity-sensors-tools
sudo snap connect validity-sensors-tools:raw-usb
sudo snap connect validity-sensors-tools:hardware-observe
sudo validity-sensors-tools.initializer
```

Some distros package the same tool differently or do not use Snap.

For `138a:0097`, direct chip enrollment is also possible:

```bash
sudo validity-sensors-tools.enroll --finger-id [0-9]
```

## Testing

After configuration:

```bash
fprintd-list <user>
fprintd-verify <user>
```

For PAM, test a terminal auth path first, then test the display manager or lock screen. For a fingerprint-backed root shell, prefer `sudo -i`; `su -l` is a separate root-auth policy choice.

## Provenance

This work builds on earlier reverse engineering and prototype work from [nmikhailov](https://github.com/nmikhailov/Validity90/) and [uunicorn](https://github.com/uunicorn/python-validity).
