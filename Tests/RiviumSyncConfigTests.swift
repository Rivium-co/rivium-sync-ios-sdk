import XCTest
@testable import RiviumSync

/// Comprehensive tests for RiviumSyncConfig and RiviumSyncConfigBuilder
final class RiviumSyncConfigTests: XCTestCase {

    // MARK: - Valid API Key Formats

    func testBuilderAcceptsValidLiveApiKey() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_live_abc123xyz789")
            .build()

        XCTAssertEqual(config.apiKey, "nl_live_abc123xyz789")
    }

    func testBuilderAcceptsValidTestApiKey() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123xyz789")
            .build()

        XCTAssertEqual(config.apiKey, "nl_test_abc123xyz789")
    }

    func testBuilderAcceptsLongApiKey() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_live_abcdefghijklmnop")
            .build()

        XCTAssertEqual(config.apiKey, "nl_live_abcdefghijklmnop")
    }

    // MARK: - Default Values

    func testBuilderSetsCorrectDefaultValues() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .build()

        XCTAssertFalse(config.debugMode)
        XCTAssertTrue(config.autoReconnect)
        XCTAssertFalse(config.offlineEnabled)
        XCTAssertEqual(config.offlineCacheSizeMb, 100)
        XCTAssertTrue(config.syncOnReconnect)
        XCTAssertEqual(config.conflictStrategy, .serverWins)
        XCTAssertNil(config.conflictResolver)
        XCTAssertEqual(config.maxSyncRetries, 3)
    }

    // MARK: - debugMode

    func testDebugModeCanBeEnabled() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .debugMode(true)
            .build()

        XCTAssertTrue(config.debugMode)
    }

    func testDebugModeCanBeDisabled() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .debugMode(true)
            .debugMode(false) // Override
            .build()

        XCTAssertFalse(config.debugMode)
    }

    // MARK: - autoReconnect

    func testAutoReconnectCanBeDisabled() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .autoReconnect(false)
            .build()

        XCTAssertFalse(config.autoReconnect)
    }

    func testAutoReconnectCanBeEnabledExplicitly() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .autoReconnect(true)
            .build()

        XCTAssertTrue(config.autoReconnect)
    }

    // MARK: - offlineEnabled

    func testOfflineEnabledCanBeEnabled() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .offlineEnabled(true)
            .build()

        XCTAssertTrue(config.offlineEnabled)
    }

    func testOfflineEnabledDefaultsToFalse() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .build()

        XCTAssertFalse(config.offlineEnabled)
    }

    // MARK: - offlineCacheSizeMb

    func testOfflineCacheSizeMbAcceptsValidPositiveValue() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .offlineCacheSizeMb(50)
            .build()

        XCTAssertEqual(config.offlineCacheSizeMb, 50)
    }

    func testOfflineCacheSizeMbAcceptsLargeValue() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .offlineCacheSizeMb(500)
            .build()

        XCTAssertEqual(config.offlineCacheSizeMb, 500)
    }

    func testOfflineCacheSizeMbDefaultValue() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .build()

        XCTAssertEqual(config.offlineCacheSizeMb, 100)
    }

    // MARK: - syncOnReconnect

    func testSyncOnReconnectCanBeDisabled() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .syncOnReconnect(false)
            .build()

        XCTAssertFalse(config.syncOnReconnect)
    }

    func testSyncOnReconnectDefaultsToTrue() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .build()

        XCTAssertTrue(config.syncOnReconnect)
    }

    // MARK: - conflictStrategy

    func testConflictStrategyServerWins() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .conflictStrategy(.serverWins)
            .build()

        XCTAssertEqual(config.conflictStrategy, .serverWins)
    }

    func testConflictStrategyClientWins() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .conflictStrategy(.clientWins)
            .build()

        XCTAssertEqual(config.conflictStrategy, .clientWins)
    }

    func testConflictStrategyMerge() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .conflictStrategy(.merge)
            .build()

        XCTAssertEqual(config.conflictStrategy, .merge)
    }

    func testConflictStrategyManual() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .conflictStrategy(.manual)
            .build()

        XCTAssertEqual(config.conflictStrategy, .manual)
    }

    func testConflictStrategyDefaultsToServerWins() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .build()

        XCTAssertEqual(config.conflictStrategy, .serverWins)
    }

    // MARK: - maxSyncRetries

    func testMaxSyncRetriesAcceptsPositiveValue() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .maxSyncRetries(5)
            .build()

        XCTAssertEqual(config.maxSyncRetries, 5)
    }

    func testMaxSyncRetriesDefaultValue() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .build()

        XCTAssertEqual(config.maxSyncRetries, 3)
    }

    // MARK: - Custom URLs

    func testApiUrlCanBeSet() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .apiUrl("https://custom.api.com")
            .build()

        XCTAssertEqual(config.apiUrl, "https://custom.api.com")
    }

    func testMqttHostCanBeSet() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .mqttHost("custom.mqtt.com")
            .build()

        XCTAssertEqual(config.mqttHost, "custom.mqtt.com")
    }

    func testMqttPortCanBeSet() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .mqttPort(1883)
            .build()

        XCTAssertEqual(config.mqttPort, 1883)
    }

    func testMqttUseTlsCanBeDisabled() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .mqttUseTls(false)
            .build()

        XCTAssertFalse(config.mqttUseTls)
    }

    // MARK: - Connection Settings

    func testConnectionTimeoutCanBeSet() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .connectionTimeout(60)
            .build()

        XCTAssertEqual(config.connectionTimeout, 60)
    }

    func testKeepAliveIntervalCanBeSet() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .keepAliveInterval(120)
            .build()

        XCTAssertEqual(config.keepAliveInterval, 120)
    }

    func testReconnectIntervalCanBeSet() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .reconnectInterval(10.0)
            .build()

        XCTAssertEqual(config.reconnectInterval, 10.0, accuracy: 0.001)
    }

    // MARK: - Builder Method Chaining

    func testBuilderMethodChaining() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .debugMode(true)
            .autoReconnect(false)
            .offlineEnabled(true)
            .offlineCacheSizeMb(200)
            .syncOnReconnect(false)
            .conflictStrategy(.clientWins)
            .maxSyncRetries(5)
            .connectionTimeout(45)
            .build()

        XCTAssertEqual(config.apiKey, "nl_test_abc123")
        XCTAssertTrue(config.debugMode)
        XCTAssertFalse(config.autoReconnect)
        XCTAssertTrue(config.offlineEnabled)
        XCTAssertEqual(config.offlineCacheSizeMb, 200)
        XCTAssertFalse(config.syncOnReconnect)
        XCTAssertEqual(config.conflictStrategy, .clientWins)
        XCTAssertEqual(config.maxSyncRetries, 5)
        XCTAssertEqual(config.connectionTimeout, 45)
    }

    // MARK: - Direct Init

    func testDirectInitWithAllParameters() {
        let config = RiviumSyncConfig(
            apiKey: "nl_live_xyz789",
            apiUrl: "https://api.example.com",
            mqttHost: "mqtt.example.com",
            mqttPort: 8883,
            mqttUseTls: true,
            debugMode: true,
            autoReconnect: false,
            reconnectInterval: 10,
            connectionTimeout: 60,
            keepAliveInterval: 120,
            offlineEnabled: true,
            offlineCacheSizeMb: 250,
            syncOnReconnect: false,
            conflictStrategy: .merge,
            conflictResolver: nil,
            maxSyncRetries: 7
        )

        XCTAssertEqual(config.apiKey, "nl_live_xyz789")
        XCTAssertEqual(config.apiUrl, "https://api.example.com")
        XCTAssertEqual(config.mqttHost, "mqtt.example.com")
        XCTAssertEqual(config.mqttPort, 8883)
        XCTAssertTrue(config.mqttUseTls)
        XCTAssertTrue(config.debugMode)
        XCTAssertFalse(config.autoReconnect)
        XCTAssertEqual(config.reconnectInterval, 10)
        XCTAssertEqual(config.connectionTimeout, 60)
        XCTAssertEqual(config.keepAliveInterval, 120)
        XCTAssertTrue(config.offlineEnabled)
        XCTAssertEqual(config.offlineCacheSizeMb, 250)
        XCTAssertFalse(config.syncOnReconnect)
        XCTAssertEqual(config.conflictStrategy, .merge)
        XCTAssertEqual(config.maxSyncRetries, 7)
    }

    // MARK: - mqttServerUri

    func testMqttServerUriWithTls() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .mqttHost("mqtt.example.com")
            .mqttPort(8883)
            .mqttUseTls(true)
            .build()

        XCTAssertEqual(config.mqttServerUri, "mqtts://mqtt.example.com:8883")
    }

    func testMqttServerUriWithoutTls() {
        let config = RiviumSyncConfigBuilder(apiKey: "nl_test_abc123")
            .mqttHost("mqtt.example.com")
            .mqttPort(1883)
            .mqttUseTls(false)
            .build()

        XCTAssertEqual(config.mqttServerUri, "mqtt://mqtt.example.com:1883")
    }
}
