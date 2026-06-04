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
