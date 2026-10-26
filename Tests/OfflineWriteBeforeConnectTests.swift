import XCTest
@testable import RiviumSync

/// With offline persistence on, a write made before the realtime connection has reported anything (the app has not
/// called connect() yet, or it is still connecting) must go to the server - like Firestore, and like reads already do
/// (`isKnownOffline`). Only a connection that has REPORTED offline queues the write locally.
///
/// Before the fix add/set/update/delete read `isOnline`, which starts false, so every such write was queued and never
/// sent unless the app connected.
final class OfflineWriteBeforeConnectTests: XCTestCase {

    private final class RecordingApiClient: ApiClient {
        private(set) var calls: [String] = []

        init() {
            super.init(config: RiviumSyncConfigBuilder(apiKey: "rv_live_test").build())
        }

        override func addDocument(databaseId: String, collectionId: String, data: [String: Any]) async throws -> SyncDocument {
            calls.append("add")
            return SyncDocument(id: "server-1", data: data)
        }

        override func setDocument(databaseId: String, collectionId: String, documentId: String, data: [String: Any], merge: Bool) async throws -> SyncDocument {
            calls.append("set")
            return SyncDocument(id: documentId, data: data)
        }

        override func updateDocument(databaseId: String, collectionId: String, documentId: String, data: [String: Any]) async throws -> SyncDocument {
            calls.append("update")
            return SyncDocument(id: documentId, data: data)
        }

        override func deleteDocument(databaseId: String, collectionId: String, documentId: String) async throws {
            calls.append("delete")
        }
    }

    private func makeCollection(_ api: RecordingApiClient) -> (SyncCollectionImpl, SyncEngine) {
        let config = RiviumSyncConfigBuilder(apiKey: "rv_live_test").build()
        let store = LocalStorageManager()
        let engine = SyncEngine(apiClient: api, localStore: store)
        let collection = SyncCollectionImpl(
            id: "col-\(UUID().uuidString)", name: "col", databaseId: "db",
            apiClient: api, mqttManager: MqttManager(config: config, apiClient: api),
            localStorageManager: store, syncEngine: engine
        )
        return (collection, engine)
    }

    func testWritesBeforeAnyConnectionReportGoToTheServer() async throws {
        let api = RecordingApiClient()
        let (collection, _) = makeCollection(api)

        _ = try await collection.add(data: ["name": "x"])
        _ = try await collection.set(documentId: "d1", data: ["name": "x"])
        _ = try await collection.update(documentId: "d1", data: ["name": "y"])
        try await collection.delete(documentId: "d1")

        XCTAssertEqual(api.calls, ["add", "set", "update", "delete"])
    }

    func testAConnectionThatReportedOfflineQueuesTheWrite() async throws {
        let api = RecordingApiClient()
        let (collection, engine) = makeCollection(api)
        engine.onConnectionStateChanged(connected: false)

        _ = try await collection.add(data: ["name": "x"])

        XCTAssertEqual(api.calls, [])
    }
}
