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
    var id: String { get }
    var name: String { get }
    var databaseId: String { get }
    
    // CRUD operations
    func add(data: [String: Any]) async throws -> SyncDocument
    func get(documentId: String) async throws -> SyncDocument?
    func getAll() async throws -> [SyncDocument]
    func update(documentId: String, data: [String: Any]) async throws -> SyncDocument
    func set(documentId: String, data: [String: Any]) async throws -> SyncDocument
    func delete(documentId: String) async throws
    
    // Query operations
    func query() -> SyncQuery
    func `where`(_ field: String, _ op: QueryOperator, _ value: Any?) -> SyncQuery
    
    // Realtime listeners
    func listen(callback: @escaping ([SyncDocument]) -> Void) -> ListenerRegistration
    func listenDocument(documentId: String, callback: @escaping (SyncDocument?) -> Void) -> ListenerRegistration
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
}
