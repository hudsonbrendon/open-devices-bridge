import Foundation
import HABatteryCore

// Minimal assertion harness (no XCTest available under Command Line Tools).
var failures = 0
var checks = 0

func check(_ name: String, _ condition: Bool) {
    checks += 1
    if !condition {
        failures += 1
        FileHandle.standardError.write(Data("  ✗ \(name)\n".utf8))
    }
}

func eq<T: Equatable>(_ name: String, _ a: T, _ b: T) {
    check("\(name) (\(a) == \(b))", a == b)
}

func decode(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
}

// --- Slug ---
eq("slug spaces", slugify("MX Keys Mini"), "mx_keys_mini")
eq("slug trailing punct", slugify("MX Master 3!"), "mx_master_3")
eq("slug collapse", slugify("Foo  --  Bar"), "foo_bar")
eq("slug empty", slugify("   "), "device")
eq("slug punct only", slugify("!!!"), "device")
eq("slug numbers", slugify("K3 Pro v2"), "k3_pro_v2")

// --- DiscoveryPayload ---
let reading = DeviceReading(
    id: "1BB5AD36-06E0-C6EB-C888-8A2863B750F3",
    name: "MX Keys Mini", battery: 55, online: true,
    firmware: "RBK73.04_0016", charging: nil
)

eq("state topic", DiscoveryPayload.stateTopic(objectId: "mx_keys_mini"),
   "habridge/mx_keys_mini/state")

let st = decode(DiscoveryPayload.stateJSON(for: reading))
eq("state battery", st["battery"] as? Int, 55)
eq("state online", st["online"] as? Bool, true)
eq("state firmware", st["firmware"] as? String, "RBK73.04_0016")
check("state charging null", st["charging"] is NSNull)

let rNil = DeviceReading(id: "x", name: "X", battery: nil, online: false)
let stNil = decode(DiscoveryPayload.stateJSON(for: rNil))
check("nil battery -> null", stNil["battery"] is NSNull)
eq("offline", stNil["online"] as? Bool, false)

let msgs = DiscoveryPayload.discoveryMessages(for: reading)
eq("3 configs without charging", msgs.count, 3)
check("all retained", msgs.allSatisfy { $0.retained })

let rCharge = DeviceReading(id: "x", name: "MX Master 3", battery: 20,
                            online: true, firmware: nil, charging: true)
let msgsC = DiscoveryPayload.discoveryMessages(for: rCharge)
eq("4 configs with charging", msgsC.count, 4)
check("has charging config", msgsC.contains { $0.topic.contains("/charging/config") })

let battery = msgs.first { $0.topic.contains("/battery/config") }!
eq("battery topic", battery.topic,
   "homeassistant/sensor/habridge_mx_keys_mini/battery/config")
let bp = decode(battery.payload)
eq("battery unique_id", bp["unique_id"] as? String, "habridge_mx_keys_mini_battery")
eq("battery device_class", bp["device_class"] as? String, "battery")
eq("battery unit", bp["unit_of_measurement"] as? String, "%")
eq("battery state_topic", bp["state_topic"] as? String, "habridge/mx_keys_mini/state")
eq("battery value_template", bp["value_template"] as? String, "{{ value_json.battery }}")
let dev = bp["device"] as? [String: Any]
eq("device name", dev?["name"] as? String, "MX Keys Mini")
eq("device identifiers", dev?["identifiers"] as? [String], ["habridge_mx_keys_mini"])

let conn = msgs.first { $0.topic.contains("/connected/config") }!
check("connected is binary_sensor", conn.topic.hasPrefix("homeassistant/binary_sensor/"))
let cp = decode(conn.payload)
eq("connected device_class", cp["device_class"] as? String, "connectivity")
eq("connected availability", cp["availability_topic"] as? String,
   DiscoveryPayload.bridgeAvailabilityTopic)

// --- summary ---
if failures == 0 {
    print("✓ all \(checks) checks passed")
    exit(0)
} else {
    FileHandle.standardError.write(Data("\(failures)/\(checks) checks FAILED\n".utf8))
    exit(1)
}
