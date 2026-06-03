// Spike: ler bateria de devices ja conectados ao sistema via CoreBluetooth (API publica).
// retrieveConnectedPeripherals(withServices:[0x180F]) -> connect (compartilha conexao do sistema) -> read 0x2A19
import Foundation
import CoreBluetooth

let BATT_SVC = CBUUID(string: "180F")
let BATT_LVL = CBUUID(string: "2A19")
let DEV_INFO = CBUUID(string: "180A")
let FW_REV = CBUUID(string: "2A26")

final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var peripherals: [CBPeripheral] = []
    var pending = 0

    func start() { central = CBCentralManager(delegate: self, queue: nil) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        print("[state] \(c.state.rawValue) (5=poweredOn, 3=unauthorized, 4=poweredOff)")
        guard c.state == .poweredOn else {
            if c.state == .unauthorized { print("[!] SEM permissao Bluetooth pro terminal") ; exit(2) }
            return
        }
        let found = c.retrieveConnectedPeripherals(withServices: [BATT_SVC])
        print("[connected w/ BatteryService] count=\(found.count)")
        if found.isEmpty {
            print("[!] Nenhum device conectado expoe 0x180F ao sistema.")
            exit(3)
        }
        for p in found {
            print("  - \(p.name ?? "?")  id=\(p.identifier)")
            peripherals.append(p)
            pending += 1
            p.delegate = self
            c.connect(p, options: nil)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        print("[connect] \(p.name ?? "?")")
        p.discoverServices([BATT_SVC, DEV_INFO])
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == BATT_LVL || ch.uuid == FW_REV { p.readValue(for: ch) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value else { return }
        if ch.uuid == BATT_LVL { print("  [\(p.name ?? "?")] BATERIA = \(Int(d[0]))%") }
        else if ch.uuid == FW_REV { print("  [\(p.name ?? "?")] FW = \(String(data: d, encoding: .utf8) ?? d.hexEncoded)") }
        pending -= 1
        if pending <= 0 { print("[done]"); exit(0) }
    }
}

extension Data { var hexEncoded: String { map { String(format: "%02x", $0) }.joined() } }

let probe = Probe()
probe.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 15) { print("[timeout]"); exit(4) }
RunLoop.main.run()
