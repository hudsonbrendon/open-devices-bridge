# Tauri Host Rewrite — Design Spec

**Date:** 2026-06-04
**Status:** Approved design, pending spec review
**Replaces:** the Go + Fyne host (`cmd/odb`, `internal/*`). The out-of-process
providers and the ODB-PP/1 protocol are unchanged and reused.
**Branch:** `feat/tauri-host` (off `main`).

## Motivation

The Go + Fyne host works but its UI is non-native and visually poor: the menu-bar
icon is Fyne's default and the settings window is Fyne's custom-drawn dark theme,
which does not match macOS conventions. We want a richer, prettier, consistent UI.
A web UI delivers that; **Tauri** (Rust core + the OS's native WebView) gives it at
~10 MB instead of Electron's ~200 MB — the right fit for a background tray utility.

The provider architecture is the stable, correct investment and survives the host
change: device access stays in the native providers (CoreBluetooth, CoreMediaIO),
spawned as subprocesses that speak ODB-PP/1 (JSONL). Only the host — orchestrator,
MQTT, config, and UI — is rewritten.

## Goals

1. Functional parity with the current host: discover and run providers, map their
   devices to Home Assistant MQTT Discovery, publish state, bridge availability/LWT.
2. A **rich popover panel** (frameless web window anchored to the tray icon) showing
   battery levels, cameras in use, and MQTT status.
3. A **native-feeling, well-designed settings** screen (broker host/port/user/
   password, poll interval, test-connection).
4. A menu-bar (tray) **template icon** that adapts to light/dark and shows summary
   text (e.g. the lowest battery percentage).
5. macOS `.app` + `.dmg`, built in CI.

## Non-Goals (deferred)

- Windows/Linux packaging (Tauri is cross-platform; we ship macOS now and the host
  is portable for later).
- Device control (host→device commands) — protocol carries it; not wired here.
- Provider marketplace/registry.
- Apple Developer signing/notarization (no account → unsigned `.dmg`, documented
  quarantine bypass).

## Prerequisites

- **Rust** is not installed on the dev machine; install via `rustup` (plan Task 0).
- Node 22 + npm are present. macOS WebKit (WKWebView) is present.
- Tauri v2 + tauri-cli.

## Repository Restructure

```
open-devices-bridge/
  providers/                 UNCHANGED — ble-battery (Swift), host-info (Python),
                             camera-mac (Swift), each with provider.json
  src-tauri/                 NEW — Rust host
    Cargo.toml
    tauri.conf.json
    build.rs
    icons/                   tray template icon (monochrome) + app icon
    src/
      main.rs                Tauri bootstrap: tray icon+title, popover window,
                             accessory activation (no Dock), start orchestrator
      protocol.rs            ODB-PP/1 message structs + JSONL (serde) — port of Go
      hapublish.rs           HA discovery configs + state topics (pure) — port of Go
      mqtt.rs                rumqttc client, LWT + bridge availability
      provider.rs            spawn a provider, stream JSONL, restart with backoff
      registry.rs            discover providers (bundled + user dirs), parse
                             provider.json, filter by OS
      config.rs              settings file (dirs crate) + password via keyring crate
      orchestrator.rs        wire providers -> mapper -> mqtt; hold a snapshot;
                             emit "snapshot" events to the frontend
      commands.rs            #[tauri::command]: get_snapshot, save_settings,
                             test_connection, open_settings, quit
  src/                       NEW — Svelte frontend (Vite)
    main.ts
    App.svelte               routes Popover vs Settings by window
    lib/Popover.svelte       battery bars, camera in-use chips, MQTT status,
                             Settings + Quit buttons
    lib/Settings.svelte      form: host, port, user, password, interval,
                             "Test connection", Save
    lib/api.ts               typed wrappers over Tauri invoke/listen
  package.json, vite.config.ts, svelte.config.js, tsconfig.json
  REMOVED: cmd/, internal/, go.mod, go.sum (Go host; preserved in git history)
  docs/, .github/workflows/build.yml (updated)
```

## Components

### Rust host (`src-tauri/src/`)

| Module | Responsibility |
|---|---|
| `protocol.rs` | `Entity`, `Device`, `ProviderInfo`, `Message`, `Command` (serde) and `decode_line(&str) -> Result<Message>`. Mirrors the Go `protocol` package. |
| `hapublish.rs` | Pure: `slug`, `object_id`, `state_topic`, `discovery_messages(provider, device) -> Vec<OutMessage>`, `state_message(...)`. Same topic/unique_id scheme and `binary_sensor`/`sensor` handling as the Go mapper. Unit-tested. |
| `mqtt.rs` | `Client` over `rumqttc`: connect with LWT `odb/bridge/availability=offline`, publish `online` on connect, `publish(OutMessage)`, status callback. |
| `provider.rs` | `Process`: spawn the executable, read stdout lines, parse via `protocol`, deliver to a channel; write commands to stdin; restart with exponential backoff (1s→60s) on exit. |
| `registry.rs` | `discover(roots) -> Vec<Manifest>`; `Manifest{id,name,exec,args,platforms,enabled,dir}` with `.command()` (`.py` → `python3`). Filter by `std::env::consts::OS`. |
| `config.rs` | `Settings{host,port,username,interval_minutes}` to a JSON file under the OS config dir; password via the `keyring` crate. |
| `orchestrator.rs` | Launch discovered providers; on `devices` publish discovery; on `state` publish state; maintain an in-memory `Snapshot` (providers→devices→values + MQTT status); emit a Tauri event `snapshot` to the frontend on change. |
| `commands.rs` | Tauri commands the frontend calls: `get_snapshot`, `save_settings(Settings, password)`, `test_connection(Settings, password) -> Result`, `quit`. |
| `main.rs` | Tauri `Builder`: register commands, build the tray (template icon, title text = lowest battery %, menu fallback), create the hidden frameless popover window, toggle it on tray click (positioned via `tauri-plugin-positioner`), set macOS activation policy to Accessory, spawn the orchestrator on a background task. |

Crates: `tauri` v2, `rumqttc`, `serde`/`serde_json`, `keyring`, `dirs`, `tokio`,
`tauri-plugin-positioner`.

### Svelte frontend (`src/`)

- **Popover panel** (`Popover.svelte`): renders the latest `snapshot` — battery
  devices with a labeled bar and %, host battery, camera chips (green when in use),
  the MQTT connection status, and buttons for Settings and Quit. Subscribes to the
  `snapshot` Tauri event and calls `get_snapshot` on mount.
- **Settings** (`Settings.svelte`): a clean form bound to `Settings`; "Test
  connection" calls `test_connection`; Save calls `save_settings`. Password field
  separate (stored in keyring).
- **api.ts**: typed `invoke`/`listen` wrappers so components stay declarative.

The two surfaces are distinguished by which Tauri window loads them (the popover
window vs a standard settings window), routed in `App.svelte`.

## Data Flow

1. `main.rs` starts the orchestrator on a Tokio task and builds the tray + hidden
   popover window.
2. Orchestrator discovers providers (`providers/` bundled in the app Resources, and
   the user dir), launches each, and connects MQTT.
3. Provider `hello`/`devices`/`state` → orchestrator publishes HA discovery + state
   to MQTT and updates the in-memory `Snapshot`, then `app_handle.emit("snapshot", …)`.
4. The frontend popover re-renders from the `snapshot` event; the tray title updates
   to the lowest battery %.
5. Saving settings writes the file + keyring and reconnects MQTT.

## Error Handling

- Provider crash → orchestrator restarts it with backoff; its devices marked offline
  in the snapshot.
- Malformed JSONL line → logged and skipped; provider keeps running.
- MQTT down → rumqttc reconnect loop; popover + tray show "disconnected".
- No broker configured (first launch) → orchestrator runs providers and updates the
  popover, but skips publishing (no panic); settings prompt the user to configure.
- Bluetooth permission (ble-battery) handled by that provider as today.

## Testing Strategy

- **`cargo test`** (native, no extra tooling):
  - `protocol`: round-trip + malformed-line tests.
  - `hapublish`: given a device+entities, assert exact discovery topics/payloads and
    state JSON (port the Go table tests, including the unknown-kind-skipped case).
  - `config`: settings file round-trip (keyring stubbed/skipped).
  - `registry`: temp-dir discovery, OS filter, `.py` command resolution.
- **Provider integration**: a Rust test launches `host-info --selftest` and asserts a
  valid hello/devices/state, mirroring the Go integration test.
- **Live end-to-end**: the existing Mosquitto harness — run the assembled app, toggle
  a camera and observe `binary_sensor` flips and battery values published; visually
  confirm the popover renders battery %, camera chips, and MQTT status.

## Packaging & CI

- `tauri build` produces `Open Devices Bridge.app` and a `.dmg` via Tauri's bundler.
  The `providers/` binaries (Swift `ble-battery`, `camera-mac`; Python `host-info`)
  are built first and included as bundled resources (Tauri `resources`/`externalBin`
  or a pre-build hook copying them into the app Resources), discoverable by
  `registry.rs` next to the executable.
- macOS activation policy = Accessory (no Dock icon).
- Unsigned: documented `xattr -dr com.apple.quarantine` bypass.
- **CI (`macos-15`)**: install Rust (`dtolnay/rust-toolchain`), Node, select Xcode;
  build the Swift providers; `npm ci`; `npm run tauri build`; upload the `.dmg`
  artifact; on tag `v*` attach it to the release. Replaces the Go build steps.

## Reference / Port Source

- `internal/protocol/messages.go`, `internal/hapublish/mapper.go`,
  `internal/provider/*.go`, `internal/config/config.go`, `internal/app/orchestrator.go`
  are the reference implementations to port to Rust (same behavior, same topic
  scheme, same tests).
