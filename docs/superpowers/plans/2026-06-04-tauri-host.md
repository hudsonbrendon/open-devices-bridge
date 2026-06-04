# Tauri Host Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Go + Fyne host with a Tauri host (Rust core + Svelte WebView UI) that keeps full functional parity with the providers/protocol unchanged, and adds a rich tray popover + native-feeling settings.

**Architecture:** A Rust `src-tauri` crate runs the orchestrator (spawns the existing out-of-process providers, parses ODB-PP/1 JSONL, maps to HA MQTT Discovery, publishes via rumqttc), holds a live snapshot, and drives a Tauri tray icon + a frameless popover window. A Svelte/Vite frontend renders the popover and settings, talking to Rust via Tauri commands/events.

**Tech Stack:** Rust (tauri v2, rumqttc, serde, keyring, dirs, tokio, tauri-plugin-positioner), Svelte + Vite + TypeScript, Node 22, the existing Swift/Python providers.

**Spec:** `docs/superpowers/specs/2026-06-04-tauri-host-design.md`

**Branch:** `feat/tauri-host` (already created off `main`).

---

## Conventions

- Commit author Hudson Brendon (`git config user.name "Hudson Brendon"; user.email "contato.hudsonbrendon@gmail.com"`). No AI co-author trailer.
- Rust tests: `cargo test --manifest-path src-tauri/Cargo.toml`.
- The Go sources in `internal/` are the reference for ports (T2–T8). They are removed in Task 1 but remain in git history (`git show main:internal/hapublish/mapper.go`).
- Tauri v2 APIs are assumed (tauri 2.x). If a minor API name differs in the resolved version, adapt minimally and note it.

---

## Task 0: Install the Rust toolchain

**Files:** none (environment setup)

- [ ] **Step 1: Install rustup + stable Rust**

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
source "$HOME/.cargo/env"
```

- [ ] **Step 2: Verify**

Run: `rustc --version && cargo --version`
Expected: prints a stable rustc (1.7x+) and cargo version. If `cargo` isn't on PATH in later steps, prefix with `source "$HOME/.cargo/env"`.

- [ ] **Step 3: Install the Tauri CLI**

```bash
cargo install tauri-cli --version "^2" --locked
cargo tauri --version
```
Expected: prints `tauri-cli 2.x`.

---

## Task 1: Scaffold the Tauri + Svelte project; remove the Go host

**Files:**
- Create: `package.json`, `vite.config.ts`, `svelte.config.js`, `tsconfig.json`, `index.html`, `src/main.ts`, `src/App.svelte`
- Create: `src-tauri/Cargo.toml`, `src-tauri/build.rs`, `src-tauri/tauri.conf.json`, `src-tauri/src/main.rs`, `src-tauri/icons/` (placeholder)
- Delete: `cmd/`, `internal/`, `go.mod`, `go.sum`

- [ ] **Step 1: Remove the Go host (kept in git history)**

```bash
cd /Users/hudsonbrendon/Github/ha-battery-bridge
git rm -r cmd internal go.mod go.sum
```

- [ ] **Step 2: Frontend scaffolding**

`package.json`:
```json
{
  "name": "open-devices-bridge",
  "private": true,
  "version": "3.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "tauri": "tauri"
  },
  "dependencies": {
    "@tauri-apps/api": "^2",
    "@tauri-apps/plugin-positioner": "^2"
  },
  "devDependencies": {
    "@sveltejs/vite-plugin-svelte": "^4",
    "@tauri-apps/cli": "^2",
    "svelte": "^5",
    "svelte-check": "^4",
    "typescript": "^5",
    "vite": "^6"
  }
}
```

`vite.config.ts`:
```ts
import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  plugins: [svelte()],
  clearScreen: false,
  server: { port: 1420, strictPort: true },
});
```

`svelte.config.js`:
```js
import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";
export default { preprocess: vitePreprocess() };
```

`tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "verbatimModuleSyntax": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*.ts", "src/**/*.svelte"]
}
```

`index.html`:
```html
<!doctype html>
<html lang="pt-br">
  <head><meta charset="UTF-8" /><title>Open Devices Bridge</title></head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.ts"></script>
  </body>
</html>
```

`src/main.ts`:
```ts
import App from "./App.svelte";
import { mount } from "svelte";

const app = mount(App, { target: document.getElementById("app")! });
export default app;
```

`src/App.svelte`:
```svelte
<main>
  <h1>Open Devices Bridge</h1>
</main>

<style>
  :global(body) { margin: 0; font-family: -apple-system, system-ui, sans-serif; }
  main { padding: 12px; }
</style>
```

- [ ] **Step 3: Rust scaffolding**

`src-tauri/Cargo.toml`:
```toml
[package]
name = "open-devices-bridge"
version = "3.0.0"
edition = "2021"

[lib]
name = "odb_lib"
crate-type = ["staticlib", "cdylib", "rlib"]

[build-dependencies]
tauri-build = { version = "2", features = [] }

[dependencies]
tauri = { version = "2", features = ["tray-icon"] }
tauri-plugin-positioner = { version = "2", features = ["tray-icon"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
rumqttc = "0.24"
keyring = "3"
dirs = "5"
tokio = { version = "1", features = ["full"] }
```

`src-tauri/build.rs`:
```rust
fn main() {
    tauri_build::build()
}
```

`src-tauri/tauri.conf.json`:
```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "Open Devices Bridge",
  "version": "3.0.0",
  "identifier": "online.99lab.opendevicesbridge",
  "build": {
    "frontendDist": "../dist",
    "devUrl": "http://localhost:1420",
    "beforeDevCommand": "npm run dev",
    "beforeBuildCommand": "npm run build"
  },
  "app": {
    "windows": [],
    "security": { "csp": null }
  },
  "bundle": {
    "active": true,
    "targets": ["app", "dmg"],
    "icon": ["icons/icon.png"],
    "macOS": { "minimumSystemVersion": "14.0" },
    "resources": { "providers/": "providers/" }
  }
}
```

`src-tauri/src/main.rs`:
```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_positioner::init())
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 4: Provide a placeholder icon**

Tauri needs an icon to build. Generate the default set from any PNG:
```bash
cd /Users/hudsonbrendon/Github/ha-battery-bridge
# A simple 512x512 solid icon as a placeholder (replaced with a real one in Task 11):
mkdir -p src-tauri/icons
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | base64 --decode > /tmp/px.png
source "$HOME/.cargo/env"
cargo tauri icon /tmp/px.png --output src-tauri/icons || cp /tmp/px.png src-tauri/icons/icon.png
```
(If `cargo tauri icon` is unavailable, the single `icons/icon.png` is enough for the manifest.)

- [ ] **Step 5: Install JS deps and verify the app builds**

```bash
cd /Users/hudsonbrendon/Github/ha-battery-bridge
npm install
source "$HOME/.cargo/env"
npm run tauri build -- --no-bundle 2>&1 | tail -20
```
Expected: Vite builds the frontend and Cargo compiles the Tauri binary (no bundle yet). It should finish without errors. (First Cargo build downloads many crates — may take several minutes.)

- [ ] **Step 6: Update `.gitignore`**

Append to `.gitignore`:
```
node_modules/
dist/
src-tauri/target/
src-tauri/gen/
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: scaffold Tauri (Rust) + Svelte host; remove Go host"
```

---

## Task 2: protocol.rs (ODB-PP/1 messages)

**Files:**
- Create: `src-tauri/src/protocol.rs`
- Modify: `src-tauri/src/main.rs` (add `mod protocol;`)

- [ ] **Step 1: Write the failing test (inline in protocol.rs)**

Create `src-tauri/src/protocol.rs`:
```rust
//! ODB Provider Protocol v1 (ODB-PP/1): newline-delimited JSON messages.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Entity {
    pub key: String,
    pub kind: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub device_class: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub unit: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub entity_category: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Device {
    pub id: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub manufacturer: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub model: String,
    #[serde(default)]
    pub entities: Vec<Entity>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProviderInfo {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub version: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Message {
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub protocol: u32,
    #[serde(default)]
    pub provider: Option<ProviderInfo>,
    #[serde(default)]
    pub devices: Vec<Device>,
    #[serde(default)]
    pub device: String,
    #[serde(default)]
    pub values: BTreeMap<String, serde_json::Value>,
    #[serde(default)]
    pub online: Option<bool>,
    #[serde(default)]
    pub level: String,
    #[serde(default)]
    pub message: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Command {
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device: Option<String>,
}

/// Parse one JSONL line into a Message.
pub fn decode_line(line: &str) -> Result<Message, serde_json::Error> {
    serde_json::from_str(line)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_hello() {
        let m = decode_line(
            r#"{"type":"hello","protocol":1,"provider":{"id":"ble-battery","name":"BLE Battery","version":"1.0.0"}}"#,
        )
        .unwrap();
        assert_eq!(m.kind, "hello");
        assert_eq!(m.protocol, 1);
        assert_eq!(m.provider.unwrap().id, "ble-battery");
    }

    #[test]
    fn decodes_devices_and_state() {
        let m = decode_line(
            r#"{"type":"devices","devices":[{"id":"mx","name":"MX","entities":[{"key":"battery","kind":"sensor","unit":"%"}]}]}"#,
        )
        .unwrap();
        assert_eq!(m.devices.len(), 1);
        assert_eq!(m.devices[0].entities[0].key, "battery");

        let s = decode_line(r#"{"type":"state","device":"mx","values":{"battery":55,"connected":true}}"#).unwrap();
        assert_eq!(s.device, "mx");
        assert_eq!(s.values["battery"], serde_json::json!(55));
    }

    #[test]
    fn malformed_is_error() {
        assert!(decode_line("not json").is_err());
    }

    #[test]
    fn command_serializes() {
        let c = Command { kind: "refresh".into(), device: None };
        assert_eq!(serde_json::to_string(&c).unwrap(), r#"{"type":"refresh"}"#);
    }
}
```

- [ ] **Step 2: Wire the module**

In `src-tauri/src/main.rs`, add `mod protocol;` as the first line after the `#![cfg_attr...]` attribute. Also add `mod protocol;` to a new `src-tauri/src/lib.rs` is NOT needed — keep modules under `main.rs`.

- [ ] **Step 3: Run the tests (they fail first if you comment the impl, but here write test+impl together and run)**

Run: `source "$HOME/.cargo/env" && cargo test --manifest-path src-tauri/Cargo.toml protocol`
Expected: 4 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/protocol.rs src-tauri/src/main.rs
git commit -m "feat(rust): ODB-PP/1 protocol structs + JSONL decode"
```

---

## Task 3: hapublish.rs (HA discovery + state mapper)

**Files:**
- Create: `src-tauri/src/hapublish.rs`
- Modify: `src-tauri/src/main.rs` (add `mod hapublish;`)

- [ ] **Step 1: Implement the mapper with tests**

Create `src-tauri/src/hapublish.rs`:
```rust
//! Maps provider devices to Home Assistant MQTT Discovery configs + state.
use crate::protocol::{Device, ProviderInfo};
use serde_json::{json, Value};
use std::collections::BTreeMap;

pub const BRIDGE_AVAILABILITY_TOPIC: &str = "odb/bridge/availability";
pub const AVAILABLE: &str = "online";
pub const UNAVAILABLE: &str = "offline";

#[derive(Debug, Clone, PartialEq)]
pub struct OutMessage {
    pub topic: String,
    pub payload: String,
    pub retained: bool,
}

pub fn slug(s: &str) -> String {
    let mut out = String::new();
    let mut last = false;
    for ch in s.to_lowercase().chars() {
        if ch.is_alphanumeric() {
            out.push(ch);
            last = false;
        } else if !last {
            out.push('_');
            last = true;
        }
    }
    let trimmed = out.trim_matches('_').to_string();
    if trimmed.is_empty() { "device".into() } else { trimmed }
}

pub fn object_id(provider_id: &str, device_id: &str) -> String {
    format!("{}_{}", slug(provider_id), slug(device_id))
}

pub fn state_topic(provider_id: &str, device_id: &str) -> String {
    format!("odb/{}/{}/state", slug(provider_id), slug(device_id))
}

fn supported_component(kind: &str) -> Option<&'static str> {
    match kind {
        "sensor" => Some("sensor"),
        "binary_sensor" => Some("binary_sensor"),
        _ => None,
    }
}

pub fn state_message(provider_id: &str, device: &Device, values: &BTreeMap<String, Value>) -> OutMessage {
    OutMessage {
        topic: state_topic(provider_id, &device.id),
        payload: serde_json::to_string(values).unwrap_or_else(|_| "{}".into()),
        retained: true,
    }
}

pub fn discovery_messages(p: &ProviderInfo, d: &Device) -> Vec<OutMessage> {
    let obj = object_id(&p.id, &d.id);
    let state = state_topic(&p.id, &d.id);
    let manufacturer = if d.manufacturer.is_empty() { &p.name } else { &d.manufacturer };
    let model = if d.model.is_empty() { &d.name } else { &d.model };
    let device = json!({
        "identifiers": [format!("odb_{}", obj)],
        "name": d.name,
        "manufacturer": manufacturer,
        "model": model,
    });

    let mut out = Vec::new();
    for e in &d.entities {
        let Some(component) = supported_component(&e.kind) else { continue };
        let mut payload = serde_json::Map::new();
        payload.insert("unique_id".into(), json!(format!("odb_{}_{}", obj, e.key)));
        payload.insert("object_id".into(), json!(format!("{}_{}", obj, e.key)));
        payload.insert("name".into(), json!(titleize(&e.key)));
        payload.insert("state_topic".into(), json!(state));
        payload.insert("availability_topic".into(), json!(BRIDGE_AVAILABILITY_TOPIC));
        payload.insert("payload_available".into(), json!(AVAILABLE));
        payload.insert("payload_not_available".into(), json!(UNAVAILABLE));
        payload.insert("device".into(), device.clone());
        if !e.device_class.is_empty() {
            payload.insert("device_class".into(), json!(e.device_class));
        }
        if !e.entity_category.is_empty() {
            payload.insert("entity_category".into(), json!(e.entity_category));
        }
        match e.kind.as_str() {
            "sensor" => {
                payload.insert("value_template".into(), json!(format!("{{{{ value_json.{} }}}}", e.key)));
                if !e.unit.is_empty() {
                    payload.insert("unit_of_measurement".into(), json!(e.unit));
                }
            }
            "binary_sensor" => {
                payload.insert(
                    "value_template".into(),
                    json!(format!("{{{{ 'ON' if value_json.{} else 'OFF' }}}}", e.key)),
                );
                payload.insert("payload_on".into(), json!("ON"));
                payload.insert("payload_off".into(), json!("OFF"));
            }
            _ => {}
        }
        out.push(OutMessage {
            topic: format!("homeassistant/{}/odb_{}/{}/config", component, obj, e.key),
            payload: serde_json::to_string(&Value::Object(payload)).unwrap(),
            retained: true,
        });
    }
    out
}

fn titleize(key: &str) -> String {
    key.split('_')
        .filter(|p| !p.is_empty())
        .map(|p| {
            let mut c = p.chars();
            match c.next() {
                Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::Entity;

    fn dev() -> Device {
        Device {
            id: "mx-keys-mini".into(),
            name: "MX Keys Mini".into(),
            manufacturer: "Logitech".into(),
            model: "MX Keys Mini".into(),
            entities: vec![
                Entity { key: "battery".into(), kind: "sensor".into(), device_class: "battery".into(), unit: "%".into(), entity_category: "".into() },
                Entity { key: "connected".into(), kind: "binary_sensor".into(), device_class: "connectivity".into(), unit: "".into(), entity_category: "".into() },
                Entity { key: "firmware".into(), kind: "sensor".into(), device_class: "".into(), unit: "".into(), entity_category: "diagnostic".into() },
            ],
        }
    }
    fn prov() -> ProviderInfo {
        ProviderInfo { id: "ble-battery".into(), name: "BLE Battery".into(), version: "1.0.0".into() }
    }
    fn parse(s: &str) -> Value { serde_json::from_str(s).unwrap() }

    #[test]
    fn slug_cases() {
        assert_eq!(slug("MX Keys Mini"), "mx_keys_mini");
        assert_eq!(slug("ble-battery"), "ble_battery");
        assert_eq!(slug("!!!"), "device");
    }

    #[test]
    fn object_and_state_topic() {
        assert_eq!(object_id("ble-battery", "mx-keys-mini"), "ble_battery_mx_keys_mini");
        assert_eq!(state_topic("ble-battery", "mx-keys-mini"), "odb/ble_battery/mx_keys_mini/state");
    }

    #[test]
    fn three_configs_without_control() {
        let msgs = discovery_messages(&prov(), &dev());
        assert_eq!(msgs.len(), 3);
        assert!(msgs.iter().all(|m| m.retained));
    }

    #[test]
    fn battery_config_payload() {
        let msgs = discovery_messages(&prov(), &dev());
        let b = msgs.iter().find(|m| m.topic.contains("/battery/config")).unwrap();
        assert_eq!(b.topic, "homeassistant/sensor/odb_ble_battery_mx_keys_mini/battery/config");
        let p = parse(&b.payload);
        assert_eq!(p["unique_id"], "odb_ble_battery_mx_keys_mini_battery");
        assert_eq!(p["device_class"], "battery");
        assert_eq!(p["unit_of_measurement"], "%");
        assert_eq!(p["state_topic"], "odb/ble_battery/mx_keys_mini/state");
        assert_eq!(p["value_template"], "{{ value_json.battery }}");
        assert_eq!(p["device"]["name"], "MX Keys Mini");
    }

    #[test]
    fn binary_sensor_template() {
        let msgs = discovery_messages(&prov(), &dev());
        let c = msgs.iter().find(|m| m.topic.contains("/connected/config")).unwrap();
        assert!(c.topic.starts_with("homeassistant/binary_sensor/"));
        let p = parse(&c.payload);
        assert_eq!(p["value_template"], "{{ 'ON' if value_json.connected else 'OFF' }}");
        assert_eq!(p["payload_on"], "ON");
    }

    #[test]
    fn unknown_kind_skipped() {
        let mut d = dev();
        d.entities = vec![
            Entity { key: "press".into(), kind: "button".into(), device_class: "".into(), unit: "".into(), entity_category: "".into() },
            Entity { key: "level".into(), kind: "sensor".into(), device_class: "".into(), unit: "".into(), entity_category: "".into() },
        ];
        assert_eq!(discovery_messages(&prov(), &d).len(), 1);
    }
}
```

- [ ] **Step 2: Wire the module** — add `mod hapublish;` to `src-tauri/src/main.rs`.

- [ ] **Step 3: Run tests**

Run: `source "$HOME/.cargo/env" && cargo test --manifest-path src-tauri/Cargo.toml hapublish`
Expected: 6 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/hapublish.rs src-tauri/src/main.rs
git commit -m "feat(rust): HA MQTT Discovery + state mapper (port of Go, cargo tests)"
```

---

## Task 4: config.rs (settings + keyring)

**Files:**
- Create: `src-tauri/src/config.rs`
- Modify: `src-tauri/src/main.rs` (`mod config;`)

- [ ] **Step 1: Implement with tests**

Create `src-tauri/src/config.rs`:
```rust
//! Persisted settings (file) + MQTT password (OS keyring).
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

const KEYRING_SERVICE: &str = "online.99lab.opendevicesbridge";
const KEYRING_ACCOUNT: &str = "mqtt.password";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Settings {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub interval_minutes: u32,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { host: String::new(), port: 1883, username: String::new(), interval_minutes: 5 }
    }
}

pub fn config_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("OpenDevicesBridge").join("config.json"))
}

pub fn load_from(path: &Path) -> Settings {
    match std::fs::read_to_string(path) {
        Ok(s) => serde_json::from_str(&s).unwrap_or_default(),
        Err(_) => Settings::default(),
    }
}

pub fn save_to(path: &Path, s: &Settings) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, serde_json::to_vec_pretty(s).unwrap())
}

pub fn load() -> Settings {
    config_path().map(|p| load_from(&p)).unwrap_or_default()
}

pub fn save(s: &Settings) -> std::io::Result<()> {
    let path = config_path().ok_or_else(|| std::io::Error::other("no config dir"))?;
    save_to(&path, s)
}

pub fn password() -> String {
    keyring::Entry::new(KEYRING_SERVICE, KEYRING_ACCOUNT)
        .and_then(|e| e.get_password())
        .unwrap_or_default()
}

pub fn set_password(p: &str) {
    if let Ok(entry) = keyring::Entry::new(KEYRING_SERVICE, KEYRING_ACCOUNT) {
        if p.is_empty() {
            let _ = entry.delete_credential();
        } else {
            let _ = entry.set_password(p);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let dir = std::env::temp_dir().join(format!("odb-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("config.json");
        let s = Settings { host: "192.168.31.150".into(), port: 1883, username: "ha".into(), interval_minutes: 5 };
        save_to(&path, &s).unwrap();
        assert_eq!(load_from(&path), s);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn missing_returns_defaults() {
        let s = load_from(Path::new("/nonexistent/odb/none.json"));
        assert_eq!(s.port, 1883);
        assert_eq!(s.interval_minutes, 5);
    }
}
```

- [ ] **Step 2: Wire** — add `mod config;` to `main.rs`.

- [ ] **Step 3: Run tests**

Run: `source "$HOME/.cargo/env" && cargo test --manifest-path src-tauri/Cargo.toml config`
Expected: 2 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/config.rs src-tauri/src/main.rs
git commit -m "feat(rust): settings file + keyring-backed MQTT password"
```

---

## Task 5: registry.rs (provider discovery)

**Files:**
- Create: `src-tauri/src/registry.rs`
- Modify: `src-tauri/src/main.rs` (`mod registry;`)

- [ ] **Step 1: Implement with tests**

Create `src-tauri/src/registry.rs`:
```rust
//! Discover provider executables from provider.json manifests.
use serde::Deserialize;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Deserialize)]
pub struct Manifest {
    pub id: String,
    pub name: String,
    pub exec: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub platforms: Vec<String>,
    #[serde(default)]
    pub enabled: bool,
    #[serde(skip)]
    pub dir: PathBuf,
}

impl Manifest {
    /// (command, args) to launch. A `.py` exec runs via python3.
    pub fn command(&self) -> (String, Vec<String>) {
        let exec_path = self.dir.join(&self.exec);
        if self.exec.ends_with(".py") {
            let mut args = vec![exec_path.to_string_lossy().to_string()];
            args.extend(self.args.clone());
            ("python3".into(), args)
        } else {
            (exec_path.to_string_lossy().to_string(), self.args.clone())
        }
    }
}

fn current_os() -> &'static str {
    std::env::consts::OS // "macos", "linux", "windows"
}

fn os_matches(platforms: &[String]) -> bool {
    // Tauri/Rust uses "macos"; manifests use "darwin". Accept both.
    let os = current_os();
    platforms.iter().any(|p| p == os || (os == "macos" && p == "darwin"))
}

pub fn discover(roots: &[PathBuf]) -> Vec<Manifest> {
    let mut out = Vec::new();
    for root in roots {
        let Ok(entries) = std::fs::read_dir(root) else { continue };
        for entry in entries.flatten() {
            if !entry.path().is_dir() {
                continue;
            }
            let manifest_path = entry.path().join("provider.json");
            let Ok(data) = std::fs::read_to_string(&manifest_path) else { continue };
            let Ok(mut m) = serde_json::from_str::<Manifest>(&data) else { continue };
            m.dir = entry.path();
            if m.enabled && os_matches(&m.platforms) {
                out.push(m);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_manifest(dir: &Path, content: &str) {
        std::fs::create_dir_all(dir).unwrap();
        std::fs::write(dir.join("provider.json"), content).unwrap();
    }

    #[test]
    fn filters_disabled_and_os() {
        let root = std::env::temp_dir().join(format!("odb-reg-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        write_manifest(&root.join("on"), r#"{"id":"on","name":"On","exec":"x","platforms":["macos","darwin","linux","windows"],"enabled":true}"#);
        write_manifest(&root.join("off"), r#"{"id":"off","name":"Off","exec":"x","platforms":["macos","darwin","linux","windows"],"enabled":false}"#);
        let got = discover(&[root.clone()]);
        let ids: Vec<_> = got.iter().map(|m| m.id.clone()).collect();
        assert!(ids.contains(&"on".to_string()));
        assert!(!ids.contains(&"off".to_string()));
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn py_command_uses_python3() {
        let m = Manifest {
            id: "h".into(), name: "H".into(), exec: "host_info.py".into(),
            args: vec![], platforms: vec![], enabled: true, dir: PathBuf::from("/p"),
        };
        let (cmd, args) = m.command();
        assert_eq!(cmd, "python3");
        assert_eq!(args[0], "/p/host_info.py");
    }
}
```

- [ ] **Step 2: Wire** — add `mod registry;` to `main.rs`.

- [ ] **Step 3: Run tests**

Run: `source "$HOME/.cargo/env" && cargo test --manifest-path src-tauri/Cargo.toml registry`
Expected: 2 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/registry.rs src-tauri/src/main.rs
git commit -m "feat(rust): provider registry discovery (manifest + OS filter)"
```

---

## Task 6: provider.rs (spawn + stream + restart) + host-info integration test

**Files:**
- Create: `src-tauri/src/provider.rs`
- Modify: `src-tauri/src/main.rs` (`mod provider;`)

- [ ] **Step 1: Implement the process supervisor**

Create `src-tauri/src/provider.rs`:
```rust
//! Spawn provider processes, stream their JSONL messages, restart on exit.
use crate::protocol::{decode_line, Command, Message};
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, Command as PCommand, Stdio};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

/// An event from a provider, tagged with the provider id.
pub enum ProviderEvent {
    Message(String, Message),
    Exited(String),
}

/// Supervises one provider: keeps it running, restarting with backoff.
pub struct Supervisor {
    pub id: String,
    command: String,
    args: Vec<String>,
    tx: Sender<ProviderEvent>,
    child: Arc<Mutex<Option<Child>>>,
    stop: Arc<Mutex<bool>>,
}

impl Supervisor {
    pub fn new(id: String, command: String, args: Vec<String>, tx: Sender<ProviderEvent>) -> Self {
        Supervisor { id, command, args, tx, child: Arc::new(Mutex::new(None)), stop: Arc::new(Mutex::new(false)) }
    }

    pub fn start(self: &Arc<Self>) {
        let me = Arc::clone(self);
        thread::spawn(move || me.run());
    }

    fn run(self: Arc<Self>) {
        let mut backoff = Duration::from_secs(1);
        loop {
            if *self.stop.lock().unwrap() {
                return;
            }
            match self.launch_once() {
                Ok(()) => backoff = Duration::from_secs(1),
                Err(_) => {}
            }
            let _ = self.tx.send(ProviderEvent::Exited(self.id.clone()));
            if *self.stop.lock().unwrap() {
                return;
            }
            thread::sleep(backoff);
            backoff = (backoff * 2).min(Duration::from_secs(60));
        }
    }

    fn launch_once(&self) -> std::io::Result<()> {
        let mut child = PCommand::new(&self.command)
            .args(&self.args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;
        let stdout = child.stdout.take().unwrap();
        *self.child.lock().unwrap() = Some(child);

        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            let Ok(line) = line else { break };
            if line.trim().is_empty() {
                continue;
            }
            if let Ok(msg) = decode_line(&line) {
                let _ = self.tx.send(ProviderEvent::Message(self.id.clone(), msg));
            }
        }
        if let Some(mut c) = self.child.lock().unwrap().take() {
            let _ = c.wait();
        }
        Ok(())
    }

    /// Send a host→provider command on stdin.
    pub fn send(&self, cmd: &Command) {
        if let Some(child) = self.child.lock().unwrap().as_mut() {
            if let Some(stdin) = child.stdin.as_mut() {
                if let Ok(mut json) = serde_json::to_vec(cmd) {
                    json.push(b'\n');
                    let _ = stdin.write_all(&json);
                }
            }
        }
    }

    pub fn stop(&self) {
        *self.stop.lock().unwrap() = true;
        if let Some(child) = self.child.lock().unwrap().as_mut() {
            let _ = child.kill();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc::channel;

    #[test]
    fn host_info_selftest_streams_valid_messages() {
        // Locate the repo's host-info provider relative to the crate.
        let script = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../providers/host-info/host_info.py");
        assert!(script.exists(), "host_info.py missing at {:?}", script);

        let (tx, rx) = channel();
        let sup = Arc::new(Supervisor::new(
            "host-info".into(),
            "python3".into(),
            vec![script.to_string_lossy().into(), "--selftest".into()],
            tx,
        ));
        sup.start();

        let mut kinds = Vec::new();
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        while std::time::Instant::now() < deadline && kinds.len() < 3 {
            if let Ok(ProviderEvent::Message(_, m)) = rx.recv_timeout(Duration::from_secs(2)) {
                kinds.push(m.kind);
            }
        }
        sup.stop();
        assert!(kinds.contains(&"hello".to_string()), "got {:?}", kinds);
        assert!(kinds.contains(&"devices".to_string()), "got {:?}", kinds);
        assert!(kinds.contains(&"state".to_string()), "got {:?}", kinds);
    }
}
```

- [ ] **Step 2: Wire** — add `mod provider;` to `main.rs`.

- [ ] **Step 3: Run tests**

Run: `source "$HOME/.cargo/env" && cargo test --manifest-path src-tauri/Cargo.toml provider`
Expected: the `host_info_selftest_streams_valid_messages` test passes (runs the real Python provider).

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/provider.rs src-tauri/src/main.rs
git commit -m "feat(rust): provider supervisor (spawn/stream/restart) + host-info integration test"
```

---

## Task 7: mqtt.rs (rumqttc client + LWT)

**Files:**
- Create: `src-tauri/src/mqtt.rs`
- Modify: `src-tauri/src/main.rs` (`mod mqtt;`)

- [ ] **Step 1: Implement the MQTT client**

Create `src-tauri/src/mqtt.rs`:
```rust
//! MQTT client with HA bridge availability (LWT online/offline).
use crate::config::Settings;
use crate::hapublish::{OutMessage, AVAILABLE, BRIDGE_AVAILABILITY_TOPIC, UNAVAILABLE};
use rumqttc::{Client, LastWill, MqttOptions, QoS};
use std::sync::mpsc::{channel, Sender};
use std::thread;
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Disconnected,
    Connecting,
    Connected,
}

/// A running MQTT connection. Publishes are sent through a channel to the
/// background event-loop thread.
pub struct MqttHandle {
    tx: Sender<OutMessage>,
}

impl MqttHandle {
    pub fn publish(&self, msg: OutMessage) {
        let _ = self.tx.send(msg);
    }
}

/// Connect using settings+password. `on_status` is called on state changes.
/// Returns None if host is empty.
pub fn connect(
    settings: &Settings,
    password: &str,
    on_status: impl Fn(Status) + Send + 'static,
) -> Option<MqttHandle> {
    if settings.host.is_empty() || settings.port == 0 {
        return None;
    }
    let mut opts = MqttOptions::new("open-devices-bridge", &settings.host, settings.port);
    opts.set_keep_alive(Duration::from_secs(60));
    if !settings.username.is_empty() {
        opts.set_credentials(&settings.username, password);
    }
    opts.set_last_will(LastWill::new(
        BRIDGE_AVAILABILITY_TOPIC,
        UNAVAILABLE,
        QoS::AtLeastOnce,
        true,
    ));

    let (client, mut connection) = Client::new(opts, 64);
    let (tx, rx) = channel::<OutMessage>();

    // Publisher thread: drains the channel.
    let pub_client = client.clone();
    thread::spawn(move || {
        for msg in rx {
            let _ = pub_client.publish(&msg.topic, QoS::AtLeastOnce, msg.retained, msg.payload);
        }
    });

    // Event-loop thread: drives the connection, reports status, announces online.
    on_status(Status::Connecting);
    thread::spawn(move || {
        for event in connection.iter() {
            match event {
                Ok(rumqttc::Event::Incoming(rumqttc::Packet::ConnAck(_))) => {
                    let _ = client.publish(BRIDGE_AVAILABILITY_TOPIC, QoS::AtLeastOnce, true, AVAILABLE);
                    on_status(Status::Connected);
                }
                Err(_) => {
                    on_status(Status::Connecting);
                    thread::sleep(Duration::from_secs(5));
                }
                _ => {}
            }
        }
    });

    Some(MqttHandle { tx })
}
```

- [ ] **Step 2: Wire** — add `mod mqtt;` to `main.rs`.

- [ ] **Step 3: Verify it compiles**

Run: `source "$HOME/.cargo/env" && cargo build --manifest-path src-tauri/Cargo.toml 2>&1 | tail -10`
Expected: compiles cleanly (no tests here — MQTT is integration-verified in Task 13).

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/mqtt.rs src-tauri/src/main.rs
git commit -m "feat(rust): rumqttc MQTT client with bridge availability + LWT"
```

---

## Task 8: orchestrator.rs (wire providers → mapper → mqtt → snapshot)

**Files:**
- Create: `src-tauri/src/orchestrator.rs`
- Modify: `src-tauri/src/main.rs` (`mod orchestrator;`)

- [ ] **Step 1: Implement the orchestrator + shared snapshot**

Create `src-tauri/src/orchestrator.rs`:
```rust
//! Wires providers to the HA mapper + MQTT and keeps a live snapshot.
use crate::config::{self, Settings};
use crate::hapublish::{self};
use crate::mqtt::{self, MqttHandle, Status};
use crate::protocol::{Device, ProviderInfo};
use crate::provider::{ProviderEvent, Supervisor};
use crate::registry;
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::mpsc::channel;
use std::sync::{Arc, Mutex};
use std::thread;

/// A device as shown in the UI snapshot.
#[derive(Debug, Clone, Serialize)]
pub struct UiDevice {
    pub provider: String,
    pub id: String,
    pub name: String,
    pub values: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct Snapshot {
    pub devices: Vec<UiDevice>,
    pub mqtt: String, // "connected" | "connecting" | "disconnected"
}

#[derive(Default)]
struct State {
    infos: BTreeMap<String, ProviderInfo>,
    devices: BTreeMap<String, Vec<Device>>,         // provider -> devices
    values: BTreeMap<(String, String), BTreeMap<String, Value>>,
    mqtt: Status,
}

impl Default for Status {
    fn default() -> Self { Status::Disconnected }
}

/// Shared, cloneable orchestrator handle.
#[derive(Clone)]
pub struct Orchestrator {
    state: Arc<Mutex<State>>,
    mqtt: Arc<Mutex<Option<MqttHandle>>>,
    on_change: Arc<dyn Fn(Snapshot) + Send + Sync>,
    supervisors: Arc<Mutex<Vec<Arc<Supervisor>>>>,
}

impl Orchestrator {
    pub fn new(on_change: impl Fn(Snapshot) + Send + Sync + 'static) -> Self {
        Orchestrator {
            state: Arc::new(Mutex::new(State::default())),
            mqtt: Arc::new(Mutex::new(None)),
            on_change: Arc::new(on_change),
            supervisors: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        let st = self.state.lock().unwrap();
        let mut devices = Vec::new();
        for (provider, devs) in &st.devices {
            for d in devs {
                let values = st.values.get(&(provider.clone(), d.id.clone())).cloned().unwrap_or_default();
                devices.push(UiDevice { provider: provider.clone(), id: d.id.clone(), name: d.name.clone(), values });
            }
        }
        Snapshot {
            devices,
            mqtt: match st.mqtt {
                Status::Connected => "connected",
                Status::Connecting => "connecting",
                Status::Disconnected => "disconnected",
            }
            .into(),
        }
    }

    fn emit(&self) {
        (self.on_change)(self.snapshot());
    }

    /// (Re)connect MQTT from the given settings.
    pub fn connect_mqtt(&self, settings: &Settings, password: &str) {
        let me = self.clone();
        let handle = mqtt::connect(settings, password, move |status| {
            me.state.lock().unwrap().mqtt = status;
            me.emit();
        });
        *self.mqtt.lock().unwrap() = handle;
    }

    fn publish(&self, msg: hapublish::OutMessage) {
        if let Some(h) = self.mqtt.lock().unwrap().as_ref() {
            h.publish(msg);
        }
    }

    /// Discover and launch providers in the given roots.
    pub fn start(&self, roots: Vec<PathBuf>) {
        let (tx, rx) = channel::<ProviderEvent>();
        for m in registry::discover(&roots) {
            let (cmd, args) = m.command();
            let sup = Arc::new(Supervisor::new(m.id.clone(), cmd, args, tx.clone()));
            sup.start();
            self.supervisors.lock().unwrap().push(sup);
        }
        let me = self.clone();
        thread::spawn(move || {
            for ev in rx {
                me.handle(ev);
            }
        });
    }

    fn handle(&self, ev: ProviderEvent) {
        match ev {
            ProviderEvent::Message(provider, m) => match m.kind.as_str() {
                "hello" => {
                    if let Some(info) = m.provider {
                        self.state.lock().unwrap().infos.insert(provider, info);
                    }
                }
                "devices" => {
                    let info = self.state.lock().unwrap().infos.get(&provider).cloned()
                        .unwrap_or(ProviderInfo { id: provider.clone(), name: provider.clone(), version: String::new() });
                    for d in &m.devices {
                        for msg in hapublish::discovery_messages(&info, d) {
                            self.publish(msg);
                        }
                    }
                    self.state.lock().unwrap().devices.insert(provider, m.devices);
                    self.emit();
                }
                "state" => {
                    let key = (provider.clone(), m.device.clone());
                    self.state.lock().unwrap().values.insert(key, m.values.clone());
                    let dev = self.state.lock().unwrap().devices.get(&provider)
                        .and_then(|ds| ds.iter().find(|d| d.id == m.device).cloned());
                    if let Some(d) = dev {
                        self.publish(hapublish::state_message(&provider, &d, &m.values));
                    }
                    self.emit();
                }
                _ => {}
            },
            ProviderEvent::Exited(_provider) => {
                self.emit();
            }
        }
    }
}

/// Standard provider search roots: bundled (next to the executable in the .app
/// Resources) and the user dir.
pub fn provider_roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            roots.push(dir.join("../Resources/providers")); // macOS .app
            roots.push(dir.join("providers")); // dev/other layouts
        }
    }
    if let Some(cfg) = dirs::config_dir() {
        roots.push(cfg.join("OpenDevicesBridge").join("providers"));
    }
    let _ = config::config_path(); // keep config module referenced
    roots
}
```

- [ ] **Step 2: Wire** — add `mod orchestrator;` to `main.rs`.

- [ ] **Step 3: Verify it compiles**

Run: `source "$HOME/.cargo/env" && cargo build --manifest-path src-tauri/Cargo.toml 2>&1 | tail -10`
Expected: compiles cleanly.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/orchestrator.rs src-tauri/src/main.rs
git commit -m "feat(rust): orchestrator wiring providers -> HA mapper -> MQTT + snapshot"
```

---

## Task 9: Tauri commands + tray + popover wiring (main.rs)

**Files:**
- Create: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/main.rs`

- [ ] **Step 1: Commands**

Create `src-tauri/src/commands.rs`:
```rust
//! Tauri commands callable from the Svelte frontend.
use crate::config::{self, Settings};
use crate::mqtt;
use crate::orchestrator::{Orchestrator, Snapshot};
use std::sync::mpsc::channel;
use std::time::Duration;

#[tauri::command]
pub fn get_snapshot(orch: tauri::State<Orchestrator>) -> Snapshot {
    orch.snapshot()
}

#[tauri::command]
pub fn load_settings() -> Settings {
    config::load()
}

#[tauri::command]
pub fn save_settings(orch: tauri::State<Orchestrator>, settings: Settings, password: String) -> Result<(), String> {
    config::save(&settings).map_err(|e| e.to_string())?;
    config::set_password(&password);
    orch.connect_mqtt(&settings, &password);
    Ok(())
}

/// Try connecting to the broker; returns Ok(()) on success within a timeout.
#[tauri::command]
pub fn test_connection(settings: Settings, password: String) -> Result<(), String> {
    let (tx, rx) = channel();
    let handle = mqtt::connect(&settings, &password, move |status| {
        if status == mqtt::Status::Connected {
            let _ = tx.send(());
        }
    });
    if handle.is_none() {
        return Err("Host/porta inválidos".into());
    }
    match rx.recv_timeout(Duration::from_secs(8)) {
        Ok(()) => Ok(()),
        Err(_) => Err("Timeout — sem resposta do broker".into()),
    }
}

#[tauri::command]
pub fn quit(app: tauri::AppHandle) {
    app.exit(0);
}
```

- [ ] **Step 2: Rewrite `src-tauri/src/main.rs`**

Replace `src-tauri/src/main.rs` with (keep all the `mod` lines added in prior tasks):
```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod config;
mod hapublish;
mod mqtt;
mod orchestrator;
mod protocol;
mod provider;
mod registry;

use orchestrator::Orchestrator;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{TrayIconBuilder, TrayIconEvent},
    Emitter, Manager, WebviewUrl, WebviewWindowBuilder,
};
use tauri_plugin_positioner::{Position, WindowExt};

fn lowest_battery(snap: &orchestrator::Snapshot) -> Option<i64> {
    snap.devices
        .iter()
        .filter_map(|d| d.values.get("battery").and_then(|v| v.as_i64()))
        .min()
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_positioner::init())
        .invoke_handler(tauri::generate_handler![
            commands::get_snapshot,
            commands::load_settings,
            commands::save_settings,
            commands::test_connection,
            commands::quit,
        ])
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let handle = app.handle().clone();

            // Orchestrator emits snapshots to the frontend + updates the tray title.
            let tray_handle = app.handle().clone();
            let orch = Orchestrator::new(move |snap| {
                let _ = tray_handle.emit("snapshot", &snap);
                if let Some(tray) = tray_handle.tray_by_id("main") {
                    let title = lowest_battery(&snap).map(|b| format!(" {}%", b)).unwrap_or_default();
                    let _ = tray.set_title(Some(&title));
                }
            });
            app.manage(orch.clone());

            // Hidden frameless popover window.
            let popover = WebviewWindowBuilder::new(app, "popover", WebviewUrl::App("index.html".into()))
                .title("Open Devices Bridge")
                .decorations(false)
                .always_on_top(true)
                .visible(false)
                .skip_taskbar(true)
                .inner_size(320.0, 420.0)
                .build()?;
            let _ = popover.hide();

            // Tray icon with a fallback menu.
            let settings_item = MenuItem::with_id(app, "settings", "Configurações…", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "Sair", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&settings_item, &quit_item])?;

            let _tray = TrayIconBuilder::with_id("main")
                .icon(app.default_window_icon().unwrap().clone())
                .icon_as_template(true)
                .menu(&menu)
                .menu_on_left_click(false)
                .on_menu_event(move |app, event| match event.id.as_ref() {
                    "settings" => open_settings(app),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);
                    if let TrayIconEvent::Click { .. } = event {
                        let app = tray.app_handle();
                        if let Some(win) = app.get_webview_window("popover") {
                            if win.is_visible().unwrap_or(false) {
                                let _ = win.hide();
                            } else {
                                let _ = win.move_window(Position::TrayCenter);
                                let _ = win.show();
                                let _ = win.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            // Start providers + connect MQTT from saved settings.
            let settings = config::load();
            let password = config::password();
            orch.connect_mqtt(&settings, &password);
            orch.start(orchestrator::provider_roots());

            let _ = handle; // reserved
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error building tauri app")
        .run(|_app, _event| {});
}

fn open_settings(app: &tauri::AppHandle) {
    if let Some(win) = app.get_webview_window("settings") {
        let _ = win.show();
        let _ = win.set_focus();
        return;
    }
    let _ = WebviewWindowBuilder::new(app, "settings", WebviewUrl::App("index.html?settings".into()))
        .title("Open Devices Bridge — Configurações")
        .inner_size(440.0, 380.0)
        .resizable(false)
        .build();
}
```

- [ ] **Step 3: Verify it compiles**

Run: `source "$HOME/.cargo/env" && cargo build --manifest-path src-tauri/Cargo.toml 2>&1 | tail -20`
Expected: compiles. If a Tauri v2 API name differs (e.g. `set_title`, `move_window`, `icon_as_template`, `tray_by_id`), adapt to the resolved tauri 2.x API (consult `cargo doc -p tauri --open` or the crate source) and keep behavior. Note any adaptation.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/commands.rs src-tauri/src/main.rs
git commit -m "feat(rust): Tauri commands + tray icon/title + popover window wiring"
```

---

## Task 10: Svelte frontend (popover + settings)

**Files:**
- Create: `src/lib/api.ts`, `src/lib/Popover.svelte`, `src/lib/Settings.svelte`
- Modify: `src/App.svelte`

- [ ] **Step 1: Typed API wrappers**

Create `src/lib/api.ts`:
```ts
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

export type UiDevice = {
  provider: string;
  id: string;
  name: string;
  values: Record<string, unknown>;
};
export type Snapshot = { devices: UiDevice[]; mqtt: string };
export type Settings = { host: string; port: number; username: string; interval_minutes: number };

export const getSnapshot = () => invoke<Snapshot>("get_snapshot");
export const loadSettings = () => invoke<Settings>("load_settings");
export const saveSettings = (settings: Settings, password: string) =>
  invoke<void>("save_settings", { settings, password });
export const testConnection = (settings: Settings, password: string) =>
  invoke<void>("test_connection", { settings, password });
export const quit = () => invoke<void>("quit");
export const onSnapshot = (cb: (s: Snapshot) => void) => listen<Snapshot>("snapshot", (e) => cb(e.payload));
```

- [ ] **Step 2: Popover panel**

Create `src/lib/Popover.svelte`:
```svelte
<script lang="ts">
  import { onMount } from "svelte";
  import { getSnapshot, onSnapshot, quit, type Snapshot } from "./api";

  let snap = $state<Snapshot>({ devices: [], mqtt: "disconnected" });

  onMount(async () => {
    snap = await getSnapshot();
    onSnapshot((s) => (snap = s));
  });

  function battery(d: Record<string, unknown>): number | null {
    const b = d.battery;
    return typeof b === "number" ? b : null;
  }
  function inUse(d: Record<string, unknown>): boolean {
    return d.in_use === true;
  }
  function openSettings() {
    // The settings window is opened from the native menu; here we just hint.
    window.location.search = "?settings";
  }
  const mqttLabel: Record<string, string> = {
    connected: "conectado",
    connecting: "conectando…",
    disconnected: "desconectado",
  };
</script>

<div class="panel">
  <header>Open Devices Bridge</header>
  {#if snap.devices.length === 0}
    <p class="empty">Nenhum dispositivo</p>
  {/if}
  <ul>
    {#each snap.devices as d (d.provider + d.id)}
      <li>
        <span class="name">{d.name}</span>
        {#if battery(d.values) !== null}
          <span class="bar"><i style="width:{battery(d.values)}%"></i></span>
          <span class="pct">{battery(d.values)}%</span>
        {:else if "in_use" in d.values}
          <span class="chip" class:on={inUse(d.values)}>{inUse(d.values) ? "em uso" : "livre"}</span>
        {/if}
      </li>
    {/each}
  </ul>
  <footer>
    <span class="mqtt" data-s={snap.mqtt}>MQTT: {mqttLabel[snap.mqtt] ?? snap.mqtt}</span>
    <span class="spacer"></span>
    <button onclick={openSettings}>Configurações</button>
    <button onclick={quit}>Sair</button>
  </footer>
</div>

<style>
  .panel { display: flex; flex-direction: column; height: 100vh; box-sizing: border-box; padding: 12px; gap: 8px; }
  header { font-weight: 600; font-size: 13px; opacity: 0.8; }
  ul { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 8px; overflow: auto; flex: 1; }
  li { display: flex; align-items: center; gap: 8px; font-size: 13px; }
  .name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .bar { width: 64px; height: 8px; background: rgba(127,127,127,0.25); border-radius: 4px; overflow: hidden; }
  .bar i { display: block; height: 100%; background: #34c759; }
  .pct { width: 36px; text-align: right; font-variant-numeric: tabular-nums; }
  .chip { font-size: 11px; padding: 2px 8px; border-radius: 10px; background: rgba(127,127,127,0.2); }
  .chip.on { background: #34c759; color: white; }
  .empty { opacity: 0.5; font-size: 13px; }
  footer { display: flex; align-items: center; gap: 6px; border-top: 1px solid rgba(127,127,127,0.2); padding-top: 8px; }
  .spacer { flex: 1; }
  .mqtt { font-size: 11px; opacity: 0.7; }
  button { font: inherit; font-size: 12px; padding: 4px 10px; border-radius: 6px; border: none; background: rgba(127,127,127,0.18); cursor: pointer; }
  button:hover { background: rgba(127,127,127,0.3); }
</style>
```

- [ ] **Step 3: Settings form**

Create `src/lib/Settings.svelte`:
```svelte
<script lang="ts">
  import { onMount } from "svelte";
  import { loadSettings, saveSettings, testConnection, type Settings } from "./api";

  let s = $state<Settings>({ host: "", port: 1883, username: "", interval_minutes: 5 });
  let password = $state("");
  let testMsg = $state("");
  let testing = $state(false);

  onMount(async () => { s = await loadSettings(); });

  async function runTest() {
    testing = true; testMsg = "";
    try { await testConnection($state.snapshot(s), password); testMsg = "✓ Conectado"; }
    catch (e) { testMsg = "✗ " + e; }
    finally { testing = false; }
  }
  async function save() { await saveSettings($state.snapshot(s), password); }
</script>

<form class="settings" onsubmit={(e) => { e.preventDefault(); save(); }}>
  <h1>Home Assistant — MQTT</h1>
  <label>Broker (host)<input bind:value={s.host} placeholder="192.168.31.150" /></label>
  <label>Porta<input type="number" bind:value={s.port} /></label>
  <label>Usuário<input bind:value={s.username} placeholder="opcional" /></label>
  <label>Senha<input type="password" bind:value={password} placeholder="opcional" /></label>
  <label>Intervalo (min)<input type="number" min="1" bind:value={s.interval_minutes} /></label>
  <div class="row">
    <button type="button" onclick={runTest} disabled={testing}>{testing ? "Testando…" : "Testar conexão"}</button>
    <span class="msg">{testMsg}</span>
    <span class="spacer"></span>
    <button type="submit" class="primary">Salvar</button>
  </div>
</form>

<style>
  .settings { display: flex; flex-direction: column; gap: 12px; padding: 20px; }
  h1 { font-size: 14px; margin: 0 0 4px; }
  label { display: grid; grid-template-columns: 120px 1fr; align-items: center; gap: 10px; font-size: 13px; }
  input { font: inherit; padding: 6px 8px; border-radius: 6px; border: 1px solid rgba(127,127,127,0.4); background: transparent; color: inherit; }
  .row { display: flex; align-items: center; gap: 10px; margin-top: 8px; }
  .msg { font-size: 12px; opacity: 0.7; }
  .spacer { flex: 1; }
  button { font: inherit; font-size: 13px; padding: 6px 14px; border-radius: 6px; border: none; background: rgba(127,127,127,0.18); cursor: pointer; }
  button.primary { background: #0a84ff; color: white; }
  button:disabled { opacity: 0.5; }
</style>
```

- [ ] **Step 4: Route by query string in App.svelte**

Replace `src/App.svelte`:
```svelte
<script lang="ts">
  import Popover from "./lib/Popover.svelte";
  import Settings from "./lib/Settings.svelte";
  const isSettings = window.location.search.includes("settings");
</script>

{#if isSettings}
  <Settings />
{:else}
  <Popover />
{/if}

<style>
  :global(html, body) { margin: 0; }
  :global(body) {
    font-family: -apple-system, system-ui, sans-serif;
    color: #1d1d1f;
    background: rgba(250, 250, 250, 0.96);
  }
  @media (prefers-color-scheme: dark) {
    :global(body) { color: #f5f5f7; background: rgba(30, 30, 30, 0.96); }
  }
</style>
```

- [ ] **Step 5: Build the frontend**

Run: `cd /Users/hudsonbrendon/Github/ha-battery-bridge && npm run build 2>&1 | tail -10`
Expected: Vite builds to `dist/` with no errors.

- [ ] **Step 6: Commit**

```bash
git add src package.json
git commit -m "feat(ui): Svelte popover panel + settings form"
```

---

## Task 11: Packaging — bundle providers, real icon, build the .dmg

**Files:**
- Modify: `src-tauri/tauri.conf.json`
- Create: `scripts/build-providers.sh`

- [ ] **Step 1: Build the native providers before bundling**

Create `scripts/build-providers.sh`:
```bash
#!/usr/bin/env bash
# Builds the Swift providers and stages all providers under a clean tree that
# Tauri bundles as Resources/providers.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> build ble-battery"
( cd providers/ble-battery && swift build -c release )
echo "==> build camera-mac"
( cd providers/camera-mac && swift build -c release )

STAGE="src-tauri/providers"
rm -rf "$STAGE"
mkdir -p "$STAGE/ble-battery" "$STAGE/camera-mac" "$STAGE/host-info"
cp providers/ble-battery/.build/release/ble-battery "$STAGE/ble-battery/ble-battery"
cp providers/ble-battery/provider.json "$STAGE/ble-battery/provider.json"
cp providers/camera-mac/.build/release/camera-mac "$STAGE/camera-mac/camera-mac"
cp providers/camera-mac/provider.json "$STAGE/camera-mac/provider.json"
cp providers/host-info/host_info.py "$STAGE/host-info/host_info.py"
cp providers/host-info/provider.json "$STAGE/host-info/provider.json"
echo "==> staged providers in $STAGE"
```
Then: `chmod +x scripts/build-providers.sh` and add `src-tauri/providers/` to `.gitignore`.

The `tauri.conf.json` `bundle.resources` already maps `"providers/": "providers/"`; with the stage at `src-tauri/providers/` it lands at `Contents/Resources/providers/` (matching `provider_roots()`'s `../Resources/providers`). Update `beforeBuildCommand` so the stage is built first:
```json
"beforeBuildCommand": "bash scripts/build-providers.sh && npm run build"
```
(Edit `src-tauri/tauri.conf.json` `build.beforeBuildCommand` to that value.)

- [ ] **Step 2: Build the full .dmg and verify providers are bundled**

```bash
cd /Users/hudsonbrendon/Github/ha-battery-bridge
source "$HOME/.cargo/env"
npm run tauri build 2>&1 | tail -15
ls "src-tauri/target/release/bundle/macos/Open Devices Bridge.app/Contents/Resources/providers"
ls src-tauri/target/release/bundle/dmg/*.dmg
```
Expected: the `.app` and a `.dmg` are produced; the providers dir lists `ble-battery`, `camera-mac`, `host-info`.

- [ ] **Step 3: Commit**

```bash
git add scripts/build-providers.sh src-tauri/tauri.conf.json .gitignore
git commit -m "build: stage + bundle providers into the Tauri app"
```

---

## Task 12: CI — build the Tauri .dmg

**Files:**
- Modify: `.github/workflows/build.yml`

- [ ] **Step 1: Replace the workflow**

Overwrite `.github/workflows/build.yml`:
```yaml
name: Build DMG

on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Rust toolchain
        uses: dtolnay/rust-toolchain@stable

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "22"

      - name: Select latest stable Xcode (Swift 6)
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Install JS deps
        run: npm ci || npm install

      - name: Rust tests
        run: cargo test --manifest-path src-tauri/Cargo.toml

      - name: Build app + .dmg
        run: npm run tauri build

      - name: Locate .dmg
        id: dmg
        run: echo "path=$(ls src-tauri/target/release/bundle/dmg/*.dmg | head -1)" >> "$GITHUB_OUTPUT"

      - name: Upload .dmg artifact
        uses: actions/upload-artifact@v4
        with:
          name: Open-Devices-Bridge-dmg
          path: ${{ steps.dmg.outputs.path }}
          if-no-files-found: error

      - name: Attach .dmg to release (on tag)
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: ${{ steps.dmg.outputs.path }}
```
The steps order is: checkout → rust-toolchain → setup-node → setup-xcode → npm install → cargo test → tauri build → locate dmg → upload → release.

- [ ] **Step 2: Validate YAML**

Run: `ruby -ryaml -e "YAML.load_file('.github/workflows/build.yml'); puts 'yaml ok'"`
Expected: `yaml ok`. Ensure there is no leftover `setup-go` step.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "ci: build the Tauri .dmg (Rust + Node + Swift providers)"
```

---

## Task 13: Live end-to-end verification + README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run the built app against a local broker; verify popover + MQTT**

```bash
cd /Users/hudsonbrendon/Github/ha-battery-bridge
CFG="$HOME/Library/Application Support/OpenDevicesBridge"
mkdir -p "$CFG"
printf '{"host":"127.0.0.1","port":18831,"username":"","interval_minutes":1}\n' > "$CFG/config.json"
pkill -f "Open Devices Bridge" 2>/dev/null; pkill -f mosquitto 2>/dev/null; sleep 1
printf 'listener 18831 127.0.0.1\nallow_anonymous true\n' > /tmp/mosq.conf
/opt/homebrew/sbin/mosquitto -c /tmp/mosq.conf >/tmp/mosq.log 2>&1 & MOSQ=$!; sleep 1
/opt/homebrew/bin/mosquitto_sub -h 127.0.0.1 -p 18831 -t 'homeassistant/#' -t 'odb/#' -v >/tmp/odb_t.log 2>&1 & SUB=$!; sleep 1
open "src-tauri/target/release/bundle/macos/Open Devices Bridge.app"
echo ">>> clique no ícone da menu bar (abre o popover); abra/feche uma câmera"
sleep 20
pkill -f "Open Devices Bridge" 2>/dev/null; kill $SUB $MOSQ 2>/dev/null
rm -f "$CFG/config.json"
echo "=== topics ==="; grep -aE "odb/|homeassistant/binary_sensor/odb_camera" /tmp/odb_t.log | sort -u | head -30
```
Expected: bridge availability `online`, discovery + state for the three providers (battery devices, host-info, cameras), and camera `in_use` transitions when toggled. Visually confirm the popover shows battery bars + camera chips + MQTT status, and the tray icon shows the lowest battery %.

- [ ] **Step 2: Rewrite the README for the Tauri app**

Overwrite `README.md`:
```markdown
# Open Devices Bridge

A cross-platform, community-extensible bridge that discovers devices on your
machine and publishes them to **Home Assistant** over **MQTT Discovery**, with a
native, lightweight menu-bar UI (Tauri — Rust core + the OS WebView).

Support is added through **providers**: small executables the host launches that
speak a simple line-delimited JSON protocol (ODB-PP/1). Providers can be written
in any language. The host (orchestrator, MQTT, tray popover, settings) is a Tauri
app; on macOS it runs as a menu-bar agent.

## Bundled providers

- **ble-battery** (macOS, Swift) — battery, connection, firmware of paired BLE
  devices (Logitech MX Keys Mini, MX Master 3) via CoreBluetooth.
- **host-info** (any OS, Python) — the host machine's own battery + online state.
- **camera-mac** (macOS, Swift) — each camera's "in use" state via CoreMediaIO.

## Build (macOS)

Requires Rust (rustup), Node 22, Swift (Command Line Tools), Python 3.

```bash
cargo test --manifest-path src-tauri/Cargo.toml   # core tests
npm install
npm run tauri build                               # => src-tauri/target/release/bundle/dmg/*.dmg
```

Install: copy **Open Devices Bridge.app** to `/Applications`. First launch asks for
**Bluetooth** permission (ble-battery). The app is unsigned; on first open
right-click → **Open**, or:
```bash
xattr -dr com.apple.quarantine "/Applications/Open Devices Bridge.app"
```

Click the menu-bar icon to open the popover (battery, cameras, MQTT status) and
configure the broker in **Configurações** (requires the Mosquitto add-on + MQTT
integration in Home Assistant).

## Writing a provider

A provider is a directory under `providers/` (bundled) or
`~/Library/Application Support/OpenDevicesBridge/providers/` (user) with a
`provider.json` and an executable that prints `hello`, then `devices`, then `state`
JSONL lines on stdout. See `docs/superpowers/specs/` for the protocol.

## Roadmap

- Windows/Linux packaging (the Tauri host is already cross-platform).
- Device control (host→device), provider registry.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for the Tauri host"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** toolchain (T0), scaffold + remove Go (T1), protocol (T2),
  hapublish (T3), config (T4), registry (T5), provider+integration (T6), mqtt (T7),
  orchestrator+snapshot (T8), commands+tray+popover (T9), Svelte popover+settings
  (T10), packaging+providers (T11), CI (T12), end-to-end + README (T13). Every spec
  section maps to a task.
- **Type consistency:** Rust `OutMessage`, `Settings`, `Manifest`, `Message`/`Device`/
  `ProviderInfo`, `Snapshot`/`UiDevice`, `Status`, `Orchestrator`, `Supervisor`/
  `ProviderEvent`, and the Tauri command names (`get_snapshot`, `load_settings`,
  `save_settings`, `test_connection`, `quit`) are used identically across tasks and
  match the frontend `api.ts`. Topic/unique_id scheme matches the Go original and the
  SP1/SP2 providers (`odb_<provider>_<device>_<entity>`, `odb/<provider>/<device>/state`).
- **No XCTest needed:** Rust uses `cargo test` natively for protocol, hapublish,
  config, registry, and the host-info integration test.
- **Tauri v2 API risk:** Task 9 explicitly instructs adapting tray/window API names
  to the resolved tauri 2.x if they differ, keeping behavior.
- **Deferred by design:** Windows/Linux packaging, control, registry — per spec.
```
