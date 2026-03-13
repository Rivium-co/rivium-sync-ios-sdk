import Foundation
import Combine

/// Manages local storage for offline persistence
public class LocalStorageManager {

    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let operationsDirectory: URL

    private var documentCache: [String: CachedDocument] = [:]
    private var operationsCache: [String: PendingOperation] = [:]
    private let cacheLock = NSLock()

    // Publishers for reactive updates
    private let documentsSubject = PassthroughSubject<[String: [SyncDocument]], Never>()
    private let documentSubject = PassthroughSubject<(String, SyncDocument?), Never>()
    private let pendingCountSubject = CurrentValueSubject<Int, Never>(0)

    public var pendingCountPublisher: AnyPublisher<Int, Never> {
        pendingCountSubject.eraseToAnyPublisher()
    }

    public init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let riviumSyncDir = appSupport.appendingPathComponent("RiviumSync", isDirectory: true)
        documentsDirectory = riviumSyncDir.appendingPathComponent("documents", isDirectory: true)
        operationsDirectory = riviumSyncDir.appendingPathComponent("operations", isDirectory: true)

        // Create directories
        try? fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: operationsDirectory, withIntermediateDirectories: true)

        // Load cached data
        loadAllDocuments()
        loadAllOperations()
        updatePendingCount()

        RiviumSyncLogger.d("LocalStorageManager: Initialized with \(documentCache.count) documents, \(operationsCache.count) operations")
    }

    // MARK: - Document Operations

    /// Save a document to local cache
    public func saveDocument(
        document: SyncDocument,
        databaseId: String,
        collectionId: String,
        syncStatus: SyncStatus,
        baseVersion: Int? = nil
    ) {
        let cached = CachedDocument.fromSyncDocument(
            document,
            databaseId: databaseId,
            collectionId: collectionId,
            syncStatus: syncStatus,
            baseVersion: baseVersion
        )

        cacheLock.lock()
        documentCache[document.id] = cached
        cacheLock.unlock()

        persistDocument(cached)
        notifyDocumentChange(documentId: document.id, databaseId: databaseId, collectionId: collectionId)
        updatePendingCount()

        RiviumSyncLogger.d("LocalStorage: Saved document \(document.id) with status \(syncStatus)")
    }

    /// Save multiple documents
    public func saveDocuments(
        documents: [SyncDocument],
        databaseId: String,
        collectionId: String,
        syncStatus: SyncStatus
    ) {
        cacheLock.lock()
        for doc in documents {
            let cached = CachedDocument.fromSyncDocument(
                doc,
                databaseId: databaseId,
                collectionId: collectionId,
                syncStatus: syncStatus
            )
            documentCache[doc.id] = cached
            persistDocument(cached)
        }
        cacheLock.unlock()

        notifyCollectionChange(databaseId: databaseId, collectionId: collectionId)
        updatePendingCount()
        RiviumSyncLogger.d("LocalStorage: Saved \(documents.count) documents")
    }

    /// Get a document from local cache
    public func getDocument(documentId: String) -> SyncDocument? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return documentCache[documentId]?.toSyncDocument()
    }

    /// Get all documents in a collection
    public func getDocuments(databaseId: String, collectionId: String) -> [SyncDocument] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return documentCache.values
            .filter { $0.databaseId == databaseId && $0.collectionId == collectionId && $0.syncStatus != .pendingDelete }
            .map { $0.toSyncDocument() }
    }

    /// Get documents as a publisher
    public func getDocumentsPublisher(databaseId: String, collectionId: String) -> AnyPublisher<[SyncDocument], Never> {
        // Initial value + updates
        let initial = Just(getDocuments(databaseId: databaseId, collectionId: collectionId))
        let updates = documentsSubject
            .compactMap { dict -> [SyncDocument]? in
                guard let key = dict.keys.first, key == "\(databaseId)/\(collectionId)" else { return nil }
                return dict[key]
            }
        return initial.merge(with: updates).eraseToAnyPublisher()
    }

    /// Get document as a publisher
    public func getDocumentPublisher(documentId: String) -> AnyPublisher<SyncDocument?, Never> {
        let initial = Just(getDocument(documentId: documentId))
        let updates = documentSubject
            .filter { $0.0 == documentId }
            .map { $0.1 }
        return initial.merge(with: updates).eraseToAnyPublisher()
    }

    /// Delete a document from local cache
    public func deleteDocument(documentId: String) {
        cacheLock.lock()
        let cached = documentCache.removeValue(forKey: documentId)
        cacheLock.unlock()

        let fileUrl = documentsDirectory.appendingPathComponent("\(documentId).json")
        try? fileManager.removeItem(at: fileUrl)

        if let doc = cached {
            notifyDocumentChange(documentId: documentId, databaseId: doc.databaseId, collectionId: doc.collectionId)
        }
        updatePendingCount()

        RiviumSyncLogger.d("LocalStorage: Deleted document \(documentId)")
    }

    /// Mark a document for pending delete
    public func markPendingDelete(documentId: String, databaseId: String, collectionId: String, baseVersion: Int) {
        cacheLock.lock()
        if var existing = documentCache[documentId] {
            existing.syncStatus = .pendingDelete
            existing.baseVersion = baseVersion
            existing.localUpdatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            documentCache[documentId] = existing
            persistDocument(existing)
        }
        cacheLock.unlock()

        updatePendingCount()
        RiviumSyncLogger.d("LocalStorage: Marked document \(documentId) for deletion")
    }

    /// Update sync status for a document
    public func updateSyncStatus(documentId: String, status: SyncStatus, error: String? = nil) {
        cacheLock.lock()
        if var cached = documentCache[documentId] {
            cached.syncStatus = status
            cached.lastError = error
            if status == .syncFailed {
                cached.retryCount += 1
            }
            documentCache[documentId] = cached
            persistDocument(cached)
        }
        cacheLock.unlock()

        updatePendingCount()
        RiviumSyncLogger.d("LocalStorage: Updated sync status for \(documentId) to \(status)")
    }

    // MARK: - Pending Documents

    /// Get all documents with pending sync status
    public func getPendingDocuments() -> [CachedDocument] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return documentCache.values.filter {
            $0.syncStatus == .pendingCreate ||
            $0.syncStatus == .pendingUpdate ||
            $0.syncStatus == .pendingDelete ||
            $0.syncStatus == .syncFailed
        }
    }

    /// Get count of pending operations
    public func getPendingCount() -> Int {
        return getPendingDocuments().count
    }

    // MARK: - Cache Management

    /// Clear all local cache
    public func clearAll() {
        cacheLock.lock()
        documentCache.removeAll()
        operationsCache.removeAll()
        cacheLock.unlock()

        try? fileManager.removeItem(at: documentsDirectory)
        try? fileManager.removeItem(at: operationsDirectory)
        try? fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: operationsDirectory, withIntermediateDirectories: true)

        updatePendingCount()
        RiviumSyncLogger.d("LocalStorage: Cleared all cache")
    }

    /// Get cache size (number of documents)
    public func getCacheSize() -> Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return documentCache.count
    }

    /// Evict old documents to make room for new ones
    public func evictOldDocuments(maxCacheSize: Int) {
        cacheLock.lock()
        let currentSize = documentCache.count
        if currentSize > maxCacheSize {
            // Get synced documents sorted by local update time
            let syncedDocs = documentCache.values
                .filter { $0.syncStatus == .synced }
                .sorted { $0.localUpdatedAt < $1.localUpdatedAt }

            let toEvict = currentSize - maxCacheSize
            for doc in syncedDocs.prefix(toEvict) {
                documentCache.removeValue(forKey: doc.id)
                let fileUrl = documentsDirectory.appendingPathComponent("\(doc.id).json")
                try? fileManager.removeItem(at: fileUrl)
            }
            RiviumSyncLogger.d("LocalStorage: Evicted \(toEvict) old documents")
        }
        cacheLock.unlock()
    }

    /// Clear cache for a specific collection
    public func clearCollection(databaseId: String, collectionId: String) {
        cacheLock.lock()
        let toRemove = documentCache.values.filter {
            $0.databaseId == databaseId && $0.collectionId == collectionId
        }
        for doc in toRemove {
            documentCache.removeValue(forKey: doc.id)
            let fileUrl = documentsDirectory.appendingPathComponent("\(doc.id).json")
            try? fileManager.removeItem(at: fileUrl)
        }
        cacheLock.unlock()

        updatePendingCount()
        RiviumSyncLogger.d("LocalStorage: Cleared collection \(collectionId) cache")
    }

    // MARK: - Private Helpers

    private func loadAllDocuments() {
        guard let files = try? fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let doc = try? decoder.decode(CachedDocument.self, from: data) else {
                continue
            }
            documentCache[doc.id] = doc
        }
    }

    private func loadAllOperations() {
        guard let files = try? fileManager.contentsOfDirectory(at: operationsDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let op = try? decoder.decode(PendingOperation.self, from: data) else {
                continue
            }
            operationsCache[op.id] = op
        }
    }

    private func persistDocument(_ doc: CachedDocument) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(doc) else { return }
        let fileUrl = documentsDirectory.appendingPathComponent("\(doc.id).json")
        try? data.write(to: fileUrl)
    }

    private func updatePendingCount() {
        pendingCountSubject.send(getPendingCount())
    }

    private func notifyDocumentChange(documentId: String, databaseId: String, collectionId: String) {
        let doc = getDocument(documentId: documentId)
        documentSubject.send((documentId, doc))
        notifyCollectionChange(databaseId: databaseId, collectionId: collectionId)
    }

    private func notifyCollectionChange(databaseId: String, collectionId: String) {
        let docs = getDocuments(databaseId: databaseId, collectionId: collectionId)
        let key = "\(databaseId)/\(collectionId)"
        documentsSubject.send([key: docs])
    }
}
