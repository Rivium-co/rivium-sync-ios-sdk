import XCTest
@testable import RiviumSync

/// Tests for RiviumSyncError enum
final class RiviumSyncErrorTests: XCTestCase {

    // MARK: - Error Creation

    func testNotInitializedError() {
        let error = RiviumSyncError.notInitialized

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not initialized"))
    }

    func testNetworkErrorWithMessage() {
        let error = RiviumSyncError.networkError("Connection refused", nil)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Network error"))
        XCTAssertTrue(error.errorDescription!.contains("Connection refused"))
    }

    func testNetworkErrorWithUnderlyingError() {
        let underlying = NSError(domain: "test", code: -1, userInfo: nil)
        let error = RiviumSyncError.networkError("Connection failed", underlying)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Connection failed"))
    }

    func testAuthenticationError() {
        let error = RiviumSyncError.authenticationError("Invalid API key")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Authentication error"))
        XCTAssertTrue(error.errorDescription!.contains("Invalid API key"))
    }

    func testDatabaseError() {
        let error = RiviumSyncError.databaseError("Database not found")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Database error"))
        XCTAssertTrue(error.errorDescription!.contains("Database not found"))
    }

    func testCollectionError() {
        let error = RiviumSyncError.collectionError("Collection does not exist")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Collection error"))
        XCTAssertTrue(error.errorDescription!.contains("Collection does not exist"))
    }

    func testDocumentError() {
        let error = RiviumSyncError.documentError("Document not found")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Document error"))
        XCTAssertTrue(error.errorDescription!.contains("Document not found"))
    }

    func testConnectionErrorWithMessage() {
        let error = RiviumSyncError.connectionError("MQTT connection lost", nil)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Connection error"))
        XCTAssertTrue(error.errorDescription!.contains("MQTT connection lost"))
    }

    func testConnectionErrorWithUnderlyingError() {
        let underlying = NSError(domain: "mqtt", code: 100, userInfo: nil)
        let error = RiviumSyncError.connectionError("Broker unavailable", underlying)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Broker unavailable"))
    }

    func testTimeoutError() {
        let error = RiviumSyncError.timeoutError("Request timed out after 30 seconds")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Timeout error"))
        XCTAssertTrue(error.errorDescription!.contains("Request timed out"))
    }

    func testPermissionError() {
        let error = RiviumSyncError.permissionError("Access denied to collection")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Permission error"))
        XCTAssertTrue(error.errorDescription!.contains("Access denied"))
    }

    func testInvalidResponseError() {
        let error = RiviumSyncError.invalidResponse("Unexpected JSON format")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Invalid response"))
        XCTAssertTrue(error.errorDescription!.contains("Unexpected JSON format"))
    }

    func testBatchWriteError() {
        let error = RiviumSyncError.batchWriteError("Batch exceeded 500 operations limit")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Batch write error"))
        XCTAssertTrue(error.errorDescription!.contains("500 operations"))
    }

    func testTransactionError() {
        let error = RiviumSyncError.transactionError("Transaction conflict detected")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Transaction error"))
        XCTAssertTrue(error.errorDescription!.contains("Transaction conflict"))
    }

    func testUnknownErrorWithUnderlyingError() {
        let underlying = NSError(domain: "unknown", code: 999, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
        let error = RiviumSyncError.unknown(underlying)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Something went wrong"))
    }

    func testUnknownErrorWithNilError() {
        let error = RiviumSyncError.unknown(nil)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Unknown error"))
    }

    // MARK: - Error Conforms to Error Protocol

    func testErrorConformsToErrorProtocol() {
        let errors: [Error] = [
            RiviumSyncError.notInitialized,
            RiviumSyncError.networkError("test", nil),
            RiviumSyncError.authenticationError("test"),
            RiviumSyncError.databaseError("test"),
            RiviumSyncError.collectionError("test"),
            RiviumSyncError.documentError("test"),
            RiviumSyncError.connectionError("test", nil),
            RiviumSyncError.timeoutError("test"),
            RiviumSyncError.permissionError("test"),
            RiviumSyncError.invalidResponse("test"),
            RiviumSyncError.batchWriteError("test"),
            RiviumSyncError.transactionError("test"),
            RiviumSyncError.unknown(nil)
        ]

        XCTAssertEqual(errors.count, 13)
        for error in errors {
            XCTAssertNotNil(error.localizedDescription)
        }
    }

    // MARK: - Pattern Matching

    func testPatternMatchingNetworkError() {
        let error: RiviumSyncError = .networkError("Connection failed", nil)

        switch error {
        case .networkError(let message, _):
            XCTAssertEqual(message, "Connection failed")
        default:
            XCTFail("Expected networkError")
        }
    }

    func testPatternMatchingDocumentError() {
        let error: RiviumSyncError = .documentError("Not found")

        switch error {
        case .documentError(let message):
            XCTAssertEqual(message, "Not found")
        default:
            XCTFail("Expected documentError")
        }
    }

    // MARK: - Exhaustive Switch

    func testExhaustiveSwitchCoversAllCases() {
        let errors: [RiviumSyncError] = [
            .notInitialized,
            .networkError("", nil),
            .authenticationError(""),
            .databaseError(""),
            .collectionError(""),
            .documentError(""),
            .connectionError("", nil),
            .timeoutError(""),
            .permissionError(""),
            .invalidResponse(""),
            .batchWriteError(""),
            .transactionError(""),
            .unknown(nil)
        ]

        for error in errors {
            let description: String
            switch error {
            case .notInitialized:
                description = "notInitialized"
            case .networkError:
                description = "networkError"
            case .authenticationError:
                description = "authenticationError"
            case .databaseError:
                description = "databaseError"
            case .collectionError:
                description = "collectionError"
            case .documentError:
                description = "documentError"
            case .connectionError:
                description = "connectionError"
            case .timeoutError:
                description = "timeoutError"
            case .permissionError:
                description = "permissionError"
            case .invalidResponse:
                description = "invalidResponse"
            case .batchWriteError:
                description = "batchWriteError"
            case .transactionError:
                description = "transactionError"
            case .unknown:
                description = "unknown"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }
}
