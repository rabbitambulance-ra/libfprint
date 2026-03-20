#!/usr/bin/env python3

import logging
import os
import sys
from binascii import hexlify, unhexlify
from struct import unpack
from time import sleep

from usb import core as usb_core

from validitysensor import init
from validitysensor.sensor import (
    sensor,
    RebootException,
    CaptureMode,
    get_prg_status,
)
from validitysensor.tls import tls
from validitysensor.usb import usb, Usb, CancelledException
from validitysensor.util import assert_status


def patch_usb_open_dev():
    def open_dev_without_set_configuration(self, dev):
        if dev is None:
            raise Exception("No matching devices found")

        self.dev = dev
        self.dev.default_timeout = 15000

    Usb.open_dev = open_dev_without_set_configuration


def patch_vfs0090_capture():
    original_capture = sensor.capture

    def capture_vfs0090(mode):
        if sensor.device_info.type != 0xDB:
            return original_capture(mode)

        effective_mode = CaptureMode.ENROLL if mode == CaptureMode.IDENTIFY else mode
        assert_status(tls.app(sensor.build_cmd_02(effective_mode)))

        try:
            start = usb.wait_int()
            if start[0] != 0:
                raise Exception(f"wait_start: Unexpected interrupt type {hexlify(start).decode()}")

            while True:
                finger = usb.wait_int()
                if finger[0] == 2:
                    break

                if finger[0] == 3 and finger[1] == 0x20 and finger[2] == 0x07:
                    raise Exception(
                        f"identify program stalled with interrupt {hexlify(finger).decode()}"
                    )

            while True:
                status = get_prg_status()
                print(f"capture status: {hexlify(status).decode()}")
                if status[0] in [0, 7]:
                    break
                sleep(0.2)

            res = tls.app(unhexlify("5100200000"))
            print(f"stop response: {hexlify(res).decode()}")

            while True:
                done = usb.wait_int()
                print(f"done interrupt: {hexlify(done).decode()}")
                if done[0] != 3:
                    raise Exception(f"Unexpected interrupt type {hexlify(done).decode()}")
                if done[1] == 0x43:
                    break

            assert_status(res)
            payload = res[2:]
            if len(payload) < 4:
                print(
                    f"short stop payload after status, skipping geometry parse: {hexlify(payload).decode()}"
                )
                return 0, 0, 0, 0

            (length,), payload = unpack("<L", payload[:4]), payload[4:]
            if length != len(payload):
                print(
                    f"response size mismatch, skipping geometry parse: expected {length}, got {len(payload)}"
                )
                return 0, 0, 0, 0

            if len(payload) < 12:
                print(
                    f"payload too short for geometry parse, skipping: {hexlify(payload).decode()}"
                )
                return 0, 0, 0, 0

            x, y, w1, w2, error = unpack("<HHHHL", payload[:12])
            if error != 0:
                raise Exception(f"Scanning problem: {error:04x}")

            return x, y, w1, w2
        finally:
            try:
                tls.app(unhexlify("04"))
            except Exception:
                pass

    sensor.capture = capture_vfs0090


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run this script as root.")

    logging.basicConfig(level=logging.DEBUG)
    usb.trace_enabled = True
    tls.trace_enabled = True
    patch_usb_open_dev()
    patch_vfs0090_capture()

    try:
        init.open()
    except RebootException:
        print("Sensor rebooted during init; rerun the script.")
        return 0

    print("Identify test started. Touch the sensor once and wait.")

    def update_cb(exc):
        print(f"identify retry: {exc}")

    try:
        usrid, subtype, hsh = sensor.identify(update_cb)
        print(f"identify success: usrid={usrid} subtype=0x{subtype:02x} hash={hsh.hex()}")
        return 0
    except usb_core.USBError as exc:
        print(f"USB error: {exc!r}")
        return 1
    except Exception as exc:
        print(f"identify failed: {exc!r}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
