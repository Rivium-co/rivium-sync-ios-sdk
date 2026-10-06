import Foundation

/// Protocol for RiviumSync database operations
public protocol SyncDatabase {
    /// How this database is addressed in API paths and realtime topics. For a
    /// reference from `RiviumSync.database(_:)` this is the database name you passed.
    var id: String { get }
    var name: String { get }
    
    /// Get a collection reference by name.
    ///
    /// - Parameter name: The collection NAME exactly as shown in Rivium Console
    ///   (for example `"todos"`), not its UUID. Realtime updates are published on
    ///   topics that use the name, so `listen` callbacks only fire when you pass the name.
    func collection(_ name: String) -> SyncCollection
    
    /// List all collections in this database
    func listCollections() async throws -> [CollectionInfo]
    
    /// Create a new collection in this database
    func createCollection(name: String) async throws -> SyncCollection
    
    /// Delete a collection.
    ///
    /// - Parameter collectionId: The collection's `id` as returned by `listCollections()`.
    ///   Unlike `collection(_:)`, this call takes the id, not the name.
    func deleteCollection(collectionId: String) async throws
}

/// Internal database implementation
internal class SyncDatabaseImpl: SyncDatabase {
    let id: String
    let name: String
    private let apiClient: ApiClient
    private let mqttManager: MqttManager
    private let localStorageManager: LocalStorageManager?
    private let syncEngine: SyncEngine?

    init(
        id: String,
        name: String,
        apiClient: ApiClient,
        mqttManager: MqttManager,
        localStorageManager: LocalStorageManager? = nil,
        syncEngine: SyncEngine? = nil
    ) {
        self.id = id
        self.name = name
        self.apiClient = apiClient
        self.mqttManager = mqttManager
        self.localStorageManager = localStorageManager
        self.syncEngine = syncEngine
    }

    func collection(_ name: String) -> SyncCollection {
        return SyncCollectionImpl(
            id: name,
            name: name,
            databaseId: id,
            apiClient: apiClient,
            mqttManager: mqttManager,
            localStorageManager: localStorageManager,
            syncEngine: syncEngine
        )
    }

    func listCollections() async throws -> [CollectionInfo] {
        return try await apiClient.listCollections(databaseId: id)
    }

    func createCollection(name: String) async throws -> SyncCollection {
        let info = try await apiClient.createCollection(databaseId: id, name: name)
        // Keyed by name, like collection(_:): realtime topics carry names, so a
        // UUID-keyed collection would never receive live updates.
        return SyncCollectionImpl(
            id: info.name,
            name: info.name,
            databaseId: id,
            apiClient: apiClient,
            mqttManager: mqttManager,
            localStorageManager: localStorageManager,
            syncEngine: syncEngine
        )
    }

    func deleteCollection(collectionId: String) async throws {
        try await apiClient.deleteCollection(collectionId: collectionId)
    }
}
