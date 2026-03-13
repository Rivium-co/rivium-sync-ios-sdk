import XCTest
@testable import RiviumSync

/// Tests for conflict resolution: ConflictStrategy, ConflictChoice, ConflictInfo, ConflictResolver
final class ConflictResolutionTests: XCTestCase {

    // MARK: - ConflictStrategy

    func testConflictStrategyServerWins() {
        let strategy = ConflictStrategy.serverWins
        XCTAssertNotNil(strategy)
    }

    func testConflictStrategyClientWins() {
        let strategy = ConflictStrategy.clientWins
        XCTAssertNotNil(strategy)
    }

    func testConflictStrategyMerge() {
        let strategy = ConflictStrategy.merge
        XCTAssertNotNil(strategy)
    }

    func testConflictStrategyManual() {
        let strategy = ConflictStrategy.manual
        XCTAssertNotNil(strategy)
    }

    func testConflictStrategyAllCasesCount() {
        let allCases: [ConflictStrategy] = [.serverWins, .clientWins, .merge, .manual]
        XCTAssertEqual(allCases.count, 4)
    }

    func testConflictStrategyEquality() {
        XCTAssertTrue(ConflictStrategy.serverWins == ConflictStrategy.serverWins)
        XCTAssertFalse(ConflictStrategy.serverWins == ConflictStrategy.clientWins)
    }

    // MARK: - ConflictChoice

    func testConflictChoiceUseLocal() {
        let choice = ConflictChoice.useLocal
        XCTAssertNotNil(choice)
    }

    func testConflictChoiceUseServer() {
        let choice = ConflictChoice.useServer
        XCTAssertNotNil(choice)
    }

    func testConflictChoiceUseMerged() {
        let choice = ConflictChoice.useMerged
        XCTAssertNotNil(choice)
    }

    func testConflictChoiceAllCasesCount() {
        let allCases: [ConflictChoice] = [.useLocal, .useServer, .useMerged]
        XCTAssertEqual(allCases.count, 3)
    }

    func testConflictChoiceEquality() {
        XCTAssertTrue(ConflictChoice.useLocal == ConflictChoice.useLocal)
        XCTAssertFalse(ConflictChoice.useLocal == ConflictChoice.useServer)
    }

    // MARK: - ConflictInfo

    func testConflictInfoCreation() {
        let info = ConflictInfo(
            documentId: "doc-123",
            databaseId: "db-456",
            collectionId: "users",
            localData: ["name": "Local Name", "age": 30],
            serverData: ["name": "Server Name", "age": 31],
            localVersion: 2,
            serverVersion: 3
        )

        XCTAssertEqual(info.documentId, "doc-123")
        XCTAssertEqual(info.databaseId, "db-456")
        XCTAssertEqual(info.collectionId, "users")
        XCTAssertEqual(info.localData["name"] as? String, "Local Name")
        XCTAssertEqual(info.localData["age"] as? Int, 30)
        XCTAssertEqual(info.serverData["name"] as? String, "Server Name")
        XCTAssertEqual(info.serverData["age"] as? Int, 31)
        XCTAssertEqual(info.localVersion, 2)
        XCTAssertEqual(info.serverVersion, 3)
    }

    func testConflictInfoWithEmptyData() {
        let info = ConflictInfo(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            localData: [:],
            serverData: [:],
            localVersion: 1,
            serverVersion: 1
        )

        XCTAssertTrue(info.localData.isEmpty)
        XCTAssertTrue(info.serverData.isEmpty)
    }

    func testConflictInfoWithComplexData() {
        let localData: [String: Any] = [
            "name": "John",
            "address": ["city": "NYC", "zip": "10001"],
            "tags": ["vip", "premium"]
        ]
        let serverData: [String: Any] = [
            "name": "John Doe",
            "address": ["city": "LA", "zip": "90001"],
            "tags": ["vip"]
        ]

        let info = ConflictInfo(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "users",
            localData: localData,
            serverData: serverData,
            localVersion: 5,
            serverVersion: 6
        )

        XCTAssertEqual(info.localData["name"] as? String, "John")
        XCTAssertEqual(info.serverData["name"] as? String, "John Doe")

        let localAddress = info.localData["address"] as? [String: Any]
        XCTAssertEqual(localAddress?["city"] as? String, "NYC")

        let serverAddress = info.serverData["address"] as? [String: Any]
        XCTAssertEqual(serverAddress?["city"] as? String, "LA")
    }

    // MARK: - ConflictResolver Protocol

    func testCustomConflictResolverUseLocal() {
        class LocalWinsResolver: ConflictResolver {
            func resolve(conflict: ConflictInfo) -> (ConflictChoice, [String: Any]?) {
                return (.useLocal, nil)
            }
        }

        let resolver = LocalWinsResolver()
        let conflict = ConflictInfo(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "users",
            localData: ["name": "Local"],
            serverData: ["name": "Server"],
            localVersion: 1,
            serverVersion: 2
        )

        let (choice, mergedData) = resolver.resolve(conflict: conflict)

        XCTAssertEqual(choice, .useLocal)
        XCTAssertNil(mergedData)
    }

    func testCustomConflictResolverUseServer() {
        class ServerWinsResolver: ConflictResolver {
            func resolve(conflict: ConflictInfo) -> (ConflictChoice, [String: Any]?) {
                return (.useServer, nil)
            }
        }

        let resolver = ServerWinsResolver()
        let conflict = ConflictInfo(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "users",
            localData: ["name": "Local"],
            serverData: ["name": "Server"],
            localVersion: 1,
            serverVersion: 2
        )

        let (choice, mergedData) = resolver.resolve(conflict: conflict)

        XCTAssertEqual(choice, .useServer)
        XCTAssertNil(mergedData)
    }

    func testCustomConflictResolverUseMerged() {
        class MergingResolver: ConflictResolver {
            func resolve(conflict: ConflictInfo) -> (ConflictChoice, [String: Any]?) {
                // Take name from local, age from server
                var merged: [String: Any] = [:]
                merged["name"] = conflict.localData["name"]
                merged["age"] = conflict.serverData["age"]
                merged["version"] = max(conflict.localVersion, conflict.serverVersion)
                return (.useMerged, merged)
            }
        }

        let resolver = MergingResolver()
        let conflict = ConflictInfo(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "users",
            localData: ["name": "Local Name", "age": 25],
            serverData: ["name": "Server Name", "age": 30],
            localVersion: 3,
            serverVersion: 5
        )

        let (choice, mergedData) = resolver.resolve(conflict: conflict)

        XCTAssertEqual(choice, .useMerged)
        XCTAssertNotNil(mergedData)
        XCTAssertEqual(mergedData?["name"] as? String, "Local Name")
        XCTAssertEqual(mergedData?["age"] as? Int, 30)
        XCTAssertEqual(mergedData?["version"] as? Int, 5)
    }

    func testCustomConflictResolverVersionBasedDecision() {
        class VersionBasedResolver: ConflictResolver {
            func resolve(conflict: ConflictInfo) -> (ConflictChoice, [String: Any]?) {
                if conflict.serverVersion > conflict.localVersion {
                    return (.useServer, nil)
                } else {
                    return (.useLocal, nil)
                }
            }
        }

        let resolver = VersionBasedResolver()

        // Server has higher version
        let conflict1 = ConflictInfo(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "users",
            localData: [:],
            serverData: [:],
            localVersion: 3,
            serverVersion: 5
        )
        let (choice1, _) = resolver.resolve(conflict: conflict1)
        XCTAssertEqual(choice1, .useServer)

        // Local has higher or equal version
        let conflict2 = ConflictInfo(
            documentId: "doc-2",
            databaseId: "db-1",
            collectionId: "users",
            localData: [:],
            serverData: [:],
            localVersion: 5,
            serverVersion: 3
        )
        let (choice2, _) = resolver.resolve(conflict: conflict2)
        XCTAssertEqual(choice2, .useLocal)
    }

    // MARK: - Exhaustive Switch Tests

    func testConflictStrategyExhaustiveSwitch() {
        let strategies: [ConflictStrategy] = [.serverWins, .clientWins, .merge, .manual]

        for strategy in strategies {
            let description: String
            switch strategy {
            case .serverWins:
                description = "Server wins"
            case .clientWins:
                description = "Client wins"
            case .merge:
                description = "Merge data"
            case .manual:
                description = "Manual resolution"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }

    func testConflictChoiceExhaustiveSwitch() {
        let choices: [ConflictChoice] = [.useLocal, .useServer, .useMerged]

        for choice in choices {
            let description: String
            switch choice {
            case .useLocal:
                description = "Use local"
            case .useServer:
                description = "Use server"
            case .useMerged:
                description = "Use merged"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }
}
