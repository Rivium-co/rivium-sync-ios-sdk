import Foundation
import RiviumSync

/// Stands in for YOUR backend, so this example can run against a project that has "Require signed user tokens"
/// turned on.
///
/// Security Rules read `auth.uid`. An app cannot decide that value: its API key ships inside the app, so anyone could
/// claim any user. Only a server holding the project's server secret can mint a user token.
///
/// In a real app, replace `fetchToken()` with a call to your own endpoint, behind your own login, that mints a token
/// for the user who is actually signed in (the Node SDK's `createUserToken` does this). The server secret must never
/// be in an app - this example only reads it in debug builds, from Local.plist.
enum DemoTokenMinter {
    private static var apiUrl: String {
        AppConfig.emulatorHost.map { "http://\($0):3006" } ?? "https://sync.rivium.co"
    }

    private static let lock = NSLock()
    private static var _currentUserId = AppConfig.demoUserId

    /// The user the demo signs tokens for: `demoUserId`, or a second demo user after `switchUser()` (to see what
    /// Security Rules do with another user's data). A real app signs in through its own login instead.
    static var currentUserId: String {
        lock.lock(); defer { lock.unlock() }
        return _currentUserId
    }

    /// The other demo user's id (`demoUserId` + "-2").
    static var otherUserId: String {
        currentUserId == AppConfig.demoUserId ? "\(AppConfig.demoUserId)-2" : AppConfig.demoUserId
    }

    /// True when Local.plist gave this debug build a server secret.
    static var isConfigured: Bool { AppConfig.serverSecret != nil }

    /// Sign in as the other demo user: the SDK asks `fetchToken()` again and reconnects as that user.
    static func switchUser() {
        let next = otherUserId
        lock.lock(); _currentUserId = next; lock.unlock()
        RiviumSync.shared.refreshUserToken()
    }

    /// Mints a token for the demo user. Called by the SDK: at first use, shortly before the token expires, and again
    /// if the server says it expired.
    static func fetchToken() async throws -> String? {
        guard let secret = AppConfig.serverSecret, let url = URL(string: "\(apiUrl)/users/token") else { return nil }
        let userId = currentUserId
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(secret, forHTTPHeaderField: "x-server-secret")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["userId": userId])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("DemoTokenMinter: token request failed (\(status))")
            return nil
        }
        // The Sync API wraps answers in `data`; accept both shapes.
        let token = (json["data"] as? [String: Any])?["token"] as? String ?? json["token"] as? String
        print("DemoTokenMinter: minted a user token for \(userId)")
        return token
    }
}
