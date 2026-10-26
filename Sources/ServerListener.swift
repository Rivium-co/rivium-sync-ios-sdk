import Foundation

// Server-routed listeners (Sync API 0.3.0+): the app asks the server to listen to one document or a query, the
// server checks it against the security rules and answers with the current result and a private realtime topic
// that only this connection may receive. Changes then arrive on that topic as added / modified / removed events.

// MARK: - Wire format

/// What a listener listens to.
internal struct ListenSpec {
    let databaseId: String
    let collectionId: String
    /// A document listener; nil for a collection or query listener.
    let documentId: String?
    var filters: [[String: Any]] = []
    var orderByField: String?
    var orderDirection: String = "asc"
    var limit: Int?
    var offset: Int?

    var isDocument: Bool { documentId != nil }

    /// The listener sees every document of its scope (one document, or a whole collection), so a document it no
    /// longer has is gone - not just out of a query's results.
    var seesWholeScope: Bool { documentId != nil || (filters.isEmpty && limit == nil && (offset ?? 0) == 0) }

    /// The POST …/listen body. The server has no offset: it is asked for `offset + limit` results and the SDK skips
    /// the first `offset` itself.
    func body(clientId: String) -> [String: Any] {
        var body: [String: Any] = ["clientId": clientId]
        if let documentId = documentId {
            body["documentId"] = documentId
            return body
        }
        if !filters.isEmpty { body["filters"] = filters }
        if let field = orderByField { body["orderBy"] = ["field": field, "direction": orderDirection] }
        if let limit = limit { body["limit"] = limit + max(offset ?? 0, 0) }
        return body
    }
}

/// The answer to POST …/listen.
internal struct ListenAnswer {
    let subscriptionId: String
    let topic: String
    let expiresAt: Date?
    /// Document listener: the document, nil when it does not exist.
    let document: SyncDocument?
    /// Query listener: the current results.
    let documents: [SyncDocument]?

    static func parse(_ data: Data) -> ListenAnswer? {
        guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if json["subscriptionId"] == nil, let wrapped = json["data"] as? [String: Any] { json = wrapped }
        guard let id = json["subscriptionId"] as? String, !id.isEmpty,
              let topic = json["topic"] as? String, !topic.isEmpty else { return nil }
        return ListenAnswer(
            subscriptionId: id,
            topic: topic,
            expiresAt: ListenWire.date(json["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) },
            document: (json["document"] as? [String: Any]).flatMap(ListenWire.document),
            documents: (json["documents"] as? [Any])?.compactMap { ($0 as? [String: Any]).flatMap(ListenWire.document) }
        )
    }
}

/// One event on a listener's private topic.
internal struct ListenEvent {
    enum Kind: String {
        case added, modified, removed, revoked
    }

    let subscriptionId: String?
    let kind: Kind
    let documentId: String?
    let data: [String: Any]?
    let version: Int?
    /// Milliseconds since 1970.
    let updatedAt: TimeInterval?
    let reason: String?

    static func parse(_ payload: String) -> ListenEvent? {
        guard let raw = payload.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let type = json["type"] as? String, let kind = Kind(rawValue: type) else { return nil }
        return ListenEvent(
            subscriptionId: json["subscriptionId"] as? String,
            kind: kind,
            documentId: json["documentId"] as? String,
            data: json["data"] as? [String: Any],
            version: ListenWire.int(json["version"]),
            updatedAt: ListenWire.date(json["updatedAt"]),
            reason: json["reason"] as? String
        )
    }
}

internal enum ListenWire {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// A JSON true / false. `is Bool` also matches the numbers 0 and 1 once they are NSNumbers.
    static func isBool(_ value: Any?) -> Bool {
        guard let n = value as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    /// An ISO time or a millisecond number, as milliseconds since 1970.
    static func date(_ value: Any?) -> TimeInterval? {
        if let s = value as? String {
            if let d = withFraction.date(from: s) ?? plain.date(from: s) { return d.timeIntervalSince1970 * 1000 }
            return nil
        }
        if let n = value as? NSNumber, !isBool(value) { return n.doubleValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if isBool(value) { return nil }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    /// `{ id, data, version, updatedAt }` as a document.
    static func document(_ json: [String: Any]) -> SyncDocument? {
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }
        let updatedAt = date(json["updatedAt"]) ?? Date().timeIntervalSince1970 * 1000
        return SyncDocument(
            id: id,
            data: json["data"] as? [String: Any] ?? [:],
            createdAt: date(json["createdAt"]) ?? updatedAt,
            updatedAt: updatedAt,
            version: int(json["version"]) ?? 1
        )
    }
}

// MARK: - Seams (the API and the realtime connection), so the listener can be tested without either

internal protocol ListenTransport: AnyObject {
    func listen(databaseId: String, collectionId: String, body: [String: Any]) async throws -> ListenAnswer
    func unlisten(databaseId: String, subscriptionId: String) async
    /// The user the next request is sent as (the signed token's user), nil without a token.
    func listenUser() async -> String?
}

internal protocol ListenTopics: AnyObject {
    /// The realtime client id: only that connection may receive a listener's private topic.
    var listenClientId: String { get }
    func subscribeTopic(_ topic: String, callback: @escaping (String) -> Void) -> AnyObject
    func unsubscribeTopic(_ handle: AnyObject)
}

extension ApiClient: ListenTransport {
    func listenUser() async -> String? {
        UserTokenStore.user(of: await userTokens.current())
    }
}

extension MqttManager: ListenTopics {
    var listenClientId: String { clientId }

    func subscribeTopic(_ topic: String, callback: @escaping (String) -> Void) -> AnyObject {
        subscribe(topic: topic, callback: callback)
    }

    func unsubscribeTopic(_ handle: AnyObject) {
        if let handle = handle as? SubscriptionHandle { unsubscribe(handle: handle) }
    }
}

// MARK: - The listener

/// One server-routed listener: its snapshot, the events that keep it current, and what keeps it alive (re-listen
/// before it expires, after the user changes, when the connection comes back). A 404 from the server (an older
/// Sync API) switches to the topic listening of SDK 0.2.x.
internal final class ServerListener {
    enum Phase: Equatable {
        case idle, starting, active, retrying, awaitingUserToken, fallback, ended
    }

    /// How a failed listen request is handled.
    enum Failure {
        /// An older Sync API without listeners: use topic listening.
        case olderBackend
        /// Refused (rules, bad request, invalid key): report it and stop.
        case fatal
        /// Nobody is signed in yet in a project that requires it: wait for a token.
        case awaitUserToken
        /// Offline or a server hiccup: try again.
        case transient
    }

    let spec: ListenSpec
    private let transport: ListenTransport
    private let topics: ListenTopics
    private let callbackQueue: DispatchQueue
    private let onDocuments: (([SyncDocument]) -> Void)?
    private let onDocument: ((SyncDocument?) -> Void)?
    private let onError: ((Error) -> Void)?
    private let fallback: () -> ListenerRegistration
    private let offlineSnapshot: (() -> [SyncDocument]?)?
    private let cacheWriter: ((_ saved: [SyncDocument], _ removed: [String]) -> Void)?
    /// Collection listener (no filters, no limit): a snapshot of a full page is completed from every page.
    private let completeSnapshot: (() async throws -> [SyncDocument])?

    private let lock = NSLock()
    private var _phase: Phase = .idle
    private var generation = 0
    private var subscriptionId: String?
    private var topicHandle: AnyObject?
    private var expiresAt: Date?
    private var listenedUser: String?
    private var docs: [String: SyncDocument] = [:]
    private var order: [String] = []
    private var delivered = false
    private var lastSignature: [String]?
    private var fallbackRegistration: ListenerRegistration?
    private var relistenTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0

    /// Re-listen this long before the listener expires.
    static let relistenLead: TimeInterval = 3600
    private static let retryBaseSeconds: Double = 2
    private static let retryMaxSeconds: Double = 60

    init(
        spec: ListenSpec,
        transport: ListenTransport,
        topics: ListenTopics,
        callbackQueue: DispatchQueue = .main,
        onDocuments: (([SyncDocument]) -> Void)? = nil,
        onDocument: ((SyncDocument?) -> Void)? = nil,
        onError: ((Error) -> Void)?,
        fallback: @escaping () -> ListenerRegistration,
        offlineSnapshot: (() -> [SyncDocument]?)? = nil,
        cacheWriter: ((_ saved: [SyncDocument], _ removed: [String]) -> Void)? = nil,
        completeSnapshot: (() async throws -> [SyncDocument])? = nil
    ) {
        self.spec = spec
        self.transport = transport
        self.topics = topics
        self.callbackQueue = callbackQueue
        self.onDocuments = onDocuments
        self.onDocument = onDocument
        self.onError = onError
        self.fallback = fallback
        self.offlineSnapshot = offlineSnapshot
        self.cacheWriter = cacheWriter
        self.completeSnapshot = completeSnapshot
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var phase: Phase { locked { _phase } }
    var currentSubscriptionId: String? { locked { subscriptionId } }

    // MARK: Lifecycle

    func start() {
        Task { await performStart() }
    }

    /// The app removed the listener: unsubscribe, and tell the server (best effort).
    func stop() {
        let (sub, handle, registration): (String?, AnyObject?, ListenerRegistration?) = locked {
            _phase = .ended
            generation += 1
            relistenTask?.cancel(); relistenTask = nil
            retryTask?.cancel(); retryTask = nil
            defer { subscriptionId = nil; topicHandle = nil; fallbackRegistration = nil }
            return (subscriptionId, topicHandle, fallbackRegistration)
        }
        if let handle = handle { topics.unsubscribeTopic(handle) }
        registration?.remove()
        if let sub = sub {
            let transport = self.transport, databaseId = spec.databaseId
            Task { await transport.unlisten(databaseId: databaseId, subscriptionId: sub) }
        }
    }

    /// The realtime connection is up: a listener that could not start (offline) starts now.
    func connected() {
        let retry: Bool = locked {
            guard _phase == .retrying else { return false }
            retryTask?.cancel(); retryTask = nil
            return true
        }
        if retry { start() }
    }

    /// The app set or cleared its user token: a listener of another user is started again for this one.
    func userMayHaveChanged(_ user: String?) {
        let action: Int = locked {
            switch _phase {
            case .awaitingUserToken, .retrying:
                retryTask?.cancel(); retryTask = nil
                return 1
            case .active:
                return listenedUser != user ? 2 : 0
            default:
                return 0
            }
        }
        if action == 1 { start() }
        if action == 2 { Task { await performRelisten() } }
    }

    // MARK: Start / re-listen

    /// First listen (or a retry of it).
    func performStart() async {
        let mine: Int? = locked {
            guard _phase == .idle || _phase == .retrying || _phase == .awaitingUserToken else { return nil }
            _phase = .starting
            generation += 1
            return generation
        }
        guard let mine = mine else { return }

        do {
            let user = await transport.listenUser()
            var answer = try await transport.listen(
                databaseId: spec.databaseId, collectionId: spec.collectionId,
                body: spec.body(clientId: topics.listenClientId)
            )
            answer = await completed(answer)
            let current: Bool = locked {
                guard generation == mine, _phase == .starting else { return false }
                _phase = .active
                retryAttempt = 0
                subscriptionId = answer.subscriptionId
                expiresAt = answer.expiresAt
                listenedUser = user
                return true
            }
            guard current else {
                // Removed while the request was in flight: end the server side too.
                await transport.unlisten(databaseId: spec.databaseId, subscriptionId: answer.subscriptionId)
                return
            }
            applySnapshot(answer)
            let handle = subscribe(answer.topic)
            let keep: Bool = locked {
                guard generation == mine, _phase == .active else { return false }
                topicHandle = handle
                return true
            }
            guard keep else {
                topics.unsubscribeTopic(handle)
                return
            }
            scheduleRelisten(expiresAt: answer.expiresAt)
        } catch {
            guard locked({ generation == mine && _phase == .starting }) else { return }
            handleStartFailure(error)
        }
    }

    /// Listen again (before expiry, after an `expired` revoke, for another user): new subscription first, then the
    /// old one is stopped. The app hears nothing unless the data changed.
    func performRelisten() async {
        let mine: (Int, String?, AnyObject?)? = locked {
            guard _phase == .active else { return nil }
            generation += 1
            relistenTask?.cancel(); relistenTask = nil
            return (generation, subscriptionId, topicHandle)
        }
        guard let mineValues = mine else { return }
        let (gen, oldSub, oldHandle) = mineValues

        do {
            let user = await transport.listenUser()
            var answer = try await transport.listen(
                databaseId: spec.databaseId, collectionId: spec.collectionId,
                body: spec.body(clientId: topics.listenClientId)
            )
            answer = await completed(answer)
            guard locked({ generation == gen && _phase == .active }) else {
                await transport.unlisten(databaseId: spec.databaseId, subscriptionId: answer.subscriptionId)
                return
            }
            applySnapshot(answer)
            let handle = subscribe(answer.topic)
            let swapped: Bool = locked {
                guard generation == gen, _phase == .active else { return false }
                subscriptionId = answer.subscriptionId
                topicHandle = handle
                expiresAt = answer.expiresAt
                listenedUser = user
                retryAttempt = 0
                return true
            }
            guard swapped else {
                topics.unsubscribeTopic(handle)
                await transport.unlisten(databaseId: spec.databaseId, subscriptionId: answer.subscriptionId)
                return
            }
            if let oldHandle = oldHandle { topics.unsubscribeTopic(oldHandle) }
            if let oldSub = oldSub { await transport.unlisten(databaseId: spec.databaseId, subscriptionId: oldSub) }
            scheduleRelisten(expiresAt: answer.expiresAt)
        } catch {
            guard locked({ generation == gen && _phase == .active }) else { return }
            switch Self.classify(error) {
            case .fatal:
                end(with: error)
            case .olderBackend:
                // The server went back to an older Sync API: drop this subscription, use topic listening.
                let handle: AnyObject? = locked {
                    relistenTask?.cancel(); relistenTask = nil
                    defer { topicHandle = nil; subscriptionId = nil }
                    return topicHandle
                }
                if let handle = handle { topics.unsubscribeTopic(handle) }
                startFallback()
            case .awaitUserToken, .transient:
                // Keep the current subscription while it lasts and try again.
                let delay = nextRetryDelay()
                RiviumSyncLogger.w("Listener: re-listen failed, retrying in \(delay)s: \(error.localizedDescription)")
                locked {
                    relistenTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        await self?.performRelisten()
                    }
                }
            }
        }
    }

    /// A collection listener's snapshot is one page; read every page when it is full.
    private func completed(_ answer: ListenAnswer) async -> ListenAnswer {
        guard let complete = completeSnapshot, let docs = answer.documents, docs.count >= ApiClient.pageSize,
              let all = try? await complete() else { return answer }
        return ListenAnswer(subscriptionId: answer.subscriptionId, topic: answer.topic, expiresAt: answer.expiresAt,
                            document: nil, documents: all)
    }

    private func subscribe(_ topic: String) -> AnyObject {
        topics.subscribeTopic(topic) { [weak self] payload in
            self?.handle(payload: payload)
        }
    }

    static func classify(_ error: Error) -> Failure {
        if HttpStatusError.isStatus(404, error) { return .olderBackend }
        if case RiviumSyncError.queryNotAllowed = error { return .fatal }
        if case RiviumSyncError.permissionError = error { return .fatal }
        if MqttManager.isUserTokenRequired(error) { return .awaitUserToken }
        if case RiviumSyncError.networkError(_, let cause as HttpStatusError) = error,
           (400..<500).contains(cause.status), cause.status != 408, cause.status != 429 {
            return .fatal
        }
        return .transient
    }

    private func handleStartFailure(_ error: Error) {
        switch Self.classify(error) {
        case .olderBackend:
            RiviumSyncLogger.i("Listener: the Sync API has no server-routed listeners; using topic listening")
            startFallback()
        case .fatal:
            RiviumSyncLogger.w("Listener refused: \(error.localizedDescription)")
            end(with: error)
        case .awaitUserToken:
            RiviumSyncLogger.i("Listener: waiting for a user token")
            locked { _phase = .awaitingUserToken }
        case .transient:
            deliverOfflineSnapshot()
            let delay = nextRetryDelay()
            RiviumSyncLogger.w("Listener: could not start, retrying in \(delay)s: \(error.localizedDescription)")
            locked {
                _phase = .retrying
                retryTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    await self?.performStart()
                }
            }
        }
    }

    private func nextRetryDelay() -> Double {
        locked {
            let delay = min(Self.retryBaseSeconds * pow(2, Double(min(retryAttempt, 5))), Self.retryMaxSeconds)
            retryAttempt += 1
            return delay
        }
    }

    private func startFallback() {
        let proceed: Bool = locked {
            guard _phase != .ended, _phase != .fallback else { return false }
            _phase = .fallback
            return true
        }
        guard proceed else { return }
        let registration = fallback()
        let keep = locked { () -> Bool in
            guard _phase == .fallback else { return false }
            fallbackRegistration = registration
            return true
        }
        if !keep { registration.remove() }
    }

    /// Stop for good; report `error` to the app when there is one.
    private func end(with error: Error?) {
        let (handle, sub): (AnyObject?, String?) = locked {
            _phase = .ended
            generation += 1
            relistenTask?.cancel(); relistenTask = nil
            retryTask?.cancel(); retryTask = nil
            defer { topicHandle = nil; subscriptionId = nil }
            return (topicHandle, subscriptionId)
        }
        if let handle = handle { topics.unsubscribeTopic(handle) }
        if let sub = sub, error != nil, !Self.isRevoked(error) {
            let transport = self.transport, databaseId = spec.databaseId
            Task { await transport.unlisten(databaseId: databaseId, subscriptionId: sub) }
        }
        if let error = error, let onError = onError {
            callbackQueue.async { onError(error) }
        }
    }

    private static func isRevoked(_ error: Error?) -> Bool {
        if case RiviumSyncError.listenerRevoked? = error as? RiviumSyncError { return true }
        return false
    }

    /// When to listen again: an hour before expiry, or halfway there when that is sooner.
    static func relistenDelay(expiresAt: Date, now: Date = Date()) -> TimeInterval {
        let remaining = expiresAt.timeIntervalSince(now)
        if remaining > 2 * relistenLead { return remaining - relistenLead }
        return max(remaining / 2, 1)
    }

    private func scheduleRelisten(expiresAt: Date?) {
        guard let expiresAt = expiresAt else { return }
        let delay = Self.relistenDelay(expiresAt: expiresAt)
        locked {
            relistenTask?.cancel()
            relistenTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.performRelisten()
            }
        }
    }

    // MARK: Data

    /// The answer's documents become the kept state; a kept document newer than the answer's copy stays.
    private func applySnapshot(_ answer: ListenAnswer) {
        var saved: [SyncDocument] = []
        var removed: [String] = []
        let output: Output? = locked {
            let incoming: [SyncDocument]
            if let documentId = spec.documentId {
                incoming = answer.document.map { $0.id == documentId ? [$0] : [] } ?? []
            } else {
                incoming = answer.documents ?? []
            }
            var nextDocs: [String: SyncDocument] = [:]
            var nextOrder: [String] = []
            for doc in incoming where nextDocs[doc.id] == nil {
                if let kept = docs[doc.id], kept.version > doc.version {
                    nextDocs[doc.id] = kept
                } else {
                    nextDocs[doc.id] = doc
                    saved.append(doc)
                }
                nextOrder.append(doc.id)
            }
            removed = order.filter { nextDocs[$0] == nil }
            docs = nextDocs
            order = nextOrder
            return outputIfChanged(force: !delivered)
        }
        // Removed = deleted only for a listener that sees its whole scope; a query's results are only a part.
        if !spec.seesWholeScope { removed = [] }
        if !saved.isEmpty || !removed.isEmpty { cacheWriter?(saved, removed) }
        deliver(output)
    }

    /// An event on the private topic.
    func handle(payload: String) {
        guard let event = ListenEvent.parse(payload) else {
            RiviumSyncLogger.w("Listener: ignoring an unreadable event")
            return
        }
        if event.kind == .revoked {
            let current: Bool = locked {
                guard _phase == .active else { return false }
                return event.subscriptionId == nil || event.subscriptionId == subscriptionId
            }
            guard current else { return }
            if event.reason == "permission" {
                end(with: RiviumSyncError.listenerRevoked("This listener was stopped: the security rules no longer allow it."))
            } else {
                Task { await performRelisten() }
            }
            return
        }
        guard let documentId = event.documentId else { return }
        if let only = spec.documentId, only != documentId { return }

        var saved: [SyncDocument] = []
        var removed: [String] = []
        let output: Output? = locked {
            guard _phase == .active else { return nil }
            switch event.kind {
            case .added, .modified:
                guard let data = event.data else { return nil }
                let known = docs[documentId]
                if let known = known, let version = event.version, known.version >= version {
                    return nil // stale: we already have this version or a newer one
                }
                let updatedAt = event.updatedAt ?? Date().timeIntervalSince1970 * 1000
                let doc = SyncDocument(
                    id: documentId,
                    data: data,
                    createdAt: known?.createdAt ?? updatedAt,
                    updatedAt: updatedAt,
                    version: event.version ?? (known?.version ?? 0) + 1
                )
                if known == nil { order.append(documentId) }
                docs[documentId] = doc
                saved.append(doc)
            case .removed:
                guard docs.removeValue(forKey: documentId) != nil || spec.isDocument else { return nil }
                order.removeAll { $0 == documentId }
                removed.append(documentId)
            case .revoked:
                return nil
            }
            return outputIfChanged(force: false)
        }
        if !spec.seesWholeScope { removed = [] }
        if !saved.isEmpty || !removed.isEmpty { cacheWriter?(saved, removed) }
        deliver(output)
    }

    private func deliverOfflineSnapshot() {
        guard let offlineSnapshot = offlineSnapshot, !locked({ delivered }), let cached = offlineSnapshot() else { return }
        let output: Output? = locked {
            guard !delivered else { return nil }
            docs = [:]
            order = []
            for doc in cached where docs[doc.id] == nil {
                docs[doc.id] = doc
                order.append(doc.id)
            }
            let out = outputIfChanged(force: true)
            // Cached data is not the server's: the first server snapshot is always delivered.
            delivered = false
            lastSignature = nil
            return out
        }
        deliver(output)
    }

    // MARK: Output

    enum Output {
        case documents([SyncDocument])
        case document(SyncDocument?)
    }

    /// What the app sees now, unless it is what it saw last time. Call with the lock held.
    private func outputIfChanged(force: Bool) -> Output? {
        let output: Output
        let signature: [String]
        if let documentId = spec.documentId {
            let doc = docs[documentId]
            output = .document(doc)
            signature = [doc.map { "\($0.id)@\($0.version)" } ?? "-"]
        } else {
            let visible = Self.visible(order.compactMap { docs[$0] }, spec: spec)
            output = .documents(visible)
            signature = visible.map { "\($0.id)@\($0.version)" }
        }
        if !force, signature == lastSignature { return nil }
        lastSignature = signature
        delivered = true
        return output
    }

    private func deliver(_ output: Output?) {
        guard let output = output else { return }
        switch output {
        case .documents(let list):
            guard let onDocuments = onDocuments else { return }
            callbackQueue.async { onDocuments(list) }
        case .document(let doc):
            guard let onDocument = onDocument else { return }
            callbackQueue.async { onDocument(doc) }
        }
    }

    /// The query's order, offset and limit applied to every matching document we know.
    static func visible(_ list: [SyncDocument], spec: ListenSpec) -> [SyncDocument] {
        var result = list
        if let field = spec.orderByField {
            let descending = spec.orderDirection == "desc"
            // Stable: equal values keep the server's order.
            result = result.enumerated().sorted { a, b in
                let c = compare(a.element.data[field]?.value, b.element.data[field]?.value)
                if c != 0 { return descending ? c > 0 : c < 0 }
                return a.offset < b.offset
            }.map { $0.element }
        }
        if let offset = spec.offset, offset > 0 { result = Array(result.dropFirst(offset)) }
        if let limit = spec.limit { result = Array(result.prefix(max(limit, 0))) }
        return result
    }

    /// -1, 0 or 1. Missing / null first, then booleans, numbers, strings; other values compare equal.
    static func compare(_ a: Any?, _ b: Any?) -> Int {
        func rank(_ v: Any?) -> Int {
            guard let v = v, !(v is NSNull) else { return 0 }
            if ListenWire.isBool(v) || (v is Bool && !(v is NSNumber)) { return 1 }
            if v is NSNumber { return 2 }
            if v is String { return 3 }
            return 4
        }
        let ra = rank(a), rb = rank(b)
        if ra != rb { return ra < rb ? -1 : 1 }
        switch ra {
        case 1:
            let x = (a as? Bool) ?? false, y = (b as? Bool) ?? false
            return x == y ? 0 : (!x ? -1 : 1)
        case 2:
            let x = (a as! NSNumber).doubleValue, y = (b as! NSNumber).doubleValue
            return x == y ? 0 : (x < y ? -1 : 1)
        case 3:
            let x = a as! String, y = b as! String
            return x == y ? 0 : (x < y ? -1 : 1)
        default:
            return 0
        }
    }
}

// MARK: - Registry

/// Every running server-routed listener, so the connection and the user token can reach them.
internal final class ServerListenerRegistry {
    private let lock = NSLock()
    private var listeners: [ObjectIdentifier: ServerListener] = [:]

    func add(_ listener: ServerListener) {
        lock.lock(); listeners[ObjectIdentifier(listener)] = listener; lock.unlock()
    }

    func remove(_ listener: ServerListener) {
        lock.lock(); listeners.removeValue(forKey: ObjectIdentifier(listener)); lock.unlock()
    }

    var all: [ServerListener] {
        lock.lock(); defer { lock.unlock() }
        return Array(listeners.values)
    }

    func connected() {
        all.forEach { $0.connected() }
    }

    func userMayHaveChanged(_ user: String?) {
        all.forEach { $0.userMayHaveChanged(user) }
    }
}
