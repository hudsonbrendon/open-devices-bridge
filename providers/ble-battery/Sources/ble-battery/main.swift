import Foundation

// ODB-PP/1 provider wrapping BatteryReader. Emits hello + devices + state JSONL
// on stdout; honors {"type":"refresh"} / {"type":"shutdown"} on stdin.

let stdoutQueue = DispatchQueue(label: "stdout")

func emit(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
          var s = String(data: data, encoding: .utf8) else { return }
    s += "\n"
    stdoutQueue.sync { FileHandle.standardOutput.write(Data(s.utf8)) }
}

let provider = BatteryReader()
var announcedDevices = Set<String>()

func slug(_ s: String) -> String {
    var out = "", lastUnderscore = false
    for ch in s.lowercased() {
        if ch.isLetter || ch.isNumber { out.append(ch); lastUnderscore = false }
        else if !lastUnderscore { out.append("_"); lastUnderscore = true }
    }
    let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return trimmed.isEmpty ? "device" : trimmed
}

func publish(_ readings: [DeviceReading]) {
    // Announce devices once (or when a new one appears).
    let newOnes = readings.filter { !announcedDevices.contains($0.id) }
    if !newOnes.isEmpty {
        let devices: [[String: Any]] = readings.map { r in
            [
                "id": slug(r.name),
                "name": r.name,
                "manufacturer": "Logitech",
                "model": r.name,
                "entities": [
                    ["key": "battery", "kind": "sensor", "device_class": "battery", "unit": "%"],
                    ["key": "connected", "kind": "binary_sensor", "device_class": "connectivity"],
                    ["key": "firmware", "kind": "sensor", "entity_category": "diagnostic"],
                ],
            ]
        }
        emit(["type": "devices", "devices": devices])
        readings.forEach { announcedDevices.insert($0.id) }
    }
    for r in readings {
        emit([
            "type": "state",
            "device": slug(r.name),
            "values": [
                "battery": r.battery as Any? ?? NSNull(),
                "connected": r.online,
                "firmware": r.firmware as Any? ?? NSNull(),
            ],
        ])
    }
}

func poll() { provider.refresh { readings in publish(readings) } }

// Hello first.
emit(["type": "hello", "protocol": 1,
      "provider": ["id": "ble-battery", "name": "BLE Battery", "version": "1.0.0"]])

// Poll on a timer; also poll once Bluetooth is powered on.
provider.onStateChange = { state in if state == .poweredOn { poll() } }
let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in poll() }
RunLoop.main.add(timer, forMode: .common)

// Read stdin commands on a background thread.
DispatchQueue.global().async {
    while let line = readLine(strippingNewline: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { continue }
        switch type {
        case "refresh": poll()
        case "shutdown": exit(0)
        default: break
        }
    }
}

poll()
RunLoop.main.run()
