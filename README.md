# Open Devices Bridge

A cross-platform, community-extensible bridge that discovers devices on your
machine and publishes them to **Home Assistant** over **MQTT Discovery**, with a
native, lightweight menu-bar UI (**Tauri** — Rust core + the OS WebView; the macOS
`.dmg` is ~4 MB).

Support is added through **providers**: small executables the host launches that
speak a simple line-delimited JSON protocol (ODB-PP/1). Providers can be written
in any language. The host (orchestrator, MQTT, tray popover, settings) is a Tauri
app; on macOS it runs as a menu-bar agent (no Dock icon).

## Bundled providers

- **ble-battery** (macOS, Swift) — battery, connection, firmware of paired BLE
  devices (Logitech MX Keys Mini, MX Master 3) via CoreBluetooth.
- **host-info** (any OS, Python) — the host machine's own battery + online state.
- **camera-mac** (macOS, Swift) — each camera's "in use" state via CoreMediaIO.

## UI

Click the menu-bar icon (it shows the lowest battery %) to open a **popover** with
battery bars, camera in-use chips, and MQTT status. **Configurações** opens the
settings (broker host/port/user/password, poll interval, test-connection).

## Build (macOS)

Requires Rust (rustup), Node 22, Swift (Command Line Tools), Python 3.

```bash
cargo test --manifest-path src-tauri/Cargo.toml   # core tests
npm install
npm run tauri build   # => src-tauri/target/release/bundle/dmg/*.dmg
```

Install: copy **Open Devices Bridge.app** to `/Applications`. First launch asks for
**Bluetooth** permission (ble-battery). The app is unsigned; on first open
right-click → **Open**, or:
```bash
xattr -dr com.apple.quarantine "/Applications/Open Devices Bridge.app"
```

Configure the broker in **Configurações** (requires the Mosquitto add-on + MQTT
integration in Home Assistant).

## Writing a provider

A provider is a directory under `providers/` (bundled) or
`~/Library/Application Support/OpenDevicesBridge/providers/` (user) with a
`provider.json` and an executable that prints `hello`, then `devices`, then `state`
JSONL lines on stdout. See `docs/superpowers/specs/` for the protocol.

## Architecture

- `src-tauri/` — Rust host: `protocol`, `hapublish` (HA discovery mapping),
  `mqtt` (rumqttc), `provider` (subprocess supervisor), `registry`, `config`,
  `orchestrator`, `commands` + the tray/popover (`main.rs`). `cargo test` covers the
  pure modules + a host-info integration test.
- `src/` — Svelte frontend: popover panel + settings, talking to Rust via Tauri
  commands/events.
- `providers/` — the native providers (unchanged across host rewrites).

## Roadmap

- Windows/Linux packaging (the Tauri host is already cross-platform).
- Device control (host→device), provider registry.
