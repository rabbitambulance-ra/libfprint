#!/usr/bin/env python3

import argparse
import errno
import logging
import os
import sys
import time
from binascii import hexlify

from usb.core import USBError

from validitysensor import init
from validitysensor.sensor import sensor, glow_start_scan, CaptureMode, RebootException
from validitysensor.tls import tls
from validitysensor.usb import usb, Usb
from validitysensor.util import assert_status


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode",
        choices=("identify", "enroll"),
        default="identify",
        help="Scan program to arm before waiting for raw interrupts.",
    )
    return parser.parse_args()


def patch_usb_open_dev():
    def open_dev_without_set_configuration(self, dev):
        if dev is None:
            raise Exception("No matching devices found")

        self.dev = dev
        self.dev.default_timeout = 15000

    Usb.open_dev = open_dev_without_set_configuration


def wait_for_interrupt(label: str, timeout_s: float):
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        try:
            resp = usb.dev.read(131, 1024, timeout=100)
            resp = bytes(resp)
            print(f"{label}: got interrupt {hexlify(resp).decode()}", flush=True)
            return resp
        except USBError as exc:
            if exc.errno == errno.ETIMEDOUT:
                continue
            raise

    print(f"{label}: timed out waiting for interrupt", flush=True)
    return None


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run this script as root.")

    args = parse_args()

    logging.basicConfig(level=logging.DEBUG)
    usb.trace_enabled = True
    tls.trace_enabled = True
    patch_usb_open_dev()

    try:
        init.open()
    except RebootException:
        print("Sensor rebooted during init; rerun the script.", flush=True)
        return 0

    print("Phase probe started.", flush=True)
    mode_name = args.mode.upper()
    mode = CaptureMode.IDENTIFY if args.mode == "identify" else CaptureMode.ENROLL
    print(f"Lighting LED and starting {mode_name} capture program.", flush=True)

    glow_start_scan()
    assert_status(tls.app(sensor.build_cmd_02(mode)))

    try:
        start = wait_for_interrupt("start", 5.0)
        finger = wait_for_interrupt("finger", 15.0) if start is not None else None
        done = wait_for_interrupt("done", 15.0) if finger is not None else None
        print(f"summary: start={start!r} finger={finger!r} done={done!r}", flush=True)
    finally:
        try:
            tls.app(b"\x04")
        except Exception as exc:
            print(f"stop-capture error: {exc!r}", flush=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
