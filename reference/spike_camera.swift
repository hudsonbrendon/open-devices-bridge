// Spike: detectar câmera em uso no macOS via CoreMediaIO IsRunningSomewhere.
// Enumera devices CMIO e faz poll de kCMIODevicePropertyDeviceIsRunningSomewhere.
import Foundation
import CoreMediaIO

func addr(_ sel: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
    CMIOObjectPropertyAddress(mSelector: sel,
                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
}

func devices() -> [CMIOObjectID] {
    var a = addr(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    var dataSize: UInt32 = 0
    CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &a, 0, nil, &dataSize)
    let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
    var ids = [CMIOObjectID](repeating: 0, count: count)
    var used: UInt32 = 0
    CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &a, 0, nil, dataSize, &used, &ids)
    return ids
}

func name(_ id: CMIOObjectID) -> String {
    var a = addr(CMIOObjectPropertySelector(kCMIOObjectPropertyName))
    var size: UInt32 = 0
    CMIOObjectGetPropertyDataSize(id, &a, 0, nil, &size)
    var cf: CFString? = nil
    var used: UInt32 = 0
    withUnsafeMutablePointer(to: &cf) { ptr in
        CMIOObjectGetPropertyData(id, &a, 0, nil, size, &used, ptr)
    }
    return (cf as String?) ?? "?"
}

func isRunning(_ id: CMIOObjectID) -> Bool {
    var a = addr(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
    var value: UInt32 = 0
    var used: UInt32 = 0
    let st = CMIOObjectGetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
    return st == 0 && value != 0
}

let cams = devices()
print("== \(cams.count) devices CMIO ==")
for id in cams { print("  - \(name(id))") }
print("\n== poll IsRunningSomewhere por 25s (abra/feche uma câmera p/ ver flipar) ==")
for tick in 0..<25 {
    let active = cams.filter { isRunning($0) }.map { name($0) }
    let line = active.isEmpty ? "(nenhuma em uso)" : active.joined(separator: ", ")
    print(String(format: "  t=%02ds  EM USO: %@", tick, line))
    Thread.sleep(forTimeInterval: 1)
}
print("== fim ==")
