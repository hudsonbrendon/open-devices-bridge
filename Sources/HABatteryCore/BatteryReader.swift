import Foundation
import CoreBluetooth

/// Abstraction so the menu bar / publisher can be driven by a fake in tests.
public protocol BatteryReading: AnyObject {
    /// Current Bluetooth authorization/power state.
    var state: CBManagerState { get }
    /// Called whenever `state` changes (e.g. permission granted, BT toggled).
    var onStateChange: ((CBManagerState) -> Void)? { get set }
    /// Read all currently-connected battery devices, then return one
    /// `DeviceReading` per device ever seen (absent ones marked offline).
    func refresh(completion: @escaping ([DeviceReading]) -> Void)
}

/// Reads battery (0x2A19) and firmware (0x2A26) from peripherals already
/// connected to the system, by piggybacking on the system connection via
/// `retrieveConnectedPeripherals`. No bonding, no extra pairing slot.
public final class BatteryReader: NSObject, BatteryReading {
    private static let batteryService = CBUUID(string: "180F")
    private static let deviceInfoService = CBUUID(string: "180A")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let firmwareRev = CBUUID(string: "2A26")

    private var central: CBCentralManager!
    public private(set) var state: CBManagerState = .unknown
    public var onStateChange: ((CBManagerState) -> Void)?

    // Per-refresh state.
    private var pending: Set<UUID> = []
    private var collected: [UUID: DeviceReading] = [:]
    private var firmwareDone: Set<UUID> = []
    private var completion: (([DeviceReading]) -> Void)?
    private var timeoutTimer: Timer?

    // Last battery/firmware seen per device, to keep value when it goes offline.
    private var lastKnown: [UUID: DeviceReading] = [:]
    // Keep strong refs to peripherals during a refresh (CB requires it).
    private var active: [UUID: CBPeripheral] = [:]

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func refresh(completion: @escaping ([DeviceReading]) -> Void) {
        guard state == .poweredOn else {
            // Can't read now: report last known, all offline.
            completion(offlineSnapshot())
            return
        }
        // If a refresh is already running, replace its completion.
        self.completion = completion
        pending.removeAll()
        collected.removeAll()
        firmwareDone.removeAll()
        active.removeAll()

        let peripherals = central.retrieveConnectedPeripherals(
            withServices: [Self.batteryService])
        if peripherals.isEmpty {
            finish()
            return
        }
        for p in peripherals {
            pending.insert(p.identifier)
            active[p.identifier] = p
            p.delegate = self
            central.connect(p, options: nil)
        }
        // Safety timeout: finalizes the cycle even if a device never returns
        // firmware (or has no Device Info Service at all).
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) {
            [weak self] _ in self?.finish()
        }
    }

    private func offlineSnapshot() -> [DeviceReading] {
        lastKnown.values.map {
            DeviceReading(id: $0.id, name: $0.name, battery: $0.battery,
                          online: false, firmware: $0.firmware, charging: nil)
        }
    }

    private func markDone(_ id: UUID) {
        pending.remove(id)
        if let p = active[id] { central.cancelPeripheralConnection(p) }
        if pending.isEmpty { finish() }
    }

    private func finish() {
        guard let completion = completion else { return }
        self.completion = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        // Merge this cycle's readings into lastKnown.
        for (id, r) in collected { lastKnown[id] = r }
        let onlineIDs = Set(collected.keys)

        var result: [DeviceReading] = []
        for (id, known) in lastKnown {
            if onlineIDs.contains(id) {
                result.append(known)
            } else {
                result.append(DeviceReading(
                    id: known.id, name: known.name, battery: known.battery,
                    online: false, firmware: known.firmware, charging: nil))
            }
        }
        active.removeAll()
        completion(result.sorted { $0.name < $1.name })
    }
}

extension BatteryReader: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        onStateChange?(state)
    }

    public func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.batteryService, Self.deviceInfoService])
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect p: CBPeripheral, error: Error?) {
        markDone(p.identifier)
    }
}

extension BatteryReader: CBPeripheralDelegate {
    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = p.services, !services.isEmpty else {
            recordPartial(p); markDone(p.identifier); return
        }
        for s in services {
            p.discoverCharacteristics([Self.batteryLevel, Self.firmwareRev], for: s)
        }
    }

    public func peripheral(_ p: CBPeripheral,
                           didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] where
            ch.uuid == Self.batteryLevel || ch.uuid == Self.firmwareRev {
            p.readValue(for: ch)
        }
    }

    public func peripheral(_ p: CBPeripheral,
                           didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        let id = p.identifier
        var current = collected[id] ?? DeviceReading(
            id: id.uuidString, name: p.name ?? "Unknown", battery: nil, online: true)

        if ch.uuid == Self.batteryLevel, let d = ch.value, let first = d.first {
            current = DeviceReading(id: current.id, name: current.name,
                                    battery: Int(first), online: true,
                                    firmware: current.firmware, charging: nil)
        } else if ch.uuid == Self.firmwareRev {
            let fw = ch.value.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
            current = DeviceReading(id: current.id, name: current.name,
                                    battery: current.battery, online: true,
                                    firmware: fw, charging: nil)
            firmwareDone.insert(id)
        }
        collected[id] = current

        // Done once we have battery AND firmware has been read. Devices with no
        // Device Info Service never set firmwareDone and are finalized by the
        // safety timeout instead.
        if current.battery != nil && firmwareDone.contains(id) { markDone(id) }
    }

    /// If discovery fails but the device was connected, still record it online
    /// with whatever (if anything) we have.
    private func recordPartial(_ p: CBPeripheral) {
        let id = p.identifier
        if collected[id] == nil {
            collected[id] = DeviceReading(id: id.uuidString,
                                          name: p.name ?? "Unknown",
                                          battery: lastKnown[id]?.battery,
                                          online: true,
                                          firmware: lastKnown[id]?.firmware)
        }
    }
}
