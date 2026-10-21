import Foundation

/// Identity this SDK reports to the backend: `X-Rivium-SDK: name/version` on
/// every API request (MQTT has no headers).
internal enum RiviumSyncSDKInfo {
    /// Native iOS SDK name.
    static let name = "ios"

    /// The SDK version (`RiviumSync.version`, kept equal to the podspec by a test).
    static var version: String { RiviumSync.version }

    /// Header carrying the SDK identity on every request.
    static let headerName = "X-Rivium-SDK"

    /// Backend contract: <=32 chars of `[A-Za-z0-9._+-]`.
    private static let maxLength = 32
    private static let allowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-")

    static func isValid(_ value: String?) -> Bool {
        guard let value = value, !value.isEmpty, value.count <= maxLength else { return false }
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// The reported identity. A wrapper identity replaces the native one only
    /// when both its name and version are valid.
    static func identity(wrapperName: String?, wrapperVersion: String?) -> (name: String, version: String) {
        if isValid(wrapperName), isValid(wrapperVersion), let n = wrapperName, let v = wrapperVersion {
            return (n, v)
        }
        if wrapperName != nil || wrapperVersion != nil {
            RiviumSyncLogger.w("Ignoring invalid wrapper SDK identity '\(wrapperName ?? "nil")/\(wrapperVersion ?? "nil")'")
        }
        return (name, version)
    }

    /// `name/version`; for a wrapper, the native SDK underneath follows,
    /// User-Agent style: `flutter/0.2.4 ios/0.2.3` (wrapper first). Only public
    /// SDK names and versions - never a key, user or device detail.
    static func headerValue(wrapperName: String?, wrapperVersion: String?) -> String {
        let id = identity(wrapperName: wrapperName, wrapperVersion: wrapperVersion)
        if id.name == name { return "\(name)/\(version)" }
        return "\(id.name)/\(id.version) \(name)/\(version)"
    }
}
