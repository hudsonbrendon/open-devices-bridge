import Foundation
import CoreMediaIO

let stdoutQueue = DispatchQueue(label: "stdout")

func emit(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
          let s = String(data: data, encoding: .utf8) else { return }
    stdoutQueue.sync { FileHandle.standardOutput.write(Data((s + "\n").utf8)) }
}

struct Cam { let oid: CMIOObjectID; let id: String; let name: String }

func buildCams() -> [Cam] {
    let oids = cmioDevices()
    let names = oids.map { cmioName($0) }
    let ids = uniqueIDs(names)
    var cams: [Cam] = []
    for i in oids.indices { cams.append(Cam(oid: oids[i], id: ids[i], name: names[i])) }
    return cams
}

func emitDevices(_ cams: [Cam]) {
    let devices: [[String: Any]] = cams.map { c in
        [
            "id": c.id, "name": c.name,
            "manufacturer": "macOS / CoreMediaIO", "model": c.name,
            "entities": [["key": "in_use", "kind": "binary_sensor", "device_class": "running"]],
        ]
    }
    emit(["type": "devices", "devices": devices])
}

func emitState(_ c: Cam) {
    emit(["type": "state", "device": c.id, "values": ["in_use": cmioIsRunning(c.oid)]])
}

// hello
emit(["type": "hello", "protocol": 1,
      "provider": ["id": "camera-mac", "name": "Camera (macOS)", "version": "1.0.0"]])

if CommandLine.arguments.contains("--selftest") {
    precondition(uniqueIDs(["Cam", "Cam"]) == ["cam", "cam-2"], "uniqueIDs suffix broken")
    precondition(slug("Logitech BRIO") == "logitech-brio", "slug broken")
    let cams = buildCams()
    emitDevices(cams)
    cams.forEach { emitState($0) }
    exit(0)
}

// (continuous run loop is added in Task 3)
let cams = buildCams()
emitDevices(cams)
cams.forEach { emitState($0) }
