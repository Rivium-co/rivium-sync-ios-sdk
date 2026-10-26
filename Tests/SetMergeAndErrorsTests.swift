import XCTest
@testable import RiviumSync

/// Answers requests without a network and keeps what was sent.
final class StubURLProtocol: URLProtocol {
    struct Sent {
        let method: String
        let path: String
        let body: [String: Any]?
    }

    private static let lock = NSLock()
    private static var _sent: [Sent] = []
    private static var _respond: (URLRequest) -> (Int, Any) = { _ in (200, ["data": [:]]) }

    static var sent: [Sent] { lock.lock(); defer { lock.unlock() }; return _sent }

    static func reset(_ respond: @escaping (URLRequest) -> (Int, Any)) {
        lock.lock(); _sent = []; _respond = respond; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(buffer, maxLength: 4096)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            buffer.deallocate()
            stream.close()
            bodyData = data
        }
        let body = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        Self.lock.lock()
        Self._sent.append(Sent(method: request.httpMethod ?? "GET", path: request.url?.path ?? "", body: body))
        let respond = Self._respond
        Self.lock.unlock()

        let (status, json) = respond(request)
        let data = json is NSNull ? Data() : ((try? JSONSerialization.data(withJSONObject: json)) ?? Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// `set()` replaces unless `merge: true`, in single writes, batches and the offline queue; the server's
/// `query_not_allowed` and the listen refusals are typed errors.
final class SetMergeAndErrorsTests: XCTestCase {

    private let config = RiviumSyncConfigBuilder(apiKey: "rv_live_test").build()
    private lazy var api = ApiClient(config: config, protocolClasses: [StubURLProtocol.self])

    private static let documentJSON: [String: Any] = [
        "data": ["id": "d1", "data": ["a": 1], "createdAt": "2026-10-26T10:00:00.000Z", "updatedAt": "2026-10-26T10:00:00.000Z", "version": 2],
    ]

    // MARK: - set()

    func testSetSendsMergeFalseByDefaultAndTrueWhenAsked() async throws {
        StubURLProtocol.reset { _ in (200, Self.documentJSON) }
        let collection = SyncCollectionImpl(id: "todos", name: "todos", databaseId: "app", apiClient: api,
                                            mqttManager: MqttManager(config: config, apiClient: api))

        _ = try await collection.set(documentId: "d1", data: ["a": 1])
        _ = try await collection.set(documentId: "d1", data: ["a": 1], merge: true)
        let asProtocol: SyncCollection = collection
        _ = try await asProtocol.set(documentId: "d1", data: ["a": 1])
        _ = try await asProtocol.set(documentId: "d1", data: ["a": 1], merge: true)

        let sent = StubURLProtocol.sent
        XCTAssertEqual(sent.map { $0.method }, ["PUT", "PUT", "PUT", "PUT"])
        XCTAssertEqual(sent.first?.path, "/databases/app/collections/todos/documents/sdk/d1")
        XCTAssertEqual(sent.map { $0.body?["merge"] as? Bool }, [false, true, false, true])
        XCTAssertEqual((sent.first?.body?["data"] as? [String: Any])?["a"] as? Int, 1)
    }

    func testBatchSetCarriesTheMergeFlag() {
        let collection = SyncCollectionImpl(id: "todos", name: "todos", databaseId: "app", apiClient: api,
                                            mqttManager: MqttManager(config: config, apiClient: api))
        let batch = WriteBatch(apiClient: api)
        batch.set(collection, documentId: "a", data: ["x": 1])
        batch.set(collection, documentId: "b", data: ["x": 1], merge: true)
        batch.update(collection, documentId: "c", data: ["x": 1])

        let ops = batch.operationDicts
        XCTAssertEqual(ops[0]["type"] as? String, "set")
        XCTAssertEqual(ops[0]["merge"] as? Bool, false)
        XCTAssertEqual(ops[1]["merge"] as? Bool, true)
        XCTAssertNil(ops[2]["merge"], "update has no merge flag: it always merges")
    }

    func testBatchCommitSendsTheFlag() async throws {
        StubURLProtocol.reset { _ in (200, ["data": [:]]) }
        let collection = SyncCollectionImpl(id: "todos", name: "todos", databaseId: "app", apiClient: api,
                                            mqttManager: MqttManager(config: config, apiClient: api))
        let batch = WriteBatch(apiClient: api)
        batch.set(collection, documentId: "a", data: ["x": 1], merge: true)
        try await batch.commit()
        let op = (StubURLProtocol.sent.first?.body?["operations"] as? [[String: Any]])?.first
        XCTAssertEqual(StubURLProtocol.sent.first?.path, "/batch/sdk")
        XCTAssertEqual(op?["merge"] as? Bool, true)
    }

    // MARK: - Offline queue

    private final class RecordingApiClient: ApiClient {
        private(set) var calls: [String] = []

        init() { super.init(config: RiviumSyncConfigBuilder(apiKey: "rv_live_test").build()) }

        override func addDocument(databaseId: String, collectionId: String, data: [String: Any]) async throws -> SyncDocument {
            calls.append("add:\(collectionId)")
            return SyncDocument(id: "server-1", data: data)
        }

        override func getDocument(databaseId: String, collectionId: String, documentId: String) async throws -> SyncDocument? {
            calls.append("get")
            return SyncDocument(id: documentId, data: [:], version: 1)
        }

        override func setDocument(databaseId: String, collectionId: String, documentId: String, data: [String: Any], merge: Bool) async throws -> SyncDocument {
            calls.append("set:\(documentId):merge=\(merge)")
            return SyncDocument(id: documentId, data: data, version: 2)
        }

        override func updateDocument(databaseId: String, collectionId: String, documentId: String, data: [String: Any]) async throws -> SyncDocument {
            calls.append("update:\(documentId)")
            return SyncDocument(id: documentId, data: data, version: 2)
        }
    }

    private func waitForSync(_ engine: SyncEngine) async {
        let end = Date().addingTimeInterval(3)
        while Date() < end {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if engine.syncState == .idle { break }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func testAQueuedSetKeepsItsMergeFlagAndIsSentWithIt() async throws {
        let api = RecordingApiClient()
        let store = LocalStorageManager()
        let engine = SyncEngine(apiClient: api, localStore: store)
        let collectionId = "col-\(UUID().uuidString)"
        let collection = SyncCollectionImpl(id: collectionId, name: "col", databaseId: "db", apiClient: api,
                                            mqttManager: MqttManager(config: config, apiClient: api),
                                            localStorageManager: store, syncEngine: engine)
        engine.onConnectionStateChanged(connected: false)

        let replaced = "r-\(UUID().uuidString)", merged = "m-\(UUID().uuidString)"
        store.saveDocument(document: SyncDocument(id: merged, data: ["keep": true], version: 1), databaseId: "db", collectionId: collectionId, syncStatus: .synced)
        _ = try await collection.set(documentId: replaced, data: ["a": 1])
        let local = try await collection.set(documentId: merged, data: ["b": 2], merge: true)

        XCTAssertEqual(local.getBool("keep"), true, "the local copy shows the merged document")
        XCTAssertEqual(local.getInt("b"), 2)

        let pending = store.getPendingDocuments()
        XCTAssertEqual(pending.first { $0.id == replaced }?.setMerge, false)
        XCTAssertEqual(pending.first { $0.id == merged }?.setMerge, true)

        // Survives being written to disk.
        let roundTripped = try JSONDecoder().decode(CachedDocument.self, from: JSONEncoder().encode(pending.first { $0.id == merged }!))
        XCTAssertEqual(roundTripped.setMerge, true)

        engine.onConnectionStateChanged(connected: true)
        await waitForSync(engine)
        XCTAssertTrue(api.calls.contains("set:\(replaced):merge=false"), "\(api.calls)")
        XCTAssertTrue(api.calls.contains("set:\(merged):merge=true"), "\(api.calls)")
        XCTAssertFalse(api.calls.contains("add:\(collectionId)"), "a queued set keeps its id: \(api.calls)")

        store.deleteDocument(documentId: replaced)
        store.deleteDocument(documentId: merged)
    }

    func testAWriteQueuedByAnOlderSdkIsSentAsBefore() async throws {
        // A queued update stored by 0.2.x: no setMerge key.
        let id = "old-\(UUID().uuidString)"
        let json: [String: Any] = [
            "id": id, "databaseId": "db", "collectionId": "col", "data": ["a": 1], "createdAt": 1, "updatedAt": 1,
            "version": 2, "syncStatus": "pending_update", "baseVersion": 1, "retryCount": 0, "localUpdatedAt": 1,
        ]
        let cached = try JSONDecoder().decode(CachedDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(cached.setMerge)

        let api = RecordingApiClient()
        let store = LocalStorageManager()
        let engine = SyncEngine(apiClient: api, localStore: store)
        store.saveDocument(document: cached.toSyncDocument(), databaseId: "db", collectionId: "col", syncStatus: .pendingUpdate, baseVersion: 1)
        engine.onConnectionStateChanged(connected: true)
        await waitForSync(engine)
        XCTAssertTrue(api.calls.contains("update:\(id)"), "\(api.calls)")
        store.deleteDocument(documentId: id)
    }

    // MARK: - Typed errors

    func testQueryNotAllowedIsTypedWithFields() async {
        StubURLProtocol.reset { _ in
            (403, ["statusCode": 403, "code": "query_not_allowed", "message": "This query is not allowed by the security rules. Filter on 'teamId'.", "fields": ["teamId"]])
        }
        let query = SyncQueryImpl(databaseId: "app", collectionId: "team_members", apiClient: api,
                                  mqttManager: MqttManager(config: config, apiClient: api))
        do {
            _ = try await query.where("status", .equal, "open").get()
            XCTFail("expected queryNotAllowed")
        } catch let error as RiviumSyncError {
            guard case .queryNotAllowed(let message, let fields) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("teamId"))
            XCTAssertEqual(fields, ["teamId"])
            XCTAssertEqual(error.code, "query_not_allowed")
            XCTAssertEqual(error.fields, ["teamId"])
        } catch {
            XCTFail("\(error)")
        }
    }

    func testQueryNotAllowedWithoutFields() {
        let body = try! JSONSerialization.data(withJSONObject: ["code": "query_not_allowed", "message": "no"])
        let error = ApiClient.error(status: 403, body: body)
        XCTAssertEqual(error.code, "query_not_allowed")
        XCTAssertEqual(error.fields, [])
        // Another 403 stays what it was.
        let other = ApiClient.error(status: 403, body: try! JSONSerialization.data(withJSONObject: ["message": "denied"]))
        XCTAssertNil(other.code)
        XCTAssertTrue(HttpStatusError.isStatus(403, other))
    }

    func testQueryGetCallbackReceivesTheTypedError() {
        StubURLProtocol.reset { _ in (403, ["code": "query_not_allowed", "message": "no", "fields": ["ownerId"]]) }
        let query = SyncQueryImpl(databaseId: "app", collectionId: "posts", apiClient: api,
                                  mqttManager: MqttManager(config: config, apiClient: api))
        let done = expectation(description: "onError")
        query.get(onSuccess: { _ in XCTFail("expected an error") }, onError: { error in
            XCTAssertEqual((error as? RiviumSyncError)?.fields, ["ownerId"])
            done.fulfill()
        })
        wait(for: [done], timeout: 5)
    }

    // MARK: - Listen requests

    func testListenRequestAndAnswer() async throws {
        StubURLProtocol.reset { _ in
            (200, ["subscriptionId": "s1", "topic": "rivium_sync/p/s/s1", "expiresAt": "2026-10-27T10:00:00.000Z", "document": NSNull()])
        }
        let answer = try await api.listen(databaseId: "app", collectionId: "todos", body: ["clientId": "c1", "documentId": "d1"])
        XCTAssertEqual(answer.subscriptionId, "s1")
        XCTAssertNil(answer.document)
        let sent = StubURLProtocol.sent.first
        XCTAssertEqual(sent?.method, "POST")
        XCTAssertEqual(sent?.path, "/databases/app/collections/todos/listen")
        XCTAssertEqual(sent?.body?["clientId"] as? String, "c1")

        StubURLProtocol.reset { _ in (200, ["data": ["success": true]]) }
        await api.unlisten(databaseId: "app", subscriptionId: "s1")
        XCTAssertEqual(StubURLProtocol.sent.first?.method, "DELETE")
        XCTAssertEqual(StubURLProtocol.sent.first?.path, "/databases/app/listen/s1")
    }

    func testListenRefusalsAreTyped() async {
        StubURLProtocol.reset { _ in (403, ["statusCode": 403, "message": "Read permission denied by security rules"]) }
        do {
            _ = try await api.listen(databaseId: "app", collectionId: "todos", body: ["clientId": "c1"])
            XCTFail("expected an error")
        } catch {
            guard case RiviumSyncError.permissionError(let message) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(message, "Read permission denied by security rules")
            XCTAssertEqual(ServerListener.classify(error), .fatal)
        }

        StubURLProtocol.reset { _ in (403, ["code": "query_not_allowed", "message": "no", "fields": ["teamId"]]) }
        do {
            _ = try await api.listen(databaseId: "app", collectionId: "todos", body: ["clientId": "c1"])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? RiviumSyncError)?.fields, ["teamId"])
        }

        StubURLProtocol.reset { _ in (404, ["statusCode": 404, "message": "Cannot POST /databases/app/collections/todos/listen"]) }
        do {
            _ = try await api.listen(databaseId: "app", collectionId: "todos", body: ["clientId": "c1"])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(ServerListener.classify(error), .olderBackend)
        }
    }

    /// Through the public API: a 404 from an older Sync API switches to topic listening, and a document listener then
    /// listens to its own document's topic, not the whole collection.
    func testDocumentListenerOnAnOlderBackendUsesTheDocumentTopic() async throws {
        StubURLProtocol.reset { request in
            if request.url?.path.hasSuffix("/listen") == true { return (404, ["statusCode": 404, "message": "Cannot POST"]) }
            return (200, Self.documentJSON)
        }
        let manager = MqttManager(config: config, apiClient: api)
        let collection = SyncCollectionImpl(id: "todos", name: "todos", databaseId: "app", apiClient: api, mqttManager: manager)

        let got = expectation(description: "initial document")
        let registration = collection.listenDocument(documentId: "d1") { doc in
            XCTAssertEqual(doc?.id, "d1")
            got.fulfill()
        }
        await fulfillment(of: [got], timeout: 5)

        let topics = manager.subscribedTopics
        XCTAssertEqual(topics, ["rivium_sync/unknown/app/todos/d1"])
        XCTAssertFalse(topics.contains { $0.hasSuffix("/changes") })
        registration.remove()
        XCTAssertEqual(manager.subscribedTopics, [])
    }

    func testListenersAreStartedAgainForANewUser() async throws {
        StubURLProtocol.reset { request in
            if request.url?.path.hasSuffix("/listen") == true {
                return (200, ["subscriptionId": UUID().uuidString, "topic": "rivium_sync/p/s/\(UUID().uuidString)", "expiresAt": "2099-01-01T00:00:00.000Z", "document": NSNull()])
            }
            return (200, ["data": ["success": true]])
        }
        let manager = MqttManager(config: config, apiClient: api)
        let collection = SyncCollectionImpl(id: "todos", name: "todos", databaseId: "app", apiClient: api, mqttManager: manager)
        let first = expectation(description: "snapshot")
        let registration = collection.listenDocument(documentId: "d1") { _ in first.fulfill() }
        await fulfillment(of: [first], timeout: 5)
        let listens = { StubURLProtocol.sent.filter { $0.path.hasSuffix("/listen") }.count }
        XCTAssertEqual(listens(), 1)

        api.userTokens.set(Self.token(for: "bob"))
        let end = Date().addingTimeInterval(3)
        while listens() < 2 && Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(listens(), 2, "a new user listens again")
        registration.remove()
    }

    private static func token(for user: String) -> String {
        let payload: [String: Any] = ["sub": user, "exp": Date().timeIntervalSince1970 + 3600]
        let body = try! JSONSerialization.data(withJSONObject: payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "h.\(body).s"
    }
}
