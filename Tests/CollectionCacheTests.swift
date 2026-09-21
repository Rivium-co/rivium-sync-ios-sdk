import XCTest
@testable import RiviumSync

/// getAll() used to make one request, so it stopped at the server's default
/// page of 100 without saying so. And the cache only ever added and updated
/// documents, so anything deleted on the server came back whenever the app was
/// offline. These pin both fixes - and that the cleanup never eats a local
/// change that has not synced yet.
final class CollectionCacheTests: XCTestCase {

    // MARK: - Paging

    /// Serves `total` documents a page at a time, like the real endpoint.
    private final class PagedApiClient: ApiClient {
        var total: Int
        var reportTotal = true
        /// Documents that vanish between pages, to simulate concurrent deletes.
        var vanishAfterFirstPage = 0
        private(set) var requests: [(skip: Int, limit: Int)] = []

        init(total: Int) {
            self.total = total
            super.init(config: RiviumSyncConfigBuilder(apiKey: "rv_live_test").build())
        }

        override func fetchPage(
            databaseId: String, collectionId: String, skip: Int, limit: Int
        ) async throws -> (documents: [SyncDocument], total: Int?) {
            requests.append((skip, limit))
            let available = requests.count == 1 ? total : total - vanishAfterFirstPage
            let end = min(skip + limit, available)
            let docs = skip < end ? (skip..<end).map { SyncDocument(id: "doc-\($0)", data: [:]) } : []
            return (docs, reportTotal ? total : nil)
        }
    }

    func testReadsEveryPageNotJustTheFirst100() async throws {
        let api = PagedApiClient(total: 150)
        let snapshot = try await api.fetchCollection(databaseId: "db", collectionId: "todos")

        XCTAssertEqual(snapshot.documents.count, 150)
        XCTAssertEqual(snapshot.documents.last?.id, "doc-149")
        XCTAssertTrue(snapshot.complete)
        XCTAssertEqual(api.requests.map { $0.skip }, [0, 100])
        XCTAssertEqual(api.requests.map { $0.limit }, [100, 100])
    }

    func testASingleShortPageIsComplete() async throws {
        let api = PagedApiClient(total: 10)
        let snapshot = try await api.fetchCollection(databaseId: "db", collectionId: "todos")

        XCTAssertEqual(snapshot.documents.count, 10)
        XCTAssertTrue(snapshot.complete)
        XCTAssertEqual(api.requests.count, 1)
    }

    func testWithoutATotalItIsNeverComplete() async throws {
        let api = PagedApiClient(total: 10)
        api.reportTotal = false
        let snapshot = try await api.fetchCollection(databaseId: "db", collectionId: "todos")

        XCTAssertEqual(snapshot.documents.count, 10)
        XCTAssertFalse(snapshot.complete)
    }

    func testACollectionThatChangedWhilePagingIsNotComplete() async throws {
        let api = PagedApiClient(total: 150)
        api.vanishAfterFirstPage = 2
        let snapshot = try await api.fetchCollection(databaseId: "db", collectionId: "todos")

        XCTAssertEqual(snapshot.documents.count, 148)
        XCTAssertFalse(snapshot.complete)
    }

    // MARK: - Cache cleanup

    /// A database id no other test or run uses, so the on-disk cache is clean.
    private let db = "test-db-\(UUID().uuidString)"

    override func tearDown() {
        // LocalStorageManager writes real files; remove what these tests made.
        let store = LocalStorageManager()
        for suffix in ["a", "b", "gone", "offline-edit", "note"] {
            store.deleteDocument(documentId: "\(db)-\(suffix)")
        }
        super.tearDown()
    }

    func testDropsDocumentsDeletedOnTheServer() {
        let store = LocalStorageManager()
        store.saveDocuments(
            documents: ["a", "b", "gone"].map { SyncDocument(id: "\(db)-\($0)", data: [:]) },
            databaseId: db, collectionId: "todos", syncStatus: .synced
        )

        store.replaceSyncedDocuments(
            documents: ["a", "b"].map { SyncDocument(id: "\(db)-\($0)", data: [:]) },
            databaseId: db, collectionId: "todos"
        )

        let ids = Set(store.getDocuments(databaseId: db, collectionId: "todos").map { $0.id })
        XCTAssertEqual(ids, ["\(db)-a", "\(db)-b"])
        XCTAssertNil(store.getDocument(documentId: "\(db)-gone"))
    }

    func testNeverDropsALocalChangeThatHasNotSynced() {
        let store = LocalStorageManager()
        store.saveDocument(
            document: SyncDocument(id: "\(db)-offline-edit", data: ["title": "made offline"]),
            databaseId: db, collectionId: "todos", syncStatus: .pendingCreate
        )

        // The server has not seen it yet, so it is missing from a full read.
        store.replaceSyncedDocuments(documents: [], databaseId: db, collectionId: "todos")

        XCTAssertNotNil(store.getDocument(documentId: "\(db)-offline-edit"))
    }

    func testLeavesOtherCollectionsAlone() {
        let store = LocalStorageManager()
        store.saveDocuments(
            documents: [SyncDocument(id: "\(db)-note", data: [:])],
            databaseId: db, collectionId: "notes", syncStatus: .synced
        )

        store.replaceSyncedDocuments(documents: [], databaseId: db, collectionId: "todos")

        XCTAssertNotNil(store.getDocument(documentId: "\(db)-note"))
    }
}
