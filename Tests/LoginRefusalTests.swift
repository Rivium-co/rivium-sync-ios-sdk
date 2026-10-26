import XCTest
import PNProtocol
@testable import RiviumSync

/// A refused realtime login (expired token) is told apart from network trouble: only a refused login fetches a new
/// token, anything else is the socket's to retry. PNProtocol 0.2.1 reports it as a rejected connection, later
/// versions as authFailed. Found 2026-10-26 on Android (same PN design): after the token expired every reconnect was
/// refused and realtime stayed down.
final class LoginRefusalTests: XCTestCase {
    func testRefusedLoginsInBothPNProtocolForms() {
        XCTAssertTrue(MqttManager.isLoginRefused(PNError.connectionFailed("Connection rejected: notAuthorized")))
        XCTAssertTrue(MqttManager.isLoginRefused(PNError.connectionFailed("Connection rejected: badUsernameOrPassword")))
        XCTAssertTrue(MqttManager.isLoginRefused(PNError.authFailed("Connection rejected: notAuthorized")))
    }

    func testNetworkTroubleAndOtherRejectionsAreNot() {
        XCTAssertFalse(MqttManager.isLoginRefused(PNError.connectionFailed("Connection rejected: serverUnavailable")))
        XCTAssertFalse(MqttManager.isLoginRefused(PNError.connectionFailed("Connection rejected: identifierRejected")))
        XCTAssertFalse(MqttManager.isLoginRefused(PNError.connectionFailed("The network connection was lost.")))
    }
}
