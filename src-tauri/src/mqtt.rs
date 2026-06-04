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
