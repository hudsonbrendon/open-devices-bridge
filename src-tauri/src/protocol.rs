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
