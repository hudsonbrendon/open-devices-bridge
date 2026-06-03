import Foundation

/// Persisted configuration: MQTT connection + poll interval.
/// Non-secret fields in UserDefaults; password in the Keychain.
public final class SettingsStore {
    public struct Config: Equatable {
        public var host: String
        public var port: Int
        public var username: String
        public var password: String
        public var pollIntervalMinutes: Int
        public var clientID: String

        public init(host: String = "", port: Int = 1883, username: String = "",
                    password: String = "", pollIntervalMinutes: Int = 5,
                    clientID: String = "ha-battery-bridge") {
            self.host = host
            self.port = port
            self.username = username
            self.password = password
            self.pollIntervalMinutes = pollIntervalMinutes
            self.clientID = clientID
        }

        public var isConfigured: Bool { !host.isEmpty && port > 0 }
    }

    private enum Key {
        static let host = "mqtt.host"
        static let port = "mqtt.port"
        static let username = "mqtt.username"
        static let interval = "poll.intervalMinutes"
    }
    private static let pwAccount = "mqtt.password"

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> Config {
        Config(
            host: defaults.string(forKey: Key.host) ?? "",
            port: defaults.object(forKey: Key.port) as? Int ?? 1883,
            username: defaults.string(forKey: Key.username) ?? "",
            password: Keychain.get(account: Self.pwAccount) ?? "",
            pollIntervalMinutes: defaults.object(forKey: Key.interval) as? Int ?? 5
        )
    }

    public func save(_ c: Config) {
        defaults.set(c.host, forKey: Key.host)
        defaults.set(c.port, forKey: Key.port)
        defaults.set(c.username, forKey: Key.username)
        defaults.set(max(1, c.pollIntervalMinutes), forKey: Key.interval)
        if c.password.isEmpty {
            Keychain.delete(account: Self.pwAccount)
        } else {
            Keychain.set(c.password, account: Self.pwAccount)
        }
    }
}
