import Foundation

/// Protocol for RiviumSync database operations
public protocol SyncDatabase {
    var id: String { get }
    var name: String { get }
    
    /// Get a collection reference by ID or name
    func collection(_ collectionIdOrName: String) -> SyncCollection
    
    /// List all collections in this database
    func listCollections() async throws -> [CollectionInfo]
    
    /// Create a new collection in this database
    func createCollection(name: String) async throws -> SyncCollection
    
    /// Delete a collection
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

    func collection(_ collectionIdOrName: String) -> SyncCollection {
        return SyncCollectionImpl(
            id: collectionIdOrName,
            name: collectionIdOrName,
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
        return SyncCollectionImpl(
            id: info.id,
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
