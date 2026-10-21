import XCTest
@testable import RiviumSync

/// X-Rivium-SDK: `ios/<version>`, or the wrapper first with the native SDK underneath.
final class SdkHeaderTests: XCTestCase {

    func testSdkVersionMatchesPodspec() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let spec = try String(contentsOf: root.appendingPathComponent("RiviumSync.podspec"), encoding: .utf8)
        XCTAssertTrue(
            spec.contains("s.version          = '\(RiviumSync.version)'"),
            "RiviumSync.podspec version does not match RiviumSync.version (\(RiviumSync.version))"
        )
    }

    func testEveryRequestCarriesNativeIdentity() async throws {
        let api = ApiClient(config: RiviumSyncConfig(apiKey: "rv_live_test"))
        for endpoint in ["/databases", "/connections/token"] {
            let request = try await api.buildRequest(endpoint: endpoint, method: "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Rivium-SDK"), "ios/\(RiviumSync.version)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "rv_live_test")
        }
    }

    func testWrapperIsReportedFirst() async throws {
        let config = RiviumSyncConfigBuilder(apiKey: "rv_live_test").wrapperSdk(name: "flutter", version: "0.2.4").build()
        let request = try await ApiClient(config: config).buildRequest(endpoint: "/databases")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Rivium-SDK"), "flutter/0.2.4 ios/\(RiviumSync.version)")
    }

    func testInvalidOrHalfSetWrapperFallsBackToNative() {
        let native = "ios/\(RiviumSync.version)"
        XCTAssertEqual(RiviumSyncConfig(apiKey: "k").sdkHeaderValue, native)
        XCTAssertEqual(RiviumSyncConfig(apiKey: "k", wrapperSdkName: "flutter").sdkHeaderValue, native)
        XCTAssertEqual(RiviumSyncConfig(apiKey: "k", wrapperSdkName: "flut ter", wrapperSdkVersion: "1.0").sdkHeaderValue, native)
        XCTAssertEqual(RiviumSyncConfig(apiKey: "k", wrapperSdkName: String(repeating: "x", count: 33), wrapperSdkVersion: "1.0").sdkHeaderValue, native)
        XCTAssertEqual(
            RiviumSyncConfig(apiKey: "k", wrapperSdkName: "react-native", wrapperSdkVersion: "1.0.0+2").sdkHeaderValue,
            "react-native/1.0.0+2 \(native)"
        )
    }
}
