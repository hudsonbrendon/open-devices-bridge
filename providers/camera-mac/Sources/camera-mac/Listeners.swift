import Foundation
import CoreMediaIO

// Registers a listener for the device's IsRunningSomewhere; returns the block
// so the caller can deregister it later.
func addRunningListener(_ id: CMIOObjectID, _ queue: DispatchQueue,
                        _ handler: @escaping () -> Void) -> CMIOObjectPropertyListenerBlock {
    var a = cmioAddr(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
    let block: CMIOObjectPropertyListenerBlock = { _, _ in handler() }
    CMIOObjectAddPropertyListenerBlock(id, &a, queue, block)
    return block
}

func removeRunningListener(_ id: CMIOObjectID, _ queue: DispatchQueue,
                           _ block: @escaping CMIOObjectPropertyListenerBlock) {
    var a = cmioAddr(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
    CMIOObjectRemovePropertyListenerBlock(id, &a, queue, block)
}

// Fires `handler` whenever the set of CMIO devices changes.
func addDeviceListListener(_ queue: DispatchQueue, _ handler: @escaping () -> Void) {
    var a = cmioAddr(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &a, queue) { _, _ in handler() }
}
