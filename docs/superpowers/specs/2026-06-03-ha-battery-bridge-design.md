# HA Battery Bridge — Design Spec

**Date:** 2026-06-03
**Status:** Approved design, pending spec review

## Problem

The user's Bluetooth peripherals (Logitech **MX Keys Mini** keyboard, **MX Master 3** mouse) report battery level over BLE to the Mac they're paired with, but this data is not exposed to Home Assistant. The user wants a native macOS menu-bar app that reads each device's battery (and related info) and publishes it to their Home Assistant instance (HA "99lab", LAN `192.168.31.150`) so it shows up as sensors.

## Validated Technical Foundation

A Swift CoreBluetooth spike (`spike_battery.swift`) proved the core mechanism using **public APIs only**:

```
CBCentralManager.retrieveConnectedPeripherals(withServices: [CBUUID("180F")])
  → returns devices already connected to the system that expose the Battery Service
  → connect (shares the system's existing connection, no bonding conflict)
  → readValue(for: 0x2A19)  → battery %
```

Spike result on the user's Mac:
```
[connected w/ BatteryService] count=2
  [MX Master 3]  BATERIA = 20%
  [MX Keys Mini] BATERIA = 55%
```

This sidesteps the BLE-HID single-active-host / bonding wall: the Mac is already the active host, and CoreBluetooth lets the app piggyback on that connection to read GATT. No extra hardware (no Logi Bolt receiver), no sacrificed pairing slot.

## Scope

### In scope (per user decisions)
- **Form factor:** menu-bar app (`NSStatusItem`), no Dock icon (`LSUIElement=true`).
- **Transport to HA:** MQTT with Home Assistant MQTT Discovery (HA auto-creates the device + entities). Requires a Mosquitto broker on the HA side.
- **Data published per device:**
  - Battery % — `sensor`, `device_class: battery` (core, proven)
  - Online/connected — `binary_sensor`, `device_class: connectivity` (via presence in `retrieveConnectedPeripherals`)
  - Firmware version — `sensor` (best-effort, Device Info Service `0x2A26`)
  - Charging state — **best-effort only**; likely unavailable (see Risks). Published only if the GATT exposes it.
- **Config UI:** SwiftUI settings window — MQTT host/port/username/password, poll interval, "test connection", "start at login".
- **Packaging:** unsigned `.dmg` (user has no Apple Developer account). Runs on the build Mac via automatic ad-hoc signing; on other Macs requires right-click → Open once (or `xattr -d com.apple.quarantine`). Documented in README.

### Out of scope (YAGNI / infeasible)
- Keychron K3 — it is Bluetooth Classic HID (not BLE) / closed firmware; not addressable by this app or HA. Confirmed in prior recon.
- Keyboard LED/backlight state — host-driven output report, not reported back by the device. Impossible.
- Remapping, macros, RGB control — unrelated; not this app.
- Reading battery while the device is connected to a *different* host (iPad/phone) — by BLE design the Mac isn't the active host then, so the device shows offline. Expected behavior, not a feature gap.

## Architecture

```
┌──────────────── HA Battery Bridge (.app, menu bar) ────────────────┐
│                                                                      │
│  BatteryReader (CoreBluetooth)                                       │
│    - Timer (default 5 min, configurable)                             │
│    - retrieveConnectedPeripherals([180F]) → connect → read 2A19      │
│      + best-effort 2A26 (firmware), 2BED (charging)                  │
│    - emits [DeviceReading]                                           │
│                                                                      │
│  MQTTPublisher (CocoaMQTT via SwiftPM)                               │
│    - on connect: publish retained discovery configs                  │
│    - on each reading: publish state + availability                   │
│    - reconnect with backoff                                          │
│                                                                      │
│  SettingsStore (UserDefaults + Keychain for password)               │
│                                                                      │
│  MenuBarController (NSStatusItem)                                    │
│    - menu: per-device battery %, MQTT status, Settings…, Quit        │
│    - opens SettingsView                                              │
│                                                                      │
│  AppDelegate — wiring, LSUIElement, login-item registration         │
└──────────────────────────────────────────────────────────────────────┘
        │ MQTT (TCP, optional TLS later)
        ▼
   Mosquitto add-on @ HA 99lab → HA auto-creates:
     device "MX Keys Mini": sensor.mx_keys_mini_battery, binary_sensor.…_connected, sensor.…_firmware
     device "MX Master 3":  sensor.mx_master_3_battery,  binary_sensor.…_connected, sensor.…_firmware
```

## Components (focused files)

| File | Responsibility | Depends on |
|---|---|---|
| `DeviceReading.swift` | Plain model: `id, name, battery: Int?, online: Bool, firmware: String?, charging: Bool?`. Pure value type. | — |
| `BatteryReader.swift` | CoreBluetooth polling; produces `[DeviceReading]`. Behind a `BatteryReading` protocol so it can be mocked. | CoreBluetooth |
| `MQTTPublisher.swift` | Discovery config generation + state/availability publishing; reconnect/backoff. | CocoaMQTT, `DeviceReading` |
| `DiscoveryPayload.swift` | Pure functions building HA MQTT Discovery JSON (config topic + payload) and state topics from a `DeviceReading`. **Pure → unit-tested.** | `DeviceReading` |
| `SettingsStore.swift` | Read/write MQTT host, port, username, poll interval (UserDefaults); password (Keychain). | Security framework |
| `MenuBarController.swift` | `NSStatusItem`, menu rendering, opens settings. | AppKit, app state |
| `SettingsView.swift` | SwiftUI form; "Test connection" calls MQTTPublisher; "Start at login" via `SMAppService`. | SwiftUI |
| `AppDelegate.swift` | Composition root; `LSUIElement`; ties reader → publisher → menu. | all |

## Data Flow

1. App launches (login item, no Dock icon).
2. `BatteryReader` timer fires (default every 5 min; also once immediately on launch and on MQTT (re)connect).
3. `retrieveConnectedPeripherals([180F])` → for each: connect, read `0x2A19` (+ best-effort `0x2A26`, `0x2BED`), disconnect.
4. Devices known but absent from the list → `online=false`, last battery retained.
5. `MQTTPublisher` publishes per device: discovery config (retained, once per connect) + state JSON + availability.
6. HA updates entities. Menu bar reflects latest %.

## MQTT Topic Design (HA Discovery)

Object id per device derived from a slug of its name (e.g. `mx_keys_mini`). Stable `unique_id` from the CoreBluetooth peripheral `identifier` (UUID) so entities persist.

- Discovery (retained): `homeassistant/sensor/<obj>/battery/config`, `.../binary_sensor/<obj>/connected/config`, `homeassistant/sensor/<obj>/firmware/config`
- State: `habridge/<obj>/state` (single JSON: `{"battery":55,"online":true,"firmware":"RBK73.04_0016","charging":null}`) — discovery configs use `value_template` / `availability_template` against this one topic.
- Availability: app-level `habridge/bridge/availability` (LWT `offline`) plus per-device `online` via template.

## Error Handling

- **MQTT down:** exponential backoff reconnect (1s→60s cap); menu bar icon/text indicates "MQTT: disconnected"; LWT marks bridge offline in HA.
- **Bluetooth unauthorized/off:** menu shows warning + button opening System Settings → Privacy → Bluetooth; reader pauses.
- **Device offline:** keep last known battery, set `online=false`; never delete entity.
- **Read failure on a device:** skip that cycle for that device, keep prior value, log.

## Testing Strategy

- **Unit (pure, no BT/MQTT):**
  - `DiscoveryPayload` — given a `DeviceReading`, asserts exact config topic + JSON payload (unique_id, device block, value_template) and state JSON.
  - Name→slug/object_id derivation (stable, collision-safe).
  - `SettingsStore` round-trip (UserDefaults; Keychain stubbed).
- **Reader logic:** `BatteryReader` behind `BatteryReading` protocol; a fake feeds canned peripherals to test online/offline transitions and last-value retention — no real radio.
- **Manual integration:** run against a local Mosquitto; checklist verifying the two devices' entities appear and update in HA.

## Packaging

- SwiftPM executable target → `.app` bundle. `Info.plist`: `NSBluetoothAlwaysUsageDescription`, `LSUIElement=true`, bundle id `online.99lab.habatterybridge`.
- `.dmg` via `create-dmg`.
- Unsigned: documented Gatekeeper bypass (right-click → Open, or `xattr -dr com.apple.quarantine`). Build Mac runs it via automatic ad-hoc signing.
- "Start at login" via `SMAppService.mainApp.register()`.

## Risks / Open Items

1. **Charging state** — standard Battery Service has no charging field. Newer `Battery Level Status 0x2BED` (BAS 1.1) may not be present on these Logitech devices; Logitech's real charging info is HID++ (requires writing the HID report channel the system owns — not possible over the shared CB connection). **Mitigation:** read best-effort; if absent, omit the charging entity. Not a blocker.
2. **Firmware via `0x2A26`** — spike exited before confirming; macOS already surfaces it, so DIS is present. Best-effort; omit if unreadable.
3. **CoreBluetooth connect latency** — connecting to read then disconnecting each cycle is fine at a 5-min cadence; avoid hammering. Consider subscribing to `0x2A19` notifications as a later optimization (not in v1).
4. **MQTT broker prerequisite** — user must have Mosquitto add-on on HA 99lab. README documents setup.

## Reference Artifacts

- `spike_battery.swift` — validated CoreBluetooth battery read (kept in repo as reference/seed for `BatteryReader`).
- `k3_ble_scan.py` — BLE recon script used to characterize the Keychron K3 (kept for reference).
