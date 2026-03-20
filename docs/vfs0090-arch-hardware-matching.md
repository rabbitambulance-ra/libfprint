# VFS0090 Hardware-Matching Workflow

This guide covers the `138a:0090` and `138a:0097` Validity sensors commonly found in older ThinkPad systems.

It focuses on the Linux-side hardware-matching workflow used when the sensor has already been paired in Windows and you want Linux to consume that paired state reliably.

## What Was Wrong

The failure mode was not a simple `fprintd` enrollment problem.

The issues were:

1. The sensor was paired against a host identity that the Linux stack did not reproduce correctly.
2. The `python-validity` capture path for `138a:0090` used the wrong scan flow on identify.
3. Some error paths masked the real protocol mismatch behind generic retry behavior.

The fix is to match the pairing identity, use the sensor-specific capture sequence, and keep the Linux runtime configuration replayable after package upgrades.

## Windows VM Role

Use Windows only as a recovery and pairing-state discovery tool.

That means:

* Discovering which host identity the sensor was originally paired against
* Confirming that the paired Windows state still works
* Re-enrolling only if you need to refresh the sensor state

It is not part of the normal Linux authentication path. Once the Linux side is configured, you should not need Windows for day-to-day use.

## Requirements

You need:

* A `138a:0090` or `138a:0097` sensor
* A sensor state that is already paired and enrolled from Windows, if you are using the `0090` hardware-matching flow
* `python-validity`, `open-fprintd`, and `fprintd` or equivalent client tools
* Root access for service overrides and package installation
* A stable USB connection while testing

## Arch/CachyOS-Specific Pieces

The local packaging and replay flow in this repository uses Arch packaging and `systemd` overrides.

That includes:

* A local package that reapplies the Python patches after upgrades
* A `systemd` drop-in for `python3-validity.service`
* A local config file under `/etc` that stores the pairing identity
* Optional PAM helpers for local authentication entry points

If you are on another distro, the same ideas still apply. The file names and package manager commands will change.

## Distro-Agnostic Pieces

The following parts are not Arch-specific:

* The pairing identity must match the host state used when the sensor was enrolled
* `138a:0090` needs the sensor-specific identify path, not the generic scan path
* `138a:0097` can use the match-on-sensor workflow directly
* The Linux runtime needs the same Windows SID mapping that owns the enrolled prints

## Host Identity

The sensor pairing is tied to a host identity.

If the sensor was paired in a VM, keep the VM identity consistent. In practice, that usually means the VM firmware or BIOS serial, not the guest OS product name alone.

Example:

```ini
Environment=PYTHON_VALIDITY_PRODUCT_NAME=<vm-product-name>
Environment=PYTHON_VALIDITY_PRODUCT_SERIAL=<vm-bios-serial>
```

If your pairing came from bare metal Windows, use the real machine identity values from that system instead.

## SID Mapping

`python-validity` needs a mapping from the local Linux user to the Windows SID that owns the enrolled prints.

Example:

```yaml
user_to_sid:
  your-linux-user: S-1-5-21-xxxxxxxxxx-xxxxxxxxxx-xxxxxxxxxx-1000
```

Only map the user that should own the enrolled fingerprints.

## Replayable Install Flow

The goal of the local package and helper scripts is to make the fix easy to replay if an upgrade overwrites the patched Python modules.

The flow is:

1. Bootstrap the local identity config into `/etc/python-validity-vfs0090-fix/identity.env`.
2. Install the local patch package or run the apply script.
3. Keep the `dbus-service.yaml` SID mapping in place.
4. Let the pacman hook or apply script reapply the patches after upgrades.

If you need to reapply manually, the helper scripts in this repository are:

* `scripts/bootstrap-python-validity-vfs0090-config.sh`
* `scripts/apply-python-validity-vfs0090-fix.sh`
* `scripts/revert-python-validity-vfs0090-fix.sh`

## Testing

After deployment, test in this order:

1. `systemctl status python3-validity.service --no-pager`
2. `fprintd-list <your-linux-user>`
3. `fprintd-verify <your-linux-user>`

For PAM testing, verify a terminal auth path first, then test your display manager or lock screen.

For privileged shells, prefer `sudo -i`.

That keeps biometric auth tied to the invoking user. `su -l` authenticates the target account instead, so it is not enabled by default in the broader PAM helper flow.

## Caveats

* This is not a generic upstream `fprintd` fix for every Validity device.
* It is specific to the `138a:0090` and `138a:0097` family and the paired Windows-state workflow.
* Package upgrades may overwrite files under the installed Python `site-packages` directory.
* If a package upgrade replaces the patched modules, the service may regress until the fix is replayed.
* Keep the Windows-enrolled prints intact unless you intentionally want to reset the pairing state.
* Fingerprint for `su` or `su -l` is a separate root-auth policy choice. It requires explicit root-side enrollment or mapping and is not part of the default published flow.

## Upstreamability

The fix is most upstreamable when it is phrased generically:

1. Match the host identity used at pairing time.
2. Use the sensor-specific capture flow that emits the expected interrupts.
3. Avoid hard-coding user-specific identities in the driver.
4. Keep the service configuration in runtime overrides or distro packaging, not in the driver core.

That keeps the change portable across Arch, CachyOS, and other distros while leaving the device-specific handling in the right layer.
