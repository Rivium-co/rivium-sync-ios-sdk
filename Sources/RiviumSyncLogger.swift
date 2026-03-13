import Foundation
import os.log

/// Log level for RiviumSync SDK
public enum RiviumSyncLogLevel: Int {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case none = 4
}

/// Internal logger for RiviumSync SDK
/// All logs are disabled by default to avoid exposing internal implementation details
internal class RiviumSyncLogger {
    private static let subsystem = "co.rivium"
    private static let category = "RiviumSync"
    private static let osLog = OSLog(subsystem: subsystem, category: category)

    static var logLevel: RiviumSyncLogLevel = .none
    
    static func d(_ message: String) {
        guard logLevel.rawValue <= RiviumSyncLogLevel.debug.rawValue else { return }
        os_log(.debug, log: osLog, "%{public}@", message)
    }
    
    static func i(_ message: String) {
        guard logLevel.rawValue <= RiviumSyncLogLevel.info.rawValue else { return }
        os_log(.info, log: osLog, "%{public}@", message)
    }
    
    static func w(_ message: String, error: Error? = nil) {
        guard logLevel.rawValue <= RiviumSyncLogLevel.warning.rawValue else { return }
        if let error = error {
            os_log(.error, log: osLog, "%{public}@ - %{public}@", message, error.localizedDescription)
        } else {
            os_log(.error, log: osLog, "%{public}@", message)
        }
    }
    
    static func e(_ message: String, error: Error? = nil) {
        guard logLevel.rawValue <= RiviumSyncLogLevel.error.rawValue else { return }
        if let error = error {
            os_log(.fault, log: osLog, "%{public}@ - %{public}@", message, error.localizedDescription)
        } else {
            os_log(.fault, log: osLog, "%{public}@", message)
        }
    }
}
