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
    devices: BTreeMap<String, Vec<Device>>,
    values: BTreeMap<(String, String), BTreeMap<String, Value>>,
    mqtt: Status,
}

impl Default for Status {
    fn default() -> Self {
        Status::Disconnected
    }
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
                let values = st
                    .values
                    .get(&(provider.clone(), d.id.clone()))
                    .cloned()
                    .unwrap_or_default();
                devices.push(UiDevice {
                    provider: provider.clone(),
                    id: d.id.clone(),
                    name: d.name.clone(),
                    values,
                });
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
                    let info = self
                        .state
                        .lock()
                        .unwrap()
                        .infos
                        .get(&provider)
                        .cloned()
                        .unwrap_or(ProviderInfo {
                            id: provider.clone(),
                            name: provider.clone(),
                            version: String::new(),
                        });
                    for d in &m.devices {
                        for msg in hapublish::discovery_messages(&info, d) {
                            self.publish(msg);
                        }
                    }
                    self.state
                        .lock()
                        .unwrap()
                        .devices
                        .insert(provider, m.devices);
                    self.emit();
                }
                "state" => {
                    let key = (provider.clone(), m.device.clone());
                    self.state
                        .lock()
                        .unwrap()
                        .values
                        .insert(key, m.values.clone());
                    let dev = self
                        .state
                        .lock()
                        .unwrap()
                        .devices
                        .get(&provider)
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
            roots.push(dir.join("../Resources/providers"));
            roots.push(dir.join("providers"));
        }
    }
    if let Some(cfg) = dirs::config_dir() {
        roots.push(cfg.join("OpenDevicesBridge").join("providers"));
    }
    let _ = config::config_path();
    roots
}
