#!/usr/bin/env python3
"""host-info provider: publishes the host machine's battery + online state.

Speaks ODB Provider Protocol v1 (JSONL on stdout). Stdlib only.
"""
import json
import subprocess
import sys
import time

PROVIDER = {"id": "host-info", "name": "Host Info", "version": "1.0.0"}
DEVICE_ID = "this-host"


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def host_battery():
    """Return host battery percent (int) or None, via `pmset -g batt` on macOS."""
    try:
        out = subprocess.run(["pmset", "-g", "batt"], capture_output=True,
                             text=True, timeout=5).stdout
    except Exception:
        return None
    for token in out.replace(";", " ").split():
        if token.endswith("%"):
            try:
                return int(token[:-1])
            except ValueError:
                return None
    return None


def devices_message():
    return {
        "type": "devices",
        "devices": [{
            "id": DEVICE_ID,
            "name": "This Host",
            "manufacturer": "Open Devices Bridge",
            "model": "host-info",
            "entities": [
                {"key": "battery", "kind": "sensor", "device_class": "battery", "unit": "%"},
                {"key": "online", "kind": "binary_sensor", "device_class": "connectivity"},
            ],
        }],
    }


def state_message():
    return {"type": "state", "device": DEVICE_ID,
            "values": {"battery": host_battery(), "online": True}}


def selftest():
    emit({"type": "hello", "protocol": 1, "provider": PROVIDER})
    emit(devices_message())
    emit(state_message())


def run():
    emit({"type": "hello", "protocol": 1, "provider": PROVIDER})
    emit(devices_message())
    while True:
        emit(state_message())
        time.sleep(60)


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        run()
