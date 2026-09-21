import XCTest
@testable import RiviumSync

/// When the app starts offline the token request fails before any MQTT socket
/// exists, so the socket's own autoReconnect never runs. The SDK used to stay
/// "connecting" forever after the network came back; it now retries the whole
/// connect with backoff - and must stop the moment the app disconnects.
final class MqttReconnectTests: XCTestCase {

    /// An API that is offline: every token request fails, and we count them.
    private final class OfflineApiClient: ApiClient {
        private let lock = NSLock()
        private var _calls = 0
        var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }

        override func fetchMqttToken() async throws -> MqttTokenResponse {
            lock.lock(); _calls += 1; lock.unlock()
            throw URLError(.cannotFindHost)
        }
    }

    private func makeManager() -> (MqttManager, OfflineApiClient) {
        let config = RiviumSyncConfigBuilder(apiKey: "rv_live_test").autoReconnect(true).build()
        let api = OfflineApiClient(config: config)
        return (MqttManager(config: config, apiClient: api), api)
    }

    func testRetriesTheConnectAfterTheTokenRequestFails() async throws {
        let (manager, api) = makeManager()
        var completions = 0
        manager.connect { _ in completions += 1 }

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(api.calls, 1)

        try await Task.sleep(nanoseconds: 2_500_000_000) // first retry is due after 2s
        XCTAssertEqual(api.calls, 2)
        // The caller hears about the failure once, never again from a retry:
        // `connect() async` would crash resuming its continuation twice.
        XCTAssertEqual(completions, 1)
        manager.disconnect()
    }

    func testDisconnectCancelsAPendingRetry() async throws {
        let (manager, api) = makeManager()
        manager.connect { _ in }

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(api.calls, 1)

        manager.disconnect()
        try await Task.sleep(nanoseconds: 2_500_000_000) // past when the retry would fire
        XCTAssertEqual(api.calls, 1)
    }
}
