import Foundation

/// Holds the signed user token the SDK sends as `X-User-Token`.
///
/// Security Rules read `auth.uid`, and the `X-User-Id` header cannot decide that:
/// the API key shipped in your app is public, so any client could claim any user.
/// Your backend mints a token instead (it holds the server secret) and the app
/// hands it to the SDK here.
///
/// Set `provider` so the SDK can fetch a fresh token by itself when the one it
/// holds is close to expiry or the server rejects it as expired. Without a
/// provider, call `set(_:)` again whenever you refresh.
public final class UserTokenStore {
    /// Refresh this many seconds before the token actually expires.
    private static let refreshSkew: TimeInterval = 60

    private let lock = NSLock()
    private var token: String?
    private var expiresAt: TimeInterval = 0

    /// Fetches a token for the signed-in user. Return nil to send none.
    public var provider: (() async throws -> String?)?

    internal init() {}

    /// Replace the current token. Safe to call from any thread.
    public func set(_ newToken: String?) {
        lock.lock()
        defer { lock.unlock() }
        token = newToken
        expiresAt = newToken.map(Self.expiry(of:)) ?? 0
    }

    /// Forget the current token so the next request asks `provider` for another.
    public func invalidate() {
        set(nil)
    }

    /// The token to send, refreshing through `provider` when needed.
    internal func current() async -> String? {
        lock.lock()
        let held = token
        let fresh = held != nil && expiresAt - Self.refreshSkew > Date().timeIntervalSince1970
        lock.unlock()

        if fresh { return held }
        guard let provider = provider else { return held } // Whatever was set, even if stale.

        do {
            if let fetched = try await provider() {
                set(fetched)
                return fetched
            }
            return held
        } catch {
            RiviumSyncLogger.e("User token provider failed: \(error.localizedDescription)", error: error)
            return held // Let the server decide; the old token may still work.
        }
    }

    /// Expiry from the JWT payload, or 0 when it cannot be read.
    private static func expiry(of jwt: String) -> TimeInterval {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return 0 }

        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval
        else { return 0 }

        return exp
    }
}
