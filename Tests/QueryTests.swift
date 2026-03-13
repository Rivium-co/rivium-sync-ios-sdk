import XCTest
@testable import RiviumSync

/// Tests for query-related enums: QueryOperator, OrderDirection
final class QueryTests: XCTestCase {

    // MARK: - QueryOperator

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

    func testQueryOperatorAllCasesCount() {
        let allCases: [QueryOperator] = [
            .equal, .notEqual, .greaterThan, .greaterThanOrEqual,
            .lessThan, .lessThanOrEqual, .arrayContains, .in, .notIn
        ]
        XCTAssertEqual(allCases.count, 9)
    }

    func testQueryOperatorFromRawValue() {
        XCTAssertEqual(QueryOperator(rawValue: "=="), .equal)
        XCTAssertEqual(QueryOperator(rawValue: "!="), .notEqual)
        XCTAssertEqual(QueryOperator(rawValue: ">"), .greaterThan)
        XCTAssertEqual(QueryOperator(rawValue: ">="), .greaterThanOrEqual)
        XCTAssertEqual(QueryOperator(rawValue: "<"), .lessThan)
        XCTAssertEqual(QueryOperator(rawValue: "<="), .lessThanOrEqual)
        XCTAssertEqual(QueryOperator(rawValue: "array-contains"), .arrayContains)
        XCTAssertEqual(QueryOperator(rawValue: "in"), .in)
        XCTAssertEqual(QueryOperator(rawValue: "not-in"), .notIn)
    }

    func testQueryOperatorInvalidRawValue() {
        XCTAssertNil(QueryOperator(rawValue: "invalid"))
        XCTAssertNil(QueryOperator(rawValue: ""))
        XCTAssertNil(QueryOperator(rawValue: "equals"))
    }

    func testQueryOperatorEquality() {
        XCTAssertEqual(QueryOperator.equal, QueryOperator.equal)
        XCTAssertNotEqual(QueryOperator.equal, QueryOperator.notEqual)
    }

    // MARK: - OrderDirection

    func testOrderDirectionAscendingRawValue() {
        XCTAssertEqual(OrderDirection.ascending.rawValue, "asc")
    }

    func testOrderDirectionDescendingRawValue() {
        XCTAssertEqual(OrderDirection.descending.rawValue, "desc")
    }

    func testOrderDirectionAllCasesCount() {
        let allCases: [OrderDirection] = [.ascending, .descending]
        XCTAssertEqual(allCases.count, 2)
    }

    func testOrderDirectionFromRawValue() {
        XCTAssertEqual(OrderDirection(rawValue: "asc"), .ascending)
        XCTAssertEqual(OrderDirection(rawValue: "desc"), .descending)
    }

    func testOrderDirectionInvalidRawValue() {
        XCTAssertNil(OrderDirection(rawValue: "invalid"))
        XCTAssertNil(OrderDirection(rawValue: ""))
        XCTAssertNil(OrderDirection(rawValue: "ASC")) // case sensitive
    }

    func testOrderDirectionEquality() {
        XCTAssertEqual(OrderDirection.ascending, OrderDirection.ascending)
        XCTAssertNotEqual(OrderDirection.ascending, OrderDirection.descending)
    }

    // MARK: - Exhaustive Switch Tests

    func testQueryOperatorExhaustiveSwitch() {
        let operators: [QueryOperator] = [
            .equal, .notEqual, .greaterThan, .greaterThanOrEqual,
            .lessThan, .lessThanOrEqual, .arrayContains, .in, .notIn
        ]

        for op in operators {
            let description: String
            switch op {
            case .equal:
                description = "Equal to"
            case .notEqual:
                description = "Not equal to"
            case .greaterThan:
                description = "Greater than"
            case .greaterThanOrEqual:
                description = "Greater than or equal"
            case .lessThan:
                description = "Less than"
            case .lessThanOrEqual:
                description = "Less than or equal"
            case .arrayContains:
                description = "Array contains"
            case .in:
                description = "In array"
            case .notIn:
                description = "Not in array"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }

    func testOrderDirectionExhaustiveSwitch() {
        let directions: [OrderDirection] = [.ascending, .descending]

        for direction in directions {
            let description: String
            switch direction {
            case .ascending:
                description = "Ascending order"
            case .descending:
                description = "Descending order"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }

    // MARK: - Hashable Tests

    func testQueryOperatorHashable() {
        var set = Set<QueryOperator>()
        set.insert(.equal)
        set.insert(.greaterThan)
        set.insert(.equal) // duplicate

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(.equal))
        XCTAssertTrue(set.contains(.greaterThan))
    }

    func testOrderDirectionHashable() {
        var set = Set<OrderDirection>()
        set.insert(.ascending)
        set.insert(.descending)
        set.insert(.ascending) // duplicate

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(.ascending))
        XCTAssertTrue(set.contains(.descending))
    }

    // MARK: - Dictionary Key Tests

    func testQueryOperatorAsDictionaryKey() {
        var dict = [QueryOperator: String]()
        dict[.equal] = "equals"
        dict[.greaterThan] = "gt"

        XCTAssertEqual(dict[.equal], "equals")
        XCTAssertEqual(dict[.greaterThan], "gt")
        XCTAssertNil(dict[.lessThan])
    }

    func testOrderDirectionAsDictionaryKey() {
        var dict = [OrderDirection: String]()
        dict[.ascending] = "asc"
        dict[.descending] = "desc"

        XCTAssertEqual(dict[.ascending], "asc")
        XCTAssertEqual(dict[.descending], "desc")
    }
}
