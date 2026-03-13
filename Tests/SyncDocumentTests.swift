import XCTest
@testable import RiviumSync

/// Comprehensive tests for SyncDocument struct
/// Tests all public methods: get, getString, getInt, getDouble, getBool, getArray, getDictionary, contains, exists, toDict
final class SyncDocumentTests: XCTestCase {

    let now = Date().timeIntervalSince1970 * 1000

    // MARK: - Basic Properties

    func testSyncDocumentStoresAllPropertiesCorrectly() {
        let data: [String: Any] = ["name": "John", "age": 30]
        let doc = SyncDocument(
            id: "doc-123",
            data: data,
            createdAt: 1704067200000,
            updatedAt: 1704153600000,
            version: 5
        )

        XCTAssertEqual(doc.id, "doc-123")
        XCTAssertEqual(doc.getString("name"), "John")
        XCTAssertEqual(doc.getInt("age"), 30)
        XCTAssertEqual(doc.createdAt, 1704067200000)
        XCTAssertEqual(doc.updatedAt, 1704153600000)
        XCTAssertEqual(doc.version, 5)
    }

    func testSyncDocumentWithEmptyData() {
        let doc = SyncDocument(id: "doc-1", data: [:], createdAt: now, updatedAt: now, version: 1)

        XCTAssertTrue(doc.data.isEmpty)
        XCTAssertTrue(doc.exists)
    }

    // MARK: - exists

    func testExistsReturnsTrueForValidId() {
        let doc = SyncDocument(id: "doc-1", data: [:], createdAt: now, updatedAt: now, version: 1)
        XCTAssertTrue(doc.exists)
    }

    func testExistsReturnsFalseForEmptyId() {
        let doc = SyncDocument(id: "", data: [:], createdAt: now, updatedAt: now, version: 1)
        XCTAssertFalse(doc.exists)
    }

    func testExistsReturnsTrueForWhitespaceId() {
        let doc = SyncDocument(id: "   ", data: [:], createdAt: now, updatedAt: now, version: 1)
        XCTAssertTrue(doc.exists) // whitespace is still a non-empty string
    }

    // MARK: - contains()

    func testContainsReturnsTrueForExistingField() {
        let doc = SyncDocument(id: "doc-1", data: ["name": "John"], createdAt: now, updatedAt: now, version: 1)
        XCTAssertTrue(doc.contains("name"))
    }

    func testContainsReturnsFalseForNonExistingField() {
        let doc = SyncDocument(id: "doc-1", data: ["name": "John"], createdAt: now, updatedAt: now, version: 1)
        XCTAssertFalse(doc.contains("age"))
    }

    // MARK: - get<T>() generic method

    func testGetReturnsValueWithCorrectType() {
        let doc = SyncDocument(id: "doc-1", data: ["name": "John", "count": 42], createdAt: now, updatedAt: now, version: 1)

        let name: String? = doc.get("name")
        let count: Int? = doc.get("count")

        XCTAssertEqual(name, "John")
        XCTAssertEqual(count, 42)
    }

    func testGetReturnsNilForNonExistingField() {
        let doc = SyncDocument(id: "doc-1", data: ["name": "John"], createdAt: now, updatedAt: now, version: 1)

        let result: String? = doc.get("nonexistent")

        XCTAssertNil(result)
    }

    // MARK: - getString()

    func testGetStringReturnsStringValue() {
        let doc = SyncDocument(id: "doc-1", data: ["name": "John Doe"], createdAt: now, updatedAt: now, version: 1)
        XCTAssertEqual(doc.getString("name"), "John Doe")
    }

    func testGetStringReturnsNilForNonExistingField() {
        let doc = SyncDocument(id: "doc-1", data: [:], createdAt: now, updatedAt: now, version: 1)
        XCTAssertNil(doc.getString("name"))
    }

    func testGetStringReturnsNilForNonStringValue() {
        let doc = SyncDocument(id: "doc-1", data: ["age": 30], createdAt: now, updatedAt: now, version: 1)
        XCTAssertNil(doc.getString("age"))
    }

    func testGetStringHandlesEmptyString() {
        let doc = SyncDocument(id: "doc-1", data: ["name": ""], createdAt: now, updatedAt: now, version: 1)
        XCTAssertEqual(doc.getString("name"), "")
    }

    // MARK: - getInt()

    func testGetIntReturnsIntegerValue() {
        let doc = SyncDocument(id: "doc-1", data: ["age": 30], createdAt: now, updatedAt: now, version: 1)
        XCTAssertEqual(doc.getInt("age"), 30)
    }

    func testGetIntConvertsDoubleToInt() {
        let doc = SyncDocument(id: "doc-1", data: ["age": 30.0], createdAt: now, updatedAt: now, version: 1)
        XCTAssertEqual(doc.getInt("age"), 30)
    }

    func testGetIntReturnsNilForNonExistingField() {
        let doc = SyncDocument(id: "doc-1", data: [:], createdAt: now, updatedAt: now, version: 1)
        XCTAssertNil(doc.getInt("age"))
    }

    func testGetIntReturnsNilForStringValue() {
        let doc = SyncDocument(id: "doc-1", data: ["age": "thirty"], createdAt: now, updatedAt: now, version: 1)
        XCTAssertNil(doc.getInt("age"))
    }

    func testGetIntHandlesZero() {
        let doc = SyncDocument(id: "doc-1", data: ["count": 0], createdAt: now, updatedAt: now, version: 1)
        XCTAssertEqual(doc.getInt("count"), 0)
    }

    func testGetIntHandlesNegative() {
        let doc = SyncDocument(id: "doc-1", data: ["balance": -100], createdAt: now, updatedAt: now, version: 1)
        XCTAssertEqual(doc.getInt("balance"), -100)
    }

    // MARK: - getDouble()

    func testGetDoubleReturnsDoubleValue() {
        let doc = SyncDocument(id: "doc-1", data: ["price": 19.99], createdAt: now, updatedAt: now, version: 1)
        let price = doc.getDouble("price")
        XCTAssertNotNil(price)
        XCTAssertEqual(price!, 19.99, accuracy: 0.001)
    }

    func testGetDoubleConvertsIntToDouble() {
        let doc = SyncDocument(id: "doc-1", data: ["price": 20], createdAt: now, updatedAt: now, version: 1)
        let price = doc.getDouble("price")
        XCTAssertNotNil(price)
        XCTAssertEqual(price!, 20.0, accuracy: 0.001)
    }

    func testGetDoubleReturnsNilForNonExistingField() {
        let doc = SyncDocument(id: "doc-1", data: [:], createdAt: now, updatedAt: now, version: 1)
        XCTAssertNil(doc.getDouble("price"))
    }

    func testGetDoubleReturnsNilForStringValue() {
        let doc = SyncDocument(id: "doc-1", data: ["price": "19.99"], createdAt: now, updatedAt: now, version: 1)
        XCTAssertNil(doc.getDouble("price"))
    }

    // MARK: - getBool()

    func testGetBoolReturnsTrueValue() {
        let doc = SyncDocument(id: "doc-1", data: ["active": true], createdAt: now, updatedAt: now, version: 1)
        XCTAssertEqual(doc.getBool("active"), true)
    }

    func testGetBoolReturnsFalseValue() {
        let doc = SyncDocument(id: "doc-1", data: ["active": false], createdAt: now, updatedAt: now, version: 1)
        XCTAssertEqual(doc.getBool("active"), false)
    }

    func testGetBoolReturnsNilForNonExistingField() {
        let doc = SyncDocument(id: "doc-1", data: [:], createdAt: now, updatedAt: now, version: 1)
        XCTAssertNil(doc.getBool("active"))
    }

    func testGetBoolReturnsNilForStringValue() {
        let doc = SyncDocument(id: "doc-1", data: ["active": "true"], createdAt: now, updatedAt: now, version: 1)
        XCTAssertNil(doc.getBool("active"))
    }

    // MARK: - getArray()

    func testGetArrayReturnsArrayOfStrings() {
        let doc = SyncDocument(id: "doc-1", data: ["tags": ["swift", "ios", "sdk"]], createdAt: now, updatedAt: now, version: 1)
        let tags: [String]? = doc.getArray("tags")
        XCTAssertEqual(tags, ["swift", "ios", "sdk"])
    }

    func testGetArrayReturnsArrayOfInts() {
        let doc = SyncDocument(id: "doc-1", data: ["scores": [100, 95, 88]], createdAt: now, updatedAt: now, version: 1)
        let scores: [Int]? = doc.getArray("scores")
        XCTAssertEqual(scores, [100, 95, 88])
    }

    func testGetArrayReturnsNilForNonExistingField() {
        let doc = SyncDocument(id: "doc-1", data: [:], createdAt: now, updatedAt: now, version: 1)
        let tags: [String]? = doc.getArray("tags")
        XCTAssertNil(tags)
    }

    func testGetArrayReturnsEmptyArray() {
        let doc = SyncDocument(id: "doc-1", data: ["tags": [String]()], createdAt: now, updatedAt: now, version: 1)
        let tags: [String]? = doc.getArray("tags")
        XCTAssertEqual(tags, [])
    }

    // MARK: - getDictionary()

    func testGetDictionaryReturnsNestedDict() {
        let address: [String: Any] = ["city": "NYC", "zip": "10001"]
        let doc = SyncDocument(id: "doc-1", data: ["address": address], createdAt: now, updatedAt: now, version: 1)

        let result = doc.getDictionary("address")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?["city"] as? String, "NYC")
        XCTAssertEqual(result?["zip"] as? String, "10001")
    }

    func testGetDictionaryReturnsNilForNonExistingField() {
        let doc = SyncDocument(id: "doc-1", data: [:], createdAt: now, updatedAt: now, version: 1)
        XCTAssertNil(doc.getDictionary("address"))
    }

    func testGetDictionaryReturnsNilForNonDictValue() {
        let doc = SyncDocument(id: "doc-1", data: ["address": "123 Main St"], createdAt: now, updatedAt: now, version: 1)
        XCTAssertNil(doc.getDictionary("address"))
    }

    // MARK: - toDict()

    func testToDictReturnsAllFields() {
        let doc = SyncDocument(
            id: "doc-123",
            data: ["name": "John"],
            createdAt: 1704067200000,
            updatedAt: 1704153600000,
            version: 3
        )

        let dict = doc.toDict()

        XCTAssertEqual(dict["id"] as? String, "doc-123")
        XCTAssertEqual(dict["createdAt"] as? TimeInterval, 1704067200000)
        XCTAssertEqual(dict["updatedAt"] as? TimeInterval, 1704153600000)
        XCTAssertEqual(dict["version"] as? Int, 3)

        let data = dict["data"] as? [String: Any]
        XCTAssertEqual(data?["name"] as? String, "John")
    }

    // MARK: - Complex Data Types

    func testComplexNestedData() {
        let complexData: [String: Any] = [
            "user": [
                "name": "John",
                "age": 30,
                "addresses": [
                    ["city": "NYC", "zip": "10001"],
                    ["city": "LA", "zip": "90001"]
                ]
            ],
            "tags": ["vip", "premium"],
            "active": true,
            "score": 95.5
        ]

        let doc = SyncDocument(id: "doc-1", data: complexData, createdAt: now, updatedAt: now, version: 1)

        // Verify top-level fields
        XCTAssertTrue(doc.contains("user"))
        XCTAssertTrue(doc.contains("tags"))
        XCTAssertEqual(doc.getBool("active"), true)
        let score = doc.getDouble("score")
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 95.5, accuracy: 0.001)

        // Verify nested user
        let user = doc.getDictionary("user")
        XCTAssertNotNil(user)
        XCTAssertEqual(user?["name"] as? String, "John")
        XCTAssertEqual(user?["age"] as? Int, 30)
    }

    // MARK: - Edge Cases

    func testSpecialCharactersInData() {
        let doc = SyncDocument(
            id: "doc-1",
            data: [
                "emoji": "Hello 😀 World 🌍",
                "unicode": "日本語テスト",
                "special": "!@#$%^&*()_+-={}[]|\\:\";<>?,./~`"
            ],
            createdAt: now,
            updatedAt: now,
            version: 1
        )

        XCTAssertEqual(doc.getString("emoji"), "Hello 😀 World 🌍")
        XCTAssertEqual(doc.getString("unicode"), "日本語テスト")
        XCTAssertEqual(doc.getString("special"), "!@#$%^&*()_+-={}[]|\\:\";<>?,./~`")
    }

    func testLargeNumbers() {
        let doc = SyncDocument(
            id: "doc-1",
            data: [
                "bigInt": Int.max,
                "smallInt": Int.min,
                "bigDouble": Double.greatestFiniteMagnitude
            ],
            createdAt: now,
            updatedAt: now,
            version: 1
        )

        XCTAssertEqual(doc.getInt("bigInt"), Int.max)
        XCTAssertEqual(doc.getInt("smallInt"), Int.min)
    }
}
