# SP2 — `camera-mac` Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a macOS provider `camera-mac` that reports each camera's in-use state to Home Assistant as a `binary_sensor`, using CoreMediaIO — with no host (Go) code changes.

**Architecture:** A standalone SwiftPM executable under `providers/camera-mac/` enumerates CoreMediaIO devices, reads `kCMIODevicePropertyDeviceIsRunningSomewhere` per camera, and speaks ODB-PP/1 (hello → devices → state) on stdout. Updates are event-driven via CoreMediaIO property listeners with a 5 s poll fallback. The SP1 Go host discovers and runs it unchanged; only `scripts/build-app.sh` is updated to bundle it.

**Tech Stack:** Swift 6 (CoreMediaIO, Foundation), SwiftPM. No third-party deps. Validated by `reference/spike_camera.swift`.

**Spec:** `docs/superpowers/specs/2026-06-03-camera-provider-design.md`

**Branch:** `feat/sp2-camera-provider` (already created off `feat/sp1-open-devices-bridge`).

---

## Conventions

- Commit author Hudson Brendon (`git config user.name "Hudson Brendon"; user.email "contato.hudsonbrendon@gmail.com"`). No AI co-author trailer.
- Build the provider: `cd providers/camera-mac && swift build -c release`.
- No XCTest is available (Command Line Tools, no full Xcode), so correctness of pure
  helpers is asserted inside the provider's `--selftest` mode via `precondition`.

---

## Task 1: Scaffold the camera-mac package

**Files:**
- Create: `providers/camera-mac/Package.swift`
- Create: `providers/camera-mac/Sources/camera-mac/main.swift`
- Create: `providers/camera-mac/provider.json`

- [ ] **Step 1: Create the SwiftPM manifest**

`providers/camera-mac/Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "camera-mac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "camera-mac",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Create a minimal entrypoint that emits hello**

`providers/camera-mac/Sources/camera-mac/main.swift`:
```swift
import Foundation

let stdoutQueue = DispatchQueue(label: "stdout")

func emit(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
          let s = String(data: data, encoding: .utf8) else { return }
    stdoutQueue.sync { FileHandle.standardOutput.write(Data((s + "\n").utf8)) }
}

emit(["type": "hello", "protocol": 1,
      "provider": ["id": "camera-mac", "name": "Camera (macOS)", "version": "1.0.0"]])
```

- [ ] **Step 3: Create the provider manifest**

`providers/camera-mac/provider.json`:
```json
{
  "id": "camera-mac",
  "name": "Camera (macOS)",
  "exec": "camera-mac",
  "args": [],
  "platforms": ["darwin"],
  "enabled": true
}
```

- [ ] **Step 4: Build to verify it compiles and emits hello**

Run:
```bash
cd providers/camera-mac && swift build -c release && .build/release/camera-mac && cd ../..
```
Expected: one line
`{"provider":{...},"protocol":1,"type":"hello"}` (key order may vary).

- [ ] **Step 5: Commit**

```bash
git add providers/camera-mac
git commit -m "feat(camera-mac): scaffold provider package emitting hello"
```

---

## Task 2: CoreMediaIO read wrappers + slug helpers + device/state snapshot

**Files:**
- Create: `providers/camera-mac/Sources/camera-mac/CMIO.swift`
- Create: `providers/camera-mac/Sources/camera-mac/Slug.swift`
- Modify: `providers/camera-mac/Sources/camera-mac/main.swift`

- [ ] **Step 1: Add the CoreMediaIO read wrappers**

`providers/camera-mac/Sources/camera-mac/CMIO.swift`:
```swift
import Foundation
import CoreMediaIO

func cmioAddr(_ sel: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
    CMIOObjectPropertyAddress(
        mSelector: sel,
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
}

func cmioDevices() -> [CMIOObjectID] {
    var a = cmioAddr(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    var size: UInt32 = 0
    CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &a, 0, nil, &size)
    let count = Int(size) / MemoryLayout<CMIOObjectID>.size
    var ids = [CMIOObjectID](repeating: 0, count: count)
    var used: UInt32 = 0
    CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &a, 0, nil, size, &used, &ids)
    return ids
}

func cmioName(_ id: CMIOObjectID) -> String {
    var a = cmioAddr(CMIOObjectPropertySelector(kCMIOObjectPropertyName))
    var size: UInt32 = 0
    CMIOObjectGetPropertyDataSize(id, &a, 0, nil, &size)
    var cf: CFString? = nil
    var used: UInt32 = 0
    _ = withUnsafeMutablePointer(to: &cf) { ptr in
        CMIOObjectGetPropertyData(id, &a, 0, nil, size, &used, ptr)
    }
    return (cf as String?) ?? "Unknown"
}

func cmioIsRunning(_ id: CMIOObjectID) -> Bool {
    var a = cmioAddr(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
    var value: UInt32 = 0
    var used: UInt32 = 0
    let st = CMIOObjectGetPropertyData(id, &a, 0, nil,
                                       UInt32(MemoryLayout<UInt32>.size), &used, &value)
    return st == 0 && value != 0
}
```

- [ ] **Step 2: Add slug + unique-id helpers**

`providers/camera-mac/Sources/camera-mac/Slug.swift`:
```swift
import Foundation

// Lowercase alphanumeric+hyphen id, e.g. "Logitech BRIO" -> "logitech-brio".
func slug(_ s: String) -> String {
    var out = ""
    var lastDash = false
    for ch in s.lowercased() {
        if ch.isLetter || ch.isNumber {
            out.append(ch); lastDash = false
        } else if !lastDash {
            out.append("-"); lastDash = true
        }
    }
    let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "camera" : trimmed
}

// Stable unique ids for a list of names; duplicates get a -2, -3, … suffix.
func uniqueIDs(_ names: [String]) -> [String] {
    var seen: [String: Int] = [:]
    var out: [String] = []
    for n in names {
        let base = slug(n)
        let count = seen[base, default: 0] + 1
        seen[base] = count
        out.append(count == 1 ? base : "\(base)-\(count)")
    }
    return out
}
```

- [ ] **Step 3: Replace main.swift to enumerate cameras and emit devices+state, with --selftest**

`providers/camera-mac/Sources/camera-mac/main.swift`:
```swift
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
```

- [ ] **Step 4: Build and smoke-test the snapshot against real cameras**

Run:
```bash
cd providers/camera-mac && swift build -c release && .build/release/camera-mac --selftest && cd ../..
```
Expected: a `hello` line, a `devices` line listing the real cameras (Logitech BRIO,
FaceTime HD Camera, etc.), and one `state` line per camera with `"in_use":true/false`
reflecting current reality. The process exits 0. (`precondition` failures would abort
with a non-zero exit — they must not fire.)

- [ ] **Step 5: Commit**

```bash
git add providers/camera-mac
git commit -m "feat(camera-mac): CoreMediaIO enumeration + device/state snapshot + selftest"
```

---

## Task 3: Event-driven listeners, poll fallback, and stdin commands

**Files:**
- Create: `providers/camera-mac/Sources/camera-mac/Listeners.swift`
- Modify: `providers/camera-mac/Sources/camera-mac/main.swift`

- [ ] **Step 1: Add the property-listener wrappers**

`providers/camera-mac/Sources/camera-mac/Listeners.swift`:
```swift
import Foundation
import CoreMediaIO

// Fires `handler` whenever the device's IsRunningSomewhere changes.
func addRunningListener(_ id: CMIOObjectID, _ queue: DispatchQueue,
                        _ handler: @escaping () -> Void) {
    var a = cmioAddr(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
    CMIOObjectAddPropertyListenerBlock(id, &a, queue) { _, _ in handler() }
}

// Fires `handler` whenever the set of CMIO devices changes.
func addDeviceListListener(_ queue: DispatchQueue, _ handler: @escaping () -> Void) {
    var a = cmioAddr(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &a, queue) { _, _ in handler() }
}
```

- [ ] **Step 2: Replace the bottom of main.swift (everything after the `--selftest` block) with the continuous run loop**

In `providers/camera-mac/Sources/camera-mac/main.swift`, replace these lines:
```swift
// (continuous run loop is added in Task 3)
let cams = buildCams()
emitDevices(cams)
cams.forEach { emitState($0) }
```
with:
```swift
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
```

- [ ] **Step 3: Build and run a live test — confirm in_use flips**

Run the provider for ~20 s and toggle a camera during that window:
```bash
cd providers/camera-mac && swift build -c release && cd ../..
"providers/camera-mac/.build/release/camera-mac" > /tmp/cam_prov.log 2>&1 & PID=$!
echo ">>> abra e feche uma câmera (Photo Booth / chamada) nos próximos 18s"
sleep 18
kill $PID 2>/dev/null
grep '"type":"state"' /tmp/cam_prov.log | tail -20
```
Expected: after the initial snapshot, additional `state` lines appear when a camera
turns on/off, e.g. `{"type":"state","device":"facetime-hd-camera","values":{"in_use":true}}`
then `...{"in_use":false}`. Report the captured transitions.

- [ ] **Step 4: Commit**

```bash
git add providers/camera-mac
git commit -m "feat(camera-mac): event-driven in-use listeners + poll fallback + stdin commands"
```

---

## Task 4: Bundle the provider in the macOS app

**Files:**
- Modify: `scripts/build-app.sh`

- [ ] **Step 1: Add a build+bundle step for camera-mac**

In `scripts/build-app.sh`, after the existing "build Swift ble-battery provider"
block (the line `( cd providers/ble-battery && swift build -c release )`), add:
```bash
echo "==> build Swift camera-mac provider"
( cd providers/camera-mac && swift build -c release )
```
And in the assembly section, after the two `cp providers/ble-battery/... "$RES/providers/ble-battery/..."` lines, add:
```bash
mkdir -p "$RES/providers/camera-mac"
cp providers/camera-mac/.build/release/camera-mac "$RES/providers/camera-mac/camera-mac"
cp providers/camera-mac/provider.json "$RES/providers/camera-mac/provider.json"
```
Also add `"$RES/providers/camera-mac"` to the initial `mkdir -p` line that creates
the provider resource dirs (the line currently ending with `"$RES/providers/host-info"`).

- [ ] **Step 2: Build the app and verify all three providers are bundled**

Run:
```bash
bash scripts/build-app.sh
ls "build/Open Devices Bridge.app/Contents/Resources/providers"
```
Expected: lists `ble-battery`, `camera-mac`, and `host-info`.

- [ ] **Step 3: Commit**

```bash
git add scripts/build-app.sh
git commit -m "build: bundle camera-mac provider in the macOS app"
```

---

## Task 5: Live end-to-end verification (host → MQTT → in_use flip)

**Files:** none (verification task; no commit unless a fix is needed)

- [ ] **Step 1: Run the assembled app against a local broker and toggle a camera**

```bash
cd /Users/hudsonbrendon/Github/ha-battery-bridge
CFG="$HOME/Library/Application Support/OpenDevicesBridge"
mkdir -p "$CFG"
printf '{"host":"127.0.0.1","port":18831,"username":"","interval_minutes":1}\n' > "$CFG/config.json"
pkill -f "MacOS/odb" 2>/dev/null; pkill -f mosquitto 2>/dev/null; sleep 1
printf 'listener 18831 127.0.0.1\nallow_anonymous true\n' > /tmp/mosq.conf
/opt/homebrew/sbin/mosquitto -c /tmp/mosq.conf >/tmp/mosq.log 2>&1 & MOSQ=$!; sleep 1
/opt/homebrew/bin/mosquitto_sub -h 127.0.0.1 -p 18831 -t 'homeassistant/#' -t 'odb/#' -v >/tmp/odb_cam.log 2>&1 & SUB=$!; sleep 1
"build/Open Devices Bridge.app/Contents/MacOS/odb" >/tmp/odb.log 2>&1 & APP=$!
echo ">>> abra e feche uma câmera nos próximos 20s"
sleep 22
kill $APP $SUB $MOSQ 2>/dev/null; pkill -f "MacOS/odb" 2>/dev/null
rm -f "$CFG/config.json"
echo "=== camera discovery + state ==="
grep -E "camera_mac|odb/camera_mac" /tmp/odb_cam.log
```

Expected: discovery configs like
`homeassistant/binary_sensor/odb_camera_mac_<cam>/in_use/config` and state lines
`odb/camera_mac/<cam>/state {"in_use":true}` / `{"in_use":false}` that flip as the
camera is toggled. `/tmp/odb.log` must show no panic.

- [ ] **Step 2: If everything works, the SP2 provider is complete.** If a transition
  doesn't appear, check `/tmp/cam_prov.log`-style output by running the provider
  directly (Task 3, Step 3) to isolate provider vs host, and fix the smallest failing
  piece.

---

## Self-Review notes (addressed)

- **Spec coverage:** new provider package (T1), CMIO read + enumeration + selftest
  (T2), event-driven listeners + device-list listener + poll fallback + stdin (T3),
  packaging (T4), live end-to-end (T5). Every spec section maps to a task. No host
  (Go) changes — confirmed; only `scripts/build-app.sh` changes.
- **Type consistency:** `Cam{oid,id,name}`, `buildCams()`, `emitDevices([Cam])`,
  `emitState(Cam)`, `cmioDevices/cmioName/cmioIsRunning`, `addRunningListener`,
  `addDeviceListListener`, `slug`/`uniqueIDs` are used identically across tasks. The
  entity is `in_use` / `binary_sensor` / `device_class: running` everywhere, matching
  the SP1 mapper's supported kinds.
- **No XCTest:** pure-helper correctness (`slug`, `uniqueIDs`) is asserted via
  `precondition` in `--selftest`, which the smoke test exercises.
- **Deferred by design:** control, Windows/Linux, virtual-camera filtering — per spec.
```
