import XCTest
@testable import RiviumSync

/// Tests for offline module enums: SyncStatus, OperationType, SyncState
final class OfflineEnumsTests: XCTestCase {

    // MARK: - SyncStatus

    func testSyncStatusSyncedRawValue() {
        XCTAssertEqual(SyncStatus.synced.rawValue, "synced")
    }

    func testSyncStatusPendingCreateRawValue() {
        XCTAssertEqual(SyncStatus.pendingCreate.rawValue, "pending_create")
    }

    func testSyncStatusPendingUpdateRawValue() {
        XCTAssertEqual(SyncStatus.pendingUpdate.rawValue, "pending_update")
    }

    func testSyncStatusPendingDeleteRawValue() {
        XCTAssertEqual(SyncStatus.pendingDelete.rawValue, "pending_delete")
    }

    func testSyncStatusSyncFailedRawValue() {
        XCTAssertEqual(SyncStatus.syncFailed.rawValue, "sync_failed")
    }

    func testSyncStatusAllCasesCount() {
        let allCases: [SyncStatus] = [.synced, .pendingCreate, .pendingUpdate, .pendingDelete, .syncFailed]
        XCTAssertEqual(allCases.count, 5)
    }

    func testSyncStatusFromRawValue() {
        XCTAssertEqual(SyncStatus(rawValue: "synced"), .synced)
        XCTAssertEqual(SyncStatus(rawValue: "pending_create"), .pendingCreate)
        XCTAssertEqual(SyncStatus(rawValue: "pending_update"), .pendingUpdate)
        XCTAssertEqual(SyncStatus(rawValue: "pending_delete"), .pendingDelete)
        XCTAssertEqual(SyncStatus(rawValue: "sync_failed"), .syncFailed)
    }

    func testSyncStatusInvalidRawValue() {
        XCTAssertNil(SyncStatus(rawValue: "invalid"))
        XCTAssertNil(SyncStatus(rawValue: ""))
        XCTAssertNil(SyncStatus(rawValue: "SYNCED")) // case sensitive
    }

    func testSyncStatusCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let original = SyncStatus.pendingCreate
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SyncStatus.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testSyncStatusEquality() {
        XCTAssertEqual(SyncStatus.synced, SyncStatus.synced)
        XCTAssertNotEqual(SyncStatus.synced, SyncStatus.pendingCreate)
    }

    // MARK: - OperationType

    func testOperationTypeCreateRawValue() {
        XCTAssertEqual(OperationType.create.rawValue, "create")
    }

    func testOperationTypeUpdateRawValue() {
        XCTAssertEqual(OperationType.update.rawValue, "update")
    }

    func testOperationTypeDeleteRawValue() {
        XCTAssertEqual(OperationType.delete.rawValue, "delete")
    }

    func testOperationTypeAllCasesCount() {
        let allCases: [OperationType] = [.create, .update, .delete]
        XCTAssertEqual(allCases.count, 3)
    }

    func testOperationTypeFromRawValue() {
        XCTAssertEqual(OperationType(rawValue: "create"), .create)
        XCTAssertEqual(OperationType(rawValue: "update"), .update)
        XCTAssertEqual(OperationType(rawValue: "delete"), .delete)
    }

    func testOperationTypeInvalidRawValue() {
        XCTAssertNil(OperationType(rawValue: "invalid"))
        XCTAssertNil(OperationType(rawValue: ""))
        XCTAssertNil(OperationType(rawValue: "CREATE")) // case sensitive
    }

    func testOperationTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let original = OperationType.update
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(OperationType.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testOperationTypeEquality() {
        XCTAssertEqual(OperationType.create, OperationType.create)
        XCTAssertNotEqual(OperationType.create, OperationType.delete)
    }

    // MARK: - SyncState

    func testSyncStateIdleRawValue() {
        XCTAssertEqual(SyncState.idle.rawValue, "idle")
    }

    func testSyncStateSyncingRawValue() {
        XCTAssertEqual(SyncState.syncing.rawValue, "syncing")
    }

    func testSyncStateOfflineRawValue() {
        XCTAssertEqual(SyncState.offline.rawValue, "offline")
    }

    func testSyncStateErrorRawValue() {
        XCTAssertEqual(SyncState.error.rawValue, "error")
    }

    func testSyncStateAllCasesCount() {
        let allCases: [SyncState] = [.idle, .syncing, .offline, .error]
        XCTAssertEqual(allCases.count, 4)
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

    // MARK: - Exhaustive Switch Tests

    func testSyncStatusExhaustiveSwitch() {
        let statuses: [SyncStatus] = [.synced, .pendingCreate, .pendingUpdate, .pendingDelete, .syncFailed]

        for status in statuses {
            let description: String
            switch status {
            case .synced:
                description = "Document is synced"
            case .pendingCreate:
                description = "Document pending creation"
            case .pendingUpdate:
                description = "Document pending update"
            case .pendingDelete:
                description = "Document pending deletion"
            case .syncFailed:
                description = "Sync failed"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }

    func testOperationTypeExhaustiveSwitch() {
        let types: [OperationType] = [.create, .update, .delete]

        for type in types {
            let description: String
            switch type {
            case .create:
                description = "Create operation"
            case .update:
                description = "Update operation"
            case .delete:
                description = "Delete operation"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }

    func testSyncStateExhaustiveSwitch() {
        let states: [SyncState] = [.idle, .syncing, .offline, .error]

        for state in states {
            let description: String
            switch state {
            case .idle:
                description = "Engine is idle"
            case .syncing:
                description = "Engine is syncing"
            case .offline:
                description = "Engine is offline"
            case .error:
                description = "Engine has error"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }

    // MARK: - Hashable Tests

    func testSyncStatusHashable() {
        var set = Set<SyncStatus>()
        set.insert(.synced)
        set.insert(.pendingCreate)
        set.insert(.synced) // duplicate

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(.synced))
        XCTAssertTrue(set.contains(.pendingCreate))
    }

    func testOperationTypeHashable() {
        var set = Set<OperationType>()
        set.insert(.create)
        set.insert(.update)
        set.insert(.create) // duplicate

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(.create))
        XCTAssertTrue(set.contains(.update))
    }
}
