import Foundation

/// Conflict resolution strategy
public enum ConflictStrategy {
    /// Server data wins (default)
    case serverWins
    /// Client data wins
    case clientWins
    /// Automatically merge non-conflicting fields
    case merge
    /// Let the app decide via ConflictResolver
    case manual
}

/// User's choice when resolving conflicts manually
public enum ConflictChoice {
    case useLocal
    case useServer
    case useMerged
}

/// Information about a conflict
public struct ConflictInfo {
    public let documentId: String
    public let databaseId: String
    public let collectionId: String
    public let localData: [String: Any]
    public let serverData: [String: Any]
    public let localVersion: Int
    public let serverVersion: Int

    public init(
        documentId: String,
        databaseId: String,
        collectionId: String,
        localData: [String: Any],
        serverData: [String: Any],
        localVersion: Int,
        serverVersion: Int
    ) {
        self.documentId = documentId
        self.databaseId = databaseId
        self.collectionId = collectionId
        self.localData = localData
        self.serverData = serverData
        self.localVersion = localVersion
        self.serverVersion = serverVersion
    }
}

/// Protocol for custom conflict resolution
public protocol ConflictResolver {
    /// Resolve a conflict between local and server data
    /// - Parameter conflict: Information about the conflict
    /// - Returns: Tuple of (choice, optional merged data if choice is useMerged)
    func resolve(conflict: ConflictInfo) -> (ConflictChoice, [String: Any]?)
}
