import XCTest
@testable import RiviumSync

/// With offline persistence on, get() returns nil only when the document does not exist. When the server can't be
/// reached (or refuses) and the document is not cached, the error is thrown - before, get() returned nil, so apps
/// showed "not found" for a document that existed (on an unstable network).
final class OfflineGetErrorTests: XCTestCase {

    private final class FakeApiClient: ApiClient {
        var result: Result<SyncDocument?, Error> = .success(nil)

        init() {
            super.init(config: RiviumSyncConfigBuilder(apiKey: "rv_live_test").build())
        }

        override func getDocument(databaseId: String, collectionId: String, documentId: String) async throws -> SyncDocument? {
            try result.get()
        }
    }

    private func makeCollection(_ api: FakeApiClient) -> (SyncCollectionImpl, SyncEngine, LocalStorageManager, String) {
        let config = RiviumSyncConfigBuilder(apiKey: "rv_live_test").build()
        let store = LocalStorageManager()
        let engine = SyncEngine(apiClient: api, localStore: store)
        let collectionId = "col-\(UUID().uuidString)"
        let collection = SyncCollectionImpl(
            id: collectionId, name: "col", databaseId: "db",
            apiClient: api, mqttManager: MqttManager(config: config, apiClient: api),
            localStorageManager: store, syncEngine: engine
        )
        return (collection, engine, store, collectionId)
    }

    func testServerErrorAndNothingCachedThrows() async {
        let api = FakeApiClient()
        api.result = .failure(RiviumSyncError.networkError("timeout", nil))
        let (collection, _, _, _) = makeCollection(api)

        do {
            _ = try await collection.get(documentId: "missing-\(UUID().uuidString)")
            XCTFail("expected the network error")
        } catch {
            XCTAssertTrue("\(error)".contains("timeout"), "\(error)")
        }
    }

    func testServerErrorWithACachedCopyReturnsIt() async throws {
        let api = FakeApiClient()
        api.result = .failure(RiviumSyncError.networkError("timeout", nil))
        let (collection, _, store, collectionId) = makeCollection(api)
        let docId = "cached-\(UUID().uuidString)"
        store.saveDocument(document: SyncDocument(id: docId, data: ["name": "x"]), databaseId: "db", collectionId: collectionId, syncStatus: .synced)

        let doc = try await collection.get(documentId: docId)
        XCTAssertEqual(doc?.id, docId)
    }

    func testADocumentThatDoesNotExistIsStillNil() async throws {
        let api = FakeApiClient()
        api.result = .success(nil)
        let (collection, _, _, _) = makeCollection(api)

        let doc = try await collection.get(documentId: "missing-\(UUID().uuidString)")
        XCTAssertNil(doc)
    }

    func testKnownOfflineAndNothingCachedThrows() async {
        let api = FakeApiClient()
        let (collection, engine, _, _) = makeCollection(api)
        engine.onConnectionStateChanged(connected: false)

        do {
            _ = try await collection.get(documentId: "missing-\(UUID().uuidString)")
            XCTFail("expected an offline error")
        } catch {
            XCTAssertTrue("\(error)".contains("Offline"), "\(error)")
        }
    }
}
