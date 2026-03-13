import Foundation

/// Sync status for cached documents
public enum SyncStatus: String, Codable {
    case synced = "synced"
    case pendingCreate = "pending_create"
    case pendingUpdate = "pending_update"
    case pendingDelete = "pending_delete"
    case syncFailed = "sync_failed"
}

/// Operation type for pending operations
public enum OperationType: String, Codable {
    case create = "create"
    case update = "update"
    case delete = "delete"
}

/// Sync state for the sync engine
public enum SyncState: String {
    case idle = "idle"
    case syncing = "syncing"
    case offline = "offline"
    case error = "error"
}
