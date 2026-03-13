import XCTest
@testable import RiviumSync

/// Tests for RiviumSyncLogger and RiviumSyncLogLevel
final class LoggerTests: XCTestCase {

    // MARK: - Log Level Raw Values

    func testDebugLevelRawValue() {
        XCTAssertEqual(RiviumSyncLogLevel.debug.rawValue, 0)
    }

    func testInfoLevelRawValue() {
        XCTAssertEqual(RiviumSyncLogLevel.info.rawValue, 1)
    }

    func testWarningLevelRawValue() {
        XCTAssertEqual(RiviumSyncLogLevel.warning.rawValue, 2)
    }

    func testErrorLevelRawValue() {
        XCTAssertEqual(RiviumSyncLogLevel.error.rawValue, 3)
    }

    func testNoneLevelRawValue() {
        XCTAssertEqual(RiviumSyncLogLevel.none.rawValue, 4)
    }

    // MARK: - Log Level Ordering

    func testDebugIsLowestLevel() {
        XCTAssertTrue(RiviumSyncLogLevel.debug.rawValue < RiviumSyncLogLevel.info.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.debug.rawValue < RiviumSyncLogLevel.warning.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.debug.rawValue < RiviumSyncLogLevel.error.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.debug.rawValue < RiviumSyncLogLevel.none.rawValue)
    }

    func testInfoIsAboveDebug() {
        XCTAssertTrue(RiviumSyncLogLevel.info.rawValue > RiviumSyncLogLevel.debug.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.info.rawValue < RiviumSyncLogLevel.warning.rawValue)
    }

    func testWarningIsAboveInfo() {
        XCTAssertTrue(RiviumSyncLogLevel.warning.rawValue > RiviumSyncLogLevel.info.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.warning.rawValue < RiviumSyncLogLevel.error.rawValue)
    }

    func testErrorIsAboveWarning() {
        XCTAssertTrue(RiviumSyncLogLevel.error.rawValue > RiviumSyncLogLevel.warning.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.error.rawValue < RiviumSyncLogLevel.none.rawValue)
    }

    func testNoneIsHighestLevel() {
        XCTAssertTrue(RiviumSyncLogLevel.none.rawValue > RiviumSyncLogLevel.debug.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.none.rawValue > RiviumSyncLogLevel.info.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.none.rawValue > RiviumSyncLogLevel.warning.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.none.rawValue > RiviumSyncLogLevel.error.rawValue)
    }

    func testLogLevelsAreConsecutive() {
        XCTAssertEqual(RiviumSyncLogLevel.debug.rawValue + 1, RiviumSyncLogLevel.info.rawValue)
        XCTAssertEqual(RiviumSyncLogLevel.info.rawValue + 1, RiviumSyncLogLevel.warning.rawValue)
        XCTAssertEqual(RiviumSyncLogLevel.warning.rawValue + 1, RiviumSyncLogLevel.error.rawValue)
        XCTAssertEqual(RiviumSyncLogLevel.error.rawValue + 1, RiviumSyncLogLevel.none.rawValue)
    }

    // MARK: - Log Level From Raw Value

    func testLogLevelFromValidRawValue() {
        XCTAssertEqual(RiviumSyncLogLevel(rawValue: 0), .debug)
        XCTAssertEqual(RiviumSyncLogLevel(rawValue: 1), .info)
        XCTAssertEqual(RiviumSyncLogLevel(rawValue: 2), .warning)
        XCTAssertEqual(RiviumSyncLogLevel(rawValue: 3), .error)
        XCTAssertEqual(RiviumSyncLogLevel(rawValue: 4), RiviumSyncLogLevel.none)
    }

    func testLogLevelFromInvalidRawValue() {
        XCTAssertNil(RiviumSyncLogLevel(rawValue: -1))
        XCTAssertNil(RiviumSyncLogLevel(rawValue: 5))
        XCTAssertNil(RiviumSyncLogLevel(rawValue: 99))
    }

    // MARK: - Log Level Equality

    func testLogLevelEquality() {
        XCTAssertEqual(RiviumSyncLogLevel.debug, RiviumSyncLogLevel.debug)
        XCTAssertEqual(RiviumSyncLogLevel.info, RiviumSyncLogLevel.info)
        XCTAssertEqual(RiviumSyncLogLevel.warning, RiviumSyncLogLevel.warning)
        XCTAssertEqual(RiviumSyncLogLevel.error, RiviumSyncLogLevel.error)
        XCTAssertEqual(RiviumSyncLogLevel.none, RiviumSyncLogLevel.none)
    }

    func testLogLevelInequality() {
        XCTAssertNotEqual(RiviumSyncLogLevel.debug, RiviumSyncLogLevel.info)
        XCTAssertNotEqual(RiviumSyncLogLevel.info, RiviumSyncLogLevel.warning)
        XCTAssertNotEqual(RiviumSyncLogLevel.warning, RiviumSyncLogLevel.error)
        XCTAssertNotEqual(RiviumSyncLogLevel.error, RiviumSyncLogLevel.none)
    }

    // MARK: - Log Level Count

    func testAllLogLevelsCovered() {
        let allLevels: [RiviumSyncLogLevel] = [
            .debug, .info, .warning, .error, .none
        ]
        XCTAssertEqual(allLevels.count, 5)
    }

    func testAllLogLevelRawValuesAreUnique() {
        let allLevels: [RiviumSyncLogLevel] = [
            .debug, .info, .warning, .error, .none
        ]
        let rawValues = allLevels.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        XCTAssertEqual(rawValues.count, uniqueValues.count)
    }

    // MARK: - Logger Log Level Control

    func testLoggerDefaultLevelIsNone() {
        // Reset to default
        RiviumSyncLogger.logLevel = .none

        XCTAssertEqual(RiviumSyncLogger.logLevel, .none)
    }

    func testLoggerLevelCanBeSetToDebug() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        XCTAssertEqual(RiviumSyncLogger.logLevel, .debug)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testLoggerLevelCanBeSetToInfo() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .info

        XCTAssertEqual(RiviumSyncLogger.logLevel, .info)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testLoggerLevelCanBeSetToWarning() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .warning

        XCTAssertEqual(RiviumSyncLogger.logLevel, .warning)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testLoggerLevelCanBeSetToError() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .error

        XCTAssertEqual(RiviumSyncLogger.logLevel, .error)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    // MARK: - Debug Mode Controls Logging

    func testNoneLevelSuppressesAllLogging() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .none

        // With level .none (rawValue 4), all guard checks fail:
        // debug (0 <= 0) would pass, but .none (4 <= 0) fails
        XCTAssertFalse(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.debug.rawValue)
        XCTAssertFalse(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.info.rawValue)
        XCTAssertFalse(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.warning.rawValue)
        XCTAssertFalse(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.error.rawValue)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testDebugLevelAllowsAllLogging() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        XCTAssertTrue(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.debug.rawValue)
        XCTAssertTrue(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.info.rawValue)
        XCTAssertTrue(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.warning.rawValue)
        XCTAssertTrue(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.error.rawValue)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testWarningLevelBlocksDebugAndInfo() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .warning

        XCTAssertFalse(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.debug.rawValue)
        XCTAssertFalse(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.info.rawValue)
        XCTAssertTrue(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.warning.rawValue)
        XCTAssertTrue(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.error.rawValue)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testErrorLevelOnlyAllowsErrors() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .error

        XCTAssertFalse(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.debug.rawValue)
        XCTAssertFalse(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.info.rawValue)
        XCTAssertFalse(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.warning.rawValue)
        XCTAssertTrue(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.error.rawValue)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testInfoLevelBlocksDebugOnly() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .info

        XCTAssertFalse(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.debug.rawValue)
        XCTAssertTrue(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.info.rawValue)
        XCTAssertTrue(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.warning.rawValue)
        XCTAssertTrue(RiviumSyncLogger.logLevel.rawValue <= RiviumSyncLogLevel.error.rawValue)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    // MARK: - Log Methods Do Not Crash

    func testDebugLogDoesNotCrashWhenDisabled() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .none

        RiviumSyncLogger.d("Debug message while logging disabled")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testInfoLogDoesNotCrashWhenDisabled() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .none

        RiviumSyncLogger.i("Info message while logging disabled")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testWarningLogDoesNotCrashWhenDisabled() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .none

        RiviumSyncLogger.w("Warning message while logging disabled")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testErrorLogDoesNotCrashWhenDisabled() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .none

        RiviumSyncLogger.e("Error message while logging disabled")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testDebugLogDoesNotCrashWhenEnabled() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        RiviumSyncLogger.d("Debug message while logging enabled")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testInfoLogDoesNotCrashWhenEnabled() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        RiviumSyncLogger.i("Info message while logging enabled")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testWarningLogDoesNotCrashWhenEnabled() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        RiviumSyncLogger.w("Warning message while logging enabled")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testErrorLogDoesNotCrashWhenEnabled() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        RiviumSyncLogger.e("Error message while logging enabled")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    // MARK: - Log Methods With Error Parameter

    func testWarningLogWithErrorDoesNotCrash() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        let testError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error occurred"])
        RiviumSyncLogger.w("Warning with error", error: testError)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testErrorLogWithErrorDoesNotCrash() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        let testError = NSError(domain: "TestDomain", code: 99, userInfo: [NSLocalizedDescriptionKey: "Critical failure"])
        RiviumSyncLogger.e("Error with error", error: testError)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testWarningLogWithNilErrorDoesNotCrash() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        RiviumSyncLogger.w("Warning without error", error: nil)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testErrorLogWithNilErrorDoesNotCrash() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        RiviumSyncLogger.e("Error without error", error: nil)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    // MARK: - Various String Inputs

    func testLogWithEmptyString() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        RiviumSyncLogger.d("")
        RiviumSyncLogger.i("")
        RiviumSyncLogger.w("")
        RiviumSyncLogger.e("")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testLogWithLongString() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        let longString = String(repeating: "A", count: 10000)
        RiviumSyncLogger.d(longString)
        RiviumSyncLogger.i(longString)
        RiviumSyncLogger.w(longString)
        RiviumSyncLogger.e(longString)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testLogWithSpecialCharacters() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        RiviumSyncLogger.d("Special chars: !@#$%^&*()_+-={}[]|\\:\";<>?,./~`")
        RiviumSyncLogger.i("Unicode: \u{00E9}\u{00F1}\u{00FC}\u{00E0}")
        RiviumSyncLogger.w("Newlines:\nLine 1\nLine 2\nLine 3")
        RiviumSyncLogger.e("Tabs:\tColumn1\tColumn2\tColumn3")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testLogWithUnicodeEmoji() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        RiviumSyncLogger.d("Status: \u{2705} Success")
        RiviumSyncLogger.i("Warning: \u{26A0}\u{FE0F} Attention needed")
        RiviumSyncLogger.w("Error: \u{274C} Failed")
        RiviumSyncLogger.e("Fire: \u{1F525} Critical")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testLogWithInterpolatedStrings() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        let userId = "user-123"
        let count = 42
        let price = 19.99

        RiviumSyncLogger.d("User \(userId) logged in")
        RiviumSyncLogger.i("Found \(count) results")
        RiviumSyncLogger.w("Price changed to \(price)")
        RiviumSyncLogger.e("Failed for user \(userId) after \(count) attempts")

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testLogWithMultilineString() {
        let previousLevel = RiviumSyncLogger.logLevel
        RiviumSyncLogger.logLevel = .debug

        let multiline = """
        {
            "id": "doc-1",
            "name": "Test",
            "nested": {
                "key": "value"
            }
        }
        """
        RiviumSyncLogger.d(multiline)
        RiviumSyncLogger.i(multiline)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    // MARK: - Log Level Switching

    func testLogLevelCanBeSwitchedMultipleTimes() {
        let previousLevel = RiviumSyncLogger.logLevel

        RiviumSyncLogger.logLevel = .debug
        XCTAssertEqual(RiviumSyncLogger.logLevel, .debug)

        RiviumSyncLogger.logLevel = .info
        XCTAssertEqual(RiviumSyncLogger.logLevel, .info)

        RiviumSyncLogger.logLevel = .warning
        XCTAssertEqual(RiviumSyncLogger.logLevel, .warning)

        RiviumSyncLogger.logLevel = .error
        XCTAssertEqual(RiviumSyncLogger.logLevel, .error)

        RiviumSyncLogger.logLevel = .none
        XCTAssertEqual(RiviumSyncLogger.logLevel, .none)

        RiviumSyncLogger.logLevel = .debug
        XCTAssertEqual(RiviumSyncLogger.logLevel, .debug)

        // Restore
        RiviumSyncLogger.logLevel = previousLevel
    }

    func testLogLevelComparisonForFiltering() {
        // Verify the guard logic used in logger methods:
        // guard logLevel.rawValue <= TargetLevel.rawValue

        // When logLevel is .warning (2):
        // d() check: 2 <= 0 -> false (blocked)
        // i() check: 2 <= 1 -> false (blocked)
        // w() check: 2 <= 2 -> true (allowed)
        // e() check: 2 <= 3 -> true (allowed)
        XCTAssertFalse(RiviumSyncLogLevel.warning.rawValue <= RiviumSyncLogLevel.debug.rawValue)
        XCTAssertFalse(RiviumSyncLogLevel.warning.rawValue <= RiviumSyncLogLevel.info.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.warning.rawValue <= RiviumSyncLogLevel.warning.rawValue)
        XCTAssertTrue(RiviumSyncLogLevel.warning.rawValue <= RiviumSyncLogLevel.error.rawValue)
    }
}
