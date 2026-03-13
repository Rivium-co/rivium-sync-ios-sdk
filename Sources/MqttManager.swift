import Foundation
import PNProtocol

/// MQTT Manager for realtime data synchronization
/// Uses pn-protocol as the transport layer
internal class MqttManager {
    private let config: RiviumSyncConfig
    private let apiClient: ApiClient
    /// Maps topic -> [handleId -> callback]
    private var subscriptions: [String: [UUID: (String) -> Void]] = [:]
    private let subscriptionsQueue = DispatchQueue(label: "co.rivium.subscriptions")
    /// Stable clientId per instance — prevents orphaned sessions on reconnect
    private let clientId: String = "rivium_sync_\(UUID().uuidString.prefix(8))"

    /// Track which topics we've already called stream() for on the current PNSocket.
    /// PNSocket keeps its own messageListeners and activeChannels across reconnects,
    /// so we only need to call stream() once per topic per PNSocket instance.
    private var pnListeners: [String: PNMessageHandler] = [:]

    /// Track whether we have subscribed at least once on the current PNSocket.
    /// On reconnect, PNSocket.resubscribeChannels() handles re-subscription
    /// automatically — we do NOT need to call stream() again.
    fileprivate var hasSubscribedOnce = false

    /// Hold a reference to the PNSocket
    private var socket: PNSocket?

    /// Strong references to listeners (PNSocket stores them as weak refs)
    private var connectionHandler: ConnectionHandler?
    private var errorHandler: ErrorHandler?

    weak var delegate: MqttManagerDelegate?

    /// Callback for connection state changes
    var onConnectionStateChanged: ((Bool) -> Void)?

    protocol MqttManagerDelegate: AnyObject {
        func mqttManagerDidConnect(_ manager: MqttManager)
        func mqttManager(_ manager: MqttManager, didDisconnectWithError error: Error?)
        func mqttManager(_ manager: MqttManager, didReceiveMessage message: String, topic: String)
    }

    init(config: RiviumSyncConfig, apiClient: ApiClient) {
        self.config = config
        self.apiClient = apiClient
    }

    var isConnected: Bool {
        return socket?.isConnected() ?? false
    }

    func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        if isConnected {
            completion(.success(()))
            return
        }

        // Fetch token from API first
        Task {
            do {
                RiviumSyncLogger.d("Fetching MQTT token...")
                let tokenResponse = try await apiClient.fetchMqttToken()
                RiviumSyncLogger.d("MQTT token obtained")
                self.connectWithToken(token: tokenResponse.token, completion: completion)
            } catch {
                RiviumSyncLogger.e("Failed to fetch MQTT token", error: error)
                completion(.failure(error))
            }
        }
    }

    private func connectWithToken(token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        RiviumSyncLogger.d("Connecting to \(config.mqttHost):\(config.mqttPort) (TLS: \(config.mqttUseTls))")

        // Close any existing socket to prevent orphaned connections
        if socket != nil {
            RiviumSyncLogger.d("Closing existing socket before reconnect")
            socket?.close()
            socket = nil
            hasSubscribedOnce = false
            pnListeners.removeAll()
        }

        let pnConfig = PNConfig(
            gateway: config.mqttHost,
            port: UInt16(config.mqttPort),
            clientId: clientId,
            auth: .basic(username: "jwt", password: token),
            heartbeatInterval: UInt16(config.keepAliveInterval),
            connectionTimeout: TimeInterval(config.connectionTimeout),
            freshStart: true,
            autoReconnect: config.autoReconnect,
            secure: config.mqttUseTls
        )

        socket = PNSocket(config: pnConfig)

        // Store strong references — PNSocket uses WeakRef internally
        connectionHandler = ConnectionHandler(manager: self, completion: completion)
        errorHandler = ErrorHandler(manager: self)

        socket!.addConnectionListener(connectionHandler!)
        socket!.addErrorListener(errorHandler!)

        // Open connection — onConnected callback fires when ready
        socket!.open()
    }

    func disconnect() {
        RiviumSyncLogger.i("MqttManager.disconnect() called")
        subscriptionsQueue.sync {
            subscriptions.removeAll()
        }
        pnListeners.removeAll()
        hasSubscribedOnce = false
        socket?.close()
        socket = nil
    }

    func subscribe(topic: String, callback: @escaping (String) -> Void) -> SubscriptionHandle {
        let handle = SubscriptionHandle(topic: topic, callback: callback, manager: self)
        RiviumSyncLogger.i("MqttManager.subscribe called for topic: \(topic), handleId: \(handle.id), isConnected: \(isConnected)")

        subscriptionsQueue.sync {
            if subscriptions[topic] == nil {
                subscriptions[topic] = [:]
            }
            subscriptions[topic]?[handle.id] = callback
            RiviumSyncLogger.i("MqttManager.subscribe: Added callback, now \(subscriptions[topic]?.count ?? 0) callbacks for topic")
        }

        if isConnected {
            subscribeViaPNProtocol(topic: topic)
        } else {
            RiviumSyncLogger.w("MqttManager.subscribe: Not connected, subscription will be pending")
        }

        return handle
    }

    func unsubscribe(handle: SubscriptionHandle) {
        RiviumSyncLogger.i("MqttManager.unsubscribe called for topic: \(handle.topic), handleId: \(handle.id)")
        subscriptionsQueue.sync {
            if var callbacks = subscriptions[handle.topic] {
                RiviumSyncLogger.i("MqttManager.unsubscribe: Found \(callbacks.count) callbacks for topic")
                callbacks.removeValue(forKey: handle.id)
                if callbacks.isEmpty {
                    subscriptions.removeValue(forKey: handle.topic)
                    pnListeners.removeValue(forKey: handle.topic)
                    if isConnected {
                        socket?.detach(handle.topic)
                        RiviumSyncLogger.d("Detached from channel: \(handle.topic)")
                    }
                } else {
                    subscriptions[handle.topic] = callbacks
                    RiviumSyncLogger.i("MqttManager.unsubscribe: Still \(callbacks.count) callbacks remaining")
                }
            } else {
                RiviumSyncLogger.i("MqttManager.unsubscribe: No callbacks found for topic \(handle.topic)")
            }
        }
    }

    /// Subscribe to a topic via pn-protocol, bridging PNMessage to String callback.
    /// Only calls stream() once per topic per PNSocket instance — PNSocket handles
    /// resubscription on reconnect automatically via its activeChannels set.
    private func subscribeViaPNProtocol(topic: String) {
        if pnListeners[topic] != nil { return }

        RiviumSyncLogger.d("Subscribing to channel: \(topic)")

        let listener = PNMessageHandler { [weak self] message in
            guard let self = self else { return }
            let payload = message.payloadAsString()
            RiviumSyncLogger.d("Message received on \(message.channel)")

            self.delegate?.mqttManager(self, didReceiveMessage: payload, topic: message.channel)

            self.subscriptionsQueue.sync {
                let callbackCount = self.subscriptions[message.channel]?.count ?? 0
                RiviumSyncLogger.i("MqttManager.didReceiveMessage: topic=\(message.channel), callbackCount=\(callbackCount)")
                if callbackCount == 0 {
                    RiviumSyncLogger.w("MqttManager.didReceiveMessage: No callbacks for topic! Available topics: \(Array(self.subscriptions.keys))")
                }
                self.subscriptions[message.channel]?.values.forEach { callback in
                    RiviumSyncLogger.i("MqttManager.didReceiveMessage: Invoking callback for topic \(message.channel)")
                    callback(payload)
                }
            }
        }

        pnListeners[topic] = listener
        socket?.stream(topic, mode: .reliable, listener: listener)
    }

    /// Subscribe all pending topics (topics registered before connection was established).
    /// Called only once on first connect. On reconnect, PNSocket handles resubscription automatically.
    fileprivate func subscribePendingTopics() {
        let topics: [String] = subscriptionsQueue.sync { Array(subscriptions.keys) }
        RiviumSyncLogger.i("subscribePendingTopics: \(topics.count) pending topics: \(topics)")
        for topic in topics {
            subscribeViaPNProtocol(topic: topic)
        }
    }

    func collectionTopic(databaseId: String, collectionId: String) -> String {
        return "rivium_sync/\(databaseId)/\(collectionId)/changes"
    }

    func documentTopic(databaseId: String, collectionId: String, documentId: String) -> String {
        return "rivium_sync/\(databaseId)/\(collectionId)/\(documentId)"
    }

    class SubscriptionHandle {
        let id: UUID
        let topic: String
        let callback: (String) -> Void
        weak var manager: MqttManager?

        init(topic: String, callback: @escaping (String) -> Void, manager: MqttManager) {
            self.id = UUID()
            self.topic = topic
            self.callback = callback
            self.manager = manager
        }
    }
}

// MARK: - PNConnectionListener handler

private class ConnectionHandler: PNConnectionListener {
    private weak var manager: MqttManager?
    private var completion: ((Result<Void, Error>) -> Void)?

    init(manager: MqttManager, completion: @escaping (Result<Void, Error>) -> Void) {
        self.manager = manager
        self.completion = completion
    }

    func onStateChanged(_ state: PNState) {
        RiviumSyncLogger.d("PN state changed: \(state)")
    }

    func onConnected() {
        guard let manager = manager else { return }
        RiviumSyncLogger.i("PN connected, hasSubscribedOnce=\(manager.hasSubscribedOnce)")

        if !manager.hasSubscribedOnce {
            manager.subscribePendingTopics()
            manager.hasSubscribedOnce = true
        } else {
            RiviumSyncLogger.d("Reconnected - PNSocket handles resubscription automatically")
        }

        manager.onConnectionStateChanged?(true)
        manager.delegate?.mqttManagerDidConnect(manager)
        completion?(.success(()))
        completion = nil
    }

    func onDisconnected(reason: String?) {
        guard let manager = manager else { return }
        RiviumSyncLogger.w("PN disconnected: \(reason ?? "unknown")")
        manager.onConnectionStateChanged?(false)
        manager.delegate?.mqttManager(manager, didDisconnectWithError: reason.map {
            RiviumSyncError.connectionError($0, nil)
        })
    }

    func onReconnecting(attempt: Int, nextRetryMs: Int) {
        RiviumSyncLogger.i("PN reconnecting: attempt=\(attempt), nextRetry=\(nextRetryMs)ms")
    }
}

// MARK: - PNErrorListener handler

private class ErrorHandler: PNErrorListener {
    private weak var manager: MqttManager?

    init(manager: MqttManager) {
        self.manager = manager
    }

    func onError(_ error: PNError) {
        RiviumSyncLogger.e("PN error: code=\(error.code), message=\(error.message)")
    }
}
