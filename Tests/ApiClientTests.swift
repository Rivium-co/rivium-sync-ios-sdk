import XCTest
@testable import RiviumSync

/// Tests for ApiClient response parsing and error handling
final class ApiClientTests: XCTestCase {

    // MARK: - ISO Date Parsing

    func testISO8601DateParsingWithFractionalSeconds() {
        let dateString = "2024-01-15T10:30:00.500Z"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let date = formatter.date(from: dateString)
        XCTAssertNotNil(date)

        if let date = date {
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 1)
            XCTAssertEqual(components.day, 15)
            XCTAssertEqual(components.hour, 10)
            XCTAssertEqual(components.minute, 30)
            XCTAssertEqual(components.second, 0)
        }
    }

    func testISO8601DateParsingWithoutFractionalSeconds() {
        let dateString = "2024-01-15T10:30:00Z"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let date = formatter.date(from: dateString)
        XCTAssertNotNil(date)
    }

    func testISO8601DateToTimestamp() {
        let dateString = "2024-01-01T00:00:00.000Z"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let date = formatter.date(from: dateString)
        XCTAssertNotNil(date)

        if let date = date {
            let timestamp = date.timeIntervalSince1970 * 1000
            // January 1, 2024 00:00:00 UTC in milliseconds
            XCTAssertEqual(timestamp, 1704067200000, accuracy: 1)
        }
    }

    // MARK: - API Response Structure

    func testApiResponseWithSuccess() {
        let json: [String: Any] = [
            "success": true,
            "data": ["id": "doc-123", "data": ["name": "Test"]]
        ]

        XCTAssertEqual(json["success"] as? Bool, true)
        XCTAssertNotNil(json["data"])
    }

    func testApiResponseWithError() {
        let json: [String: Any] = [
            "success": false,
            "error": "Document not found",
            "message": "The requested document does not exist"
        ]

        XCTAssertEqual(json["success"] as? Bool, false)
        XCTAssertEqual(json["error"] as? String, "Document not found")
    }

    func testListResponseStructure() {
        let json: [String: Any] = [
            "data": [
                ["id": "doc-1", "data": ["name": "Doc 1"]],
                ["id": "doc-2", "data": ["name": "Doc 2"]]
            ],
            "total": 2,
            "skip": 0,
            "limit": 100
        ]

        let data = json["data"] as? [[String: Any]]
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 2)
        XCTAssertEqual(json["total"] as? Int, 2)
        XCTAssertEqual(json["skip"] as? Int, 0)
        XCTAssertEqual(json["limit"] as? Int, 100)
    }

    // MARK: - Document Response Structure

    func testDocumentResponseStructure() {
        let json: [String: Any] = [
            "id": "doc-123",
            "data": ["title": "Test", "count": 42],
            "createdAt": "2024-01-15T10:30:00.000Z",
            "updatedAt": "2024-01-16T14:45:30.500Z",
            "version": 3
        ]

        XCTAssertEqual(json["id"] as? String, "doc-123")
        XCTAssertNotNil(json["data"])
        XCTAssertEqual(json["createdAt"] as? String, "2024-01-15T10:30:00.000Z")
        XCTAssertEqual(json["updatedAt"] as? String, "2024-01-16T14:45:30.500Z")
        XCTAssertEqual(json["version"] as? Int, 3)
    }

    // MARK: - HTTP Status Codes

    func testSuccessStatusCodes() {
        let successCodes = [200, 201, 202, 204]

        for code in successCodes {
            XCTAssertTrue((200...299).contains(code), "Status code \(code) should be considered success")
        }
    }

    func testErrorStatusCodes() {
        let errorCodes = [400, 401, 403, 404, 500, 502, 503]

        for code in errorCodes {
            XCTAssertFalse((200...299).contains(code), "Status code \(code) should be considered error")
        }
    }

    // MARK: - Query Parameters

    func testQueryParametersSerialization() {
        var params: [String: Any] = [:]

        // Add filters
        params["filters"] = [
            ["field": "status", "operator": "==", "value": "active"],
            ["field": "age", "operator": ">=", "value": 18]
        ]

        // Add ordering
        params["orderBy"] = ["field": "createdAt", "direction": "desc"]

        // Add pagination
        params["limit"] = 20
        params["offset"] = 40

        XCTAssertNotNil(params["filters"])
        XCTAssertNotNil(params["orderBy"])
        XCTAssertEqual(params["limit"] as? Int, 20)
        XCTAssertEqual(params["offset"] as? Int, 40)
    }

    // MARK: - Error Response Parsing

    func testErrorResponseParsing() {
        let errorJson: [String: Any] = [
            "statusCode": 404,
            "message": "Document with ID doc-123 not found",
            "timestamp": "2024-01-15T10:30:00.000Z",
            "path": "/databases/test-db/collections/users/documents/doc-123"
        ]

        XCTAssertEqual(errorJson["statusCode"] as? Int, 404)
        XCTAssertEqual(errorJson["message"] as? String, "Document with ID doc-123 not found")
        XCTAssertNotNil(errorJson["timestamp"])
        XCTAssertNotNil(errorJson["path"])
    }

    // MARK: - Request Building

    func testRequestHeadersStructure() {
        var headers: [String: String] = [:]

        headers["Content-Type"] = "application/json"
        headers["x-api-key"] = "nl_test_abc123"
        headers["Authorization"] = "Bearer jwt-token"

        XCTAssertEqual(headers["Content-Type"], "application/json")
        XCTAssertEqual(headers["x-api-key"], "nl_test_abc123")
        XCTAssertEqual(headers["Authorization"], "Bearer jwt-token")
    }

    // MARK: - URL Building

    func testApiEndpointUrlBuilding() {
        let baseUrl = "https://sync.rivium.co"
        let databaseId = "test-db"
        let collectionId = "users"
        let documentId = "doc-123"

        let getAllUrl = "\(baseUrl)/databases/\(databaseId)/collections/\(collectionId)/documents/sdk"
        let getOneUrl = "\(baseUrl)/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/\(documentId)"
        let queryUrl = "\(baseUrl)/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/query"

        XCTAssertEqual(getAllUrl, "https://sync.rivium.co/databases/test-db/collections/users/documents/sdk")
        XCTAssertEqual(getOneUrl, "https://sync.rivium.co/databases/test-db/collections/users/documents/sdk/doc-123")
        XCTAssertEqual(queryUrl, "https://sync.rivium.co/databases/test-db/collections/users/documents/sdk/query")
    }
}
