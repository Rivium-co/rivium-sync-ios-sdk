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

    /// Told when the app changes who is signed in, so realtime can follow.
    internal var onUserMayHaveChanged: (() -> Void)?

    internal init() {}

    /// Replace the current token. Safe to call from any thread.
    ///
    /// If the SDK was waiting for a token to connect, it connects now; if it is
    /// connected as a different user, it reconnects as this one.
    public func set(_ newToken: String?) {
        store(newToken)
        onUserMayHaveChanged?()
    }

    /// For apps that use a `provider`: call this when the user signs in or out.
    /// The SDK asks the provider again and connects, or reconnects, as that user.
    public func refreshUserToken() {
        invalidate()
        onUserMayHaveChanged?()
    }

    /// Forget the current token so the next request asks `provider` for another.
    public func invalidate() {
        store(nil)
    }

    private func store(_ newToken: String?) {
        lock.lock()
        defer { lock.unlock() }
        token = newToken
        expiresAt = newToken.map(Self.expiry(of:)) ?? 0
    }

    /// The user the held token is for, without asking `provider`.
    internal func heldUser() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return Self.user(of: token)
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
                store(fetched)
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
        return payload(of: jwt)?["exp"] as? TimeInterval ?? 0
    }

    /// The user a token is for (its `sub`), or nil without one.
    internal static func user(of jwt: String?) -> String? {
        return jwt.flatMap(payload(of:))?["sub"] as? String
    }

    private static func payload(of jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return nil }

        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
