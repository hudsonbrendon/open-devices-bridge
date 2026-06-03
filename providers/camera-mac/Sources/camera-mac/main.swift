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

let workQueue = DispatchQueue(label: "camera-mac.work")
var cams: [Cam] = []
var listening = Set<CMIOObjectID>()
var lastState: [String: Bool] = [:]

func rescan() {
    cams = buildCams()
    emitDevices(cams)
    for c in cams where !listening.contains(c.oid) {
        listening.insert(c.oid)
        let cam = c
        addRunningListener(cam.oid, workQueue) {
            workQueue.async {
                let v = cmioIsRunning(cam.oid)
                if lastState[cam.id] != v { lastState[cam.id] = v; emitState(cam) }
            }
        }
    }
    for c in cams {
        let v = cmioIsRunning(c.oid)
        lastState[c.id] = v
        emitState(c)
    }
}

workQueue.async {
    rescan()
    addDeviceListListener(workQueue) { workQueue.async { rescan() } }
}

// Safety fallback: re-read every 5 s and emit only on change.
let timer = DispatchSource.makeTimerSource(queue: workQueue)
timer.schedule(deadline: .now() + 5, repeating: 5)
timer.setEventHandler {
    for c in cams {
        let v = cmioIsRunning(c.oid)
        if lastState[c.id] != v { lastState[c.id] = v; emitState(c) }
    }
}
timer.resume()

// Host → provider commands on stdin.
DispatchQueue.global().async {
    while let line = readLine(strippingNewline: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { continue }
        switch type {
        case "refresh": workQueue.async { cams.forEach { emitState($0) } }
        case "shutdown": exit(0)
        default: break
        }
    }
}

RunLoop.main.run()
