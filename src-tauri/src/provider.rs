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
