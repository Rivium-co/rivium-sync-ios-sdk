import XCTest
@testable import RiviumSync

/// The offline cache hides only failures where the server could not answer (Firestore). The server's final answer -
/// the security rules refused it, invalid data - reaches the app, is never queued, and a queued write that gets it is
/// rolled back instead of staying in the cache for ever.
///
/// Found 2026-10-26 on the local stack (Android, same code here): a create refused by the owner-only rules was queued
/// as an offline write, kept as syncFailed and then returned by every read; a refused query (query_not_allowed)
/// quietly answered from the cache.
final class RejectedWritesTests: XCTestCase {
    private let config = RiviumSyncConfigBuilder(apiKey: "rv_live_test").build()
    private lazy var api = ApiClient(config: config, protocolClasses: [StubURLProtocol.self])

    private static let refused: (Int, Any) = (403, ["statusCode": 403, "message": "Write permission denied by security rules"])
    private static let unavailable: (Int, Any) = (503, ["statusCode": 503, "message": "Service unavailable"])

    private final class Rejections: SyncEngine.SyncListener {
        var seen: [(String, OperationType)] = []
        func onDocumentRejected(documentId: String, operation: OperationType, error: Error) {
            seen.append((documentId, operation))
        }
    }

    private struct Setup {
        let collection: SyncCollectionImpl
        let engine: SyncEngine
        let store: LocalStorageManager
        let collectionId: String
        let rejections = Rejections()
    }

    private func makeSetup() -> Setup {
        let store = LocalStorageManager()
        let engine = SyncEngine(apiClient: api, localStore: store)
        let collectionId = "col-\(UUID().uuidString)"
        let collection = SyncCollectionImpl(id: collectionId, name: "col", databaseId: "db", apiClient: api,
                                            mqttManager: MqttManager(config: config, apiClient: api),
                                            localStorageManager: store, syncEngine: engine)
        let setup = Setup(collection: collection, engine: engine, store: store, collectionId: collectionId)
        engine.addSyncListener(setup.rejections)
        return setup
    }

    private func pending(_ setup: Setup) -> [CachedDocument] {
        setup.store.getPendingDocuments().filter { $0.collectionId == setup.collectionId }
    }

    private func waitForSync(_ engine: SyncEngine) async {
        let end = Date().addingTimeInterval(3)
        while Date() < end {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if engine.syncState == .idle { break }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    private func serverDoc(_ id: String) -> [String: Any] {
        ["data": ["id": id, "data": ["userId": "u1", "title": "server"], "version": 2,
                  "createdAt": "2026-10-26T10:00:00.000Z", "updatedAt": "2026-10-26T10:00:00.000Z"]]
    }

    // MARK: - Which failures count as "could not answer"

    func testOnlyNoAnswer401_408_429And5xxAreTransient() {
        func status(_ code: Int) -> Error { ApiClient.error(status: code, body: Data("{\"message\":\"x\"}".utf8)) }
        XCTAssertTrue(SyncErrors.isTransient(URLError(.notConnectedToInternet)))
        XCTAssertTrue(SyncErrors.isTransient(URLError(.timedOut)))
        XCTAssertTrue(SyncErrors.isTransient(ApiClient.error(status: 401, body: Data("{\"code\":\"token_required\"}".utf8))))
        for code in [401, 408, 429, 500, 502, 503] { XCTAssertTrue(SyncErrors.isTransient(status(code)), "\(code)") }
        for code in [400, 403, 404, 409, 413, 422] { XCTAssertFalse(SyncErrors.isTransient(status(code)), "\(code)") }
        XCTAssertFalse(SyncErrors.isTransient(RiviumSyncError.queryNotAllowed("x", fields: ["userId"])))
        XCTAssertFalse(SyncErrors.isTransient(RiviumSyncError.invalidResponse("bad answer")))
    }

    // MARK: - Writes made online

    func testAWriteTheRulesRefuseIsThrownAndNeverQueued() async {
        StubURLProtocol.reset { _ in Self.refused }
        let setup = makeSetup()
        let c = setup.collection

        do { _ = try await c.add(data: ["title": "x"]); XCTFail("add") } catch { XCTAssertEqual(SyncErrors.httpStatus(error), 403) }
        do { _ = try await c.update(documentId: "d1", data: ["title": "x"]); XCTFail("update") } catch { XCTAssertEqual(SyncErrors.httpStatus(error), 403) }
        do { _ = try await c.set(documentId: "d1", data: ["title": "x"]); XCTFail("set") } catch { XCTAssertEqual(SyncErrors.httpStatus(error), 403) }
        do { try await c.delete(documentId: "d1"); XCTFail("delete") } catch { XCTAssertEqual(SyncErrors.httpStatus(error), 403) }

        XCTAssertTrue(pending(setup).isEmpty, "nothing queued: \(pending(setup).map(\.id))")
    }

    func testAWriteThatGets5xxIsStillQueued() async throws {
        StubURLProtocol.reset { _ in Self.unavailable }
        let setup = makeSetup()

        let local = try await setup.collection.add(data: ["title": "x"])

        XCTAssertTrue(local.id.hasPrefix("local_"))
        XCTAssertEqual(pending(setup).map(\.id), [local.id])
        setup.store.deleteDocument(documentId: local.id)
    }

    func testDeletingADocumentThatIsAlreadyGoneIsADelete() async throws {
        StubURLProtocol.reset { _ in (404, ["statusCode": 404, "message": "Document with ID d1 not found"]) }
        let setup = makeSetup()

        try await setup.collection.delete(documentId: "gone-\(UUID().uuidString)")

        XCTAssertTrue(pending(setup).isEmpty)
    }

    func testARefusedBatchCarriesTheServersStatus() async {
        StubURLProtocol.reset { _ in Self.refused }
        let setup = makeSetup()
        let batch = WriteBatch(apiClient: api)
        batch.create(setup.collection, data: ["title": "not mine"])

        do {
            try await batch.commit()
            XCTFail("expected the batch to be refused")
        } catch {
            guard case RiviumSyncError.batchWriteError = error else { return XCTFail("\(error)") }
            XCTAssertEqual((error as? RiviumSyncError)?.statusCode, 403)
        }
    }

    // MARK: - Reads

    func testARefusedListIsThrownNotAnsweredFromTheCache() async {
        StubURLProtocol.reset { _ in (403, ["statusCode": 403, "code": "query_not_allowed", "message": "Filter on 'userId'", "fields": ["userId"]]) }
        let setup = makeSetup()
        let id = "c-\(UUID().uuidString)"
        setup.store.saveDocument(document: SyncDocument(id: id, data: ["title": "cached"]), databaseId: "db", collectionId: setup.collectionId, syncStatus: .synced)

        do {
            let docs = try await setup.collection.getAll()
            XCTFail("expected query_not_allowed, got \(docs.count) cached documents")
        } catch RiviumSyncError.queryNotAllowed(_, let fields) {
            XCTAssertEqual(fields, ["userId"])
        } catch {
            XCTFail("\(error)")
        }
        setup.store.deleteDocument(documentId: id)
    }

    func testAListWithNoAnswerStillComesFromTheCache() async throws {
        StubURLProtocol.reset { _ in Self.unavailable }
        let setup = makeSetup()
        let id = "c-\(UUID().uuidString)"
        setup.store.saveDocument(document: SyncDocument(id: id, data: ["title": "cached"]), databaseId: "db", collectionId: setup.collectionId, syncStatus: .synced)

        let docs = try await setup.collection.getAll()

        XCTAssertEqual(docs.map(\.id), [id])
        setup.store.deleteDocument(documentId: id)
    }

    func testARefusedGetIsThrownEvenWhenTheDocumentIsCached() async {
        StubURLProtocol.reset { _ in (403, ["statusCode": 403, "message": "Read permission denied by security rules"]) }
        let setup = makeSetup()
        let id = "c-\(UUID().uuidString)"
        setup.store.saveDocument(document: SyncDocument(id: id, data: ["title": "cached"]), databaseId: "db", collectionId: setup.collectionId, syncStatus: .synced)

        do {
            _ = try await setup.collection.get(documentId: id)
            XCTFail("expected 403")
        } catch {
            XCTAssertEqual(SyncErrors.httpStatus(error), 403)
        }
        setup.store.deleteDocument(documentId: id)
    }

    // MARK: - Queued writes the server refuses

    func testAQueuedCreateTheRulesRefuseDisappearsAndIsReported() async throws {
        StubURLProtocol.reset { _ in Self.refused }
        let setup = makeSetup()
        setup.engine.onConnectionStateChanged(connected: false)
        let local = try await setup.collection.add(data: ["title": "not mine"])
        XCTAssertEqual(pending(setup).map(\.id), [local.id])

        setup.engine.onConnectionStateChanged(connected: true)
        await waitForSync(setup.engine)

        XCTAssertTrue(pending(setup).isEmpty, "rolled back, not kept as syncFailed")
        XCTAssertNil(setup.store.getDocument(documentId: local.id), "the refused document is gone from the cache")
        // The device's store is shared: other tests' queued writes may be replayed too.
        XCTAssertEqual(setup.rejections.seen.filter { $0.0 == local.id }.map(\.1), [.create])
    }

    func testAQueuedUpdateTheRulesRefuseShowsTheServersDocumentAgain() async throws {
        let id = "d-\(UUID().uuidString)"
        StubURLProtocol.reset { request in
            request.httpMethod == "GET" ? (200, self.serverDoc(id)) : Self.refused
        }
        let setup = makeSetup()
        setup.store.saveDocument(document: SyncDocument(id: id, data: ["userId": "u1", "title": "server"], version: 2),
                                 databaseId: "db", collectionId: setup.collectionId, syncStatus: .synced)
        setup.engine.onConnectionStateChanged(connected: false)
        _ = try await setup.collection.update(documentId: id, data: ["title": "mine"])

        setup.engine.onConnectionStateChanged(connected: true)
        await waitForSync(setup.engine)

        XCTAssertTrue(pending(setup).isEmpty)
        XCTAssertEqual(setup.store.getDocument(documentId: id)?.getString("title"), "server")
        XCTAssertEqual(setup.rejections.seen.filter { $0.0 == id }.map(\.1), [.update])
        setup.store.deleteDocument(documentId: id)
    }

    func testAQueuedDeleteTheRulesRefuseBringsTheDocumentBack() async throws {
        let id = "d-\(UUID().uuidString)"
        StubURLProtocol.reset { request in
            request.httpMethod == "GET" ? (200, self.serverDoc(id)) : Self.refused
        }
        let setup = makeSetup()
        setup.store.saveDocument(document: SyncDocument(id: id, data: ["userId": "u1", "title": "server"], version: 2),
                                 databaseId: "db", collectionId: setup.collectionId, syncStatus: .synced)
        setup.engine.onConnectionStateChanged(connected: false)
        try await setup.collection.delete(documentId: id)

        setup.engine.onConnectionStateChanged(connected: true)
        await waitForSync(setup.engine)

        XCTAssertTrue(pending(setup).isEmpty)
        XCTAssertEqual(setup.store.getDocument(documentId: id)?.getString("title"), "server")
        XCTAssertEqual(setup.rejections.seen.filter { $0.0 == id }.map(\.1), [.delete])
        setup.store.deleteDocument(documentId: id)
    }

    // MARK: - Writes that could not be sent: retried as they are, until they go through

    func testAQueuedDeleteThatGets5xxStaysAQueuedDelete() async throws {
        // It used to become syncFailed and be retried as an update, so the document was never deleted.
        StubURLProtocol.reset { _ in Self.unavailable }
        let setup = makeSetup()
        let id = "d-\(UUID().uuidString)"
        setup.store.saveDocument(document: SyncDocument(id: id, data: ["title": "x"], version: 2), databaseId: "db", collectionId: setup.collectionId, syncStatus: .synced)
        setup.engine.onConnectionStateChanged(connected: false)
        try await setup.collection.delete(documentId: id)

        setup.engine.onConnectionStateChanged(connected: true)
        await waitForSync(setup.engine)

        XCTAssertEqual(pending(setup).first { $0.id == id }?.syncStatus, .pendingDelete)
        StubURLProtocol.reset { _ in (200, ["data": [:]]) }
        setup.engine.forceSync()
        await waitForSync(setup.engine)
        XCTAssertTrue(StubURLProtocol.sent.contains { $0.method == "DELETE" && $0.path.hasSuffix(id) }, "\(StubURLProtocol.sent.map { "\($0.method) \($0.path)" })")
        setup.store.deleteDocument(documentId: id)
    }

    func testAWriteLeftFailedAfterManyAttemptsIsStillSent() async throws {
        let setup = makeSetup()
        let id = "local_\(UUID().uuidString)"
        setup.store.saveDocument(document: SyncDocument(id: id, data: ["title": "x"]), databaseId: "db", collectionId: setup.collectionId, syncStatus: .pendingCreate)
        for _ in 0..<5 { setup.store.updateSyncStatus(documentId: id, status: .syncFailed, error: "Service unavailable") }
        StubURLProtocol.reset { _ in (201, ["data": ["id": "server-1", "data": ["title": "x"], "version": 1]]) }

        setup.engine.onConnectionStateChanged(connected: true)
        await waitForSync(setup.engine)

        XCTAssertTrue(StubURLProtocol.sent.contains { $0.method == "POST" && $0.path.hasSuffix("/documents/sdk") })
        setup.store.deleteDocument(documentId: id)
        setup.store.deleteDocument(documentId: "server-1")
    }

    func testAQueuedWriteThatGets5xxStaysQueued() async throws {
        StubURLProtocol.reset { _ in Self.unavailable }
        let setup = makeSetup()
        setup.engine.onConnectionStateChanged(connected: false)
        let local = try await setup.collection.add(data: ["title": "x"])

        setup.engine.onConnectionStateChanged(connected: true)
        await waitForSync(setup.engine)

        XCTAssertEqual(pending(setup).map(\.id), [local.id])
        XCTAssertTrue(setup.rejections.seen.filter { $0.0 == local.id }.isEmpty)
        setup.store.deleteDocument(documentId: local.id)
    }
}
