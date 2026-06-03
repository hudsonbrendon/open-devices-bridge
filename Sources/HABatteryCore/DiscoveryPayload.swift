import Foundation

/// A single MQTT message to publish (retained config or live state).
public struct MQTTMessage: Equatable, Sendable {
    public let topic: String
    public let payload: String
    public let retained: Bool
    public init(topic: String, payload: String, retained: Bool) {
        self.topic = topic
        self.payload = payload
        self.retained = retained
    }
}

/// Builds Home Assistant MQTT Discovery configs and per-device state payloads.
/// Pure: no I/O, fully unit-testable.
public enum DiscoveryPayload {
    /// Bridge-level availability topic (used as Last Will and per-entity availability).
    public static let bridgeAvailabilityTopic = "habridge/bridge/availability"
    public static let availableOnline = "online"
    public static let availableOffline = "offline"

    public static func stateTopic(objectId: String) -> String {
        "habridge/\(objectId)/state"
    }

    /// JSON published to the per-device state topic.
    public static func stateJSON(for reading: DeviceReading) -> String {
        var dict: [String: Any] = [
            "online": reading.online,
        ]
        dict["battery"] = reading.battery as Any? ?? NSNull()
        dict["firmware"] = reading.firmware as Any? ?? NSNull()
        dict["charging"] = reading.charging as Any? ?? NSNull()
        return jsonString(dict)
    }

    /// All discovery config messages for a device (battery, connected, firmware,
    /// and charging only when the device exposes it).
    public static func discoveryMessages(for reading: DeviceReading) -> [MQTTMessage] {
        let obj = slugify(reading.name)
        let state = stateTopic(objectId: obj)
        let device: [String: Any] = [
            "identifiers": ["habridge_\(obj)"],
            "name": reading.name,
            "manufacturer": "Logitech (via HA Battery Bridge)",
            "model": reading.name,
        ]

        func config(_ component: String, _ key: String, _ extra: [String: Any]) -> MQTTMessage {
            var payload: [String: Any] = [
                "unique_id": "habridge_\(obj)_\(key)",
                "object_id": "\(obj)_\(key)",
                "state_topic": state,
                "availability_topic": bridgeAvailabilityTopic,
                "payload_available": availableOnline,
                "payload_not_available": availableOffline,
                "device": device,
            ]
            for (k, v) in extra { payload[k] = v }
            let topic = "homeassistant/\(component)/habridge_\(obj)/\(key)/config"
            return MQTTMessage(topic: topic, payload: jsonString(payload), retained: true)
        }

        var messages = [
            config("sensor", "battery", [
                "name": "Battery",
                "value_template": "{{ value_json.battery }}",
                "unit_of_measurement": "%",
                "device_class": "battery",
                "state_class": "measurement",
            ]),
            config("binary_sensor", "connected", [
                "name": "Connected",
                "value_template": "{{ 'ON' if value_json.online else 'OFF' }}",
                "payload_on": "ON",
                "payload_off": "OFF",
                "device_class": "connectivity",
            ]),
            config("sensor", "firmware", [
                "name": "Firmware",
                "value_template": "{{ value_json.firmware }}",
                "entity_category": "diagnostic",
            ]),
        ]

        if reading.charging != nil {
            messages.append(config("binary_sensor", "charging", [
                "name": "Charging",
                "value_template": "{{ 'ON' if value_json.charging else 'OFF' }}",
                "payload_on": "ON",
                "payload_off": "OFF",
                "device_class": "battery_charging",
            ]))
        }
        return messages
    }

    /// Deterministic JSON (sorted keys) so output is stable and testable.
    static func jsonString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.sortedKeys]),
            let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}
