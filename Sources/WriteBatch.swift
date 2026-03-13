import Foundation

/// A write batch is used to perform multiple writes as a single atomic unit.
///
/// A WriteBatch object can be acquired by calling `RiviumSync.shared.batch()`. It provides
/// methods for adding writes to the batch. None of the writes will be committed
/// (or visible locally) until `commit()` is called.
///
/// Unlike transactions, write batches are persisted offline and therefore are
/// preferable when you don't need to condition your writes on read data.
///
/// Usage:
/// ```swift
/// let batch = RiviumSync.shared.batch()
///
/// // Set a document
/// batch.set(usersCollection, documentId: "user1", data: ["name": "John", "age": 30])
///
/// // Update a document
/// batch.update(usersCollection, documentId: "user2", data: ["status": "active"])
///
/// // Delete a document
/// batch.delete(usersCollection, documentId: "user3")
///
/// // Commit the batch
/// try await batch.commit()
/// ```
public class WriteBatch {
    private let apiClient: ApiClient
    private var operations: [BatchOperation] = []
    private var committed = false

    /// Represents a single operation in the batch
    internal enum BatchOperation {
        case set(databaseId: String, collectionId: String, documentId: String, data: [String: Any])
        case update(databaseId: String, collectionId: String, documentId: String, data: [String: Any])
        case delete(databaseId: String, collectionId: String, documentId: String)
        case create(databaseId: String, collectionId: String, data: [String: Any])

        func toDict() -> [String: Any] {
            switch self {
            case .set(let databaseId, let collectionId, let documentId, let data):
                return [
                    "type": "set",
                    "databaseId": databaseId,
                    "collectionId": collectionId,
                    "documentId": documentId,
                    "data": data
                ]
            case .update(let databaseId, let collectionId, let documentId, let data):
                return [
                    "type": "update",
                    "databaseId": databaseId,
                    "collectionId": collectionId,
                    "documentId": documentId,
                    "data": data
                ]
            case .delete(let databaseId, let collectionId, let documentId):
                return [
                    "type": "delete",
                    "databaseId": databaseId,
                    "collectionId": collectionId,
                    "documentId": documentId
                ]
            case .create(let databaseId, let collectionId, let data):
                return [
                    "type": "create",
                    "databaseId": databaseId,
                    "collectionId": collectionId,
                    "data": data
                ]
            }
        }
    }

    internal init(apiClient: ApiClient) {
        self.apiClient = apiClient
    }

    /// Writes to the document referred to by the provided collection and document ID.
    /// If the document does not exist yet, it will be created.
    /// If the document exists, its contents will be overwritten.
    ///
    /// - Parameters:
    ///   - collection: The collection containing the document
    ///   - documentId: The ID of the document to write
    ///   - data: The data to write to the document
    /// - Returns: This WriteBatch instance for chaining
    @discardableResult
    public func set(_ collection: SyncCollection, documentId: String, data: [String: Any]) -> WriteBatch {
        guard !committed else {
            fatalError("WriteBatch has already been committed")
        }
        operations.append(.set(
            databaseId: collection.databaseId,
            collectionId: collection.id,
            documentId: documentId,
            data: data
        ))
        return self
    }

    /// Updates fields in the document referred to by the provided collection and document ID.
    /// The document must exist. Fields not specified in the update are not modified.
    ///
    /// - Parameters:
    ///   - collection: The collection containing the document
    ///   - documentId: The ID of the document to update
    ///   - data: The fields to update
    /// - Returns: This WriteBatch instance for chaining
    @discardableResult
    public func update(_ collection: SyncCollection, documentId: String, data: [String: Any]) -> WriteBatch {
        guard !committed else {
            fatalError("WriteBatch has already been committed")
        }
        operations.append(.update(
            databaseId: collection.databaseId,
            collectionId: collection.id,
            documentId: documentId,
            data: data
        ))
        return self
    }

    /// Deletes the document referred to by the provided collection and document ID.
    ///
    /// - Parameters:
    ///   - collection: The collection containing the document
    ///   - documentId: The ID of the document to delete
    /// - Returns: This WriteBatch instance for chaining
    @discardableResult
    public func delete(_ collection: SyncCollection, documentId: String) -> WriteBatch {
        guard !committed else {
            fatalError("WriteBatch has already been committed")
        }
        operations.append(.delete(
            databaseId: collection.databaseId,
            collectionId: collection.id,
            documentId: documentId
        ))
        return self
    }

    /// Creates a new document with an auto-generated ID in the specified collection.
    ///
    /// - Parameters:
    ///   - collection: The collection to create the document in
    ///   - data: The data for the new document
    /// - Returns: This WriteBatch instance for chaining
    @discardableResult
    public func create(_ collection: SyncCollection, data: [String: Any]) -> WriteBatch {
        guard !committed else {
            fatalError("WriteBatch has already been committed")
        }
        operations.append(.create(
            databaseId: collection.databaseId,
            collectionId: collection.id,
            data: data
        ))
        return self
    }

    /// Commits all of the writes in this write batch as a single atomic unit.
    ///
    /// - Throws: RiviumSyncError.batchWriteError if the batch commit fails
    public func commit() async throws {
        guard !committed else {
            throw RiviumSyncError.batchWriteError("WriteBatch has already been committed")
        }
        committed = true

        guard !operations.isEmpty else {
            return
        }

        do {
            try await apiClient.executeBatch(operations: operations.map { $0.toDict() })
        } catch {
            committed = false // Allow retry
            throw RiviumSyncError.batchWriteError("Batch commit failed: \(error.localizedDescription)")
        }
    }

    /// Commits all of the writes in this write batch as a single atomic unit.
    /// Callback-based version.
    ///
    /// - Parameters:
    ///   - onSuccess: Called when the batch commits successfully
    ///   - onError: Called if the batch commit fails
    public func commit(onSuccess: @escaping () -> Void, onError: @escaping (Error) -> Void) {
        Task {
            do {
                try await commit()
                DispatchQueue.main.async {
                    onSuccess()
                }
            } catch {
                DispatchQueue.main.async {
                    onError(error)
                }
            }
        }
    }

    /// Returns the number of operations in this batch
    public var size: Int {
        return operations.count
    }

    /// Returns true if this batch has no operations
    public var isEmpty: Bool {
        return operations.isEmpty
    }
}
