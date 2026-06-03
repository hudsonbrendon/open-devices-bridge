import AppKit
import CoreBluetooth
import HABatteryCore

/// Owns the NSStatusItem and renders the dropdown menu.
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength)

    var onOpenSettings: (() -> Void)?
    var onRefreshNow: (() -> Void)?
    var onQuit: (() -> Void)?

    private var readings: [DeviceReading] = []
    private var mqttStatus: MQTTPublisher.Status = .disconnected
    private var btState: CBManagerState = .unknown

    override init() {
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "battery.100",
                                   accessibilityDescription: "Battery")
            button.imagePosition = .imageLeading
            button.title = " —"
        }
        rebuild()
    }

    func update(readings: [DeviceReading]) {
        self.readings = readings
        refreshTitle()
        rebuild()
    }

    func update(mqtt: MQTTPublisher.Status) { mqttStatus = mqtt; rebuild() }
    func update(bluetooth: CBManagerState) { btState = bluetooth; rebuild() }

    private func refreshTitle() {
        let onlineBatteries = readings.filter { $0.online }.compactMap { $0.battery }
        if let minB = onlineBatteries.min() {
            statusItem.button?.title = " \(minB)%"
        } else {
            statusItem.button?.title = " —"
        }
    }

    private func rebuild() {
        let menu = NSMenu()

        if btState != .poweredOn {
            menu.addItem(warningItem(for: btState))
            menu.addItem(.separator())
        }

        if readings.isEmpty {
            let none = NSMenuItem(title: "Nenhum dispositivo encontrado",
                                  action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for r in readings.sorted(by: { $0.name < $1.name }) {
                menu.addItem(deviceItem(r))
            }
        }

        menu.addItem(.separator())
        let status = NSMenuItem(title: "MQTT: \(mqttLabel)", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Atualizar agora",
                                action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Configurações…",
                                action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair",
                                action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    private func deviceItem(_ r: DeviceReading) -> NSMenuItem {
        let battery = r.battery.map { "\($0)%" } ?? "—"
        let dot = r.online ? "🟢" : "⚪️"
        let item = NSMenuItem(title: "\(dot) \(r.name): \(battery)",
                              action: nil, keyEquivalent: "")
        if let fw = r.firmware {
            item.toolTip = "Firmware \(fw)"
        }
        item.isEnabled = false
        return item
    }

    private func warningItem(for state: CBManagerState) -> NSMenuItem {
        let msg: String
        switch state {
        case .unauthorized: msg = "⚠︎ Sem permissão de Bluetooth — abrir Ajustes"
        case .poweredOff: msg = "⚠︎ Bluetooth desligado"
        default: msg = "⚠︎ Bluetooth indisponível"
        }
        let item = NSMenuItem(title: msg, action: #selector(openBluetoothSettings),
                              keyEquivalent: "")
        item.target = self
        return item
    }

    private var mqttLabel: String {
        switch mqttStatus {
        case .connected: return "conectado"
        case .connecting: return "conectando…"
        case .disconnected: return "desconectado"
        }
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func refreshNow() { onRefreshNow?() }
    @objc private func quit() { onQuit?() }
    @objc private func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }
}
