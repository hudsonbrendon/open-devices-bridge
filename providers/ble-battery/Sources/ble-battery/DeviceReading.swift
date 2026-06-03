import Foundation

/// One snapshot of a Bluetooth peripheral's state, as read from the system.
struct DeviceReading: Equatable, Sendable {
    /// Stable CoreBluetooth peripheral identifier (UUID string).
    let id: String
    /// Human-readable device name, e.g. "MX Keys Mini".
    let name: String
    /// Battery percentage 0...100, or nil if unread this cycle.
    let battery: Int?
    /// Whether the device is currently connected to this Mac.
    let online: Bool
    /// Firmware revision string (Device Info Service 0x2A26), or nil.
    let firmware: String?
    /// Charging state if the device exposes it, else nil (best-effort).
    let charging: Bool?

    init(id: String, name: String, battery: Int?, online: Bool,
                firmware: String? = nil, charging: Bool? = nil) {
        self.id = id
        self.name = name
        self.battery = battery
        self.online = online
        self.firmware = firmware
        self.charging = charging
    }
}
