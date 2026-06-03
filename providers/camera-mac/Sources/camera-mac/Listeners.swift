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
