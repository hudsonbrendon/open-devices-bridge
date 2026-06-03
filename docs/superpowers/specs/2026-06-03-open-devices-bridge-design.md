# Open Devices Bridge — Design Spec (SP1)

**Date:** 2026-06-03
**Status:** Approved design, pending spec review
**Supersedes:** the single-purpose "HA Battery Bridge" app, which becomes the
`ble-battery` provider of this larger platform.

## Vision

An OpenRGB-style, community-extensible bridge that discovers a range of devices
(across brands and transports) on the host machine and exposes them to **Home
Assistant** over **MQTT**. Support grows over time through community-contributed
**providers** (like extensions). Cross-platform (Windows/Linux/macOS), starting
macOS-first to validate.

This spec covers **SP1 only**: the core host + out-of-process provider
architecture + generalized HA/MQTT layer, on macOS, proven with two reference
providers. Later sub-projects (own spec each):
- **SP2** — real device providers (Stream Deck, Logitech webcam, Keychron K3, …)
- **SP3** — Windows/Linux host packaging + per-OS providers
- **SP4** — community contribution model (provider registry, docs, signing)

## Key Decisions (from brainstorming)

1. **Plugin model:** out-of-process **providers** — executables the host launches
   that speak a line-delimited JSON protocol over stdio. Community writes
   providers in any language. This isolates the inherently per-OS device access.
2. **Capabilities:** telemetry-first (device→HA), but the protocol is designed
   bidirectional (host→device commands defined now, real control deferred to SP2).
3. **Reference providers:** `ble-battery` (Swift, ports the existing CoreBluetooth
   battery reader) + `host-info` (Python, proves language-agnostic + a second
   capability).
4. **Host language:** **Go** (cross-platform now). Avoids building the host twice.
   The Swift CoreBluetooth code survives as the macOS-only `ble-battery` provider.
5. **Name:** **Open Devices Bridge** (ODB). Repo `open-devices-bridge` (renamed
   from `ha-battery-bridge`), bundle id `online.99lab.opendevicesbridge`, MQTT base
   topic `odb/`.

## Why device access is per-OS (rationale for the provider model)

Reading the battery of an *already-connected* BLE device without stealing the
connection has no cross-platform library; each OS differs:

| OS | Mechanism |
|---|---|
| macOS | CoreBluetooth `retrieveConnectedPeripherals([180F])` + read `0x2A19` (validated) |
| Linux | BlueZ D-Bus `org.bluez.Battery1` → `Percentage` |
| Windows | WinRT `BluetoothLEDevice` + GATT battery service |

The provider model confines these differences to small, swappable executables.
The Go host stays portable; providers are per-OS/per-device.

## Provider Protocol v1 (ODB-PP/1)

Newline-delimited JSON (JSONL). One message object per line.
stdout = provider→host. stdin = host→provider.

### Provider → Host

```jsonc
// Announce self (first line). protocol must equal 1.
{"type":"hello","protocol":1,"provider":{"id":"ble-battery","name":"BLE Battery","version":"1.0.0"}}

// Declare current devices and their entities (capabilities). May be re-sent.
{"type":"devices","devices":[
  {"id":"mx-keys-mini","name":"MX Keys Mini","manufacturer":"Logitech","model":"MX Keys Mini",
   "entities":[
     {"key":"battery","kind":"sensor","device_class":"battery","unit":"%"},
     {"key":"connected","kind":"binary_sensor","device_class":"connectivity"},
     {"key":"firmware","kind":"sensor","entity_category":"diagnostic"}]}]}

// Live values for one device. Keys match declared entity keys.
{"type":"state","device":"mx-keys-mini","values":{"battery":55,"connected":true,"firmware":"RBK73.04_0016"}}

// Optional explicit availability for a device.
{"type":"availability","device":"mx-keys-mini","online":false}

// Optional diagnostics. level ∈ debug|info|warn|error.
{"type":"log","level":"info","message":"polled 2 devices"}
```

### Host → Provider (defined now; real control is SP2)

```jsonc
{"type":"refresh"}                                  // re-poll now
{"type":"command","device":"...","entity":"...","command":"toggle","payload":{}}
{"type":"shutdown"}                                 // exit cleanly
```

### Entity `kind`

- Telemetry (wired to HA in SP1): `sensor`, `binary_sensor`.
- Telemetry (declared, deferred): `event`.
- Control (declared, deferred to SP2): `button`, `switch`, `light`, `number`.

In SP1 the host maps `sensor` and `binary_sensor` to HA discovery; any other
`kind` is logged and skipped (forward-compatible — old hosts ignore new kinds).

### Protocol rules

- First non-blank line from a provider MUST be `hello` with `protocol:1`.
  Otherwise the host disables the provider and logs an error.
- Unknown message `type` → host logs and ignores the line.
- A malformed (non-JSON) line → host logs and skips that line; the provider keeps
  running.

## Host Architecture (Go)

```
┌──────────────── odb (Go, cross-platform host) ────────────────┐
│  internal/protocol   message structs + JSONL codec            │
│  internal/provider                                            │
│    Registry  — scan bundled + user provider dirs, read         │
│                provider.json, select by OS, launch enabled     │
│    Process   — exec.Cmd, stdio pipes, JSONL scan, send         │
│                commands, restart with exponential backoff      │
│  internal/hapublish                                           │
│    Mapper    — device+entities → HA discovery configs + topics │
│    Client    — MQTT (paho), bridge LWT availability            │
│  internal/config — settings file + password via go-keyring     │
│  internal/ui     — Fyne system tray + settings window          │
│  cmd/odb/main    — orchestrator wiring                         │
└────────────────────────────────────────────────────────────────┘
        │ launches                         │ MQTT
        ▼                                  ▼
  providers/*  (subprocess)        Mosquitto @ Home Assistant
```

### Packages / responsibilities

| Path | Responsibility | Depends on |
|---|---|---|
| `internal/protocol/messages.go` | Codable message types + `Encode`/`DecodeLine` (JSONL) | stdlib |
| `internal/hapublish/mapper.go` | Pure: `DiscoveryMessages(provider, device)` and `StateMessage(...)` → `[]Message{topic,payload,retained}` | protocol |
| `internal/hapublish/client.go` | MQTT connect, LWT `odb/bridge/availability=offline`, publish | paho.mqtt.golang |
| `internal/provider/process.go` | Launch one provider, stream messages via channels, send host→provider, restart backoff | protocol |
| `internal/provider/registry.go` | Discover providers (bundled dir + user dir), parse `provider.json`, filter by `runtime.GOOS`, launch enabled | process |
| `internal/config/config.go` | Load/save settings (host, port, user, intervalMinutes) in OS config dir; password via `github.com/zalando/go-keyring` | go-keyring |
| `internal/ui/tray.go` | Fyne tray: per-device `entity = value` rows, MQTT status, Settings/Refresh/Quit | fyne |
| `internal/ui/settings.go` | Fyne form: broker host/port/user/password, interval, test-connection | fyne, config |
| `cmd/odb/main.go` | Compose registry → processes → mapper → client → tray | all |

### HA topic / discovery design (generalized)

- Object id per device: `<provider>_<device-slug>` (e.g. `ble_battery_mx_keys_mini`).
- State topic: `odb/<provider>/<device-slug>/state` — JSON of entity key→value.
- Discovery (retained): `homeassistant/<component>/odb_<obj>/<entity>/config`,
  where `<component>` is `sensor` or `binary_sensor` per the entity `kind`.
- `unique_id`: `odb_<provider>_<device-slug>_<entity>`.
- HA `device` block groups a device's entities (identifiers
  `["odb_<provider>_<device-slug>"]`, name, manufacturer, model).
- Bridge availability: `odb/bridge/availability` (LWT `offline`, set `online` on
  connect), referenced by every entity's `availability_topic`.

This is the existing battery payload shape, generalized: `device_class`, `unit`,
`entity_category` come straight from the declared entity; `value_template` is
`{{ value_json.<key> }}` for sensors and
`{{ 'ON' if value_json.<key> else 'OFF' }}` for binary_sensors.

## Reference providers

### `providers/ble-battery` (Swift executable, macOS only)

- Reuses the existing `BatteryReader` (CoreBluetooth `retrieveConnectedPeripherals`).
- On launch: emit `hello`, then `devices` (each connected battery device with
  `battery`/`connected`/`firmware` entities), then a `state` per poll cycle.
- Polls on its own timer and on `refresh`. Marks absent devices `online:false`.
- `provider.json`: `{"id":"ble-battery","exec":"ble-battery","platforms":["darwin"]}`.
- Built as a SwiftPM executable; output binary bundled into the provider dir.

### `providers/host-info` (Python executable, cross-platform)

- Stdlib only (no pip/venv — avoids the py3.14 venv breakage). Reads host battery
  by parsing `pmset -g batt` on macOS; emits a `heartbeat`/uptime counter.
- Entities: `host_battery` (sensor, `%`, device_class battery),
  `host_online` (binary_sensor, connectivity — always ON while running).
- `--selftest`: print one `hello` + `devices` + `state` to stdout and exit 0
  (used by host integration tests to validate a real provider).
- `provider.json`: `{"id":"host-info","exec":"host_info.py","platforms":["darwin","linux","windows"]}`
  (host launches via the interpreter on the manifest's `exec`; for `.py` the host
  invokes `python3 host_info.py`).

## Repo Restructure

Rename GitHub repo `ha-battery-bridge` → `open-devices-bridge` (GitHub redirects
the old name). Internal layout:

```
open-devices-bridge/
  go.mod
  cmd/odb/main.go
  internal/{protocol,hapublish,provider,config,ui}/*.go (+ *_test.go)
  providers/
    ble-battery/  Package.swift, Sources/...     (CoreBluetooth reader, reused)
    host-info/    host_info.py, provider.json
  packaging/Info.plist                            (rebranded)
  scripts/build-app.sh, build-dmg.sh
  .github/workflows/build.yml
  docs/superpowers/specs/2026-06-03-open-devices-bridge-design.md
  README.md
```

Migration of existing Swift code:
- `BatteryReader.swift` + `DeviceReading.swift` → `providers/ble-battery/Sources/`.
- Swift `DiscoveryPayload`, `MQTTPublisher`, `SettingsStore`, `Keychain`,
  `MenuBarController`, `SettingsView`, `AppDelegate`, `main.swift`, `CoreTests`
  → **removed**; reimplemented in Go.
- `spike_battery.swift`, `k3_ble_scan.py` → kept under `docs/` or `reference/` as
  artifacts.

## Data Flow

1. Host starts, loads config, connects MQTT (publishes bridge `online`).
2. Registry discovers providers (bundled `Contents/Resources/providers/` + user
   `~/Library/Application Support/OpenDevicesBridge/providers/`), launches each
   enabled provider whose `platforms` include the current OS.
3. Each provider sends `hello` → `devices`; host publishes HA discovery configs
   (once per entity) and a `state` topic value as `state` messages arrive.
4. Tray aggregates all providers' devices and shows `entity = value` rows + MQTT
   status.
5. A periodic `refresh` (default 5 min, configurable) is sent to providers.

## Error Handling

- **Provider crash/exit:** host restarts it with exponential backoff (1s→60s),
  publishes its devices' `online:false`, logs.
- **Bad first line / wrong protocol version:** disable provider, log; do not crash
  host.
- **Malformed JSONL line:** log + skip the line; provider keeps running.
- **MQTT down:** paho auto-reconnect with backoff; tray shows "MQTT: desconectado";
  LWT marks bridge offline in HA.
- **Provider declares a control-only `kind`:** logged and skipped in SP1.

## Testing Strategy

- **`protocol`:** table tests — marshal/unmarshal round-trip for every message
  type; malformed line returns error without panic.
- **`hapublish/mapper`:** given a declared device+entities, assert exact discovery
  topics + payloads (unique_id, device block, value_template, device_class, unit)
  and the state JSON. Ports the prior 28-check battery suite into Go, generalized.
- **`provider/process`:** feed canned JSONL through an in-memory reader → assert
  the channel emits the parsed messages in order; simulate exit → assert restart
  scheduled.
- **Integration:** launch `python3 providers/host-info/host_info.py --selftest`
  from a Go test and assert it emits a valid `hello`+`devices`+`state` the
  `protocol` decoder accepts.
- **Manual end-to-end:** run against a local Mosquitto; verify HA-style discovery
  + state for both providers (battery device + host-info).

## Packaging & CI

- **macOS:** `.app` with the Go binary as `Contents/MacOS/odb`, providers under
  `Contents/Resources/providers/<id>/`, `Info.plist` (`LSUIElement`,
  `NSBluetoothAlwaysUsageDescription` for the bundled BLE provider). Ad-hoc
  codesign; `.dmg` via `hdiutil`. Unsigned → documented quarantine bypass.
- **CI (`macos-15`):** install Go, `go test ./...`, build Go host (darwin/arm64),
  build the Swift `ble-battery` provider, assemble `.app`/`.dmg`, upload artifact;
  tag `v*` attaches the `.dmg` to a release. Windows/Linux packaging is SP3.

## Scope Boundaries (YAGNI for SP1)

- No real control wiring (protocol carries commands; host ignores control kinds).
- No Windows/Linux packaging (host code is portable; only the macOS `.app` ships).
- No provider registry/marketplace/signing.
- No real devices beyond the MX battery devices and host-info (Stream Deck,
  webcam, Keychron = SP2).

## Reference Artifacts

- `spike_battery.swift` — validated CoreBluetooth battery read (seed for the
  `ble-battery` provider).
- `k3_ble_scan.py` — BLE recon for the Keychron K3 (SP2 input).
- Prior spec `2026-06-03-ha-battery-bridge-design.md` — the SP1 battery feature it
  generalizes.
