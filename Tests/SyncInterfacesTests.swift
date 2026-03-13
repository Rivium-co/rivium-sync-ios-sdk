import XCTest
@testable import RiviumSync

/// Tests for SyncCollection, SyncDatabase, SyncQuery, and ListenerRegistration protocols
final class SyncInterfacesTests: XCTestCase {

    // MARK: - Mock Implementations

    /// Mock ListenerRegistration that tracks whether remove() was called
    class MockListenerRegistration: ListenerRegistration {
        var removeCalled = false
        var onRemove: (() -> Void)?

        func remove() {
            removeCalled = true
            onRemove?()
        }
    }

    /// Mock SyncQuery that records chained builder calls
    class MockSyncQuery: SyncQuery {
        var whereClauses: [(field: String, op: QueryOperator, value: Any?)] = []
        var orderByClauses: [(field: String, direction: OrderDirection)] = []
        var limitValue: Int?
        var offsetValue: Int?
        var documentsToReturn: [SyncDocument] = []

        func `where`(_ field: String, _ op: QueryOperator, _ value: Any?) -> SyncQuery {
            whereClauses.append((field: field, op: op, value: value))
            return self
        }

        func orderBy(_ field: String, direction: OrderDirection) -> SyncQuery {
            orderByClauses.append((field: field, direction: direction))
            return self
        }

        func limit(_ count: Int) -> SyncQuery {
            limitValue = count
            return self
        }

        func offset(_ count: Int) -> SyncQuery {
            offsetValue = count
            return self
        }

        func get() async throws -> [SyncDocument] {
            return documentsToReturn
        }

        func get(onSuccess: @escaping ([SyncDocument]) -> Void, onError: @escaping (Error) -> Void) {
            onSuccess(documentsToReturn)
        }

        func listen(callback: @escaping ([SyncDocument]) -> Void) -> ListenerRegistration {
            callback(documentsToReturn)
            return MockListenerRegistration()
        }
    }

    /// Mock SyncCollection that stores documents in-memory
    class MockSyncCollection: SyncCollection {
        let id: String
        let name: String
        let databaseId: String
        var documents: [String: SyncDocument] = [:]
        private var nextId = 1

        init(id: String, name: String, databaseId: String) {
            self.id = id
            self.name = name
            self.databaseId = databaseId
        }

        func add(data: [String: Any]) async throws -> SyncDocument {
            let docId = "auto-\(nextId)"
            nextId += 1
            let now = Date().timeIntervalSince1970 * 1000
            let doc = SyncDocument(id: docId, data: data, createdAt: now, updatedAt: now, version: 1)
            documents[docId] = doc
            return doc
        }

        func get(documentId: String) async throws -> SyncDocument? {
            return documents[documentId]
        }

        func getAll() async throws -> [SyncDocument] {
            return Array(documents.values)
        }

        func update(documentId: String, data: [String: Any]) async throws -> SyncDocument {
            guard let existing = documents[documentId] else {
                throw NSError(domain: "MockCollection", code: 404, userInfo: [NSLocalizedDescriptionKey: "Document not found"])
            }
            var mergedData: [String: Any] = existing.data.mapValues { $0.value }
            for (key, value) in data {
                mergedData[key] = value
            }
            let updated = SyncDocument(id: documentId, data: mergedData, createdAt: existing.createdAt, updatedAt: Date().timeIntervalSince1970 * 1000, version: existing.version + 1)
            documents[documentId] = updated
            return updated
        }

        func set(documentId: String, data: [String: Any]) async throws -> SyncDocument {
            let now = Date().timeIntervalSince1970 * 1000
            let version = documents[documentId]?.version ?? 0
            let doc = SyncDocument(id: documentId, data: data, createdAt: documents[documentId]?.createdAt ?? now, updatedAt: now, version: version + 1)
            documents[documentId] = doc
            return doc
        }

        func delete(documentId: String) async throws {
            documents.removeValue(forKey: documentId)
        }

        func query() -> SyncQuery {
            let q = MockSyncQuery()
            q.documentsToReturn = Array(documents.values)
            return q
        }

        func `where`(_ field: String, _ op: QueryOperator, _ value: Any?) -> SyncQuery {
            let q = MockSyncQuery()
            q.documentsToReturn = Array(documents.values)
            return q.where(field, op, value)
        }

        func listen(callback: @escaping ([SyncDocument]) -> Void) -> ListenerRegistration {
            callback(Array(documents.values))
            return MockListenerRegistration()
        }

        func listenDocument(documentId: String, callback: @escaping (SyncDocument?) -> Void) -> ListenerRegistration {
            callback(documents[documentId])
            return MockListenerRegistration()
        }
    }

    /// Mock SyncDatabase that manages mock collections
    class MockSyncDatabase: SyncDatabase {
        let id: String
        let name: String
        var collections: [String: MockSyncCollection] = [:]
        private var nextCollectionId = 1

        init(id: String, name: String) {
            self.id = id
            self.name = name
        }

        func collection(_ collectionIdOrName: String) -> SyncCollection {
            if let existing = collections[collectionIdOrName] {
                return existing
            }
            let col = MockSyncCollection(id: collectionIdOrName, name: collectionIdOrName, databaseId: id)
            collections[collectionIdOrName] = col
            return col
        }

        func listCollections() async throws -> [CollectionInfo] {
            return collections.values.map { col in
                CollectionInfo(id: col.id, name: col.name, databaseId: id, documentCount: col.documents.count, createdAt: 0, updatedAt: 0)
            }
        }

        func createCollection(name: String) async throws -> SyncCollection {
            let colId = "col-\(nextCollectionId)"
            nextCollectionId += 1
            let col = MockSyncCollection(id: colId, name: name, databaseId: id)
            collections[colId] = col
            return col
        }

        func deleteCollection(collectionId: String) async throws {
            collections.removeValue(forKey: collectionId)
        }
    }

    // MARK: - Protocol Conformance

    func testMockCollectionConformsToSyncCollection() {
        let collection: SyncCollection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        XCTAssertEqual(collection.id, "col-1")
        XCTAssertEqual(collection.name, "users")
        XCTAssertEqual(collection.databaseId, "db-1")
    }

    func testMockDatabaseConformsToSyncDatabase() {
        let database: SyncDatabase = MockSyncDatabase(id: "db-1", name: "main")
        XCTAssertEqual(database.id, "db-1")
        XCTAssertEqual(database.name, "main")
    }

    func testMockQueryConformsToSyncQuery() {
        let query: SyncQuery = MockSyncQuery()
        XCTAssertNotNil(query)
    }

    func testMockListenerConformsToListenerRegistration() {
        let listener: ListenerRegistration = MockListenerRegistration()
        XCTAssertNotNil(listener)
    }

    // MARK: - Collection CRUD: add

    func testCollectionAddReturnsDocumentWithAutoId() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        let doc = try await collection.add(data: ["name": "Alice"])

        XCTAssertFalse(doc.id.isEmpty)
        XCTAssertEqual(doc.getString("name"), "Alice")
        XCTAssertEqual(doc.version, 1)
    }

    func testCollectionAddIncrementsAutoId() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        let doc1 = try await collection.add(data: ["name": "Alice"])
        let doc2 = try await collection.add(data: ["name": "Bob"])

        XCTAssertNotEqual(doc1.id, doc2.id)
        XCTAssertEqual(collection.documents.count, 2)
    }

    func testCollectionAddStoresDocumentInternally() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        let doc = try await collection.add(data: ["name": "Alice"])

        let retrieved = try await collection.get(documentId: doc.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, doc.id)
    }

    // MARK: - Collection CRUD: get

    func testCollectionGetReturnsExistingDocument() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        _ = try await collection.set(documentId: "user-1", data: ["name": "Alice"])

        let doc = try await collection.get(documentId: "user-1")
        XCTAssertNotNil(doc)
        XCTAssertEqual(doc?.getString("name"), "Alice")
    }

    func testCollectionGetReturnsNilForNonExistentDocument() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        let doc = try await collection.get(documentId: "nonexistent")
        XCTAssertNil(doc)
    }

    // MARK: - Collection CRUD: getAll

    func testCollectionGetAllReturnsAllDocuments() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        _ = try await collection.set(documentId: "u1", data: ["name": "Alice"])
        _ = try await collection.set(documentId: "u2", data: ["name": "Bob"])
        _ = try await collection.set(documentId: "u3", data: ["name": "Charlie"])

        let all = try await collection.getAll()
        XCTAssertEqual(all.count, 3)
    }

    func testCollectionGetAllReturnsEmptyForEmptyCollection() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        let all = try await collection.getAll()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Collection CRUD: update

    func testCollectionUpdateMergesData() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        _ = try await collection.set(documentId: "u1", data: ["name": "Alice", "age": 30])

        let updated = try await collection.update(documentId: "u1", data: ["age": 31])
        XCTAssertEqual(updated.getString("name"), "Alice")
        XCTAssertEqual(updated.getInt("age"), 31)
    }

    func testCollectionUpdateIncrementsVersion() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        let original = try await collection.set(documentId: "u1", data: ["name": "Alice"])

        let updated = try await collection.update(documentId: "u1", data: ["name": "Alice Updated"])
        XCTAssertTrue(updated.version > original.version)
    }

    func testCollectionUpdateThrowsForNonExistentDocument() async {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")

        do {
            _ = try await collection.update(documentId: "nonexistent", data: ["name": "Nobody"])
            XCTFail("Expected update to throw for non-existent document")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("not found"))
        }
    }

    // MARK: - Collection CRUD: set

    func testCollectionSetCreatesNewDocument() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        let doc = try await collection.set(documentId: "u1", data: ["name": "Alice"])

        XCTAssertEqual(doc.id, "u1")
        XCTAssertEqual(doc.getString("name"), "Alice")
    }

    func testCollectionSetOverwritesExistingDocument() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        _ = try await collection.set(documentId: "u1", data: ["name": "Alice", "age": 30])

        let overwritten = try await collection.set(documentId: "u1", data: ["name": "Bob"])
        XCTAssertEqual(overwritten.getString("name"), "Bob")
        XCTAssertNil(overwritten.getInt("age"))
    }

    func testCollectionSetPreservesOriginalCreatedAt() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        let original = try await collection.set(documentId: "u1", data: ["name": "Alice"])
        let originalCreatedAt = original.createdAt

        let overwritten = try await collection.set(documentId: "u1", data: ["name": "Bob"])
        XCTAssertEqual(overwritten.createdAt, originalCreatedAt)
    }

    // MARK: - Collection CRUD: delete

    func testCollectionDeleteRemovesDocument() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        _ = try await collection.set(documentId: "u1", data: ["name": "Alice"])

        try await collection.delete(documentId: "u1")

        let doc = try await collection.get(documentId: "u1")
        XCTAssertNil(doc)
    }

    func testCollectionDeleteReducesDocumentCount() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        _ = try await collection.set(documentId: "u1", data: ["name": "Alice"])
        _ = try await collection.set(documentId: "u2", data: ["name": "Bob"])

        try await collection.delete(documentId: "u1")

        let all = try await collection.getAll()
        XCTAssertEqual(all.count, 1)
    }

    func testCollectionDeleteNonExistentDocumentDoesNotThrow() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        // Should not throw for non-existent document
        try await collection.delete(documentId: "nonexistent")
    }

    // MARK: - Query Builder Chaining

    func testQueryWhereRecordsClause() {
        let query = MockSyncQuery()
        let result = query.where("age", .greaterThan, 18)

        let mockResult = result as! MockSyncQuery
        XCTAssertEqual(mockResult.whereClauses.count, 1)
        XCTAssertEqual(mockResult.whereClauses[0].field, "age")
        XCTAssertEqual(mockResult.whereClauses[0].op, .greaterThan)
        XCTAssertEqual(mockResult.whereClauses[0].value as? Int, 18)
    }

    func testQueryMultipleWhereClauses() {
        let query = MockSyncQuery()
        let result = query
            .where("age", .greaterThan, 18)
            .where("status", .equal, "active")

        let mockResult = result as! MockSyncQuery
        XCTAssertEqual(mockResult.whereClauses.count, 2)
        XCTAssertEqual(mockResult.whereClauses[0].field, "age")
        XCTAssertEqual(mockResult.whereClauses[1].field, "status")
    }

    func testQueryOrderByRecordsClause() {
        let query = MockSyncQuery()
        let result = query.orderBy("createdAt", direction: .descending)

        let mockResult = result as! MockSyncQuery
        XCTAssertEqual(mockResult.orderByClauses.count, 1)
        XCTAssertEqual(mockResult.orderByClauses[0].field, "createdAt")
        XCTAssertEqual(mockResult.orderByClauses[0].direction, .descending)
    }

    func testQueryMultipleOrderByClauses() {
        let query = MockSyncQuery()
        let result = query
            .orderBy("lastName", direction: .ascending)
            .orderBy("firstName", direction: .ascending)

        let mockResult = result as! MockSyncQuery
        XCTAssertEqual(mockResult.orderByClauses.count, 2)
        XCTAssertEqual(mockResult.orderByClauses[0].field, "lastName")
        XCTAssertEqual(mockResult.orderByClauses[1].field, "firstName")
    }

    func testQueryLimitRecordsValue() {
        let query = MockSyncQuery()
        let result = query.limit(10)

        let mockResult = result as! MockSyncQuery
        XCTAssertEqual(mockResult.limitValue, 10)
    }

    func testQueryOffsetRecordsValue() {
        let query = MockSyncQuery()
        let result = query.offset(20)

        let mockResult = result as! MockSyncQuery
        XCTAssertEqual(mockResult.offsetValue, 20)
    }

    func testQueryFullChaining() {
        let query = MockSyncQuery()
        let result = query
            .where("status", .equal, "active")
            .where("age", .greaterThanOrEqual, 21)
            .orderBy("name", direction: .ascending)
            .limit(25)
            .offset(50)

        let mockResult = result as! MockSyncQuery
        XCTAssertEqual(mockResult.whereClauses.count, 2)
        XCTAssertEqual(mockResult.orderByClauses.count, 1)
        XCTAssertEqual(mockResult.limitValue, 25)
        XCTAssertEqual(mockResult.offsetValue, 50)
    }

    func testQueryWhereWithNilValue() {
        let query = MockSyncQuery()
        let result = query.where("deletedAt", .equal, nil)

        let mockResult = result as! MockSyncQuery
        XCTAssertEqual(mockResult.whereClauses.count, 1)
        XCTAssertNil(mockResult.whereClauses[0].value)
    }

    func testQueryWhereWithStringValue() {
        let query = MockSyncQuery()
        let result = query.where("name", .equal, "Alice")

        let mockResult = result as! MockSyncQuery
        XCTAssertEqual(mockResult.whereClauses[0].value as? String, "Alice")
    }

    func testQueryWhereWithArrayValue() {
        let query = MockSyncQuery()
        let result = query.where("status", .in, ["active", "pending"])

        let mockResult = result as! MockSyncQuery
        let value = mockResult.whereClauses[0].value as? [String]
        XCTAssertEqual(value, ["active", "pending"])
    }

    func testQueryGetReturnsDocuments() async throws {
        let query = MockSyncQuery()
        let now = Date().timeIntervalSince1970 * 1000
        query.documentsToReturn = [
            SyncDocument(id: "d1", data: ["name": "Alice"], createdAt: now, updatedAt: now, version: 1),
            SyncDocument(id: "d2", data: ["name": "Bob"], createdAt: now, updatedAt: now, version: 1)
        ]

        let docs = try await query.get()
        XCTAssertEqual(docs.count, 2)
        XCTAssertEqual(docs[0].id, "d1")
        XCTAssertEqual(docs[1].id, "d2")
    }

    func testQueryGetCallbackInvokesOnSuccess() {
        let query = MockSyncQuery()
        let now = Date().timeIntervalSince1970 * 1000
        query.documentsToReturn = [
            SyncDocument(id: "d1", data: ["name": "Alice"], createdAt: now, updatedAt: now, version: 1)
        ]

        var receivedDocs: [SyncDocument]?
        query.get(onSuccess: { docs in
            receivedDocs = docs
        }, onError: { _ in
            XCTFail("Should not call onError")
        })

        XCTAssertNotNil(receivedDocs)
        XCTAssertEqual(receivedDocs?.count, 1)
    }

    // MARK: - Collection Query Methods

    func testCollectionQueryReturnsQueryObject() {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        let query = collection.query()
        XCTAssertNotNil(query)
    }

    func testCollectionWhereReturnsQueryWithClause() {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        let query = collection.where("age", .greaterThan, 18)

        let mockQuery = query as! MockSyncQuery
        XCTAssertEqual(mockQuery.whereClauses.count, 1)
        XCTAssertEqual(mockQuery.whereClauses[0].field, "age")
    }

    // MARK: - ListenerRegistration

    func testListenerRemoveCallsCallback() {
        let listener = MockListenerRegistration()
        var callbackInvoked = false
        listener.onRemove = {
            callbackInvoked = true
        }

        listener.remove()

        XCTAssertTrue(listener.removeCalled)
        XCTAssertTrue(callbackInvoked)
    }

    func testListenerRemoveCanBeCalledMultipleTimes() {
        let listener = MockListenerRegistration()
        var removeCount = 0
        listener.onRemove = {
            removeCount += 1
        }

        listener.remove()
        listener.remove()
        listener.remove()

        XCTAssertEqual(removeCount, 3)
        XCTAssertTrue(listener.removeCalled)
    }

    func testListenerInitiallyNotRemoved() {
        let listener = MockListenerRegistration()
        XCTAssertFalse(listener.removeCalled)
    }

    func testCollectionListenReturnsListenerRegistration() {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        var receivedDocs: [SyncDocument]?

        let listener = collection.listen { docs in
            receivedDocs = docs
        }

        XCTAssertNotNil(listener)
        XCTAssertNotNil(receivedDocs)
    }

    func testCollectionListenDocumentReturnsListenerRegistration() async throws {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")
        _ = try await collection.set(documentId: "u1", data: ["name": "Alice"])

        var receivedDoc: SyncDocument?
        let listener = collection.listenDocument(documentId: "u1") { doc in
            receivedDoc = doc
        }

        XCTAssertNotNil(listener)
        XCTAssertNotNil(receivedDoc)
        XCTAssertEqual(receivedDoc?.getString("name"), "Alice")
    }

    func testCollectionListenDocumentReturnsNilForMissingDoc() {
        let collection = MockSyncCollection(id: "col-1", name: "users", databaseId: "db-1")

        var receivedDoc: SyncDocument? = SyncDocument(id: "placeholder", data: [:], createdAt: 0, updatedAt: 0, version: 0)
        let listener = collection.listenDocument(documentId: "nonexistent") { doc in
            receivedDoc = doc
        }

        XCTAssertNotNil(listener)
        XCTAssertNil(receivedDoc)
    }

    func testQueryListenReturnsListenerRegistration() {
        let query = MockSyncQuery()
        var receivedDocs: [SyncDocument]?

        let listener = query.listen { docs in
            receivedDocs = docs
        }

        XCTAssertNotNil(listener)
        XCTAssertNotNil(receivedDocs)
        XCTAssertTrue(receivedDocs!.isEmpty)
    }

    // MARK: - Database Navigation

    func testDatabaseCollectionReturnsCollection() {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        let collection = db.collection("users")

        XCTAssertEqual(collection.id, "users")
        XCTAssertEqual(collection.name, "users")
        XCTAssertEqual(collection.databaseId, "db-1")
    }

    func testDatabaseCollectionReturnsSameInstanceForSameId() {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        let col1 = db.collection("users")
        let col2 = db.collection("users")

        XCTAssertEqual(col1.id, col2.id)
        XCTAssertEqual(col1.name, col2.name)
    }

    func testDatabaseCollectionReturnsDifferentInstancesForDifferentIds() {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        let users = db.collection("users")
        let posts = db.collection("posts")

        XCTAssertNotEqual(users.id, posts.id)
    }

    func testDatabaseCollectionSetsCorrectDatabaseId() {
        let db = MockSyncDatabase(id: "my-database-123", name: "production")
        let collection = db.collection("orders")

        XCTAssertEqual(collection.databaseId, "my-database-123")
    }

    // MARK: - Database Collection Management

    func testDatabaseListCollectionsReturnsEmpty() async throws {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        let collections = try await db.listCollections()
        XCTAssertTrue(collections.isEmpty)
    }

    func testDatabaseListCollectionsReturnsCreatedCollections() async throws {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        _ = try await db.createCollection(name: "users")
        _ = try await db.createCollection(name: "posts")

        let collections = try await db.listCollections()
        XCTAssertEqual(collections.count, 2)
    }

    func testDatabaseCreateCollectionReturnsCollection() async throws {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        let collection = try await db.createCollection(name: "users")

        XCTAssertFalse(collection.id.isEmpty)
        XCTAssertEqual(collection.name, "users")
        XCTAssertEqual(collection.databaseId, "db-1")
    }

    func testDatabaseCreateCollectionAssignsUniqueIds() async throws {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        let col1 = try await db.createCollection(name: "users")
        let col2 = try await db.createCollection(name: "posts")

        XCTAssertNotEqual(col1.id, col2.id)
    }

    func testDatabaseDeleteCollectionRemovesIt() async throws {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        let collection = try await db.createCollection(name: "users")
        let colId = collection.id

        try await db.deleteCollection(collectionId: colId)

        let collections = try await db.listCollections()
        XCTAssertTrue(collections.isEmpty)
    }

    func testDatabaseDeleteCollectionDoesNotAffectOthers() async throws {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        let col1 = try await db.createCollection(name: "users")
        _ = try await db.createCollection(name: "posts")

        try await db.deleteCollection(collectionId: col1.id)

        let collections = try await db.listCollections()
        XCTAssertEqual(collections.count, 1)
        XCTAssertEqual(collections[0].name, "posts")
    }

    func testDatabaseListCollectionsReturnsCorrectInfo() async throws {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        _ = try await db.createCollection(name: "users")

        let collections = try await db.listCollections()
        XCTAssertEqual(collections[0].name, "users")
        XCTAssertEqual(collections[0].databaseId, "db-1")
    }

    // MARK: - QueryOperator Enum Values

    func testQueryOperatorEqualRawValue() {
        XCTAssertEqual(QueryOperator.equal.rawValue, "==")
    }

    func testQueryOperatorNotEqualRawValue() {
        XCTAssertEqual(QueryOperator.notEqual.rawValue, "!=")
    }

    func testQueryOperatorGreaterThanRawValue() {
        XCTAssertEqual(QueryOperator.greaterThan.rawValue, ">")
    }

    func testQueryOperatorGreaterThanOrEqualRawValue() {
        XCTAssertEqual(QueryOperator.greaterThanOrEqual.rawValue, ">=")
    }

    func testQueryOperatorLessThanRawValue() {
        XCTAssertEqual(QueryOperator.lessThan.rawValue, "<")
    }

    func testQueryOperatorLessThanOrEqualRawValue() {
        XCTAssertEqual(QueryOperator.lessThanOrEqual.rawValue, "<=")
    }

    func testQueryOperatorArrayContainsRawValue() {
        XCTAssertEqual(QueryOperator.arrayContains.rawValue, "array-contains")
    }

    func testQueryOperatorInRawValue() {
        XCTAssertEqual(QueryOperator.in.rawValue, "in")
    }

    func testQueryOperatorNotInRawValue() {
        XCTAssertEqual(QueryOperator.notIn.rawValue, "not-in")
    }

    func testAllQueryOperatorRawValuesAreUnique() {
        let allValues: [QueryOperator] = [
            .equal, .notEqual, .greaterThan, .greaterThanOrEqual,
            .lessThan, .lessThanOrEqual, .arrayContains, .in, .notIn
        ]
        let rawValues = allValues.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        XCTAssertEqual(rawValues.count, uniqueValues.count)
    }

    func testQueryOperatorRoundTripFromRawValue() {
        let allCases: [QueryOperator] = [
            .equal, .notEqual, .greaterThan, .greaterThanOrEqual,
            .lessThan, .lessThanOrEqual, .arrayContains, .in, .notIn
        ]
        for op in allCases {
            let reconstructed = QueryOperator(rawValue: op.rawValue)
            XCTAssertEqual(reconstructed, op)
        }
    }

    func testQueryOperatorInvalidRawValueReturnsNil() {
        XCTAssertNil(QueryOperator(rawValue: "invalid"))
        XCTAssertNil(QueryOperator(rawValue: ""))
        XCTAssertNil(QueryOperator(rawValue: "EQUAL"))
        XCTAssertNil(QueryOperator(rawValue: "contains"))
    }

    // MARK: - OrderDirection Enum Values

    func testOrderDirectionAscendingRawValue() {
        XCTAssertEqual(OrderDirection.ascending.rawValue, "asc")
    }

    func testOrderDirectionDescendingRawValue() {
        XCTAssertEqual(OrderDirection.descending.rawValue, "desc")
    }

    func testOrderDirectionRoundTripFromRawValue() {
        XCTAssertEqual(OrderDirection(rawValue: "asc"), .ascending)
        XCTAssertEqual(OrderDirection(rawValue: "desc"), .descending)
    }

    func testOrderDirectionInvalidRawValueReturnsNil() {
        XCTAssertNil(OrderDirection(rawValue: "invalid"))
        XCTAssertNil(OrderDirection(rawValue: ""))
        XCTAssertNil(OrderDirection(rawValue: "ASC"))
        XCTAssertNil(OrderDirection(rawValue: "DESC"))
    }

    func testOrderDirectionAllValuesAreUnique() {
        let allValues: [OrderDirection] = [.ascending, .descending]
        let rawValues = allValues.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        XCTAssertEqual(rawValues.count, uniqueValues.count)
    }

    // MARK: - Integration: Database to Collection to Query

    func testDatabaseToCollectionToQueryFlow() async throws {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        let collection = db.collection("users") as! MockSyncCollection

        _ = try await collection.set(documentId: "u1", data: ["name": "Alice", "age": 25])
        _ = try await collection.set(documentId: "u2", data: ["name": "Bob", "age": 30])

        let query = collection.query()
        let chainedQuery = query.where("age", .greaterThan, 20).orderBy("name", direction: .ascending).limit(10)

        XCTAssertNotNil(chainedQuery)

        let docs = try await chainedQuery.get()
        XCTAssertEqual(docs.count, 2)
    }

    func testDatabaseToCollectionCRUDFlow() async throws {
        let db = MockSyncDatabase(id: "db-1", name: "main")
        let collection = db.collection("products")

        // Create
        let created = try await collection.add(data: ["name": "Widget", "price": 9.99])
        XCTAssertEqual(created.getString("name"), "Widget")

        // Read
        let fetched = try await collection.get(documentId: created.id)
        XCTAssertNotNil(fetched)

        // Update
        let updated = try await collection.update(documentId: created.id, data: ["price": 12.99])
        let updatedPrice = updated.getDouble("price")
        XCTAssertNotNil(updatedPrice)
        XCTAssertEqual(updatedPrice!, 12.99, accuracy: 0.001)

        // Delete
        try await collection.delete(documentId: created.id)
        let deleted = try await collection.get(documentId: created.id)
        XCTAssertNil(deleted)
    }
}
