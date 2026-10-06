import Foundation
import PNProtocol

/// MQTT Manager for realtime data synchronization
/// Uses pn-protocol as the transport layer
internal class MqttManager {
    private let config: RiviumSyncConfig
    private let apiClient: ApiClient
    /// Project the API key belongs to, learned from POST /connections/token.
    private var projectId: String?
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

    // The socket's own autoReconnect only covers a socket that exists. If the
    // token request fails (e.g. the app started offline) there is no socket yet,
    // so without this the SDK stayed "connecting" forever after the network
    // came back. These drive a retry of the whole connect, token included.
    private var wantConnected = false
    private var tokenRetryAttempt = 0
    private var tokenRetryTask: Task<Void, Never>?
    private static let tokenRetryBaseSeconds: Double = 2
    private static let tokenRetryMaxSeconds: Double = 30

    // The project requires a signed user token and the app has none yet (no
    // one is signed in). That is not a failure and retrying cannot fix it: the
    // connect is parked here until the app supplies a token.
    private var awaitingUserToken = false
    // The user the socket was authorised as, to notice a different one.
    private var socketUser: String?
    // A realtime-token request is in flight / a socket was opened with its answer.
    private var fetchingToken = false
    private var socketOpened = false
    // Bumped by every connect attempt and by disconnect, so an answer that
    // arrives after something newer replaced it is dropped.
    private var attempt = 0
    private let stateLock = NSLock()

    /// Strong references to listeners (PNSocket stores them as weak refs)
    private var connectionHandler: ConnectionHandler?
    private var errorHandler: ErrorHandler?

    weak var delegate: MqttManagerDelegate?

    /// Callback for connection state changes
    var onConnectionStateChanged: ((Bool) -> Void)?

    /// Connect is parked until the app supplies a user token.
    var onAwaitingUserToken: (() -> Void)?

    var isAwaitingUserToken: Bool {
        return locked { awaitingUserToken }
    }

    protocol MqttManagerDelegate: AnyObject {
        func mqttManagerDidConnect(_ manager: MqttManager)
        func mqttManager(_ manager: MqttManager, didDisconnectWithError error: Error?)
        func mqttManager(_ manager: MqttManager, didReceiveMessage message: String, topic: String)
    }

    init(config: RiviumSyncConfig, apiClient: ApiClient) {
        self.config = config
        self.apiClient = apiClient
        apiClient.userTokens.onUserMayHaveChanged = { [weak self] in
            self?.userMayHaveChanged()
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    var isConnected: Bool {
        return socket?.isConnected() ?? false
    }

    func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        if isConnected {
            completion(.success(()))
            return
        }

        wantConnected = true
        cancelTokenRetry()
        tokenRetryAttempt = 0
        connectInternal(completion: completion)
    }

    private func connectInternal(completion: @escaping (Result<Void, Error>) -> Void) {
        let mine: Int = locked {
            attempt += 1
            fetchingToken = true
            socketUser = apiClient.userTokens.heldUser()
            return attempt
        }
        // Fetch token from API first
        Task {
            do {
                RiviumSyncLogger.d("Fetching MQTT token...")
                let tokenResponse = try await apiClient.fetchMqttToken()
                let user = UserTokenStore.user(of: await apiClient.userTokens.current())
                let current: Bool = locked {
                    guard attempt == mine else { return false }
                    fetchingToken = false
                    socketOpened = true
                    awaitingUserToken = false
                    socketUser = user
                    return true
                }
                guard current else {
                    completion(replacedResult())
                    return
                }
                tokenRetryAttempt = 0
                projectId = tokenResponse.projectId
                rekeyUnknownTopics()
                RiviumSyncLogger.d("MQTT token obtained")
                self.connectWithToken(token: tokenResponse.token, completion: completion)
            } catch {
                let current: Bool = locked {
                    guard attempt == mine else { return false }
                    fetchingToken = false
                    return true
                }
                guard current else {
                    completion(replacedResult())
                    return
                }
                if Self.isUserTokenRequired(error) {
                    // Nobody is signed in yet. Wait for the app's token instead
                    // of retrying; connect() itself has not failed. The
                    // completion is the caller's on a first attempt and a no-op
                    // on every later one, so it is resumed exactly once.
                    tokenRetryAttempt = 0
                    let entered: Bool = locked {
                        let was = awaitingUserToken
                        awaitingUserToken = true
                        return !was
                    }
                    if entered {
                        RiviumSyncLogger.i("This project requires a user token; realtime connects when one is set")
                        onAwaitingUserToken?()
                    }
                    completion(.success(()))
                    return
                }
                locked { awaitingUserToken = false }
                RiviumSyncLogger.e("Failed to fetch MQTT token", error: error)
                if tokenRetryAttempt == 0 {
                    // Report once per failure streak. `connect() async` wraps this
                    // completion in a continuation, which must never resume twice,
                    // so retries below pass a no-op instead.
                    completion(.failure(error))
                    onConnectionStateChanged?(false)
                }
                scheduleTokenRetry()
            }
        }
    }

    /// What to tell a caller whose attempt was replaced before it finished: a
    /// newer attempt is establishing the connection, unless the app disconnected.
    private func replacedResult() -> Result<Void, Error> {
        if wantConnected { return .success(()) }
        return .failure(RiviumSyncError.connectionError("Disconnected before the connection was established", nil))
    }

    /// True when the realtime-token request was refused because the project
    /// requires a signed user token and none was sent.
    static func isUserTokenRequired(_ error: Error) -> Bool {
        if case RiviumSyncError.networkError(_, let cause) = error {
            return cause is UserTokenRequiredError
        }
        return false
    }

    /// The app set, cleared or refreshed its user token. Connect if that is what
    /// the SDK was waiting for; reconnect if the socket belongs to another user.
    /// A new token for the same user changes nothing here.
    func userMayHaveChanged() {
        guard wantConnected else { return }
        Task {
            let token = await apiClient.userTokens.current()
            let user = UserTokenStore.user(of: token)
            guard wantConnected else { return }

            // 1 = connect, 2 = reconnect
            let step: Int = locked {
                if awaitingUserToken {
                    guard token != nil else { return 0 }
                    awaitingUserToken = false
                    return 1
                }
                guard socketOpened || fetchingToken, user != socketUser else { return 0 }
                socketOpened = false
                return 2
            }
            guard step != 0 else { return }

            cancelTokenRetry()
            tokenRetryAttempt = 0
            if step == 1 {
                RiviumSyncLogger.i("User token available; connecting")
            } else {
                RiviumSyncLogger.i("Signed-in user changed; reconnecting")
                // Keep `subscriptions`: they are subscribed again on connect.
                socket?.close()
                socket = nil
                hasSubscribedOnce = false
                pnListeners.removeAll()
            }
            // No-op completion: the caller's connect() was answered long ago.
            connectInternal(completion: { _ in })
        }
    }

    private func scheduleTokenRetry() {
        guard config.autoReconnect, wantConnected else { return }
        let delay = min(
            Self.tokenRetryBaseSeconds * pow(2, Double(min(tokenRetryAttempt, 4))),
            Self.tokenRetryMaxSeconds
        )
        tokenRetryAttempt += 1
        RiviumSyncLogger.i("Connect failed; retrying in \(delay)s (attempt \(tokenRetryAttempt))")
        tokenRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self = self, !Task.isCancelled, self.wantConnected else { return }
            self.connectInternal(completion: { _ in })
        }
    }

    private func cancelTokenRetry() {
        tokenRetryTask?.cancel()
        tokenRetryTask = nil
    }

    /// Opens the socket. Separate so the token handling above can be tested
    /// without a broker.
    func connectWithToken(token: String, completion: @escaping (Result<Void, Error>) -> Void) {
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
        // A pending retry must not bring the connection back after the app
        // asked for it to close.
        wantConnected = false
        cancelTokenRetry()
        locked {
            attempt += 1
            fetchingToken = false
            socketOpened = false
            awaitingUserToken = false
            socketUser = nil
        }
        subscriptionsQueue.sync {
            subscriptions.removeAll()
        }
        pnListeners.removeAll()
        hasSubscribedOnce = false
        socket?.close()
        socket = nil
    }

    func subscribe(topic: String, callback: @escaping (String) -> Void) -> SubscriptionHandle {
        let topic = resolvedTopic(topic)
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
        // The handle may predate the project id; its subscription has moved since.
        let topic = resolvedTopic(handle.topic)
        subscriptionsQueue.sync {
            if var callbacks = subscriptions[topic] {
                RiviumSyncLogger.i("MqttManager.unsubscribe: Found \(callbacks.count) callbacks for topic")
                callbacks.removeValue(forKey: handle.id)
                if callbacks.isEmpty {
                    subscriptions.removeValue(forKey: topic)
                    pnListeners.removeValue(forKey: topic)
                    if isConnected {
                        socket?.detach(topic)
                        RiviumSyncLogger.d("Detached from channel: \(topic)")
                    }
                } else {
                    subscriptions[topic] = callbacks
                    RiviumSyncLogger.i("MqttManager.unsubscribe: Still \(callbacks.count) callbacks remaining")
                }
            } else {
                RiviumSyncLogger.i("MqttManager.unsubscribe: No callbacks found for topic \(topic)")
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
            self.deliver(payload, topic: message.channel)
        }

        pnListeners[topic] = listener
        socket?.stream(topic, mode: .reliable, listener: listener)
    }

    /// Hand a message to every callback registered for its topic.
    func deliver(_ payload: String, topic: String) {
        subscriptionsQueue.sync {
            let callbackCount = subscriptions[topic]?.count ?? 0
            RiviumSyncLogger.i("MqttManager.didReceiveMessage: topic=\(topic), callbackCount=\(callbackCount)")
            if callbackCount == 0 {
                RiviumSyncLogger.w("MqttManager.didReceiveMessage: No callbacks for topic! Available topics: \(Array(subscriptions.keys))")
            }
            subscriptions[topic]?.values.forEach { callback in
                RiviumSyncLogger.i("MqttManager.didReceiveMessage: Invoking callback for topic \(topic)")
                callback(payload)
            }
        }
    }

    /// Every topic the app is listening to, connected or not.
    var subscribedTopics: [String] {
        return subscriptionsQueue.sync { Array(subscriptions.keys) }
    }

    /// Subscribe all pending topics (topics registered before connection was established).
    /// Called only once on first connect. On reconnect, PNSocket handles resubscription automatically.
    fileprivate func subscribePendingTopics() {
        let topics = subscribedTopics
        RiviumSyncLogger.i("subscribePendingTopics: \(topics.count) pending topics: \(topics)")
        for topic in topics {
            subscribeViaPNProtocol(topic: topic)
        }
    }

    // A listener added before the first realtime-token answer (the app is
    // offline, or waiting for a user token) cannot know the project id yet, so
    // its topic carries this placeholder until the answer arrives.
    private static let unknownTopicPrefix = "rivium_sync/unknown/"

    /// The topic as it is now that the project id may be known.
    private func resolvedTopic(_ topic: String) -> String {
        guard let projectId = projectId, topic.hasPrefix(Self.unknownTopicPrefix) else { return topic }
        return "rivium_sync/\(projectId)/" + topic.dropFirst(Self.unknownTopicPrefix.count)
    }

    /// Move subscriptions made under the placeholder to the real project topic,
    /// before they are subscribed on the socket.
    private func rekeyUnknownTopics() {
        guard projectId != nil else { return }
        subscriptionsQueue.sync {
            for (topic, callbacks) in subscriptions where topic.hasPrefix(Self.unknownTopicPrefix) {
                subscriptions.removeValue(forKey: topic)
                pnListeners.removeValue(forKey: topic)
                subscriptions[resolvedTopic(topic), default: [:]].merge(callbacks) { current, _ in current }
            }
        }
    }

    /// Topic for collection changes.
    ///
    /// `rivium_sync/{projectId}/{databaseName}/{collectionName}/changes` - the
    /// names the app uses, under the project id from POST /connections/token, so
    /// the same database name in two projects cannot collide. The broker grants
    /// a client only its own `rivium_sync/{projectId}/#`.
    func collectionTopic(databaseId: String, collectionId: String) -> String {
        return "rivium_sync/\(projectId ?? "unknown")/\(databaseId)/\(collectionId)/changes"
    }

    /// Topic for one document's changes.
    func documentTopic(databaseId: String, collectionId: String, documentId: String) -> String {
        return "rivium_sync/\(projectId ?? "unknown")/\(databaseId)/\(collectionId)/\(documentId)"
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
