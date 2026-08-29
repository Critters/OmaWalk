#!/usr/bin/env python3
"""OmaWalk BLE helper: talk to an Unsit treadmill and write daily totals.

Commands:
  scan [--seconds N]              JSON list of nearby ISSC / BM70 devices
  run                             connect, accumulate daily totals, write state
  set-device ADDR [--name] [--adapter]
  set-bar none|steps|distance
  forget
  dump                            print current state.json
"""

from __future__ import annotations

import argparse
import asyncio
import fcntl
import json
import os
import re
import subprocess
import sys
import time
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

STATE_DIR = Path.home() / ".local/share/omawalk"
STATE_PATH = STATE_DIR / "state.json"
LOCK_PATH = STATE_DIR / "state.lock"

SERVICE_UUID = "49535343-fe7d-4ae5-8fa9-9fafd205e455"
NOTIFY_UUID = "49535343-1e4d-4bd9-ba61-23c647249616"
NAME_HINTS = ("bm70", "issc", "unsit", "inmovement")

BAR_DISPLAYS = ("none", "steps", "distance")
MAX_STEPS_PER_SEC = 5


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def today_key() -> str:
    return date.today().isoformat()


def iso_now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def default_state() -> dict:
    return {
        "version": 1,
        "barDisplay": "none",
        "device": None,
        "live": {
            "connected": False,
            "walking": False,
            "speedMph": 0.0,
            "updatedAt": iso_now(),
        },
        "baseline": {"time": 0, "cals": 0, "milesMilli": 0, "steps": 0},
        "days": {},
    }


def normalize_state(raw: dict | None) -> dict:
    state = default_state()
    if not isinstance(raw, dict):
        return state
    if raw.get("barDisplay") in BAR_DISPLAYS:
        state["barDisplay"] = raw["barDisplay"]
    device = raw.get("device")
    if isinstance(device, dict) and device.get("address"):
        state["device"] = {
            "address": str(device["address"]).upper(),
            "name": str(device.get("name") or ""),
            "adapter": str(device.get("adapter") or ""),
        }
    live = raw.get("live") if isinstance(raw.get("live"), dict) else {}
    state["live"] = {
        "connected": bool(live.get("connected")),
        "walking": bool(live.get("walking")),
        "speedMph": float(live.get("speedMph") or 0),
        "updatedAt": str(live.get("updatedAt") or iso_now()),
    }
    base = raw.get("baseline") if isinstance(raw.get("baseline"), dict) else {}
    state["baseline"] = {
        "time": int(base.get("time") or 0),
        "cals": int(base.get("cals") or 0),
        "milesMilli": int(base.get("milesMilli") or 0),
        "steps": int(base.get("steps") or 0),
    }
    days = raw.get("days") if isinstance(raw.get("days"), dict) else {}
    out_days = {}
    for key, val in days.items():
        if not isinstance(val, dict):
            continue
        out_days[str(key)] = {
            "steps": max(0, int(val.get("steps") or 0)),
            "distanceMilli": max(0, int(val.get("distanceMilli") or 0)),
        }
    state["days"] = out_days
    return state


def load_unlocked() -> dict:
    try:
        return normalize_state(json.loads(STATE_PATH.read_text()))
    except FileNotFoundError:
        return default_state()
    except (json.JSONDecodeError, OSError) as exc:
        log(f"state read failed: {exc}")
        return default_state()


def save_unlocked(state: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(state, indent=2) + "\n"
    with open(STATE_PATH, "w", encoding="utf-8") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())


@contextmanager
def locked_state():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with open(LOCK_PATH, "a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        state = load_unlocked()
        yield state
        save_unlocked(state)


@dataclass
class Packet:
    time_s: int
    cals: int
    miles_milli: int
    steps: int
    speed_mph: float
    framed: bool
    raw: bytes


def decode(payload: bytes) -> Packet | None:
    if len(payload) < 13:
        return None
    return Packet(
        time_s=int.from_bytes(payload[3:5], "big"),
        cals=int.from_bytes(payload[5:7], "big"),
        miles_milli=int.from_bytes(payload[7:9], "big"),
        steps=int.from_bytes(payload[9:12], "big"),
        speed_mph=payload[12] / 10.0,
        framed=(
            len(payload) == 16
            and payload[0] == 0x5B
            and payload[1] == 0x0D
            and payload[2] == 0x05
            and payload[-1] == 0x5D
        ),
        raw=bytes(payload),
    )


def list_adapters() -> list[str]:
    root = Path("/sys/class/bluetooth")
    if not root.exists():
        return [""]
    names = sorted(
        p.name
        for p in root.iterdir()
        if re.fullmatch(r"hci\d+", p.name)
    )
    return names or [""]


def bluez_args(adapter: str) -> dict:
    if not adapter:
        return {}
    return {"bluez": {"adapter": adapter}}


def looks_like_unsit(name: str, uuids: list[str]) -> str | None:
    lowered = (name or "").lower()
    for hint in NAME_HINTS:
        if hint in lowered:
            return f"name:{hint}"
    for uuid in uuids:
        if uuid.lower() == SERVICE_UUID.lower():
            return "issc-service"
    return None


def apply_packet(state: dict, packet: Packet) -> None:
    day = today_key()
    days = state["days"]
    if day not in days:
        days[day] = {"steps": 0, "distanceMilli": 0}
    base = state["baseline"]
    first = base["time"] == 0 and base["steps"] == 0
    if first:
        base["time"] = packet.time_s
        base["cals"] = packet.cals
        base["milesMilli"] = packet.miles_milli
        base["steps"] = packet.steps
    d_time = packet.time_s - base["time"]
    d_steps = packet.steps - base["steps"]
    d_dist = packet.miles_milli - base["milesMilli"]
    implausible = d_steps > max(20, d_time * MAX_STEPS_PER_SEC)
    if d_time < 0 or d_steps < 0 or d_dist < 0 or implausible:
        # New session (power cycle / e-stop) or a corrupt/misframed packet. Do not subtract.
        base["time"] = packet.time_s
        base["cals"] = packet.cals
        base["milesMilli"] = packet.miles_milli
        base["steps"] = packet.steps
    else:
        days[day]["steps"] += d_steps
        days[day]["distanceMilli"] += max(0, d_dist)
        base["time"] = packet.time_s
        base["cals"] = packet.cals
        base["milesMilli"] = packet.miles_milli
        base["steps"] = packet.steps
    walking = packet.speed_mph > 0
    state["live"] = {
        "connected": True,
        "walking": walking,
        "speedMph": packet.speed_mph,
        "updatedAt": iso_now(),
    }


def set_disconnected(state: dict) -> None:
    state["live"] = {
        "connected": False,
        "walking": False,
        "speedMph": 0.0,
        "updatedAt": iso_now(),
    }


async def scan_adapter(adapter: str, seconds: float) -> list[dict]:
    from bleak import BleakScanner

    found: dict[str, dict] = {}

    def on_detect(device, adv) -> None:
        name = device.name or adv.local_name or ""
        uuids = list(adv.service_uuids or [])
        reason = looks_like_unsit(name, uuids)
        if not reason:
            return
        rssi = adv.rssi if adv.rssi is not None else -999
        prev = found.get(device.address)
        if prev and rssi < prev["rssi"]:
            return
        found[device.address] = {
            "address": device.address.upper(),
            "name": name or "BM70",
            "rssi": rssi,
            "adapter": adapter,
            "reason": reason,
        }

    scanner = BleakScanner(
        detection_callback=on_detect,
        scanning_mode="active",
        **bluez_args(adapter),
    )
    await scanner.start()
    try:
        await asyncio.sleep(seconds)
    finally:
        await scanner.stop()
    return list(found.values())


async def cmd_scan(seconds: float) -> int:
    adapters = list_adapters()
    log(f"scanning {seconds:.0f}s on {', '.join(adapters) or 'default'}")
    batches = await asyncio.gather(
        *[scan_adapter(adapter, seconds) for adapter in adapters],
        return_exceptions=True,
    )
    merged: dict[str, dict] = {}
    for batch in batches:
        if isinstance(batch, Exception):
            log(f"scan error: {batch}")
            continue
        for row in batch:
            prev = merged.get(row["address"])
            if not prev or row["rssi"] > prev["rssi"]:
                merged[row["address"]] = row
    devices = sorted(merged.values(), key=lambda r: r["rssi"], reverse=True)
    print(json.dumps({"ok": True, "devices": devices}, indent=2), flush=True)
    return 0


async def find_device(address: str, adapter: str):
    from bleak import BleakScanner

    log(f"looking for {address} on {adapter or 'default'}")
    device = await BleakScanner.find_device_by_address(
        address, timeout=8.0, **bluez_args(adapter)
    )
    if device is None:
        raise TimeoutError(f"{address} not advertising on {adapter or 'default'}")
    return device


async def session(client, address: str, adapter: str) -> None:
    last_write = 0.0

    def on_notify(_sender, data: bytearray) -> None:
        nonlocal last_write
        packet = decode(bytes(data))
        if packet is None or not packet.framed:
            return
        with locked_state() as state:
            apply_packet(state, packet)
        now = time.time()
        if now - last_write >= 0.45:
            last_write = now
            print(
                json.dumps(
                    {
                        "event": "packet",
                        "speedMph": packet.speed_mph,
                        "steps": packet.steps,
                    }
                ),
                flush=True,
            )

    with locked_state() as state:
        state["live"]["connected"] = True
        state["live"]["updatedAt"] = iso_now()
        if state.get("device"):
            state["device"]["adapter"] = adapter
    print(json.dumps({"event": "connected", "address": address, "adapter": adapter}), flush=True)
    await client.start_notify(NOTIFY_UUID, on_notify)
    while client.is_connected:
        await asyncio.sleep(0.5)


def bluez_disconnect(address: str) -> None:
    try:
        subprocess.run(
            ["bluetoothctl", "disconnect", address],
            check=False,
            capture_output=True,
            timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass


async def listen_device(address: str, adapter: str) -> None:
    from bleak import BleakClient
    from bleak.exc import BleakDeviceNotFoundError

    kwargs = bluez_args(adapter)
    log(f"connecting {address} via {adapter or 'default'}")
    try:
        async with BleakClient(address, timeout=12.0, **kwargs) as client:
            await session(client, address, adapter)
            return
    except (BleakDeviceNotFoundError, TimeoutError, asyncio.TimeoutError) as exc:
        log(f"direct connect failed ({exc}); dropping stale link and scanning")

    bluez_disconnect(address)
    await asyncio.sleep(0.8)
    found = await find_device(address, adapter)
    async with BleakClient(found, timeout=20.0, **kwargs) as client:
        await session(client, address, adapter)


async def cmd_run() -> int:
    from bleak import BleakError
    from bleak.exc import BleakDeviceNotFoundError

    pid_path = STATE_DIR / "omawalkd.pid"
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        old = int(pid_path.read_text().strip())
        if old and old != os.getpid():
            cmd = Path(f"/proc/{old}/cmdline").read_bytes()
            if b"omawalkd.py" in cmd:
                os.kill(old, 15)
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError, OSError):
        pass
    pid_path.write_text(str(os.getpid()) + "\n")

    log("omawalkd run")
    while True:
        with locked_state() as state:
            device = state.get("device")
        if not device or not device.get("address"):
            with locked_state() as state:
                set_disconnected(state)
            await asyncio.sleep(1.5)
            continue

        address = device["address"]
        adapters = list_adapters()
        preferred = device.get("adapter") or ""
        if preferred not in adapters:
            preferred = ""
        order = []
        if preferred:
            order.append(preferred)
        for name in adapters:
            if name not in order:
                order.append(name)
        if not order:
            order = [""]

        connected = False
        for adapter in order:
            try:
                await listen_device(address, adapter)
                connected = True
            except (BleakDeviceNotFoundError, BleakError, TimeoutError, asyncio.TimeoutError) as exc:
                log(f"{adapter or 'default'}: {exc}")
            except Exception as exc:
                log(f"{adapter or 'default'} unexpected: {exc}")
            if connected:
                break

        with locked_state() as state:
            set_disconnected(state)
        print(json.dumps({"event": "disconnected"}), flush=True)
        await asyncio.sleep(3.0)


def cmd_set_device(address: str, name: str, adapter: str) -> int:
    with locked_state() as state:
        state["device"] = {
            "address": address.upper(),
            "name": name,
            "adapter": adapter,
        }
        state["baseline"] = {"time": 0, "cals": 0, "milesMilli": 0, "steps": 0}
        set_disconnected(state)
    print(json.dumps({"ok": True, "device": load_unlocked()["device"]}), flush=True)
    return 0


def cmd_set_bar(value: str) -> int:
    if value not in BAR_DISPLAYS:
        print(json.dumps({"ok": False, "error": "bar must be none, steps, or distance"}), flush=True)
        return 1
    with locked_state() as state:
        state["barDisplay"] = value
    print(json.dumps({"ok": True, "barDisplay": value}), flush=True)
    return 0


def cmd_forget() -> int:
    with locked_state() as state:
        state["device"] = None
        state["baseline"] = {"time": 0, "cals": 0, "milesMilli": 0, "steps": 0}
        set_disconnected(state)
    print(json.dumps({"ok": True, "device": None}), flush=True)
    return 0


def cmd_dump() -> int:
    print(json.dumps(load_unlocked(), indent=2), flush=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="OmaWalk BLE helper")
    sub = parser.add_subparsers(dest="cmd", required=True)

    scan_p = sub.add_parser("scan")
    scan_p.add_argument("--seconds", type=float, default=12.0)

    sub.add_parser("run")
    sub.add_parser("dump")
    sub.add_parser("forget")

    set_dev = sub.add_parser("set-device")
    set_dev.add_argument("address")
    set_dev.add_argument("--name", default="")
    set_dev.add_argument("--adapter", default="")

    set_bar = sub.add_parser("set-bar")
    set_bar.add_argument("value", choices=BAR_DISPLAYS)

    args = parser.parse_args()
    if args.cmd == "scan":
        return asyncio.run(cmd_scan(args.seconds))
    if args.cmd == "run":
        return asyncio.run(cmd_run())
    if args.cmd == "dump":
        return cmd_dump()
    if args.cmd == "forget":
        return cmd_forget()
    if args.cmd == "set-device":
        return cmd_set_device(args.address, args.name, args.adapter)
    if args.cmd == "set-bar":
        return cmd_set_bar(args.value)
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
