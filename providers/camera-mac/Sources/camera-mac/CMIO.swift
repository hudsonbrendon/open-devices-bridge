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
