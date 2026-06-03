# Open Devices Bridge

A cross-platform, community-extensible bridge that discovers devices on your
machine and publishes them to **Home Assistant** over **MQTT Discovery** —
in the spirit of OpenRGB, but for telemetry (battery, presence, firmware) with
control planned.

Support is added through **providers**: small executables the host launches that
speak a simple line-delimited JSON protocol (ODB-PP/1). Providers can be written
in any language; the host is written in Go and runs on macOS today
(Windows/Linux planned).

## Bundled providers

- **ble-battery** (macOS, Swift) — battery, connection and firmware of paired BLE
  devices (e.g. Logitech MX Keys Mini, MX Master 3) via CoreBluetooth.
- **host-info** (any OS, Python) — the host machine's own battery + online state.

## Build & run (macOS)

Requires Go 1.23+, Swift (Command Line Tools), Python 3.

```bash
go test ./...                 # core tests
bash scripts/build-dmg.sh     # => build/Open-Devices-Bridge.dmg
```

Install: copy **Open Devices Bridge.app** to `/Applications`. First launch asks
for **Bluetooth** permission (needed by the ble-battery provider). The app is
unsigned; on first open right-click → **Open**, or:
```bash
xattr -dr com.apple.quarantine "/Applications/Open Devices Bridge.app"
```

Configure the broker in the tray → **Configurações…** (requires the Mosquitto
add-on + MQTT integration in Home Assistant).

## Writing a provider

A provider is a directory under `providers/` (bundled) or
`~/Library/Application Support/OpenDevicesBridge/providers/` (user) containing a
`provider.json` and an executable. On launch it prints `hello`, then `devices`,
then `state` lines on stdout. See `docs/superpowers/specs/` for the protocol.

## Roadmap

- SP2 — real device providers (Stream Deck, Logitech webcam, Keychron K3) + control.
- SP3 — Windows/Linux host packaging + per-OS providers.
- SP4 — community provider registry.
