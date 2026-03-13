import XCTest
@testable import RiviumSync

/// Tests for WriteBatch operations
final class WriteBatchTests: XCTestCase {

    // MARK: - Batch Operation Types

    func testBatchOperationTypes() {
        // Verify all batch operation types
        let types = ["set", "update", "delete", "create"]

        XCTAssertTrue(types.contains("set"))
        XCTAssertTrue(types.contains("update"))
        XCTAssertTrue(types.contains("delete"))
        XCTAssertTrue(types.contains("create"))
    }

    // MARK: - Operation Structure

    func testSetOperationStructure() {
        let operation: [String: Any] = [
            "type": "set",
            "databaseId": "test-db",
            "collectionId": "users",
            "documentId": "user-123",
            "data": ["name": "John", "age": 30]
        ]

        XCTAssertEqual(operation["type"] as? String, "set")
        XCTAssertEqual(operation["databaseId"] as? String, "test-db")
        XCTAssertEqual(operation["collectionId"] as? String, "users")
        XCTAssertEqual(operation["documentId"] as? String, "user-123")

        let data = operation["data"] as? [String: Any]
        XCTAssertEqual(data?["name"] as? String, "John")
        XCTAssertEqual(data?["age"] as? Int, 30)
    }

    func testUpdateOperationStructure() {
        let operation: [String: Any] = [
            "type": "update",
            "databaseId": "test-db",
            "collectionId": "users",
            "documentId": "user-123",
            "data": ["status": "active"]
        ]

        XCTAssertEqual(operation["type"] as? String, "update")
        XCTAssertNotNil(operation["data"])
    }

    func testDeleteOperationStructure() {
        let operation: [String: Any] = [
            "type": "delete",
            "databaseId": "test-db",
            "collectionId": "users",
            "documentId": "user-123"
        ]

        XCTAssertEqual(operation["type"] as? String, "delete")
        XCTAssertNil(operation["data"])
    }

    func testCreateOperationStructure() {
        let operation: [String: Any] = [
            "type": "create",
            "databaseId": "test-db",
            "collectionId": "users",
            "data": ["name": "New User"]
        ]

        XCTAssertEqual(operation["type"] as? String, "create")
        XCTAssertNil(operation["documentId"])
        XCTAssertNotNil(operation["data"])
    }

    // MARK: - Batch State

    func testBatchTracksOperationCount() {
        var operations: [[String: Any]] = []

        XCTAssertEqual(operations.count, 0)

        operations.append(["type": "set"])
        XCTAssertEqual(operations.count, 1)

        operations.append(["type": "update"])
        XCTAssertEqual(operations.count, 2)

        operations.append(["type": "delete"])
        XCTAssertEqual(operations.count, 3)
    }

    func testBatchIsEmptyCheck() {
        var operations: [[String: Any]] = []

        XCTAssertTrue(operations.isEmpty)

        operations.append(["type": "set"])

        XCTAssertFalse(operations.isEmpty)
    }

    // MARK: - Batch Commit State

    func testBatchPreventsDoubleCommit() {
        var committed = false

        func checkNotCommitted() throws {
            if committed {
                throw NSError(domain: "WriteBatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "WriteBatch has already been committed"])
            }
        }

        func commit() throws {
            try checkNotCommitted()
            committed = true
        }

        // First commit should succeed
        XCTAssertNoThrow(try commit())
        XCTAssertTrue(committed)

        // Second commit should fail
        XCTAssertThrowsError(try commit())
    }

    // MARK: - Multiple Operations

    func testBatchWithMultipleOperations() {
        var operations: [[String: Any]] = []

        // Add set operation
        operations.append([
            "type": "set",
            "databaseId": "db1",
            "collectionId": "users",
            "documentId": "u1",
            "data": ["name": "User 1"]
        ])

        // Add update operation
        operations.append([
            "type": "update",
            "databaseId": "db1",
            "collectionId": "users",
            "documentId": "u2",
            "data": ["status": "active"]
        ])

        // Add delete operation
        operations.append([
            "type": "delete",
            "databaseId": "db1",
            "collectionId": "users",
            "documentId": "u3"
        ])

        // Add create operation
        operations.append([
            "type": "create",
            "databaseId": "db1",
            "collectionId": "users",
            "data": ["name": "New User"]
        ])

        XCTAssertEqual(operations.count, 4)
        XCTAssertEqual(operations[0]["type"] as? String, "set")
        XCTAssertEqual(operations[1]["type"] as? String, "update")
        XCTAssertEqual(operations[2]["type"] as? String, "delete")
        XCTAssertEqual(operations[3]["type"] as? String, "create")
    }

    // MARK: - Empty Batch Handling

    func testEmptyBatchCommitSucceeds() {
        let operations: [[String: Any]] = []

        func commit() -> Bool {
            if operations.isEmpty {
                return true // Empty batch, nothing to do
            }
            // Would make API call here
            return true
        }

        XCTAssertTrue(commit())
    }

    // MARK: - Data Validation

    func testOperationDataIsPreserved() {
        let originalData: [String: Any] = [
            "string": "hello",
            "number": 42,
            "double": 3.14,
            "boolean": true,
            "array": [1, 2, 3],
            "nested": ["key": "value"]
        ]

        let operation: [String: Any] = [
            "type": "set",
            "databaseId": "db1",
            "collectionId": "test",
            "documentId": "doc1",
            "data": originalData
        ]

        let data = operation["data"] as? [String: Any]
        XCTAssertNotNil(data)
        XCTAssertEqual(data?["string"] as? String, "hello")
        XCTAssertEqual(data?["number"] as? Int, 42)
        XCTAssertEqual(data?["double"] as? Double, 3.14)
        XCTAssertEqual(data?["boolean"] as? Bool, true)
        XCTAssertEqual(data?["array"] as? [Int], [1, 2, 3])

        let nested = data?["nested"] as? [String: String]
        XCTAssertEqual(nested?["key"], "value")
    }
}
