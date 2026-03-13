import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// RiviumSync - Realtime Database SDK
///
/// A Firebase-like realtime database service for instant data synchronization
/// across all connected devices.
///
/// Usage:
/// ```swift
/// // Initialize
/// let config = RiviumSyncConfig(jwtToken: "your-jwt-token")
/// RiviumSync.initialize(config: config)
///
/// // Connect to realtime
/// try await RiviumSync.shared.connect()
///
/// // Get database and collection
/// let db = RiviumSync.shared.database("my-database-id")
/// let todos = db.collection("todos")
///
/// // CRUD operations
/// let doc = try await todos.add(data: ["title": "Buy milk", "completed": false])
///
/// // Listen to realtime changes
/// let listener = todos.listen { documents in
///     print("Todos updated: \(documents.count)")
/// }
/// ```
public class RiviumSync {
    /// Shared singleton instance
    public private(set) static var shared: RiviumSync!

    /// SDK version
    public static let version = "1.0.0"

    private let config: RiviumSyncConfig
    internal let apiClient: ApiClient
    private let mqttManager: MqttManager

    // Offline support
    internal let localStorageManager: LocalStorageManager?
    internal let syncEngine: SyncEngine?
    private var cancellables = Set<AnyCancellable>()

    /// Resolved userId for Security Rules (auth.uid)
    public let userId: String

    /// Connection state delegate
    public weak var delegate: RiviumSyncDelegate?

    private static let prefsKey = "co.rivium.sync.userId"

    private init(config: RiviumSyncConfig) {
        self.config = config

        if config.debugMode {
            RiviumSyncLogger.logLevel = .debug
        }

        self.userId = RiviumSync.getOrCreateUserId(from: config)
        self.apiClient = ApiClient(config: config, userId: userId)
        self.mqttManager = MqttManager(config: config, apiClient: apiClient)

        // Initialize offline components if enabled
        if config.offlineEnabled {
            self.localStorageManager = LocalStorageManager()
            self.syncEngine = SyncEngine(
                apiClient: apiClient,
                localStore: localStorageManager!,
                conflictStrategy: config.conflictStrategy,
                conflictResolver: config.conflictResolver,
                maxRetries: config.maxSyncRetries
            )
            RiviumSyncLogger.i("RiviumSync: Offline persistence enabled")
        } else {
            self.localStorageManager = nil
            self.syncEngine = nil
        }

        // Setup MQTT connection state handling
        setupMqttConnectionHandling()

        RiviumSyncLogger.i("RiviumSync SDK initialized")
    }

    private func setupMqttConnectionHandling() {
        mqttManager.onConnectionStateChanged = { [weak self] connected in
            guard let self = self else { return }
            if connected {
                self.syncEngine?.onConnectionStateChanged(connected: true)
                self.delegate?.riviumSyncDidConnect(self)
            } else {
                self.syncEngine?.onConnectionStateChanged(connected: false)
                self.delegate?.riviumSync(self, didDisconnectWithError: nil)
            }
        }
    }
    
    /// Initialize the SDK with configuration
    /// - Parameter config: SDK configuration
    /// - Returns: RiviumSync instance
    @discardableResult
    public static func initialize(config: RiviumSyncConfig) -> RiviumSync {
        shared = RiviumSync(config: config)
        return shared
    }
    
    /// Check if SDK is initialized
    public static var isInitialized: Bool {
        return shared != nil
    }
    
    /// Connect to realtime sync service
    public func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            mqttManager.connect { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Connect with completion handler
    public func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        mqttManager.connect(completion: completion)
    }
    
    /// Disconnect from realtime sync service
    public func disconnect() {
        mqttManager.disconnect()
        RiviumSyncLogger.i("RiviumSync disconnected")
    }
    
    /// Check if connected to realtime service
    public var isConnected: Bool {
        return mqttManager.isConnected
    }
    
    /// Get a database reference by ID
    public func database(_ databaseId: String) -> SyncDatabase {
        return SyncDatabaseImpl(
            id: databaseId,
            name: "",
            apiClient: apiClient,
            mqttManager: mqttManager,
            localStorageManager: localStorageManager,
            syncEngine: syncEngine
        )
    }

    // MARK: - Batch Operations

    /// Create a new WriteBatch for atomic operations.
    ///
    /// A WriteBatch is used to perform multiple writes as a single atomic unit.
    /// None of the writes will be committed until `commit()` is called.
    ///
    /// Usage:
    /// ```swift
    /// let batch = RiviumSync.shared.batch()
    /// batch.set(usersCollection, documentId: "user1", data: ["name": "John"])
    /// batch.update(ordersCollection, documentId: "order1", data: ["status": "shipped"])
    /// batch.delete(tempCollection, documentId: "temp1")
    /// try await batch.commit()
    /// ```
    ///
    /// - Returns: A new WriteBatch instance
    public func batch() -> WriteBatch {
        return WriteBatch(apiClient: apiClient)
    }

    /// List all databases for the current user
    public func listDatabases() async throws -> [DatabaseInfo] {
        return try await apiClient.listDatabases()
    }

    /// Create a new database
    public func createDatabase(name: String) async throws -> DatabaseInfo {
        return try await apiClient.createDatabase(name: name)
    }

    /// Delete a database
    public func deleteDatabase(databaseId: String) async throws {
        try await apiClient.deleteDatabase(databaseId: databaseId)
    }

    // MARK: - Offline API

    /// Check if offline persistence is enabled
    public var isOfflineEnabled: Bool {
        return config.offlineEnabled
    }

    /// Get the current sync state
    public var syncState: SyncState {
        return syncEngine?.syncState ?? .idle
    }

    /// Get the count of pending operations waiting to be synced
    public var pendingCount: Int {
        return syncEngine?.pendingCount ?? 0
    }

    /// Publisher for sync state changes
    public var syncStatePublisher: AnyPublisher<SyncState, Never>? {
        return syncEngine?.$syncState.eraseToAnyPublisher()
    }

    /// Publisher for pending count changes
    public var pendingCountPublisher: AnyPublisher<Int, Never>? {
        return syncEngine?.$pendingCount.eraseToAnyPublisher()
    }

    /// Force sync all pending operations now
    public func forceSyncNow() {
        syncEngine?.forceSync()
    }

    /// Add a sync listener
    public func addSyncListener(_ listener: SyncEngine.SyncListener) {
        syncEngine?.addSyncListener(listener)
    }

    /// Remove a sync listener
    public func removeSyncListener(_ listener: SyncEngine.SyncListener) {
        syncEngine?.removeSyncListener(listener)
    }

    /// Clear all cached data
    public func clearOfflineCache() {
        localStorageManager?.clearAll()
    }

    /// Release resources
    public func destroy() {
        disconnect()
        syncEngine?.destroy()
        cancellables.removeAll()
        RiviumSyncLogger.i("RiviumSync destroyed")
    }

    private static func getOrCreateUserId(from config: RiviumSyncConfig) -> String {
        // If developer provided a userId, use it
        if let userId = config.userId, !userId.isEmpty {
            return userId
        }

        if let stored = UserDefaults.standard.string(forKey: prefsKey) {
            return stored
        }

        #if canImport(UIKit)
        let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let newId = UUID().uuidString
        #endif
        UserDefaults.standard.set(newId, forKey: prefsKey)
        RiviumSyncLogger.d("Generated new userId: \(newId)")
        return newId
    }
}

/// Delegate for RiviumSync connection events
public protocol RiviumSyncDelegate: AnyObject {
    func riviumSyncDidConnect(_ riviumSync: RiviumSync)
    func riviumSync(_ riviumSync: RiviumSync, didDisconnectWithError error: Error?)
    func riviumSync(_ riviumSync: RiviumSync, didFailToConnectWithError error: Error)
}

/// Default implementation for optional delegate methods
public extension RiviumSyncDelegate {
    func riviumSyncDidConnect(_ riviumSync: RiviumSync) {}
    func riviumSync(_ riviumSync: RiviumSync, didDisconnectWithError error: Error?) {}
    func riviumSync(_ riviumSync: RiviumSync, didFailToConnectWithError error: Error) {}
}
