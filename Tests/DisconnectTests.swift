import XCTest
@testable import RiviumSync

/// `disconnect()` tells the app at once. Found 2026-10-26 in the Flutter example on the iOS Simulator: the closed socket
/// is released and never reports closing, so the app kept showing "Connected" (and Disconnect seemed to do nothing)
/// while the SDK was offline and queueing every write.
final class DisconnectTests: XCTestCase {
    private final class Recorder: RiviumSyncDelegate {
        var disconnects = 0
        func riviumSync(_ riviumSync: RiviumSync, didDisconnectWithError error: Error?) { disconnects += 1 }
    }

    func testDisconnectTellsTheDelegateAndGoesOffline() {
        let sync = RiviumSync.initialize(config: RiviumSyncConfigBuilder(apiKey: "rv_live_test").offlineEnabled(true).build())
        let recorder = Recorder()
        sync.delegate = recorder

        sync.disconnect()

        XCTAssertEqual(recorder.disconnects, 1)
        XCTAssertEqual(sync.syncState, .offline)
    }
}
