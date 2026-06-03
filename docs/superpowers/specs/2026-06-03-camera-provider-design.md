# SP2 — `camera-mac` Provider Design Spec

**Date:** 2026-06-03
**Status:** Approved design, pending spec review
**Builds on:** SP1 (Open Devices Bridge — Go host + ODB-PP/1 providers). This adds
one new provider; the host is unchanged except for the packaging script.
**Branch:** `feat/sp2-camera-provider` (off `feat/sp1-open-devices-bridge`; merges
after SP1).

## Goal

Add a macOS provider that reports which cameras are currently in use, so Home
Assistant can automate on camera activity (e.g. a "busy / on a call" light).

## Validated foundation

A CoreMediaIO spike (`reference/spike_camera.swift`) proved the detection method
using **public APIs, with no camera (TCC) permission required**:

```
CMIOObjectGetPropertyData(device, kCMIODevicePropertyDeviceIsRunningSomewhere)
```

Live result on the user's Mac (6 CMIO devices enumerated; FaceTime camera was
active and was correctly reported in use, distinct from the idle BRIO/others):

```
== 6 devices CMIO == Logitech BRIO, FaceTime HD Camera, OBS Virtual Camera,
   iPhone Continuity, iPhone Desk View, EOS Webcam Utility
t=00s..24s  EM USO: FaceTime HD Camera
```

`kCMIODevicePropertyDeviceIsRunningSomewhere` reports whether *any* process on the
system is streaming that device — exactly the "in use" signal we want, per device.

## Scope

### In scope
- A new provider `providers/camera-mac/` — a Swift executable, macOS only.
- Exposes **every** CMIO camera (BRIO, FaceTime, iPhone Continuity, OBS, EOS, …)
  as a device with a single `in_use` binary_sensor.
- Event-driven updates via CoreMediaIO property listeners (instant), with a
  re-scan on device-list changes (cameras appearing/disappearing) and a periodic
  poll as a safety fallback.
- Speaks ODB-PP/1 (hello → devices → state) and honors `refresh` / `shutdown`.
- `--selftest` mode for verification.
- `scripts/build-app.sh` updated to build and bundle this provider.

### Out of scope (YAGNI / later)
- Control (cameras have no control surface here).
- Windows/Linux camera-in-use detection (separate providers later; the host is
  already portable).
- Filtering virtual cameras (all CMIO devices are exposed; the user ignores
  unwanted ones in HA).
- Any host (Go) code changes — the SP1 generic mapper already handles
  `binary_sensor` entities.

## Architecture

```
providers/camera-mac/   (SwiftPM executable, platforms: ["darwin"])
  main.swift
    - emit hello
    - enumerate CMIO devices → emit "devices" (one per camera)
    - register a property listener on IsRunningSomewhere for each device
        → on change: read value, emit "state" for that camera
    - register a listener on kCMIOHardwarePropertyDevices
        → on change: re-enumerate, emit "devices", (re)register listeners,
          emit current state for all
    - safety: a 5 s timer re-reads all devices and emits state if changed
    - stdin reader: {"type":"refresh"} → emit state for all;
                    {"type":"shutdown"} → exit(0)
    - --selftest: emit hello + devices + one state snapshot, then exit(0)
  CMIO.swift
    - thin Swift wrappers over CoreMediaIO: devices(), name(id),
      isRunningSomewhere(id), addRunningListener(id, handler),
      addDeviceListListener(handler)
  provider.json  {"id":"camera-mac","exec":"camera-mac","platforms":["darwin"],"enabled":true}
  Package.swift  (executable target, macOS .v14, language mode v5)
```

The provider links `CoreMediaIO` and `Foundation`. No third-party deps.

## ODB-PP/1 messages emitted

```jsonc
{"type":"hello","protocol":1,"provider":{"id":"camera-mac","name":"Camera (macOS)","version":"1.0.0"}}
{"type":"devices","devices":[
  {"id":"logitech-brio","name":"Logitech BRIO","manufacturer":"macOS / CoreMediaIO","model":"Logitech BRIO",
   "entities":[{"key":"in_use","kind":"binary_sensor","device_class":"running"}]},
  {"id":"facetime-hd-camera","name":"FaceTime HD Camera","manufacturer":"macOS / CoreMediaIO","model":"FaceTime HD Camera",
   "entities":[{"key":"in_use","kind":"binary_sensor","device_class":"running"}]}
  /* …one per CMIO camera… */ ]}
{"type":"state","device":"facetime-hd-camera","values":{"in_use":true}}
```

Device `id` is a slug of the camera name. If two cameras share a name, the second
gets a `-2` suffix to keep ids unique (rare; e.g. two identical webcams).

## HA result (via the SP1 generic mapper, no host change)

Per camera, one entity:
- `binary_sensor.camera_mac_<camera-slug>_in_use` — `device_class: running`,
  `ON` when the camera is streaming. Grouped under an HA device per camera.

Example automation: turn on a "busy" light when any
`binary_sensor.*_in_use` is `ON`.

## Error handling

- A device whose name or IsRunningSomewhere property can't be read → skipped for
  that cycle, logged via a `{"type":"log"}` message; the provider keeps running.
- A property-listener registration failure → the 5 s poll fallback still delivers
  state, so detection degrades gracefully rather than failing.
- Provider crash → the SP1 host supervisor restarts it with backoff (existing).

## Testing strategy

The provider is mostly CoreMediaIO glue with little pure logic, so testing is
behavioral, not unit:

- **`--selftest`**: build the provider, run `camera-mac --selftest`, assert it
  prints a valid `hello`, a `devices` list containing the known cameras, and one
  `state` line — decoded by the SP1 `protocol` decoder. (A Go integration test may
  invoke the built binary if present; otherwise this is a scripted smoke check.)
- **Live end-to-end**: run the assembled app against a local Mosquitto, open and
  close a camera, and confirm the corresponding
  `binary_sensor.<camera>_in_use` flips `ON`→`OFF` in the published MQTT state —
  the same Mosquitto harness used to validate SP1.
- **Slug uniqueness**: a tiny pure helper test for the name→id collision suffix.

## Packaging

- `scripts/build-app.sh` gains a step: build `providers/camera-mac` with
  `swift build -c release` and copy its binary + `provider.json` into
  `Contents/Resources/providers/camera-mac/`.
- No `Info.plist` change is required: reading IsRunningSomewhere needs no camera
  usage-description (it is device metadata, not the camera stream). If a future
  capability streams frames, `NSCameraUsageDescription` would be added — not now.

## Reference artifacts

- `reference/spike_camera.swift` — the validated CoreMediaIO in-use spike (seed for
  `CMIO.swift`).
