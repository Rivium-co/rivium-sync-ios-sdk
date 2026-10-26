import Foundation

/// Query operators for filtering
public enum QueryOperator: String {
    case equal = "=="
    case notEqual = "!="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case arrayContains = "array-contains"
    case `in` = "in"
    case notIn = "not-in"
}

/// Order direction for queries
public enum OrderDirection: String {
    case ascending = "asc"
    case descending = "desc"
}

/// Protocol for RiviumSync collection operations
public protocol SyncCollection {
    /// How this collection is addressed in API paths and realtime topics. For a
    /// reference from `SyncDatabase.collection(_:)` this is the collection name you passed.
    var id: String { get }
    var name: String { get }
    /// How the parent database is addressed; the database name for a reference
    /// from `RiviumSync.database(_:)`.
    var databaseId: String { get }
    
    // CRUD operations
    func add(data: [String: Any]) async throws -> SyncDocument
    func get(documentId: String) async throws -> SyncDocument?
    func getAll() async throws -> [SyncDocument]
    func update(documentId: String, data: [String: Any]) async throws -> SyncDocument
    /// Writes the document with this id, creating it if needed. The document becomes exactly `data`: fields
    /// left out are removed. Same as `set(documentId:data:merge: false)`.
    func set(documentId: String, data: [String: Any]) async throws -> SyncDocument
    /// Writes the document with this id, creating it if needed. `merge: false` replaces the document with
    /// `data`; `merge: true` writes only the fields in `data` and keeps the others.
    func set(documentId: String, data: [String: Any], merge: Bool) async throws -> SyncDocument
    func delete(documentId: String) async throws
    
    // Query operations
    func query() -> SyncQuery
    func `where`(_ field: String, _ op: QueryOperator, _ value: Any?) -> SyncQuery
    
    // Realtime listeners
    func listen(callback: @escaping ([SyncDocument]) -> Void) -> ListenerRegistration
    /// Like `listen(callback:)`; `onError` is told when the listener cannot start or is stopped by the server
    /// (for example `RiviumSyncError.listenerRevoked` when the security rules no longer allow it).
    func listen(callback: @escaping ([SyncDocument]) -> Void, onError: @escaping (Error) -> Void) -> ListenerRegistration
    func listenDocument(documentId: String, callback: @escaping (SyncDocument?) -> Void) -> ListenerRegistration
    /// Like `listenDocument(documentId:callback:)`, with an error callback (see `listen(callback:onError:)`).
    func listenDocument(documentId: String, callback: @escaping (SyncDocument?) -> Void, onError: @escaping (Error) -> Void) -> ListenerRegistration
}

public extension SyncCollection {
    func set(documentId: String, data: [String: Any], merge: Bool) async throws -> SyncDocument {
        try await set(documentId: documentId, data: data)
    }

    func listen(callback: @escaping ([SyncDocument]) -> Void, onError: @escaping (Error) -> Void) -> ListenerRegistration {
        listen(callback: callback)
    }

    func listenDocument(documentId: String, callback: @escaping (SyncDocument?) -> Void, onError: @escaping (Error) -> Void) -> ListenerRegistration {
        listenDocument(documentId: documentId, callback: callback)
    }
}

/// Listener registration for unsubscribing
public protocol ListenerRegistration {
    func remove()
}

/// Query builder protocol
public protocol SyncQuery {
    func `where`(_ field: String, _ op: QueryOperator, _ value: Any?) -> SyncQuery
    func orderBy(_ field: String, direction: OrderDirection) -> SyncQuery
    func limit(_ count: Int) -> SyncQuery
    func offset(_ count: Int) -> SyncQuery
    
    func get() async throws -> [SyncDocument]
    func get(onSuccess: @escaping ([SyncDocument]) -> Void, onError: @escaping (Error) -> Void)
    func listen(callback: @escaping ([SyncDocument]) -> Void) -> ListenerRegistration
    /// Like `listen(callback:)`; `onError` is told when the listener cannot start - for example
    /// `RiviumSyncError.queryNotAllowed` when the security rules do not allow the query - or is stopped by the server.
    func listen(callback: @escaping ([SyncDocument]) -> Void, onError: @escaping (Error) -> Void) -> ListenerRegistration
}

public extension SyncQuery {
    func listen(callback: @escaping ([SyncDocument]) -> Void, onError: @escaping (Error) -> Void) -> ListenerRegistration {
        listen(callback: callback)
    }
}
