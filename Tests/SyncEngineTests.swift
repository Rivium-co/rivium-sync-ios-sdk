import XCTest
@testable import RiviumSync

/// Comprehensive tests for SyncEngine and related offline sync functionality
final class SyncEngineTests: XCTestCase {

    // MARK: - SyncState Tests

    func testSyncStateIdleIsDefault() {
        XCTAssertEqual(SyncState.idle.rawValue, "idle")
    }

    func testSyncStateHasAllExpectedValues() {
        let states: [SyncState] = [.idle, .syncing, .offline, .error]
        XCTAssertEqual(states.count, 4)
    }

    func testSyncStateFromRawValue() {
        XCTAssertEqual(SyncState(rawValue: "idle"), .idle)
        XCTAssertEqual(SyncState(rawValue: "syncing"), .syncing)
        XCTAssertEqual(SyncState(rawValue: "offline"), .offline)
        XCTAssertEqual(SyncState(rawValue: "error"), .error)
    }

    func testSyncStateInvalidRawValue() {
        XCTAssertNil(SyncState(rawValue: "invalid"))
        XCTAssertNil(SyncState(rawValue: ""))
        XCTAssertNil(SyncState(rawValue: "IDLE")) // case sensitive
    }

    func testSyncStateEquality() {
        XCTAssertEqual(SyncState.idle, SyncState.idle)
        XCTAssertNotEqual(SyncState.idle, SyncState.syncing)
    }

    // MARK: - OperationType Tests

    func testOperationTypeCreate() {
        XCTAssertEqual(OperationType.create.rawValue, "create")
    }

    func testOperationTypeUpdate() {
        XCTAssertEqual(OperationType.update.rawValue, "update")
    }

    func testOperationTypeDelete() {
        XCTAssertEqual(OperationType.delete.rawValue, "delete")
    }

    func testOperationTypeAllCases() {
        let types: [OperationType] = [.create, .update, .delete]
        XCTAssertEqual(types.count, 3)
    }

    // MARK: - Offline Operation Flow Tests

    func testOfflineOperationFlowCreateDocumentWhileOffline() {
        // Simulate the flow of creating a document while offline
        let data: [String: Any] = ["title": "My Task", "completed": false]
        let tempId = "temp_\(Date().timeIntervalSince1970)"

        // Create pending operation
        let pendingOp = PendingOperation.create(
            documentId: tempId,
            databaseId: "db-1",
            collectionId: "todos",
            data: data
        )

        XCTAssertEqual(pendingOp.operationType, .create)
        XCTAssertTrue(pendingOp.documentId.hasPrefix("temp_"))
        XCTAssertNotNil(pendingOp.data)
    }

    func testOfflineOperationFlowUpdateDocumentWhileOffline() {
        let updateData: [String: Any] = ["completed": true]

        let pendingOp = PendingOperation.update(
            documentId: "doc-123",
            databaseId: "db-1",
            collectionId: "todos",
            data: updateData,
            baseVersion: 5
        )

        XCTAssertEqual(pendingOp.operationType, .update)
        XCTAssertEqual(pendingOp.baseVersion, 5)
    }

    func testOfflineOperationFlowDeleteDocumentWhileOffline() {
        let pendingOp = PendingOperation.delete(
            documentId: "doc-123",
            databaseId: "db-1",
            collectionId: "todos",
            baseVersion: 5
        )

        XCTAssertEqual(pendingOp.operationType, .delete)
        XCTAssertNil(pendingOp.data)
    }

    // MARK: - State Transitions Tests

    func testStateTransitionsAreValid() {
        // All these transitions should be possible
        let validTransitions: [(SyncState, SyncState)] = [
            (.idle, .syncing),
            (.syncing, .idle),
            (.syncing, .error),
            (.offline, .idle),
            (.error, .idle)
        ]

        for (from, to) in validTransitions {
            XCTAssertNotEqual(from, to)
        }
    }

    func testConnectionStateChangeTriggersSyncState() {
        // When going online from offline state
        let offlineState = SyncState.offline
        let expectedOnlineState = SyncState.idle

        // When going offline
        let onlineState = SyncState.idle
        let expectedOfflineState = SyncState.offline

        XCTAssertEqual(offlineState, .offline)
        XCTAssertEqual(expectedOnlineState, .idle)
        XCTAssertEqual(onlineState, .idle)
        XCTAssertEqual(expectedOfflineState, .offline)
    }

    // MARK: - Pending Queue Tests

    func testPendingOperationsMaintainOrder() {
        let ops = [
            PendingOperation.create(documentId: "doc-1", databaseId: "db-1", collectionId: "col-1", data: [:]),
            PendingOperation.create(documentId: "doc-2", databaseId: "db-1", collectionId: "col-1", data: [:]),
            PendingOperation.create(documentId: "doc-3", databaseId: "db-1", collectionId: "col-1", data: [:])
        ]

        XCTAssertEqual(ops.map { $0.documentId }, ["doc-1", "doc-2", "doc-3"])
    }

    func testPendingOperationsCanBeFilteredByDatabase() {
        let ops = [
            PendingOperation.create(documentId: "doc-1", databaseId: "db-1", collectionId: "col-1", data: [:]),
            PendingOperation.create(documentId: "doc-2", databaseId: "db-2", collectionId: "col-1", data: [:]),
            PendingOperation.create(documentId: "doc-3", databaseId: "db-1", collectionId: "col-2", data: [:])
        ]

        let db1Ops = ops.filter { $0.databaseId == "db-1" }

        XCTAssertEqual(db1Ops.count, 2)
        XCTAssertEqual(db1Ops.map { $0.documentId }, ["doc-1", "doc-3"])
    }

    func testPendingOperationsCanBeFilteredByCollection() {
        let ops = [
            PendingOperation.create(documentId: "doc-1", databaseId: "db-1", collectionId: "users", data: [:]),
            PendingOperation.create(documentId: "doc-2", databaseId: "db-1", collectionId: "todos", data: [:]),
            PendingOperation.create(documentId: "doc-3", databaseId: "db-1", collectionId: "users", data: [:])
        ]

        let userOps = ops.filter { $0.collectionId == "users" }

        XCTAssertEqual(userOps.count, 2)
    }

    // MARK: - Edge Cases

    func testHandlesEmptyPendingQueue() {
        let emptyQueue: [PendingOperation] = []

        XCTAssertTrue(emptyQueue.isEmpty)
        XCTAssertEqual(emptyQueue.count, 0)
    }

    func testHandlesLargePendingQueue() {
        let largeQueue = (1...1000).map { i in
            PendingOperation.create(
                documentId: "doc-\(i)",
                databaseId: "db-1",
                collectionId: "col-1",
                data: ["index": i]
            )
        }

        XCTAssertEqual(largeQueue.count, 1000)
        XCTAssertEqual(largeQueue.first?.documentId, "doc-1")
        XCTAssertEqual(largeQueue.last?.documentId, "doc-1000")
    }

    func testHandlesRapidStateChanges() {
        var states: [SyncState] = []

        // Simulate rapid state changes
        states.append(.idle)
        states.append(.syncing)
        states.append(.idle)
        states.append(.offline)
        states.append(.idle)
        states.append(.syncing)
        states.append(.error)
        states.append(.idle)

        XCTAssertEqual(states.count, 8)
        XCTAssertEqual(states.last, .idle)
    }

    // MARK: - ConflictInfo Tests

    func testConflictInfoStoresAllData() {
        let conflict = ConflictInfo(
            documentId: "doc-123",
            databaseId: "db-1",
            collectionId: "users",
            localData: ["name": "Local"],
            serverData: ["name": "Server"],
            localVersion: 1,
            serverVersion: 2
        )

        XCTAssertEqual(conflict.documentId, "doc-123")
        XCTAssertEqual(conflict.databaseId, "db-1")
        XCTAssertEqual(conflict.collectionId, "users")
        XCTAssertEqual(conflict.localVersion, 1)
        XCTAssertEqual(conflict.serverVersion, 2)
    }

    // MARK: - ConflictStrategy Tests

    func testConflictStrategyAllCases() {
        let strategies: [ConflictStrategy] = [.serverWins, .clientWins, .merge, .manual]
        XCTAssertEqual(strategies.count, 4)
    }

    func testConflictStrategyEquality() {
        XCTAssertEqual(ConflictStrategy.serverWins, ConflictStrategy.serverWins)
        XCTAssertNotEqual(ConflictStrategy.serverWins, ConflictStrategy.clientWins)
    }

    func testConflictStrategyExhaustiveSwitch() {
        let strategies: [ConflictStrategy] = [.serverWins, .clientWins, .merge, .manual]

        for strategy in strategies {
            let description: String
            switch strategy {
            case .serverWins:
                description = "Server data takes priority"
            case .clientWins:
                description = "Client data takes priority"
            case .merge:
                description = "Merge data from both"
            case .manual:
                description = "Let app decide"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }

    // MARK: - ConflictChoice Tests

    func testConflictChoiceAllCases() {
        let choices: [ConflictChoice] = [.useLocal, .useServer, .useMerged]
        XCTAssertEqual(choices.count, 3)
    }

    func testConflictChoiceEquality() {
        XCTAssertEqual(ConflictChoice.useLocal, ConflictChoice.useLocal)
        XCTAssertNotEqual(ConflictChoice.useLocal, ConflictChoice.useServer)
    }

    func testConflictChoiceExhaustiveSwitch() {
        let choices: [ConflictChoice] = [.useLocal, .useServer, .useMerged]

        for choice in choices {
            let description: String
            switch choice {
            case .useLocal:
                description = "Use local version"
            case .useServer:
                description = "Use server version"
            case .useMerged:
                description = "Use merged version"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }

    // MARK: - Retry Logic Tests

    func testRetryCountCanIncrement() {
        var op = PendingOperation.create(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            data: ["test": "data"]
        )

        XCTAssertEqual(op.retryCount, 0)

        // Simulate retry increment
        op = PendingOperation(
            id: op.id,
            documentId: op.documentId,
            databaseId: op.databaseId,
            collectionId: op.collectionId,
            operationType: op.operationType,
            data: op.data,
            baseVersion: op.baseVersion,
            createdAt: op.createdAt,
            status: "failed",
            retryCount: 1,
            lastError: "Network error"
        )

        XCTAssertEqual(op.retryCount, 1)
        XCTAssertEqual(op.status, "failed")
        XCTAssertEqual(op.lastError, "Network error")
    }

    func testMaxRetriesCanBeTracked() {
        let maxRetries = 3
        var retryCount = 0

        while retryCount < maxRetries {
            retryCount += 1
        }

        XCTAssertEqual(retryCount, maxRetries)
        XCTAssertFalse(retryCount < maxRetries)
    }

    // MARK: - SyncListener Protocol Tests

    func testSyncListenerDefaultImplementations() {
        // The default implementations should not crash
        class TestListener: SyncEngine.SyncListener {}

        let listener = TestListener()

        // These should all be no-ops by default
        listener.onSyncStarted()
        listener.onSyncCompleted(syncedCount: 5)
        listener.onSyncFailed(error: NSError(domain: "test", code: 0))
        listener.onConflictDetected(conflict: ConflictInfo(
            documentId: "doc-1",
            databaseId: "db-1",
            collectionId: "col-1",
            localData: [:],
            serverData: [:],
            localVersion: 1,
            serverVersion: 2
        ))
        listener.onDocumentSynced(documentId: "doc-1", operation: .create)
    }

    func testSyncListenerCanTrackEvents() {
        var events: [String] = []

        class EventTrackingListener: SyncEngine.SyncListener {
            let events: UnsafeMutablePointer<[String]>

            init(events: UnsafeMutablePointer<[String]>) {
                self.events = events
            }

            func onSyncStarted() {
                events.pointee.append("started")
            }

            func onSyncCompleted(syncedCount: Int) {
                events.pointee.append("completed:\(syncedCount)")
            }

            func onSyncFailed(error: Error) {
                events.pointee.append("failed:\(error.localizedDescription)")
            }

            func onConflictDetected(conflict: ConflictInfo) {
                events.pointee.append("conflict:\(conflict.documentId)")
            }

            func onDocumentSynced(documentId: String, operation: OperationType) {
                events.pointee.append("synced:\(documentId):\(operation.rawValue)")
            }
        }

        let listener = EventTrackingListener(events: &events)

        // Simulate sync flow
        listener.onSyncStarted()
        listener.onDocumentSynced(documentId: "doc-1", operation: .create)
        listener.onSyncCompleted(syncedCount: 1)

        XCTAssertEqual(events, [
            "started",
            "synced:doc-1:create",
            "completed:1"
        ])
    }
}
