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
