import SwiftUI
import ServiceManagement
import HABatteryCore

/// SwiftUI settings form. Reports a saved config back via `onSave`.
struct SettingsView: View {
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var interval: Int
    @State private var launchAtLogin: Bool
    @State private var testResult: String = ""
    @State private var testing = false

    let onSave: (SettingsStore.Config) -> Void
    private let tester = MQTTConnectionTester()

    init(config: SettingsStore.Config, onSave: @escaping (SettingsStore.Config) -> Void) {
        _host = State(initialValue: config.host)
        _port = State(initialValue: String(config.port))
        _username = State(initialValue: config.username)
        _password = State(initialValue: config.password)
        _interval = State(initialValue: config.pollIntervalMinutes)
        _launchAtLogin = State(initialValue: Self.loginEnabled)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Home Assistant — MQTT").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Broker (host)")
                    TextField("192.168.31.150", text: $host).frame(width: 220)
                }
                GridRow {
                    Text("Porta")
                    TextField("1883", text: $port).frame(width: 90)
                }
                GridRow {
                    Text("Usuário")
                    TextField("opcional", text: $username).frame(width: 220)
                }
                GridRow {
                    Text("Senha")
                    SecureField("opcional", text: $password).frame(width: 220)
                }
                GridRow {
                    Text("Intervalo (min)")
                    Stepper(value: $interval, in: 1...120) { Text("\(interval)") }
                        .frame(width: 120)
                }
            }

            Toggle("Iniciar no login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in Self.setLogin(enabled) }

            HStack {
                Button(testing ? "Testando…" : "Testar conexão") { runTest() }
                    .disabled(testing)
                Text(testResult).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Salvar") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func currentConfig() -> SettingsStore.Config {
        SettingsStore.Config(
            host: host.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 1883,
            username: username,
            password: password,
            pollIntervalMinutes: interval)
    }

    private func runTest() {
        testing = true
        testResult = ""
        tester.test(config: currentConfig()) { ok, msg in
            testing = false
            testResult = ok ? "✓ Conectado" : "✗ \(msg ?? "Falhou")"
        }
    }

    private func save() { onSave(currentConfig()) }

    // MARK: login item (SMAppService, macOS 13+)
    private static var loginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    private static func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("login item toggle failed: \(error)")
        }
    }
}
