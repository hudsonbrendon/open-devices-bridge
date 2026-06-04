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
