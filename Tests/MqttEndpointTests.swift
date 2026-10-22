import XCTest
@testable import RiviumSync

final class MqttEndpointTests: XCTestCase {
    private let fallback = MqttEndpoint(host: "mqtt-sync.rivium.co", port: 8885, useTls: true)

    func testUsesTheServersEndpointWhenValid() {
        XCTAssertEqual(MqttEndpoint.resolve(host: "mqtt-sync.rivium.co", port: 8885, useTls: true, default: fallback), MqttEndpoint(host: "mqtt-sync.rivium.co", port: 8885, useTls: true))
        XCTAssertEqual(MqttEndpoint.resolve(host: "Rivium.co ", port: 443, useTls: true, default: fallback), MqttEndpoint(host: "rivium.co", port: 443, useTls: true))
    }

    func testFallsBackWhenMissingOrIncomplete() {
        XCTAssertEqual(MqttEndpoint.resolve(host: nil, port: nil, useTls: nil, default: fallback), fallback)
        XCTAssertEqual(MqttEndpoint.resolve(host: "mqtt-sync.rivium.co", port: nil, useTls: true, default: fallback), fallback)
        XCTAssertEqual(MqttEndpoint.resolve(host: "mqtt-sync.rivium.co", port: 8885, useTls: nil, default: fallback), fallback)
    }

    func testNeverAnotherDomainOrInvalidPort() {
        for host in ["evil.com", "rivium.co.evil.com", "evilrivium.co", "mqtt-sync.rivium.com", "10.0.0.1", "mqtt sync.rivium.co", "-x.rivium.co"] {
            XCTAssertEqual(MqttEndpoint.resolve(host: host, port: 8885, useTls: true, default: fallback), fallback, host)
        }
        for port in [0, -1, 65536] {
            XCTAssertEqual(MqttEndpoint.resolve(host: "mqtt-sync.rivium.co", port: port, useTls: true, default: fallback), fallback)
        }
    }

    func testNeverUnencryptedWhateverTheServerAnswers() {
        XCTAssertEqual(MqttEndpoint.resolve(host: "mqtt-sync.rivium.co", port: 1884, useTls: false, default: fallback), fallback)
        XCTAssertEqual(MqttEndpoint.resolve(host: "other.rivium.co", port: 1884, useTls: false, default: fallback), fallback)
    }

    func testTheBuiltInEndpointsAreEncrypted() {
        let config = RiviumSyncConfig(apiKey: "rv_live_x")
        XCTAssertEqual(MqttEndpoint(host: config.mqttHost, port: config.mqttPort, useTls: config.mqttUseTls), fallback)
        XCTAssertEqual(config.mqttServerUri, "mqtts://mqtt-sync.rivium.co:8885")
        XCTAssertEqual(config.apiUrl, "https://sync.rivium.co")
    }
}
