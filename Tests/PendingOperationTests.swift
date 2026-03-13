import XCTest
@testable import RiviumSync

/// Comprehensive tests for PendingOperation entity
final class PendingOperationTests: XCTestCase {

    let now = Int64(Date().timeIntervalSince1970 * 1000)

    // MARK: - Factory Method: create()

    func testCreateFactoryMethodCreatesCREATEOperation() {
        let data: [String: Any] = ["name": "John", "age": 30]

        let op = PendingOperation.create(
            documentId: "doc-123",
            databaseId: "db-1",
            collectionId: "users",
            data: data
        )

        XCTAssertEqual(op.documentId, "doc-123")
        XCTAssertEqual(op.databaseId, "db-1")
        XCTAssertEqual(op.collectionId, "users")
        XCTAssertEqual(op.operationType, .create)
        XCTAssertNotNil(op.data)
        XCTAssertNil(op.baseVersion)
    }

    func testCreateFactorySerializesData() {
        let data: [String: Any] = ["title": "Test", "count": 42]

        let op = PendingOperation.create(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: data
        )

        XCTAssertNotNil(op.data)
        XCTAssertEqual(op.data?["title"]?.value as? String, "Test")
        XCTAssertEqual(op.data?["count"]?.value as? Int, 42)
    }

    func testCreateWithEmptyDataMap() {
        let op = PendingOperation.create(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: [:]
        )

        XCTAssertNotNil(op.data)
        XCTAssertTrue(op.data?.isEmpty ?? false)
    }

    // MARK: - Factory Method: update()

    func testUpdateFactoryMethodCreatesUPDATEOperation() {
        let data: [String: Any] = ["status": "active"]

        let op = PendingOperation.update(
            documentId: "doc-123",
            databaseId: "db-1",
            collectionId: "users",
            data: data,
            baseVersion: 5
        )

        XCTAssertEqual(op.documentId, "doc-123")
        XCTAssertEqual(op.databaseId, "db-1")
        XCTAssertEqual(op.collectionId, "users")
        XCTAssertEqual(op.operationType, .update)
        XCTAssertNotNil(op.data)
        XCTAssertEqual(op.baseVersion, 5)
    }

    func testUpdatePreservesBaseVersionForConflictDetection() {
        let op = PendingOperation.update(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: ["x": 1],
            baseVersion: 10
        )

        XCTAssertEqual(op.baseVersion, 10)
    }

    // MARK: - Factory Method: delete()

    func testDeleteFactoryMethodCreatesDELETEOperation() {
        let op = PendingOperation.delete(
            documentId: "doc-123",
            databaseId: "db-1",
            collectionId: "users",
            baseVersion: 3
        )

        XCTAssertEqual(op.documentId, "doc-123")
        XCTAssertEqual(op.databaseId, "db-1")
        XCTAssertEqual(op.collectionId, "users")
        XCTAssertEqual(op.operationType, .delete)
        XCTAssertNil(op.data)
        XCTAssertEqual(op.baseVersion, 3)
    }

    func testDeleteHasNilData() {
        let op = PendingOperation.delete(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            baseVersion: 1
        )

        XCTAssertNil(op.data)
    }

    // MARK: - Default Values

    func testDefaultValuesAreSetCorrectly() {
        let op = PendingOperation.create(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: [:]
        )

        XCTAssertFalse(op.id.isEmpty) // Auto-generated UUID
        XCTAssertEqual(op.retryCount, 0)
        XCTAssertNil(op.lastError)
        XCTAssertEqual(op.status, "pending")
        XCTAssertGreaterThan(op.createdAt, 0)
    }

    // MARK: - getData()

    func testGetDataReturnsConvertedData() {
        let op = PendingOperation.create(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: ["name": "Test", "count": 42]
        )

        let data = op.getData()

        XCTAssertNotNil(data)
        XCTAssertEqual(data?["name"] as? String, "Test")
        XCTAssertEqual(data?["count"] as? Int, 42)
    }

    func testGetDataReturnsNilForDeleteOperation() {
        let op = PendingOperation.delete(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            baseVersion: 1
        )

        XCTAssertNil(op.getData())
    }

    // MARK: - Codable Tests

    func testPendingOperationEncodeDecode() throws {
        let original = PendingOperation.update(
            documentId: "doc-codec",
            databaseId: "db-1",
            collectionId: "users",
            data: ["name": "Test"],
            baseVersion: 5
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PendingOperation.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.documentId, original.documentId)
        XCTAssertEqual(decoded.databaseId, original.databaseId)
        XCTAssertEqual(decoded.collectionId, original.collectionId)
        XCTAssertEqual(decoded.operationType, original.operationType)
        XCTAssertEqual(decoded.baseVersion, original.baseVersion)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.retryCount, original.retryCount)
    }

    func testPendingOperationEncodeDecodeDeleteOperation() throws {
        let original = PendingOperation.delete(
            documentId: "doc-del",
            databaseId: "db-1",
            collectionId: "col-1",
            baseVersion: 3
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PendingOperation.self, from: data)

        XCTAssertNil(decoded.data)
        XCTAssertEqual(decoded.operationType, .delete)
        XCTAssertEqual(decoded.baseVersion, 3)
    }

    // MARK: - Edge Cases

    func testHandlesSpecialCharactersInDocumentId() {
        let op = PendingOperation.create(
            documentId: "doc/with/slashes:and:colons",
            databaseId: "db-1",
            collectionId: "col-1",
            data: [:]
        )

        XCTAssertEqual(op.documentId, "doc/with/slashes:and:colons")
    }

    func testHandlesNestedData() {
        let nestedData: [String: Any] = [
            "user": [
                "name": "John",
                "address": ["city": "NYC"]
            ] as [String: Any]
        ]

        let op = PendingOperation.create(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: nestedData
        )

        let data = op.getData()
        XCTAssertNotNil(data)
    }

    func testHandlesArraysInData() {
        let op = PendingOperation.create(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: ["tags": ["swift", "ios", "sdk"]]
        )

        let data = op.getData()
        XCTAssertNotNil(data)
    }

    // MARK: - Operation Type Specific Tests

    func testCREATEOperationHasNoBaseVersion() {
        let op = PendingOperation.create(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: [:]
        )

        XCTAssertEqual(op.operationType, .create)
        XCTAssertNil(op.baseVersion)
    }

    func testUPDATEOperationRequiresBaseVersion() {
        let op = PendingOperation.update(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: [:],
            baseVersion: 3
        )

        XCTAssertEqual(op.operationType, .update)
        XCTAssertEqual(op.baseVersion, 3)
    }

    func testDELETEOperationRequiresBaseVersion() {
        let op = PendingOperation.delete(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            baseVersion: 5
        )

        XCTAssertEqual(op.operationType, .delete)
        XCTAssertEqual(op.baseVersion, 5)
    }

    // MARK: - UUID Generation

    func testEachOperationGetsUniqueId() {
        let op1 = PendingOperation.create(documentId: "doc-1", databaseId: "db-1", collectionId: "col-1", data: [:])
        let op2 = PendingOperation.create(documentId: "doc-1", databaseId: "db-1", collectionId: "col-1", data: [:])

        XCTAssertNotEqual(op1.id, op2.id)
    }
}
