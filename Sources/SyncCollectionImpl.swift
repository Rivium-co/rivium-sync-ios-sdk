import Foundation
import Combine

/// Implementation of SyncCollection protocol
internal class SyncCollectionImpl: SyncCollection {
    let id: String
    let name: String
    let databaseId: String
    private let apiClient: ApiClient
    private let mqttManager: MqttManager
    private let localStorageManager: LocalStorageManager?
    private let syncEngine: SyncEngine?

    private var isOfflineEnabled: Bool {
        return localStorageManager != nil && syncEngine != nil
    }

    init(
        id: String,
        name: String,
        databaseId: String,
        apiClient: ApiClient,
        mqttManager: MqttManager,
        localStorageManager: LocalStorageManager? = nil,
        syncEngine: SyncEngine? = nil
    ) {
        self.id = id
        self.name = name
        self.databaseId = databaseId
        self.apiClient = apiClient
        self.mqttManager = mqttManager
        self.localStorageManager = localStorageManager
        self.syncEngine = syncEngine
    }

    // MARK: - CRUD Operations

    func add(data: [String: Any]) async throws -> SyncDocument {
        if isOfflineEnabled {
            return try await addWithOfflineSupport(data: data)
        }
        return try await apiClient.addDocument(databaseId: databaseId, collectionId: id, data: data)
    }

    private func addWithOfflineSupport(data: [String: Any]) async throws -> SyncDocument {
        let isOnline = syncEngine?.isOnline ?? true
        RiviumSyncLogger.d("addWithOfflineSupport: isOnline=\(isOnline), databaseId=\(databaseId), collectionId=\(id)")

        if isOnline {
            // Online: Try server first
            do {
                RiviumSyncLogger.d("addWithOfflineSupport: Attempting API call to add document")
                let doc = try await apiClient.addDocument(databaseId: databaseId, collectionId: id, data: data)
                RiviumSyncLogger.d("addWithOfflineSupport: API call succeeded, doc.id=\(doc.id)")
                // Cache the result
                localStorageManager?.saveDocument(
                    document: doc,
                    databaseId: databaseId,
                    collectionId: id,
                    syncStatus: .synced
                )
                return doc
            } catch let error as RiviumSyncError {
                RiviumSyncLogger.e("addWithOfflineSupport: RiviumSyncError - \(error.localizedDescription)", error: error)
                return createOfflineDocument(data: data)
            } catch {
                RiviumSyncLogger.e("addWithOfflineSupport: Unknown error - \(error.localizedDescription)", error: error)
                return createOfflineDocument(data: data)
            }
        } else {
            RiviumSyncLogger.d("addWithOfflineSupport: Device is offline, creating local document")
            // Offline: Create optimistic document
            return createOfflineDocument(data: data)
        }
    }

    private func createOfflineDocument(data: [String: Any]) -> SyncDocument {
        let tempId = "local_\(UUID().uuidString)"
        let now = Date().timeIntervalSince1970 * 1000
        let doc = SyncDocument(
            id: tempId,
            data: data,
            createdAt: now,
            updatedAt: now,
            version: 1
        )

        localStorageManager?.saveDocument(
            document: doc,
            databaseId: databaseId,
            collectionId: id,
            syncStatus: .pendingCreate
        )

        RiviumSyncLogger.d("Created offline document: \(tempId)")
        return doc
    }

    func get(documentId: String) async throws -> SyncDocument? {
        if isOfflineEnabled {
            return try await getWithOfflineSupport(documentId: documentId)
        }
        return try await apiClient.getDocument(databaseId: databaseId, collectionId: id, documentId: documentId)
    }

    private func getWithOfflineSupport(documentId: String) async throws -> SyncDocument? {
        let isOnline = syncEngine?.isOnline ?? true

        // Check local cache first
        let cached = localStorageManager?.getDocument(documentId: documentId)

        // For local documents (not yet synced), always return from cache
        if documentId.hasPrefix("local_") {
            RiviumSyncLogger.d("Returning local document from cache: \(documentId)")
            return cached
        }

        if isOnline {
            do {
                let doc = try await apiClient.getDocument(databaseId: databaseId, collectionId: id, documentId: documentId)
                if let doc = doc {
                    // Update cache
                    localStorageManager?.saveDocument(
                        document: doc,
                        databaseId: databaseId,
                        collectionId: id,
                        syncStatus: .synced
                    )
                }
                return doc
            } catch {
                RiviumSyncLogger.w("Failed to get document online, using cached: \(error)")
                return cached
            }
        } else {
            return cached
        }
    }

    func getAll() async throws -> [SyncDocument] {
        if isOfflineEnabled {
            return try await getAllWithOfflineSupport()
        }
        return try await apiClient.getAllDocuments(databaseId: databaseId, collectionId: id)
    }

    private func getAllWithOfflineSupport() async throws -> [SyncDocument] {
        let isOnline = syncEngine?.isOnline ?? true

        if isOnline {
            do {
                let docs = try await apiClient.getAllDocuments(databaseId: databaseId, collectionId: id)
                // Update cache
                localStorageManager?.saveDocuments(
                    documents: docs,
                    databaseId: databaseId,
                    collectionId: id,
                    syncStatus: .synced
                )
                return docs
            } catch {
                RiviumSyncLogger.w("Failed to get documents online, using cached: \(error)")
                return localStorageManager?.getDocuments(databaseId: databaseId, collectionId: id) ?? []
            }
        } else {
            return localStorageManager?.getDocuments(databaseId: databaseId, collectionId: id) ?? []
        }
    }

    func update(documentId: String, data: [String: Any]) async throws -> SyncDocument {
        if isOfflineEnabled {
            return try await updateWithOfflineSupport(documentId: documentId, data: data)
        }
        return try await apiClient.updateDocument(databaseId: databaseId, collectionId: id, documentId: documentId, data: data)
    }

    private func updateWithOfflineSupport(documentId: String, data: [String: Any]) async throws -> SyncDocument {
        let isOnline = syncEngine?.isOnline ?? true

        // Get current version for conflict detection
        let existing = localStorageManager?.getDocument(documentId: documentId)
        let baseVersion = existing?.version ?? 1

        if isOnline {
            do {
                let doc = try await apiClient.updateDocument(databaseId: databaseId, collectionId: id, documentId: documentId, data: data)
                // Update cache
                localStorageManager?.saveDocument(
                    document: doc,
                    databaseId: databaseId,
                    collectionId: id,
                    syncStatus: .synced
                )
                return doc
            } catch {
                RiviumSyncLogger.w("Failed to update document online, saving offline: \(error)")
                return updateOfflineDocument(documentId: documentId, data: data, baseVersion: baseVersion)
            }
        } else {
            return updateOfflineDocument(documentId: documentId, data: data, baseVersion: baseVersion)
        }
    }

    private func updateOfflineDocument(documentId: String, data: [String: Any], baseVersion: Int) -> SyncDocument {
        let existing = localStorageManager?.getDocument(documentId: documentId)
        let now = Date().timeIntervalSince1970 * 1000

        let doc = SyncDocument(
            id: documentId,
            data: data,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            version: baseVersion + 1
        )

        localStorageManager?.saveDocument(
            document: doc,
            databaseId: databaseId,
            collectionId: id,
            syncStatus: .pendingUpdate,
            baseVersion: baseVersion
        )

        RiviumSyncLogger.d("Updated offline document: \(documentId)")
        return doc
    }

    func set(documentId: String, data: [String: Any]) async throws -> SyncDocument {
        if isOfflineEnabled {
            return try await setWithOfflineSupport(documentId: documentId, data: data)
        }
        return try await apiClient.setDocument(databaseId: databaseId, collectionId: id, documentId: documentId, data: data)
    }

    private func setWithOfflineSupport(documentId: String, data: [String: Any]) async throws -> SyncDocument {
        let isOnline = syncEngine?.isOnline ?? true

        if isOnline {
            do {
                let doc = try await apiClient.setDocument(databaseId: databaseId, collectionId: id, documentId: documentId, data: data)
                localStorageManager?.saveDocument(
                    document: doc,
                    databaseId: databaseId,
                    collectionId: id,
                    syncStatus: .synced
                )
                return doc
            } catch {
                RiviumSyncLogger.w("Failed to set document online, saving offline: \(error)")
                return setOfflineDocument(documentId: documentId, data: data)
            }
        } else {
            return setOfflineDocument(documentId: documentId, data: data)
        }
    }

    private func setOfflineDocument(documentId: String, data: [String: Any]) -> SyncDocument {
        let existing = localStorageManager?.getDocument(documentId: documentId)
        let now = Date().timeIntervalSince1970 * 1000
        let isCreate = existing == nil

        let doc = SyncDocument(
            id: documentId,
            data: data,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            version: (existing?.version ?? 0) + 1
        )

        localStorageManager?.saveDocument(
            document: doc,
            databaseId: databaseId,
            collectionId: id,
            syncStatus: isCreate ? .pendingCreate : .pendingUpdate,
            baseVersion: existing?.version
        )

        RiviumSyncLogger.d("Set offline document: \(documentId) (\(isCreate ? "create" : "update"))")
        return doc
    }

    func delete(documentId: String) async throws {
        if isOfflineEnabled {
            try await deleteWithOfflineSupport(documentId: documentId)
            return
        }
        try await apiClient.deleteDocument(databaseId: databaseId, collectionId: id, documentId: documentId)
    }

    private func deleteWithOfflineSupport(documentId: String) async throws {
        let isOnline = syncEngine?.isOnline ?? true

        // Get current version for sync
        let existing = localStorageManager?.getDocument(documentId: documentId)
        let baseVersion = existing?.version ?? 1

        if isOnline {
            do {
                try await apiClient.deleteDocument(databaseId: databaseId, collectionId: id, documentId: documentId)
                // Remove from cache
                localStorageManager?.deleteDocument(documentId: documentId)
            } catch {
                RiviumSyncLogger.w("Failed to delete document online, marking for delete: \(error)")
                // Mark for delete when back online
                localStorageManager?.markPendingDelete(documentId: documentId, databaseId: databaseId, collectionId: id, baseVersion: baseVersion)
            }
        } else {
            // Mark for delete when back online
            localStorageManager?.markPendingDelete(documentId: documentId, databaseId: databaseId, collectionId: id, baseVersion: baseVersion)
            RiviumSyncLogger.d("Marked offline document for deletion: \(documentId)")
        }
    }
    
    // MARK: - Query Operations
    
    func query() -> SyncQuery {
        return SyncQueryImpl(databaseId: databaseId, collectionId: id, apiClient: apiClient, mqttManager: mqttManager)
    }
    
    func `where`(_ field: String, _ op: QueryOperator, _ value: Any?) -> SyncQuery {
        return query().where(field, op, value)
    }
    
    // MARK: - Realtime Listeners
    
    func listen(callback: @escaping ([SyncDocument]) -> Void) -> ListenerRegistration {
        let topic = mqttManager.collectionTopic(databaseId: databaseId, collectionId: id)
        
        // Initial fetch
        Task {
            do {
                let documents = try await getAll()
                DispatchQueue.main.async {
                    callback(documents)
                }
            } catch {
                RiviumSyncLogger.e("Failed to fetch initial documents", error: error)
            }
        }
        
        // Subscribe to MQTT changes
        // Note: We capture self strongly here because the collection instance needs to stay alive
        // for the lifetime of the subscription. The ListenerRegistration will unsubscribe when removed.
        let handle = mqttManager.subscribe(topic: topic) { [self] _ in
            Task {
                do {
                    let documents = try await self.getAll()
                    RiviumSyncLogger.i("listen: Re-fetched \(documents.count) docs, dispatching callback to main queue")
                    DispatchQueue.main.async {
                        RiviumSyncLogger.i("listen: Calling callback with \(documents.count) documents")
                        callback(documents)
                    }
                } catch {
                    RiviumSyncLogger.e("Failed to refetch documents after change", error: error)
                }
            }
        }

        return ListenerRegistrationImpl { [mqttManager, handle] in
            mqttManager.unsubscribe(handle: handle)
        }
    }
    
    func listenDocument(documentId: String, callback: @escaping (SyncDocument?) -> Void) -> ListenerRegistration {
        // Subscribe to the collection topic and filter by documentId,
        // since the server publishes all changes to the collection-level topic
        let topic = mqttManager.collectionTopic(databaseId: databaseId, collectionId: id)
        RiviumSyncLogger.i("listenDocument: Subscribing to collection MQTT topic: \(topic) for documentId: \(documentId)")

        // Initial fetch
        Task {
            do {
                let document = try await get(documentId: documentId)
                DispatchQueue.main.async {
                    callback(document)
                }
            } catch {
                RiviumSyncLogger.e("Failed to fetch initial document", error: error)
            }
        }

        // Subscribe to MQTT changes on the collection topic, filtering by documentId
        let handle = mqttManager.subscribe(topic: topic) { [self] payload in
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                RiviumSyncLogger.e("listenDocument: Failed to parse MQTT payload", error: nil)
                return
            }

            // Filter: only process messages for our specific document
            guard let msgDocId = json["documentId"] as? String, msgDocId == documentId else {
                return
            }

            let eventType = json["type"] as? String ?? "update"
            RiviumSyncLogger.i("listenDocument: Received change for documentId=\(documentId), type=\(eventType)")

            // Handle delete
            if eventType == "delete" {
                DispatchQueue.main.async {
                    callback(nil)
                }
                return
            }

            // Use data directly from MQTT message if available
            if let docData = json["data"] as? [String: Any] {
                let now = Date().timeIntervalSince1970 * 1000

                // Parse timestamp from ISO string if available
                var updatedAt = now
                if let timestampStr = json["timestamp"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: timestampStr) {
                        updatedAt = date.timeIntervalSince1970 * 1000
                    }
                }

                let createdAt = (json["createdAt"] as? Double) ?? (json["createdAt"] as? Int).map { Double($0) } ?? updatedAt
                let docUpdatedAt = (json["updatedAt"] as? Double) ?? (json["updatedAt"] as? Int).map { Double($0) } ?? updatedAt
                let version = json["version"] as? Int ?? 1

                let doc = SyncDocument(
                    id: msgDocId,
                    data: docData,
                    createdAt: createdAt,
                    updatedAt: docUpdatedAt,
                    version: version
                )
                RiviumSyncLogger.i("listenDocument: Created document from MQTT data: id=\(doc.id), version=\(doc.version)")
                DispatchQueue.main.async {
                    callback(doc)
                }
            } else {
                // Fallback to refetch if no data in message
                RiviumSyncLogger.i("listenDocument: No data in MQTT message, refetching from API")
                Task {
                    do {
                        let document = try await self.get(documentId: documentId)
                        DispatchQueue.main.async {
                            callback(document)
                        }
                    } catch {
                        RiviumSyncLogger.e("Failed to refetch document after change", error: error)
                    }
                }
            }
        }

        return ListenerRegistrationImpl { [mqttManager, handle] in
            mqttManager.unsubscribe(handle: handle)
        }
    }
}

/// Implementation of ListenerRegistration
private class ListenerRegistrationImpl: ListenerRegistration {
    private let onRemove: () -> Void
    
    init(onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
    }
    
    func remove() {
        onRemove()
    }
}

/// Implementation of SyncQuery
internal class SyncQueryImpl: SyncQuery {
    private let databaseId: String
    private let collectionId: String
    private let apiClient: ApiClient
    private let mqttManager: MqttManager
    private var params = QueryParams()
    
    init(databaseId: String, collectionId: String, apiClient: ApiClient, mqttManager: MqttManager) {
        self.databaseId = databaseId
        self.collectionId = collectionId
        self.apiClient = apiClient
        self.mqttManager = mqttManager
    }
    
    func `where`(_ field: String, _ op: QueryOperator, _ value: Any?) -> SyncQuery {
        params.filters.append([
            "field": field,
            "operator": op.rawValue,
            "value": value ?? NSNull()
        ])
        return self
    }
    
    func orderBy(_ field: String, direction: OrderDirection = .ascending) -> SyncQuery {
        params.orderByField = field
        params.orderDirection = direction.rawValue
        return self
    }
    
    func limit(_ count: Int) -> SyncQuery {
        params.limitCount = count
        return self
    }
    
    func offset(_ count: Int) -> SyncQuery {
        params.offsetCount = count
        return self
    }
    
    func get() async throws -> [SyncDocument] {
        return try await apiClient.queryDocuments(databaseId: databaseId, collectionId: collectionId, query: params)
    }
    
    func get(onSuccess: @escaping ([SyncDocument]) -> Void, onError: @escaping (Error) -> Void) {
        Task {
            do {
                let docs = try await get()
                DispatchQueue.main.async {
                    onSuccess(docs)
                }
            } catch {
                DispatchQueue.main.async {
                    onError(error)
                }
            }
        }
    }
    
    func listen(callback: @escaping ([SyncDocument]) -> Void) -> ListenerRegistration {
        let topic = mqttManager.collectionTopic(databaseId: databaseId, collectionId: collectionId)
        
        // Initial fetch with query
        Task {
            do {
                let documents = try await get()
                DispatchQueue.main.async {
                    callback(documents)
                }
            } catch {
                RiviumSyncLogger.e("Failed to fetch initial query results", error: error)
            }
        }
        
        // Subscribe to MQTT changes and re-run query
        // Note: We capture self strongly here because the query instance needs to stay alive
        // for the lifetime of the subscription. The ListenerRegistration will unsubscribe when removed.
        let handle = mqttManager.subscribe(topic: topic) { [self] _ in
            Task {
                do {
                    let documents = try await self.get()
                    DispatchQueue.main.async {
                        callback(documents)
                    }
                } catch {
                    RiviumSyncLogger.e("Failed to refetch query results after change", error: error)
                }
            }
        }

        return ListenerRegistrationImpl { [mqttManager, handle] in
            mqttManager.unsubscribe(handle: handle)
        }
    }
}
