import XCTest
@testable import RiviumSync

/// Server-routed listeners: the snapshot from POST …/listen comes first, then events on the private topic keep it
/// current (stale versions dropped), and the listener is kept alive or ended as the server says.
final class ServerListenerTests: XCTestCase {

    // MARK: - Fakes

    final class FakeTransport: ListenTransport {
        private let lock = NSLock()
        private var answers: [Result<ListenAnswer, Error>] = []
        private(set) var bodies: [[String: Any]] = []
        private(set) var unlistened: [String] = []
        var user: String?

        func enqueue(_ result: Result<ListenAnswer, Error>) {
            lock.lock(); answers.append(result); lock.unlock()
        }

        var listenCalls: Int { lock.lock(); defer { lock.unlock() }; return bodies.count }
        var unlistenedIds: [String] { lock.lock(); defer { lock.unlock() }; return unlistened }

        func listen(databaseId: String, collectionId: String, body: [String: Any]) async throws -> ListenAnswer {
            lock.lock()
            bodies.append(body)
            let next = answers.isEmpty ? .failure(URLError(.notConnectedToInternet)) : answers.removeFirst()
            lock.unlock()
            return try next.get()
        }

        func unlisten(databaseId: String, subscriptionId: String) async {
            lock.lock(); unlistened.append(subscriptionId); lock.unlock()
        }

        func listenUser() async -> String? { user }
    }

    final class FakeTopics: ListenTopics {
        final class Handle {
            let topic: String
            let callback: (String) -> Void
            init(topic: String, callback: @escaping (String) -> Void) { self.topic = topic; self.callback = callback }
        }

        private let lock = NSLock()
        private var handles: [Handle] = []
        let listenClientId = "rivium_sync_test1234"

        var topics: [String] { lock.lock(); defer { lock.unlock() }; return handles.map { $0.topic } }

        func subscribeTopic(_ topic: String, callback: @escaping (String) -> Void) -> AnyObject {
            let handle = Handle(topic: topic, callback: callback)
            lock.lock(); handles.append(handle); lock.unlock()
            return handle
        }

        func unsubscribeTopic(_ handle: AnyObject) {
            lock.lock(); handles.removeAll { $0 === handle }; lock.unlock()
        }

        func send(_ topic: String, _ event: [String: Any]) {
            let payload = String(data: try! JSONSerialization.data(withJSONObject: event), encoding: .utf8)!
            lock.lock(); let targets = handles.filter { $0.topic == topic }; lock.unlock()
            targets.forEach { $0.callback(payload) }
        }
    }

    /// Records what the app is told, in order.
    final class Recorder {
        private let lock = NSLock()
        private var _lists: [[SyncDocument]] = []
        private var _docs: [SyncDocument?] = []
        private var _errors: [Error] = []
        var lists: [[SyncDocument]] { lock.lock(); defer { lock.unlock() }; return _lists }
        var docs: [SyncDocument?] { lock.lock(); defer { lock.unlock() }; return _docs }
        var errors: [Error] { lock.lock(); defer { lock.unlock() }; return _errors }
        func list(_ l: [SyncDocument]) { lock.lock(); _lists.append(l); lock.unlock() }
        func doc(_ d: SyncDocument?) { lock.lock(); _docs.append(d); lock.unlock() }
        func error(_ e: Error) { lock.lock(); _errors.append(e); lock.unlock() }
    }

    private struct NoopRegistration: ListenerRegistration {
        let onRemove: () -> Void
        func remove() { onRemove() }
    }

    private let queue = DispatchQueue(label: "test.callbacks")
    private let transport = FakeTransport()
    private let topics = FakeTopics()
    private let recorder = Recorder()
    private var fallbacks = 0
    private var fallbackRemoved = 0

    private func flush() { queue.sync {} }

    private func answer(_ id: String, document: SyncDocument? = nil, documents: [SyncDocument]? = nil,
                        expiresIn: TimeInterval = 24 * 3600) -> ListenAnswer {
        ListenAnswer(subscriptionId: id, topic: "rivium_sync/p1/s/\(id)", expiresAt: Date().addingTimeInterval(expiresIn),
                     document: document, documents: documents)
    }

    private func doc(_ id: String, _ data: [String: Any], v: Int) -> SyncDocument {
        SyncDocument(id: id, data: data, createdAt: 1, updatedAt: 1, version: v)
    }

    private func makeListener(_ spec: ListenSpec) -> ServerListener {
        ServerListener(
            spec: spec, transport: transport, topics: topics, callbackQueue: queue,
            onDocuments: { [recorder] in recorder.list($0) },
            onDocument: { [recorder] in recorder.doc($0) },
            onError: { [recorder] in recorder.error($0) },
            fallback: { [unowned self] in
                self.fallbacks += 1
                return NoopRegistration { self.fallbackRemoved += 1 }
            }
        )
    }

    private func documentSpec() -> ListenSpec { ListenSpec(databaseId: "app", collectionId: "todos", documentId: "d1") }

    private func waitUntil(_ timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    // MARK: - Start

    func testDocumentListenerDeliversTheSnapshotFirstAndSubscribesThePrivateTopic() async {
        transport.enqueue(.success(answer("s1", document: doc("d1", ["title": "a"], v: 3))))
        let listener = makeListener(documentSpec())
        await listener.performStart()
        flush()

        XCTAssertEqual(listener.phase, .active)
        XCTAssertEqual(recorder.docs.count, 1)
        XCTAssertEqual(recorder.docs.first??.getString("title"), "a")
        XCTAssertEqual(topics.topics, ["rivium_sync/p1/s/s1"])

        let body = transport.bodies[0]
        XCTAssertEqual(body["clientId"] as? String, "rivium_sync_test1234")
        XCTAssertEqual(body["documentId"] as? String, "d1")
        XCTAssertNil(body["filters"])
    }

    func testMissingDocumentIsDeliveredAsNil() async {
        transport.enqueue(.success(answer("s1", document: nil)))
        let listener = makeListener(documentSpec())
        await listener.performStart()
        flush()
        XCTAssertEqual(recorder.docs.count, 1)
        XCTAssertNil(recorder.docs[0])
    }

    func testQueryBodyCarriesFiltersOrderAndLimit() {
        var spec = ListenSpec(databaseId: "app", collectionId: "todos", documentId: nil)
        spec.filters = [["field": "teamId", "operator": "==", "value": "T1"]]
        spec.orderByField = "createdAt"
        spec.orderDirection = "desc"
        spec.limit = 50
        let body = spec.body(clientId: "c1")
        XCTAssertEqual(body["clientId"] as? String, "c1")
        XCTAssertNil(body["documentId"])
        XCTAssertEqual((body["filters"] as? [[String: Any]])?.first?["field"] as? String, "teamId")
        XCTAssertEqual((body["orderBy"] as? [String: Any])?["direction"] as? String, "desc")
        XCTAssertEqual(body["limit"] as? Int, 50)

        spec.offset = 10
        XCTAssertEqual(spec.body(clientId: "c1")["limit"] as? Int, 60, "offset is applied by the SDK: ask for offset + limit")
    }

    // MARK: - Events

    func testEventsApplyAndStaleVersionsAreDropped() async {
        transport.enqueue(.success(answer("s1", document: doc("d1", ["title": "a"], v: 3))))
        let listener = makeListener(documentSpec())
        await listener.performStart()
        let topic = "rivium_sync/p1/s/s1"

        // Already in the snapshot (version 3) and older: dropped.
        topics.send(topic, ["subscriptionId": "s1", "type": "modified", "documentId": "d1", "data": ["title": "old"], "version": 3])
        topics.send(topic, ["subscriptionId": "s1", "type": "modified", "documentId": "d1", "data": ["title": "older"], "version": 2])
        // Newer: applied.
        topics.send(topic, ["subscriptionId": "s1", "type": "modified", "documentId": "d1", "data": ["title": "b"], "version": 4,
                            "updatedAt": "2026-10-26T10:00:00.000Z"])
        // Another document's event on a document listener: ignored.
        topics.send(topic, ["subscriptionId": "s1", "type": "modified", "documentId": "other", "data": ["title": "x"], "version": 9])
        topics.send(topic, ["subscriptionId": "s1", "type": "removed", "documentId": "d1", "version": NSNull()])
        flush()

        XCTAssertEqual(recorder.docs.count, 3)
        XCTAssertEqual(recorder.docs[1]?.getString("title"), "b")
        XCTAssertEqual(recorder.docs[1]?.version, 4)
        XCTAssertNil(recorder.docs[2], "removed = the document was deleted")

        // Created again after the delete: applied even with a low version.
        topics.send(topic, ["subscriptionId": "s1", "type": "added", "documentId": "d1", "data": ["title": "new"], "version": 1])
        flush()
        XCTAssertEqual(recorder.docs.last??.getString("title"), "new")
    }

    func testQueryListenerSortsAndTrimsItself() async {
        var spec = ListenSpec(databaseId: "app", collectionId: "todos", documentId: nil)
        spec.orderByField = "n"
        spec.orderDirection = "desc"
        spec.limit = 2
        transport.enqueue(.success(answer("s1", documents: [doc("a", ["n": 3], v: 1), doc("b", ["n": 2], v: 1)])))
        let listener = makeListener(spec)
        await listener.performStart()
        let topic = "rivium_sync/p1/s/s1"

        // Below the top 2: the app sees nothing new.
        topics.send(topic, ["type": "added", "documentId": "c", "data": ["n": 1], "version": 1])
        // A new first.
        topics.send(topic, ["type": "added", "documentId": "d", "data": ["n": 10], "version": 1])
        // b leaves the query; c moves into the top 2.
        topics.send(topic, ["type": "removed", "documentId": "b", "version": NSNull()])
        // a moves down to last.
        topics.send(topic, ["type": "modified", "documentId": "a", "data": ["n": 0], "version": 2])
        flush()

        let ids = recorder.lists.map { $0.map { $0.id } }
        // Only changes the app can see are delivered.
        XCTAssertEqual(ids, [["a", "b"], ["d", "a"], ["d", "c"]])
    }

    func testVisibleOrdersMixedValuesAndAppliesOffset() {
        var spec = ListenSpec(databaseId: "app", collectionId: "todos", documentId: nil)
        spec.orderByField = "k"
        spec.offset = 1
        spec.limit = 2
        let list = [doc("s", ["k": "b"], v: 1), doc("n", ["k": 5], v: 1), doc("none", [:], v: 1), doc("s2", ["k": "a"], v: 1)]
        XCTAssertEqual(ServerListener.visible(list, spec: spec).map { $0.id }, ["n", "s2"])

        // Numbers 0 and 1 from JSON are numbers, not booleans.
        var byN = ListenSpec(databaseId: "app", collectionId: "todos", documentId: nil)
        byN.orderByField = "n"
        let decoded = try! JSONSerialization.jsonObject(with: Data(#"[{"n":1},{"n":0},{"n":0.5},{"n":true}]"#.utf8)) as! [[String: Any]]
        let docs = decoded.enumerated().map { doc("x\($0.offset)", $0.element, v: 1) }
        XCTAssertEqual(ServerListener.visible(docs, spec: byN).map { $0.id }, ["x3", "x1", "x2", "x0"])
    }

    // MARK: - Revoked

    func testRevokedForPermissionStopsAndReportsATypedError() async {
        transport.enqueue(.success(answer("s1", document: doc("d1", [:], v: 1))))
        let listener = makeListener(documentSpec())
        await listener.performStart()

        topics.send("rivium_sync/p1/s/s1", ["subscriptionId": "s1", "type": "revoked", "reason": "permission"])
        flush()

        XCTAssertEqual(listener.phase, .ended)
        XCTAssertEqual(topics.topics, [])
        XCTAssertEqual(transport.listenCalls, 1, "not restarted")
        guard let error = recorder.errors.first as? RiviumSyncError, case .listenerRevoked = error else {
            return XCTFail("expected listenerRevoked, got \(recorder.errors)")
        }
        XCTAssertEqual(error.code, "listener_revoked")
    }

    func testRevokedExpiredListensAgainWithoutADuplicateSnapshot() async {
        transport.enqueue(.success(answer("s1", document: doc("d1", ["t": 1], v: 1))))
        transport.enqueue(.success(answer("s2", document: doc("d1", ["t": 1], v: 1))))
        let listener = makeListener(documentSpec())
        await listener.performStart()

        topics.send("rivium_sync/p1/s/s1", ["subscriptionId": "s1", "type": "revoked", "reason": "expired"])
        await waitUntil { listener.currentSubscriptionId == "s2" && transport.unlistenedIds == ["s1"] }
        flush()

        XCTAssertEqual(transport.listenCalls, 2)
        XCTAssertEqual(topics.topics, ["rivium_sync/p1/s/s2"], "new topic subscribed, old one dropped")
        XCTAssertEqual(transport.unlistenedIds, ["s1"])
        XCTAssertEqual(recorder.docs.count, 1, "same data: the app is not told again")
        XCTAssertTrue(recorder.errors.isEmpty)
        XCTAssertEqual(listener.phase, .active)
    }

    func testRelistenDeliversWhenTheDataChanged() async {
        transport.enqueue(.success(answer("s1", document: doc("d1", ["t": 1], v: 1))))
        transport.enqueue(.success(answer("s2", document: doc("d1", ["t": 2], v: 2))))
        let listener = makeListener(documentSpec())
        await listener.performStart()
        await listener.performRelisten()
        flush()
        XCTAssertEqual(recorder.docs.map { $0?.version }, [1, 2])
    }

    func testRevokedForAnOldSubscriptionIsIgnored() async {
        transport.enqueue(.success(answer("s1", document: doc("d1", [:], v: 1))))
        let listener = makeListener(documentSpec())
        await listener.performStart()
        topics.send("rivium_sync/p1/s/s1", ["subscriptionId": "s0", "type": "revoked", "reason": "permission"])
        flush()
        XCTAssertEqual(listener.phase, .active)
        XCTAssertTrue(recorder.errors.isEmpty)
    }

    // MARK: - Keep alive

    func testRelistenIsDueAnHourBeforeExpiry() {
        let now = Date()
        XCTAssertEqual(ServerListener.relistenDelay(expiresAt: now.addingTimeInterval(24 * 3600), now: now), 23 * 3600, accuracy: 1)
        XCTAssertEqual(ServerListener.relistenDelay(expiresAt: now.addingTimeInterval(1800), now: now), 900, accuracy: 1)
        XCTAssertEqual(ServerListener.relistenDelay(expiresAt: now.addingTimeInterval(-5), now: now), 1, accuracy: 0.1)
    }

    func testANewUserListensAgainTheSameUserDoesNot() async {
        transport.user = "alice"
        transport.enqueue(.success(answer("s1", document: doc("d1", [:], v: 1))))
        let listener = makeListener(documentSpec())
        await listener.performStart()

        listener.userMayHaveChanged("alice")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(transport.listenCalls, 1)

        transport.user = "bob"
        transport.enqueue(.success(answer("s2", document: doc("d1", [:], v: 1))))
        listener.userMayHaveChanged("bob")
        await waitUntil { listener.currentSubscriptionId == "s2" }
        XCTAssertEqual(transport.listenCalls, 2)
        XCTAssertEqual(topics.topics, ["rivium_sync/p1/s/s2"])
    }

    func testWaitsForAUserTokenThenStarts() async {
        transport.enqueue(.failure(RiviumSyncError.networkError("token required", UserTokenRequiredError())))
        let listener = makeListener(documentSpec())
        await listener.performStart()
        XCTAssertEqual(listener.phase, .awaitingUserToken)
        XCTAssertTrue(recorder.errors.isEmpty, "not an error: nobody is signed in yet")

        transport.enqueue(.success(answer("s1", document: doc("d1", [:], v: 1))))
        listener.userMayHaveChanged("alice")
        await waitUntil { listener.phase == .active }
        XCTAssertEqual(listener.phase, .active)
    }

    func testOfflineStartRetriesWhenTheConnectionIsBack() async {
        let cached = doc("d1", ["t": "cached"], v: 1)
        let listener = ServerListener(
            spec: documentSpec(), transport: transport, topics: topics, callbackQueue: queue,
            onDocument: { [recorder] in recorder.doc($0) }, onError: { [recorder] in recorder.error($0) },
            fallback: { NoopRegistration {} }, offlineSnapshot: { [cached] }
        )
        transport.enqueue(.failure(URLError(.notConnectedToInternet)))
        await listener.performStart()
        flush()
        XCTAssertEqual(listener.phase, .retrying)
        XCTAssertEqual(recorder.docs.first??.getString("t"), "cached", "the local copy while offline")
        XCTAssertTrue(recorder.errors.isEmpty)

        transport.enqueue(.success(answer("s1", document: doc("d1", ["t": "cached"], v: 1))))
        listener.connected()
        await waitUntil { listener.phase == .active }
        flush()
        XCTAssertEqual(listener.phase, .active)
        XCTAssertEqual(recorder.docs.count, 2, "the server's snapshot is always delivered after a cached one")
        listener.stop()
    }

    // MARK: - Older backends and refusals

    func testA404FallsBackToTopicListening() async {
        transport.enqueue(.failure(RiviumSyncError.networkError("Cannot POST", HttpStatusError(status: 404, code: nil))))
        let listener = makeListener(documentSpec())
        await listener.performStart()
        XCTAssertEqual(listener.phase, .fallback)
        XCTAssertEqual(fallbacks, 1)
        XCTAssertTrue(recorder.errors.isEmpty)

        listener.stop()
        XCTAssertEqual(fallbackRemoved, 1, "removing the listener stops the topic listening")
    }

    func testA403NeverFallsBack() async {
        transport.enqueue(.failure(RiviumSyncError.permissionError("Read permission denied by security rules")))
        let listener = makeListener(documentSpec())
        await listener.performStart()
        flush()
        XCTAssertEqual(fallbacks, 0)
        XCTAssertEqual(listener.phase, .ended)
        guard case RiviumSyncError.permissionError(let message)? = recorder.errors.first as? RiviumSyncError else {
            return XCTFail("expected permissionError")
        }
        XCTAssertTrue(message.contains("security rules"))
    }

    func testQueryNotAllowedReachesTheErrorCallbackWithFields() async {
        transport.enqueue(.failure(RiviumSyncError.queryNotAllowed("Filter on 'teamId'", fields: ["teamId"])))
        let listener = makeListener(ListenSpec(databaseId: "app", collectionId: "team_members", documentId: nil))
        await listener.performStart()
        flush()
        XCTAssertEqual(fallbacks, 0)
        let error = recorder.errors.first as? RiviumSyncError
        XCTAssertEqual(error?.code, "query_not_allowed")
        XCTAssertEqual(error?.fields, ["teamId"])
        XCTAssertTrue(recorder.lists.isEmpty)
    }

    func testClassification() {
        XCTAssertEqual(ServerListener.classify(RiviumSyncError.networkError("x", HttpStatusError(status: 404, code: nil))), .olderBackend)
        XCTAssertEqual(ServerListener.classify(RiviumSyncError.networkError("x", HttpStatusError(status: 400, code: nil))), .fatal)
        XCTAssertEqual(ServerListener.classify(RiviumSyncError.networkError("x", HttpStatusError(status: 503, code: nil))), .transient)
        XCTAssertEqual(ServerListener.classify(RiviumSyncError.networkError("x", HttpStatusError(status: 429, code: nil))), .transient)
        XCTAssertEqual(ServerListener.classify(URLError(.timedOut)), .transient)
        XCTAssertEqual(ServerListener.classify(RiviumSyncError.permissionError("x")), .fatal)
    }

    // MARK: - Stop

    func testStopTellsTheServerAndUnsubscribes() async {
        transport.enqueue(.success(answer("s1", document: doc("d1", [:], v: 1))))
        let listener = makeListener(documentSpec())
        await listener.performStart()
        listener.stop()
        await waitUntil { transport.unlistenedIds == ["s1"] }
        XCTAssertEqual(transport.unlistenedIds, ["s1"])
        XCTAssertEqual(topics.topics, [])

        topics.send("rivium_sync/p1/s/s1", ["type": "modified", "documentId": "d1", "data": [:], "version": 5])
        flush()
        XCTAssertEqual(recorder.docs.count, 1, "nothing after stop")
    }

    // MARK: - Wire

    func testAnswerParsesPlainAndWrapped() {
        let body: [String: Any] = [
            "subscriptionId": "s1", "topic": "rivium_sync/p/s/s1", "expiresAt": "2026-10-27T10:00:00.000Z",
            "documents": [["id": "a", "data": ["n": 1], "version": 2, "updatedAt": "2026-10-26T10:00:00.000Z"]],
        ]
        for json in [body, ["data": body]] {
            let answer = ListenAnswer.parse(try! JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(answer?.subscriptionId, "s1")
            XCTAssertEqual(answer?.documents?.first?.version, 2)
            XCTAssertEqual(answer?.documents?.first?.getInt("n"), 1)
            XCTAssertNotNil(answer?.expiresAt)
        }
        XCTAssertNil(ListenAnswer.parse(Data("{}".utf8)))
    }
}
