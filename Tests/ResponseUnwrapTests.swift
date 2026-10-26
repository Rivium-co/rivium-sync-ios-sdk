import XCTest
@testable import RiviumSync

/// The Sync API answers SDK routes as `{ "data": … }`; every call unwraps it and still accepts the bare value.
final class ResponseUnwrapTests: XCTestCase {

    private let api = ApiClient(config: RiviumSyncConfigBuilder(apiKey: "rv_live_test").build(),
                                protocolClasses: [StubURLProtocol.self])

    private static let doc: [String: Any] = [
        "id": "d1", "data": ["title": "a", "data": ["nested": true]],
        "createdAt": "2026-10-26T10:00:00.000Z", "updatedAt": "2026-10-26T10:00:00.000Z", "version": 3,
    ]

    private func both(_ value: Any, extra: [String: Any] = [:], _ check: () async throws -> Void) async throws {
        var wrapped = extra
        wrapped["data"] = value
        for (name, body) in [("wrapped", wrapped as Any), ("bare", value)] {
            StubURLProtocol.reset { _ in (200, body) }
            do { try await check() } catch { XCTFail("\(name): \(error)") }
        }
    }

    func testSingleDocumentRoutes() async throws {
        try await both(Self.doc) {
            let got = try await api.getDocument(databaseId: "app", collectionId: "todos", documentId: "d1")
            XCTAssertEqual(got?.id, "d1")
            XCTAssertEqual(got?.version, 3)
            XCTAssertEqual(got?.getString("title"), "a")
            let added = try await api.addDocument(databaseId: "app", collectionId: "todos", data: [:])
            let set = try await api.setDocument(databaseId: "app", collectionId: "todos", documentId: "d1", data: [:], merge: false)
            let updated = try await api.updateDocument(databaseId: "app", collectionId: "todos", documentId: "d1", data: [:])
            XCTAssertEqual([added.id, set.id, updated.id], ["d1", "d1", "d1"])
            XCTAssertEqual(added.getDictionary("data")?["nested"] as? Bool, true, "a document's own `data` field stays")
        }
    }

    func testGetOfAMissingDocumentIsNil() async throws {
        StubURLProtocol.reset { _ in (200, ["data": NSNull()]) }
        let got = try await api.getDocument(databaseId: "app", collectionId: "todos", documentId: "d1")
        XCTAssertNil(got)
    }

    func testListRoutes() async throws {
        try await both([Self.doc], extra: ["total": 1]) {
            let page = try await api.fetchPage(databaseId: "app", collectionId: "todos", skip: 0, limit: 100)
            XCTAssertEqual(page.documents.map { $0.id }, ["d1"])
            let all = try await api.getAllDocuments(databaseId: "app", collectionId: "todos")
            XCTAssertEqual(all.map { $0.id }, ["d1"])
            let queried = try await api.queryDocuments(databaseId: "app", collectionId: "todos", query: QueryParams())
            XCTAssertEqual(queried.map { $0.id }, ["d1"])
        }
        StubURLProtocol.reset { _ in (200, ["data": [Self.doc], "total": 1]) }
        let page = try await api.fetchPage(databaseId: "app", collectionId: "todos", skip: 0, limit: 100)
        XCTAssertEqual(page.total, 1)
    }

    func testRealtimeToken() async throws {
        try await both(["token": "jwt", "projectId": "p1", "mqtt": ["host": "mqtt-sync.rivium.co", "port": 8885, "useTls": true]]) {
            let token = try await api.fetchMqttToken()
            XCTAssertEqual(token.token, "jwt")
            XCTAssertEqual(token.projectId, "p1")
            XCTAssertEqual(token.mqtt?.port, 8885)
        }
    }

    func testWritesWithoutAValueAcceptAnyAnswer() async throws {
        for body: Any in [["data": ["success": true]], ["success": true, "operationCount": 1], NSNull()] {
            StubURLProtocol.reset { _ in (200, body) }
            try await api.deleteDocument(databaseId: "app", collectionId: "todos", documentId: "d1")
            try await api.executeBatch(operations: [])
        }
    }

    func testListenAnswerWrappedAndBare() async throws {
        let answer: [String: Any] = ["subscriptionId": "s1", "topic": "rivium_sync/p/s/s1", "expiresAt": "2026-10-27T10:00:00.000Z", "document": Self.doc]
        try await both(answer) {
            let got = try await api.listen(databaseId: "app", collectionId: "todos", body: ["clientId": "c"])
            XCTAssertEqual(got.subscriptionId, "s1")
            XCTAssertEqual(got.document?.version, 3)
        }
    }

    func testABareDocumentWithItsOwnDataFieldIsNotUnwrapped() {
        let body = try! JSONSerialization.data(withJSONObject: Self.doc)
        XCTAssertEqual((ApiClient.unwrap(body, bareKey: "id") as? [String: Any])?["id"] as? String, "d1")
        let wrapped = try! JSONSerialization.data(withJSONObject: ["data": Self.doc])
        XCTAssertEqual((ApiClient.unwrap(wrapped, bareKey: "id") as? [String: Any])?["id"] as? String, "d1")
    }
}
