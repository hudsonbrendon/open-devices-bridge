import Foundation
import CocoaMQTT

/// Publishes HA MQTT Discovery configs + per-device state, with a Last-Will
/// that marks the bridge offline if the app dies.
public final class MQTTPublisher: NSObject {
    public enum Status: Equatable { case disconnected, connecting, connected }

    public private(set) var status: Status = .disconnected {
        didSet { if status != oldValue { onMain { self.onStatusChange?(self.status) } } }
    }
    /// Status changes, always delivered on the main queue.
    public var onStatusChange: ((Status) -> Void)?
    /// Fired right after a successful connect, so the app can push a fresh read.
    public var onConnected: (() -> Void)?

    private var mqtt: CocoaMQTT?
    private var config: SettingsStore.Config
    private var announced: Set<String> = []
    private var latest: [DeviceReading] = []

    public init(config: SettingsStore.Config) { self.config = config }

    // MARK: lifecycle

    public func start() {
        stop()
        guard config.isConfigured else { status = .disconnected; return }
        let client = makeClient(config: config, clientID: config.clientID)
        client.willMessage = CocoaMQTTMessage(
            topic: DiscoveryPayload.bridgeAvailabilityTopic,
            string: DiscoveryPayload.availableOffline, qos: .qos1, retained: true)
        client.autoReconnect = true
        client.delegate = self
        mqtt = client
        status = .connecting
        _ = client.connect()
    }

    public func stop() {
        if let m = mqtt {
            _ = m.publish(DiscoveryPayload.bridgeAvailabilityTopic,
                          withString: DiscoveryPayload.availableOffline,
                          qos: .qos1, retained: true)
            m.disconnect()
        }
        mqtt = nil
        announced.removeAll()
        status = .disconnected
    }

    public func updateConfig(_ c: SettingsStore.Config) {
        config = c
        start()
    }

    // MARK: publishing

    /// Publish discovery (once per device per connection) + live state.
    public func publish(readings: [DeviceReading]) {
        latest = readings
        guard let m = mqtt, status == .connected else { return }
        for r in readings {
            let obj = slugify(r.name)
            if !announced.contains(obj) {
                for msg in DiscoveryPayload.discoveryMessages(for: r) {
                    _ = m.publish(msg.topic, withString: msg.payload,
                                  qos: .qos1, retained: msg.retained)
                }
                announced.insert(obj)
            }
            _ = m.publish(DiscoveryPayload.stateTopic(objectId: obj),
                          withString: DiscoveryPayload.stateJSON(for: r),
                          qos: .qos1, retained: true)
        }
    }

    private func makeClient(config: SettingsStore.Config, clientID: String) -> CocoaMQTT {
        let m = CocoaMQTT(clientID: clientID, host: config.host,
                          port: UInt16(config.port))
        if !config.username.isEmpty { m.username = config.username }
        if !config.password.isEmpty { m.password = config.password }
        m.keepAlive = 60
        return m
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
}

extension MQTTPublisher: CocoaMQTTDelegate {
    public func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        guard ack == .accept else { status = .disconnected; return }
        status = .connected
        announced.removeAll()
        _ = mqtt.publish(DiscoveryPayload.bridgeAvailabilityTopic,
                         withString: DiscoveryPayload.availableOnline,
                         qos: .qos1, retained: true)
        let snapshot = latest
        onMain {
            if !snapshot.isEmpty { self.publish(readings: snapshot) }
            self.onConnected?()
        }
    }

    public func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        status = mqtt.autoReconnect ? .connecting : .disconnected
        announced.removeAll()
    }

    // Unused delegate requirements.
    public func mqtt(_ m: CocoaMQTT, didPublishMessage msg: CocoaMQTTMessage, id: UInt16) {}
    public func mqtt(_ m: CocoaMQTT, didPublishAck id: UInt16) {}
    public func mqtt(_ m: CocoaMQTT, didReceiveMessage msg: CocoaMQTTMessage, id: UInt16) {}
    public func mqtt(_ m: CocoaMQTT, didSubscribeTopics s: NSDictionary, failed: [String]) {}
    public func mqtt(_ m: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    public func mqttDidPing(_ m: CocoaMQTT) {}
    public func mqttDidReceivePong(_ m: CocoaMQTT) {}
}

/// One-shot connection test for the settings "Test connection" button.
public final class MQTTConnectionTester: NSObject, CocoaMQTTDelegate {
    private var mqtt: CocoaMQTT?
    private var completion: ((Bool, String?) -> Void)?
    private var timer: Timer?

    public override init() { super.init() }

    public func test(config: SettingsStore.Config,
                     completion: @escaping (Bool, String?) -> Void) {
        guard config.isConfigured else { completion(false, "Host/porta inválidos"); return }
        self.completion = completion
        let m = CocoaMQTT(clientID: config.clientID + "-test", host: config.host,
                          port: UInt16(config.port))
        if !config.username.isEmpty { m.username = config.username }
        if !config.password.isEmpty { m.password = config.password }
        m.autoReconnect = false
        m.keepAlive = 10
        m.delegate = self
        mqtt = m
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            self?.done(false, "Timeout — sem resposta do broker")
        }
        _ = m.connect()
    }

    private func done(_ ok: Bool, _ msg: String?) {
        timer?.invalidate(); timer = nil
        mqtt?.disconnect(); mqtt = nil
        let c = completion; completion = nil
        DispatchQueue.main.async { c?(ok, msg) }
    }

    public func mqtt(_ m: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        if ack == .accept { done(true, nil) }
        else { done(false, "Recusado pelo broker: \(ack)") }
    }
    public func mqttDidDisconnect(_ m: CocoaMQTT, withError err: Error?) {
        if completion != nil { done(false, err?.localizedDescription ?? "Conexão falhou") }
    }
    public func mqtt(_ m: CocoaMQTT, didPublishMessage msg: CocoaMQTTMessage, id: UInt16) {}
    public func mqtt(_ m: CocoaMQTT, didPublishAck id: UInt16) {}
    public func mqtt(_ m: CocoaMQTT, didReceiveMessage msg: CocoaMQTTMessage, id: UInt16) {}
    public func mqtt(_ m: CocoaMQTT, didSubscribeTopics s: NSDictionary, failed: [String]) {}
    public func mqtt(_ m: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    public func mqttDidPing(_ m: CocoaMQTT) {}
    public func mqttDidReceivePong(_ m: CocoaMQTT) {}
}
