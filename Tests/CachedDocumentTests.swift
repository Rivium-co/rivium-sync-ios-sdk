import XCTest
@testable import RiviumSync

/// Comprehensive tests for CachedDocument entity
final class CachedDocumentTests: XCTestCase {

    let now = Int64(Date().timeIntervalSince1970 * 1000)

    // MARK: - Basic Construction

    func testCachedDocumentStoresAllProperties() {
        let cached = CachedDocument(
            id: "doc-123",
            databaseId: "db-1",
            collectionId: "users",
            data: ["name": AnyCodable("John"), "age": AnyCodable(30)],
            createdAt: 1704067200000,
            updatedAt: 1704153600000,
            version: 5,
            syncStatus: .synced
        )

        XCTAssertEqual(cached.id, "doc-123")
        XCTAssertEqual(cached.databaseId, "db-1")
        XCTAssertEqual(cached.collectionId, "users")
        XCTAssertEqual(cached.createdAt, 1704067200000)
        XCTAssertEqual(cached.updatedAt, 1704153600000)
        XCTAssertEqual(cached.version, 5)
        XCTAssertEqual(cached.syncStatus, .synced)
    }

    func testCachedDocumentHasCorrectDefaultValues() {
        let cached = CachedDocument(
            id: "doc-123",
            databaseId: "db-1",
            collectionId: "users",
            data: [:],
            createdAt: now,
            updatedAt: now,
            version: 1,
            syncStatus: .synced
        )

        XCTAssertNil(cached.baseVersion)
        XCTAssertEqual(cached.retryCount, 0)
        XCTAssertNil(cached.lastError)
        XCTAssertGreaterThan(cached.localUpdatedAt, 0)
    }

    // MARK: - fromSyncDocument()

    func testFromSyncDocumentCreatesCachedDocumentWithSyncedStatus() {
        let syncDoc = SyncDocument(
            id: "doc-123",
            data: ["name": "John", "age": 30],
            createdAt: 1704067200000,
            updatedAt: 1704153600000,
            version: 3
        )

        let cached = CachedDocument.fromSyncDocument(
            syncDoc,
            databaseId: "db-1",
            collectionId: "users",
            syncStatus: .synced
        )

        XCTAssertEqual(cached.id, "doc-123")
        XCTAssertEqual(cached.databaseId, "db-1")
        XCTAssertEqual(cached.collectionId, "users")
        XCTAssertEqual(cached.createdAt, 1704067200000)
        XCTAssertEqual(cached.updatedAt, 1704153600000)
        XCTAssertEqual(cached.version, 3)
        XCTAssertEqual(cached.syncStatus, .synced)
    }

    func testFromSyncDocumentCreatesCachedDocumentWithPendingCreateStatus() {
        let syncDoc = SyncDocument(
            id: "doc-new",
            data: ["title": "New Document"],
            createdAt: TimeInterval(now),
            updatedAt: TimeInterval(now),
            version: 1
        )

        let cached = CachedDocument.fromSyncDocument(
            syncDoc,
            databaseId: "db-1",
            collectionId: "documents",
            syncStatus: .pendingCreate
        )

        XCTAssertEqual(cached.syncStatus, .pendingCreate)
    }

    func testFromSyncDocumentPreservesBaseVersionWhenProvided() {
        let syncDoc = SyncDocument(id: "doc-1", data: [:], createdAt: TimeInterval(now), updatedAt: TimeInterval(now), version: 5)

        let cached = CachedDocument.fromSyncDocument(
            syncDoc,
            databaseId: "db-1",
            collectionId: "col-1",
            syncStatus: .pendingUpdate,
            baseVersion: 4
        )

        XCTAssertEqual(cached.baseVersion, 4)
        XCTAssertEqual(cached.version, 5)
    }

    // MARK: - toSyncDocument()

    func testToSyncDocumentCreatesSyncDocumentWithAllFields() {
        let cached = CachedDocument(
            id: "doc-123",
            databaseId: "db-1",
            collectionId: "users",
            data: ["name": AnyCodable("John"), "age": AnyCodable(30)],
            createdAt: 1704067200000,
            updatedAt: 1704153600000,
            version: 5,
            syncStatus: .synced
        )

        let syncDoc = cached.toSyncDocument()

        XCTAssertEqual(syncDoc.id, "doc-123")
        XCTAssertEqual(syncDoc.getString("name"), "John")
        XCTAssertEqual(syncDoc.createdAt, 1704067200000)
        XCTAssertEqual(syncDoc.updatedAt, 1704153600000)
        XCTAssertEqual(syncDoc.version, 5)
    }

    func testToSyncDocumentHandlesEmptyData() {
        let cached = CachedDocument(
            id: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: [:],
            createdAt: now,
            updatedAt: now,
            version: 1,
            syncStatus: .synced
        )

        let syncDoc = cached.toSyncDocument()

        XCTAssertTrue(syncDoc.data.isEmpty)
    }

    // MARK: - getData()

    func testGetDataReturnsParsedDataMap() {
        let cached = CachedDocument(
            id: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: ["name": AnyCodable("Jane"), "score": AnyCodable(95)],
            createdAt: now,
            updatedAt: now,
            version: 1,
            syncStatus: .synced
        )

        let data = cached.getData()

        XCTAssertEqual(data["name"] as? String, "Jane")
        XCTAssertEqual(data["score"] as? Int, 95)
    }

    func testGetDataReturnsEmptyMapForEmptyData() {
        let cached = CachedDocument(
            id: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: [:],
            createdAt: now,
            updatedAt: now,
            version: 1,
            syncStatus: .synced
        )

        XCTAssertTrue(cached.getData().isEmpty)
    }

    func testGetDataHandlesNestedStructures() {
        let cached = CachedDocument(
            id: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: [
                "user": AnyCodable([
                    "name": "John",
                    "address": ["city": "NYC"]
                ] as [String: Any])
            ],
            createdAt: now,
            updatedAt: now,
            version: 1,
            syncStatus: .synced
        )

        let data = cached.getData()
        let user = data["user"] as? [String: Any]

        XCTAssertNotNil(user)
        XCTAssertEqual(user?["name"] as? String, "John")
    }

    // MARK: - Roundtrip Tests

    func testRoundtripFromSyncDocumentToSyncDocumentPreservesData() {
        let original = SyncDocument(
            id: "doc-roundtrip",
            data: [
                "name": "Test",
                "count": 42,
                "active": true
            ],
            createdAt: 1704067200000,
            updatedAt: 1704153600000,
            version: 7
        )

        let cached = CachedDocument.fromSyncDocument(
            original,
            databaseId: "db",
            collectionId: "col",
            syncStatus: .synced
        )
        let restored = cached.toSyncDocument()

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.getString("name"), "Test")
        XCTAssertEqual(restored.createdAt, original.createdAt)
        XCTAssertEqual(restored.updatedAt, original.updatedAt)
        XCTAssertEqual(restored.version, original.version)
    }

    // MARK: - Codable Tests

    func testCachedDocumentEncodeDecode() throws {
        let original = CachedDocument(
            id: "doc-codec",
            databaseId: "db-1",
            collectionId: "users",
            data: ["name": AnyCodable("Test")],
            createdAt: 1704067200000,
            updatedAt: 1704153600000,
            version: 3,
            syncStatus: .pendingUpdate,
            baseVersion: 2,
            retryCount: 1,
            lastError: "Network error",
            localUpdatedAt: 1704200000000
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CachedDocument.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.databaseId, original.databaseId)
        XCTAssertEqual(decoded.collectionId, original.collectionId)
        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.syncStatus, original.syncStatus)
        XCTAssertEqual(decoded.baseVersion, original.baseVersion)
        XCTAssertEqual(decoded.retryCount, original.retryCount)
        XCTAssertEqual(decoded.lastError, original.lastError)
        XCTAssertEqual(decoded.localUpdatedAt, original.localUpdatedAt)
    }

    func testCachedDocumentEncodeDecodeWithNilValues() throws {
        let original = CachedDocument(
            id: "doc-nil",
            databaseId: "db-1",
            collectionId: "col-1",
            data: [:],
            createdAt: now,
            updatedAt: now,
            version: 1,
            syncStatus: .synced,
            baseVersion: nil,
            retryCount: 0,
            lastError: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CachedDocument.self, from: data)

        XCTAssertNil(decoded.baseVersion)
        XCTAssertNil(decoded.lastError)
    }

    // MARK: - Edge Cases

    func testHandlesNullValuesInData() {
        let cached = CachedDocument(
            id: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: ["name": AnyCodable("John"), "middleName": AnyCodable(NSNull())],
            createdAt: now,
            updatedAt: now,
            version: 1,
            syncStatus: .synced
        )

        let data = cached.getData()

        XCTAssertEqual(data["name"] as? String, "John")
    }

    func testHandlesArraysInData() {
        let cached = CachedDocument(
            id: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: ["tags": AnyCodable(["a", "b", "c"])],
            createdAt: now,
            updatedAt: now,
            version: 1,
            syncStatus: .synced
        )

        let data = cached.getData()
        let tags = data["tags"] as? [String]

        XCTAssertEqual(tags, ["a", "b", "c"])
    }

    func testHandlesSpecialCharactersInDocumentId() {
        let cached = CachedDocument(
            id: "doc/with/slashes:and:colons",
            databaseId: "db-1",
            collectionId: "col-1",
            data: [:],
            createdAt: now,
            updatedAt: now,
            version: 1,
            syncStatus: .synced
        )

        XCTAssertEqual(cached.id, "doc/with/slashes:and:colons")
    }
}
