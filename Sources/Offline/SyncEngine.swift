import Foundation
import Combine

/// Sync engine handles synchronization between local cache and server
public class SyncEngine {

    private let apiClient: ApiClient
    private let localStore: LocalStorageManager
    private let conflictStrategy: ConflictStrategy
    private let conflictResolver: ConflictResolver?
    private let maxRetries: Int

    // Published state
    @Published public private(set) var syncState: SyncState = .idle
    @Published public private(set) var isOnline: Bool = false
    @Published public private(set) var pendingCount: Int = 0

    /// Set once the first connection attempt has reported, either way.
    private var connectionStateKnown = false

    /// True only when a connection attempt has actually reported that we are
    /// offline. `isOnline` starts false, so before the first report it cannot
    /// tell "not connected yet" from "offline" - and reads that trusted it
    /// served the local cache at every app launch, including rows deleted
    /// elsewhere since. Reads should try the network unless this is true.
    public var isKnownOffline: Bool {
        connectionStateKnown && !isOnline
    }

    private var syncTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var syncListeners: [SyncListener] = []

    /// Listener for sync events
    public protocol SyncListener: AnyObject {
        func onSyncStarted()
        func onSyncCompleted(syncedCount: Int)
        func onSyncFailed(error: Error)
        func onConflictDetected(conflict: ConflictInfo)
        func onDocumentSynced(documentId: String, operation: OperationType)
        /// The server refused a write that was waiting offline (the security rules, invalid data), as in Firestore:
        /// the write is dropped, not retried, and the local copy goes back to what the server has (a refused new
        /// document disappears). `error` is the server's answer.
        func onDocumentRejected(documentId: String, operation: OperationType, error: Error)
    }

    internal init(
        apiClient: ApiClient,
        localStore: LocalStorageManager,
        conflictStrategy: ConflictStrategy = .serverWins,
        conflictResolver: ConflictResolver? = nil,
        maxRetries: Int = 3
    ) {
        self.apiClient = apiClient
        self.localStore = localStore
        self.conflictStrategy = conflictStrategy
        self.conflictResolver = conflictResolver
        self.maxRetries = maxRetries

        // Observe pending count
        localStore.pendingCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.pendingCount = count
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Add a sync listener
    public func addSyncListener(_ listener: SyncListener) {
        syncListeners.append(listener)
    }

    /// Remove a sync listener
    public func removeSyncListener(_ listener: SyncListener) {
        syncListeners.removeAll { $0 === listener }
    }

    /// Called when connection state changes
    public func onConnectionStateChanged(connected: Bool) {
        connectionStateKnown = true
        isOnline = connected
        RiviumSyncLogger.i("SyncEngine: Connection state changed to \(connected)")

        if connected {
            syncState = .idle
            // Trigger sync when coming online
            syncPendingOperations()
        } else {
            syncState = .offline
        }
    }

    /// Sync all pending operations
    public func syncPendingOperations() {
        guard isOnline else {
            RiviumSyncLogger.d("SyncEngine: Cannot sync, offline")
            return
        }

        guard syncTask == nil else {
            RiviumSyncLogger.d("SyncEngine: Sync already in progress")
            return
        }

        syncTask = Task { [weak self] in
            await self?.performSync()
            self?.syncTask = nil
        }
    }

    /// Force sync now
    public func forceSync() {
        syncTask?.cancel()
        syncTask = nil
        syncPendingOperations()
    }

    /// Cancel ongoing sync
    public func cancelSync() {
        syncTask?.cancel()
        syncTask = nil
        syncState = .idle
    }

    /// Clean up resources
    public func destroy() {
        syncTask?.cancel()
        syncTask = nil
        cancellables.removeAll()
        syncListeners.removeAll()
    }

    // MARK: - Private Sync Logic

    private func performSync() async {
        do {
            syncState = .syncing
            syncListeners.forEach { $0.onSyncStarted() }

            let pending = localStore.getPendingDocuments()
            pendingCount = pending.count

            if pending.isEmpty {
                RiviumSyncLogger.d("SyncEngine: No pending operations")
                syncState = .idle
                syncListeners.forEach { $0.onSyncCompleted(syncedCount: 0) }
                return
            }

            RiviumSyncLogger.i("SyncEngine: Syncing \(pending.count) pending operations")
            var syncedCount = 0

            for doc in pending {
                do {
                    let result = try await syncDocument(doc)
                    if result {
                        syncedCount += 1
                        pendingCount -= 1
                    }
                } catch let rejection where Self.isRejection(rejection) {
                    await rollBack(doc, error: rejection)
                } catch {
                    RiviumSyncLogger.e("SyncEngine: Failed to sync document \(doc.id): \(error)")
                    // Keep it queued as it is (retried by the next sync) and continue with the others.
                    localStore.updateSyncStatus(documentId: doc.id, status: doc.syncStatus, error: error.localizedDescription)
                }
            }

            syncState = .idle
            syncListeners.forEach { $0.onSyncCompleted(syncedCount: syncedCount) }
            RiviumSyncLogger.i("SyncEngine: Sync completed, synced \(syncedCount) documents")

        } catch {
            RiviumSyncLogger.e("SyncEngine: Sync failed: \(error)")
            syncState = .error
            syncListeners.forEach { $0.onSyncFailed(error: error) }
        }
    }

    private func syncDocument(_ cached: CachedDocument) async throws -> Bool {
        switch cached.syncStatus {
        case .pendingCreate:
            return try await syncCreate(cached)
        case .pendingUpdate:
            return try await syncUpdate(cached)
        case .pendingDelete:
            return try await syncDelete(cached)
        case .syncFailed:
            return try await retrySyncFailed(cached)
        default:
            return true // Already synced
        }
    }

    /// A queued `set()`: written with its id and its merge flag.
    private func syncSet(_ cached: CachedDocument, merge: Bool, operation: OperationType) async throws -> Bool {
        let serverDoc = try await apiClient.setDocument(
            databaseId: cached.databaseId,
            collectionId: cached.collectionId,
            documentId: cached.id,
            data: cached.getData(),
            merge: merge
        )
        localStore.saveDocument(
            document: serverDoc,
            databaseId: cached.databaseId,
            collectionId: cached.collectionId,
            syncStatus: .synced
        )
        syncListeners.forEach { $0.onDocumentSynced(documentId: cached.id, operation: operation) }
        RiviumSyncLogger.d("SyncEngine: Set document \(cached.id)")
        return true
    }

    private func syncCreate(_ cached: CachedDocument) async throws -> Bool {
        if let merge = cached.setMerge {
            return try await syncSet(cached, merge: merge, operation: .create)
        }
        let data = cached.getData()
        let serverDoc = try await apiClient.addDocument(
            databaseId: cached.databaseId,
            collectionId: cached.collectionId,
            data: data
        )

        // Update local cache with server response
        localStore.saveDocument(
            document: serverDoc,
            databaseId: cached.databaseId,
            collectionId: cached.collectionId,
            syncStatus: .synced
        )

        // If the server assigned a different ID, delete the old local entry
        if serverDoc.id != cached.id {
            localStore.deleteDocument(documentId: cached.id)
        }

        syncListeners.forEach { $0.onDocumentSynced(documentId: serverDoc.id, operation: .create) }
        RiviumSyncLogger.d("SyncEngine: Created document \(serverDoc.id)")
        return true
    }

    private func syncUpdate(_ cached: CachedDocument) async throws -> Bool {
        // First, check for conflicts
        let serverDoc = try await apiClient.getDocument(
            databaseId: cached.databaseId,
            collectionId: cached.collectionId,
            documentId: cached.id
        )

        let baseVersion = cached.baseVersion ?? cached.version

        if let serverDoc = serverDoc, serverDoc.version != baseVersion {
            // Conflict detected!
            return try await handleConflict(local: cached, server: serverDoc)
        }

        if let merge = cached.setMerge {
            return try await syncSet(cached, merge: merge, operation: .update)
        }

        // No conflict, proceed with update
        let data = cached.getData()
        let updatedDoc = try await apiClient.updateDocument(
            databaseId: cached.databaseId,
            collectionId: cached.collectionId,
            documentId: cached.id,
            data: data
        )

        localStore.saveDocument(
            document: updatedDoc,
            databaseId: cached.databaseId,
            collectionId: cached.collectionId,
            syncStatus: .synced
        )

        syncListeners.forEach { $0.onDocumentSynced(documentId: cached.id, operation: .update) }
        RiviumSyncLogger.d("SyncEngine: Updated document \(cached.id)")
        return true
    }

    private func handleConflict(local: CachedDocument, server: SyncDocument) async throws -> Bool {
        let conflictInfo = ConflictInfo(
            documentId: local.id,
            databaseId: local.databaseId,
            collectionId: local.collectionId,
            localData: local.getData(),
            serverData: server.data,
            localVersion: local.version,
            serverVersion: server.version
        )

        syncListeners.forEach { $0.onConflictDetected(conflict: conflictInfo) }
        RiviumSyncLogger.w("SyncEngine: Conflict detected for document \(local.id)")

        switch conflictStrategy {
        case .serverWins:
            // Use server version
            localStore.saveDocument(
                document: server,
                databaseId: local.databaseId,
                collectionId: local.collectionId,
                syncStatus: .synced
            )
            RiviumSyncLogger.d("SyncEngine: Conflict resolved - server wins")
            return true

        case .clientWins:
            // Force update server with local version
            let updated = try await apiClient.setDocument(
                databaseId: local.databaseId,
                collectionId: local.collectionId,
                documentId: local.id,
                data: local.getData(),
                merge: local.setMerge ?? true
            )
            localStore.saveDocument(
                document: updated,
                databaseId: local.databaseId,
                collectionId: local.collectionId,
                syncStatus: .synced
            )
            RiviumSyncLogger.d("SyncEngine: Conflict resolved - client wins")
            return true

        case .merge:
            // Auto-merge non-conflicting fields
            let merged = mergeData(local: local.getData(), server: server.data)
            let updated = try await apiClient.setDocument(
                databaseId: local.databaseId,
                collectionId: local.collectionId,
                documentId: local.id,
                data: merged,
                merge: true
            )
            localStore.saveDocument(
                document: updated,
                databaseId: local.databaseId,
                collectionId: local.collectionId,
                syncStatus: .synced
            )
            RiviumSyncLogger.d("SyncEngine: Conflict resolved - merged")
            return true

        case .manual:
            // Let the app decide
            if let resolver = conflictResolver {
                let (choice, mergedData) = resolver.resolve(conflict: conflictInfo)
                switch choice {
                case .useLocal:
                    let updated = try await apiClient.setDocument(
                        databaseId: local.databaseId,
                        collectionId: local.collectionId,
                        documentId: local.id,
                        data: local.getData(),
                        merge: local.setMerge ?? true
                    )
                    localStore.saveDocument(
                        document: updated,
                        databaseId: local.databaseId,
                        collectionId: local.collectionId,
                        syncStatus: .synced
                    )
                case .useServer:
                    localStore.saveDocument(
                        document: server,
                        databaseId: local.databaseId,
                        collectionId: local.collectionId,
                        syncStatus: .synced
                    )
                case .useMerged:
                    let data = mergedData ?? mergeData(local: local.getData(), server: server.data)
                    let updated = try await apiClient.setDocument(
                        databaseId: local.databaseId,
                        collectionId: local.collectionId,
                        documentId: local.id,
                        data: data,
                        merge: true
                    )
                    localStore.saveDocument(
                        document: updated,
                        databaseId: local.databaseId,
                        collectionId: local.collectionId,
                        syncStatus: .synced
                    )
                }
                RiviumSyncLogger.d("SyncEngine: Conflict resolved - manual choice: \(choice)")
                return true
            } else {
                // No resolver, default to server wins
                localStore.saveDocument(
                    document: server,
                    databaseId: local.databaseId,
                    collectionId: local.collectionId,
                    syncStatus: .synced
                )
                RiviumSyncLogger.d("SyncEngine: Conflict resolved - no resolver, server wins")
                return true
            }
        }
    }

    private func mergeData(local: [String: Any], server: [String: Any]) -> [String: Any] {
        var merged = server
        // Local changes override server for fields that were modified locally
        for (key, value) in local {
            merged[key] = value
        }
        return merged
    }

    private func syncDelete(_ cached: CachedDocument) async throws -> Bool {
        do {
            try await apiClient.deleteDocument(
                databaseId: cached.databaseId,
                collectionId: cached.collectionId,
                documentId: cached.id
            )

            // Remove from local cache
            localStore.deleteDocument(documentId: cached.id)

            syncListeners.forEach { $0.onDocumentSynced(documentId: cached.id, operation: .delete) }
            RiviumSyncLogger.d("SyncEngine: Deleted document \(cached.id)")
            return true
        } catch {
            // If document not found on server, consider it deleted
            if SyncErrors.httpStatus(error) == 404 ||
                error.localizedDescription.contains("404") || error.localizedDescription.contains("not found") {
                localStore.deleteDocument(documentId: cached.id)
                RiviumSyncLogger.d("SyncEngine: Document \(cached.id) already deleted on server")
                return true
            }
            throw error
        }
    }

    /// The server's final answer to a queued write (403 refused by the rules, 400 / 422 invalid...): retrying cannot
    /// change it. A 409 is a version conflict, handled by retrying with conflict resolution as before.
    static func isRejection(_ error: Error) -> Bool {
        !SyncErrors.isTransient(error) && SyncErrors.httpStatus(error) != 409
    }

    /// Drop a queued write the server refused and put the local copy back to the server's (Firestore): a refused
    /// new document disappears, a refused update or delete shows the server's document again. Sync listeners get
    /// `onDocumentRejected`.
    private func rollBack(_ cached: CachedDocument, error: Error) async {
        let operation: OperationType
        switch cached.syncStatus {
        case .pendingDelete: operation = .delete
        case .pendingCreate: operation = .create
        default: operation = cached.baseVersion == nil ? .create : .update
        }
        RiviumSyncLogger.w("SyncEngine: Server refused queued \(operation) of \(cached.id), rolling back: \(error.localizedDescription)")
        var server: SyncDocument?
        // A document created offline with add() (local_ id) was never on the server; anything else is read back.
        if !(operation == .create && cached.setMerge == nil) {
            do {
                server = try await apiClient.getDocument(databaseId: cached.databaseId, collectionId: cached.collectionId, documentId: cached.id)
            } catch let readError where SyncErrors.isTransient(readError) {
                // Can't read the server's copy now: keep it queued, the next sync rolls it back.
                localStore.updateSyncStatus(documentId: cached.id, status: cached.syncStatus, error: error.localizedDescription)
                return
            } catch {
                server = nil // The user may not read it either: nothing to show.
            }
        }
        if let server = server {
            localStore.saveDocument(document: server, databaseId: cached.databaseId, collectionId: cached.collectionId, syncStatus: .synced)
        } else {
            localStore.deleteDocument(documentId: cached.id)
        }
        syncListeners.forEach { $0.onDocumentRejected(documentId: cached.id, operation: operation, error: error) }
    }

    private func retrySyncFailed(_ cached: CachedDocument) async throws -> Bool {
        // No cap (Firestore): a write the server could not take is sent until it goes through; one the server
        // refuses is rolled back. Rows of older versions only: a failed send now keeps its pending state.
        // Determine the original operation type based on the document state
        if cached.baseVersion == nil {
            return try await syncCreate(cached)
        } else {
            return try await syncUpdate(cached)
        }
    }
}

// Default empty implementations for optional listener methods
public extension SyncEngine.SyncListener {
    func onSyncStarted() {}
    func onSyncCompleted(syncedCount: Int) {}
    func onSyncFailed(error: Error) {}
    func onConflictDetected(conflict: ConflictInfo) {}
    func onDocumentSynced(documentId: String, operation: OperationType) {}
    func onDocumentRejected(documentId: String, operation: OperationType, error: Error) {}
}
