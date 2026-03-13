import Foundation

/// Configuration for RiviumSync SDK
public struct RiviumSyncConfig {
    /// Your RiviumSync API key from AuthLeap Console (rv_live_xxx or rv_test_xxx)
    public let apiKey: String
    /// Optional user/device identifier for Security Rules (used as auth.uid).
    /// If not provided, the SDK auto-generates a stable device ID.
    public let userId: String?
    public let apiUrl: String
    public let mqttHost: String
    public let mqttPort: Int
    public let mqttUseTls: Bool
    public let debugMode: Bool
    public let autoReconnect: Bool
    public let reconnectInterval: TimeInterval
    public let connectionTimeout: Int
    public let keepAliveInterval: Int

    // Offline persistence options
    public let offlineEnabled: Bool
    public let offlineCacheSizeMb: Int
    public let syncOnReconnect: Bool
    public let conflictStrategy: ConflictStrategy
    public let conflictResolver: ConflictResolver?
    public let maxSyncRetries: Int

    private static let defaultApiUrl = "https://sync.rivium.co"
    // TCP connection (DNS-only mode in Cloudflare for mqtt-sync subdomain)
    // Same as Android - CocoaMQTT works well with plain TCP
    private static let defaultMqttHost = "mqtt-sync.rivium.co"
    private static let defaultMqttPort = 1884
    private static let defaultMqttUseTls = false
    private static let defaultOfflineCacheSizeMb = 100
    private static let defaultMaxSyncRetries = 3

    public init(
        apiKey: String,
        userId: String? = nil,
        apiUrl: String? = nil,
        mqttHost: String? = nil,
        mqttPort: Int? = nil,
        mqttUseTls: Bool? = nil,
        debugMode: Bool = false,
        autoReconnect: Bool = true,
        reconnectInterval: TimeInterval = 5.0,
        connectionTimeout: Int = 30,
        keepAliveInterval: Int = 60,
        offlineEnabled: Bool = false,
        offlineCacheSizeMb: Int? = nil,
        syncOnReconnect: Bool = true,
        conflictStrategy: ConflictStrategy = .serverWins,
        conflictResolver: ConflictResolver? = nil,
        maxSyncRetries: Int? = nil
    ) {
        precondition(!apiKey.isEmpty, "API key cannot be empty")

        self.apiKey = apiKey
        self.userId = userId
        self.apiUrl = apiUrl ?? Self.defaultApiUrl
        self.mqttHost = mqttHost ?? Self.defaultMqttHost
        self.mqttPort = mqttPort ?? Self.defaultMqttPort
        self.mqttUseTls = mqttUseTls ?? Self.defaultMqttUseTls
        self.debugMode = debugMode
        self.autoReconnect = autoReconnect
        self.reconnectInterval = reconnectInterval
        self.connectionTimeout = connectionTimeout
        self.keepAliveInterval = keepAliveInterval
        self.offlineEnabled = offlineEnabled
        self.offlineCacheSizeMb = offlineCacheSizeMb ?? Self.defaultOfflineCacheSizeMb
        self.syncOnReconnect = syncOnReconnect
        self.conflictStrategy = conflictStrategy
        self.conflictResolver = conflictResolver
        self.maxSyncRetries = maxSyncRetries ?? Self.defaultMaxSyncRetries
    }

    internal var mqttServerUri: String {
        let scheme = mqttUseTls ? "mqtts" : "mqtt"
        return "\(scheme)://\(mqttHost):\(mqttPort)"
    }
}

/// Builder for RiviumSyncConfig
public class RiviumSyncConfigBuilder {
    /// Your RiviumSync API key from AuthLeap Console (rv_live_xxx or rv_test_xxx)
    private let apiKey: String
    private var userId: String?
    private var apiUrl: String?
    private var mqttHost: String?
    private var mqttPort: Int?
    private var mqttUseTls: Bool = false  // Default to plain TCP like Android
    private var debugMode: Bool = false
    private var autoReconnect: Bool = true
    private var reconnectInterval: TimeInterval = 5.0
    private var connectionTimeout: Int = 30
    private var keepAliveInterval: Int = 60
    private var offlineEnabled: Bool = false
    private var offlineCacheSizeMb: Int?
    private var syncOnReconnect: Bool = true
    private var conflictStrategy: ConflictStrategy = .serverWins
    private var conflictResolver: ConflictResolver?
    private var maxSyncRetries: Int?

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Set user/device identifier for Security Rules (used as auth.uid).
    /// If not set, the SDK auto-generates a stable device ID.
    public func userId(_ userId: String) -> Self {
        self.userId = userId
        return self
    }

    public func apiUrl(_ url: String) -> Self {
        self.apiUrl = url
        return self
    }

    public func mqttHost(_ host: String) -> Self {
        self.mqttHost = host
        return self
    }

    public func mqttPort(_ port: Int) -> Self {
        self.mqttPort = port
        return self
    }

    public func mqttUseTls(_ useTls: Bool) -> Self {
        self.mqttUseTls = useTls
        return self
    }

    public func debugMode(_ debug: Bool) -> Self {
        self.debugMode = debug
        return self
    }

    public func autoReconnect(_ autoReconnect: Bool) -> Self {
        self.autoReconnect = autoReconnect
        return self
    }

    public func reconnectInterval(_ interval: TimeInterval) -> Self {
        self.reconnectInterval = interval
        return self
    }

    public func connectionTimeout(_ timeout: Int) -> Self {
        self.connectionTimeout = timeout
        return self
    }

    public func keepAliveInterval(_ interval: Int) -> Self {
        self.keepAliveInterval = interval
        return self
    }

    /// Enable offline persistence
    public func offlineEnabled(_ enabled: Bool) -> Self {
        self.offlineEnabled = enabled
        return self
    }

    /// Set the maximum cache size in megabytes
    public func offlineCacheSizeMb(_ sizeMb: Int) -> Self {
        self.offlineCacheSizeMb = sizeMb
        return self
    }

    /// Automatically sync pending operations when connection is restored
    public func syncOnReconnect(_ sync: Bool) -> Self {
        self.syncOnReconnect = sync
        return self
    }

    /// Set the conflict resolution strategy
    public func conflictStrategy(_ strategy: ConflictStrategy) -> Self {
        self.conflictStrategy = strategy
        return self
    }

    /// Set a custom conflict resolver for manual conflict strategy
    public func conflictResolver(_ resolver: ConflictResolver) -> Self {
        self.conflictResolver = resolver
        return self
    }

    /// Set maximum number of sync retries
    public func maxSyncRetries(_ retries: Int) -> Self {
        self.maxSyncRetries = retries
        return self
    }

    public func build() -> RiviumSyncConfig {
        return RiviumSyncConfig(
            apiKey: apiKey,
            userId: userId,
            apiUrl: apiUrl,
            mqttHost: mqttHost,
            mqttPort: mqttPort,
            mqttUseTls: mqttUseTls,
            debugMode: debugMode,
            autoReconnect: autoReconnect,
            reconnectInterval: reconnectInterval,
            connectionTimeout: connectionTimeout,
            keepAliveInterval: keepAliveInterval,
            offlineEnabled: offlineEnabled,
            offlineCacheSizeMb: offlineCacheSizeMb,
            syncOnReconnect: syncOnReconnect,
            conflictStrategy: conflictStrategy,
            conflictResolver: conflictResolver,
            maxSyncRetries: maxSyncRetries
        )
    }
}
