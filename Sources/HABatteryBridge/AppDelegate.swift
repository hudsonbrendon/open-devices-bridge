import AppKit
import SwiftUI
import HABatteryCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private let menu = MenuBarController()
    private let reader = BatteryReader()
    private var publisher: MQTTPublisher!
    private var timer: Timer?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = store.load()
        publisher = MQTTPublisher(config: config)

        menu.onOpenSettings = { [weak self] in self?.showSettings() }
        menu.onRefreshNow = { [weak self] in self?.refreshNow() }
        menu.onQuit = { [weak self] in self?.quit() }

        reader.onStateChange = { [weak self] state in
            self?.menu.update(bluetooth: state)
            if state == .poweredOn { self?.refreshNow() }
        }
        publisher.onStatusChange = { [weak self] status in
            self?.menu.update(mqtt: status)
        }
        publisher.onConnected = { [weak self] in self?.refreshNow() }

        menu.update(bluetooth: reader.state)
        menu.update(mqtt: publisher.status)
        publisher.start()
        startTimer(minutes: config.pollIntervalMinutes)
        refreshNow()
    }

    private func refreshNow() {
        reader.refresh { [weak self] readings in
            guard let self else { return }
            self.menu.update(readings: readings)
            self.publisher.publish(readings: readings)
        }
    }

    private func startTimer(minutes: Int) {
        timer?.invalidate()
        let interval = TimeInterval(max(1, minutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in self?.refreshNow()
        }
    }

    private func showSettings() {
        let config = store.load()
        let view = SettingsView(config: config) { [weak self] newConfig in
            guard let self else { return }
            self.store.save(newConfig)
            let saved = self.store.load()
            self.publisher.updateConfig(saved)
            self.startTimer(minutes: saved.pollIntervalMinutes)
            self.settingsWindow?.close()
            self.refreshNow()
        }

        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "HA Battery Bridge"
            window.contentViewController = NSHostingController(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func quit() {
        publisher.stop()
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        publisher.stop()
        return .terminateNow
    }
}
