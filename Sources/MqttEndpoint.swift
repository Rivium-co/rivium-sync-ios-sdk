import Foundation

/// Where the realtime connection goes: the host and port the Sync API returns with the connection token, so they can
/// change on the server without a new SDK. The connection is always encrypted.
///
/// The answer is used only when it is valid and encrypted: a host of rivium.co (or one of its subdomains), a port
/// from 1 to 65535 and useTls = true. Anything else — no answer, a missing field, another domain, an unencrypted
/// endpoint — falls back to the built-in encrypted endpoint, so the connection token is never sent anywhere but
/// Rivium and never in clear.
internal struct MqttEndpoint: Equatable {
    let host: String
    let port: Int
    let useTls: Bool

    private static let hostPattern = try! NSRegularExpression(pattern: "^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)*rivium\\.co$")

    static func resolve(host: String?, port: Int?, useTls: Bool?, default fallback: MqttEndpoint) -> MqttEndpoint {
        guard let raw = host?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty, raw.count <= 253,
              hostPattern.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) != nil,
              let port = port, (1...65535).contains(port),
              useTls == true
        else { return fallback }
        return MqttEndpoint(host: raw, port: port, useTls: true)
    }
}
