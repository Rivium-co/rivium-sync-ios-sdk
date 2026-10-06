import XCTest
@testable import RiviumSync

/// A project with "Require signed user tokens" refuses the realtime-token
/// request while nobody is signed in. That is not a network failure: the SDK
/// must wait for a token instead of retrying, connect when one is set, and
/// reconnect when a different user signs in.
final class MqttUserTokenTests: XCTestCase {

    /// An API for a project that requires user tokens: the realtime-token
    /// request is refused unless a user token is held, and we count the calls.
    private final class StrictApiClient: ApiClient {
        private let lock = NSLock()
        private var _calls = 0
        var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }

        override func fetchMqttToken() async throws -> MqttTokenResponse {
            lock.lock(); _calls += 1; let n = _calls; lock.unlock()
            guard await userTokens.current() != nil else {
                throw RiviumSyncError.networkError("token required", UserTokenRequiredError())
            }
            return MqttTokenResponse(token: "realtime-\(n)", expiresIn: nil, projectId: "p1", mqtt: nil)
        }
    }

    /// Stands in for the socket: records each open and reports it connected.
    private final class SocketlessManager: MqttManager {
        private let lock = NSLock()
        private var _opened = 0
        var opened: Int { lock.lock(); defer { lock.unlock() }; return _opened }

        override func connectWithToken(token: String, completion: @escaping (Result<Void, Error>) -> Void) {
            lock.lock(); _opened += 1; lock.unlock()
            completion(.success(()))
        }
    }

    /// Counts from any thread.
    private final class Counter {
        private let lock = NSLock()
        private var _value = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
        func add() { lock.lock(); _value += 1; lock.unlock() }
    }

    private func makeManager() -> (SocketlessManager, StrictApiClient) {
        let config = RiviumSyncConfigBuilder(apiKey: "rv_live_test").autoReconnect(true).build()
        let api = StrictApiClient(config: config)
        return (SocketlessManager(config: config, apiClient: api), api)
    }

    /// An unsigned token for `user` that expires in an hour.
    private func token(for user: String, salt: String = "a") -> String {
        let payload: [String: Any] = ["sub": user, "exp": Date().timeIntervalSince1970 + 3600, "jti": salt]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let body = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "h.\(body).s"
    }

    private func wait(_ what: String, until condition: @escaping () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for: \(what)")
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    // MARK: - Awaiting a token

    func testTokenRequiredParksTheConnectInsteadOfRetrying() async throws {
        let (manager, api) = makeManager()
        let awaiting = Counter(), stateChanges = Counter(), completions = Counter(), failures = Counter()
        manager.onAwaitingUserToken = { awaiting.add() }
        manager.onConnectionStateChanged = { _ in stateChanges.add() }

        manager.connect { result in
            completions.add()
            if case .failure = result { failures.add() }
        }
        await wait("awaiting state") { manager.isAwaitingUserToken }

        try await Task.sleep(nanoseconds: 2_500_000_000) // past when a retry would fire
        XCTAssertEqual(api.calls, 1)
        XCTAssertEqual(completions.value, 1)
        XCTAssertEqual(failures.value, 0)
        XCTAssertEqual(awaiting.value, 1)
        XCTAssertEqual(stateChanges.value, 0) // no connection failure reported
        XCTAssertTrue(manager.isAwaitingUserToken)
        manager.disconnect()
    }

    func testSettingATokenWhileAwaitingConnects() async {
        let (manager, api) = makeManager()
        let completions = Counter()
        manager.connect { _ in completions.add() }
        await wait("awaiting state") { manager.isAwaitingUserToken }

        api.userTokens.set(token(for: "alice"))
        await wait("socket opened") { manager.opened == 1 }

        XCTAssertEqual(api.calls, 2)
        XCTAssertFalse(manager.isAwaitingUserToken)
        // The caller's connect() was answered when the SDK started waiting.
        XCTAssertEqual(completions.value, 1)
        manager.disconnect()
    }

    func testClearingTheTokenWhileAwaitingDoesNothing() async {
        let (manager, api) = makeManager()
        manager.connect { _ in }
        await wait("awaiting state") { manager.isAwaitingUserToken }

        api.userTokens.set(nil)
        await settle()

        XCTAssertEqual(api.calls, 1)
        XCTAssertTrue(manager.isAwaitingUserToken)
        manager.disconnect()
    }

    func testSettingATokenDoesNothingUnlessAConnectionIsWanted() async {
        let (manager, api) = makeManager()
        api.userTokens.set(token(for: "alice"))
        await settle()
        XCTAssertEqual(api.calls, 0)
        XCTAssertEqual(manager.opened, 0)
    }

    // MARK: - A different user

    func testADifferentUserReconnectsAndKeepsSubscriptions() async {
        let (manager, api) = makeManager()
        api.userTokens.set(token(for: "alice"))
        manager.connect { _ in }
        await wait("socket opened") { manager.opened == 1 }
        _ = manager.subscribe(topic: "rivium_sync/p1/db/todos/changes") { _ in }

        api.userTokens.set(token(for: "bob"))
        await wait("socket reopened") { manager.opened == 2 }

        XCTAssertEqual(api.calls, 2)
        XCTAssertEqual(manager.subscribedTopics, ["rivium_sync/p1/db/todos/changes"])
        manager.disconnect()
    }

    func testANewTokenForTheSameUserDoesNotReconnect() async {
        let (manager, api) = makeManager()
        api.userTokens.set(token(for: "alice"))
        manager.connect { _ in }
        await wait("socket opened") { manager.opened == 1 }

        api.userTokens.set(token(for: "alice", salt: "refreshed"))
        await settle()

        XCTAssertEqual(api.calls, 1)
        XCTAssertEqual(manager.opened, 1)
        manager.disconnect()
    }

    func testSigningOutWhileConnectedGoesBackToAwaiting() async {
        let (manager, api) = makeManager()
        let awaiting = Counter()
        manager.onAwaitingUserToken = { awaiting.add() }
        api.userTokens.set(token(for: "alice"))
        manager.connect { _ in }
        await wait("socket opened") { manager.opened == 1 }

        api.userTokens.set(nil)
        await wait("awaiting state") { manager.isAwaitingUserToken }

        XCTAssertEqual(api.calls, 2)
        XCTAssertEqual(manager.opened, 1)
        XCTAssertEqual(awaiting.value, 1)
        manager.disconnect()
    }

    // MARK: - Provider

    func testRefreshUserTokenAsksTheProviderAndFollowsTheUser() async {
        let (manager, api) = makeManager()
        let lock = NSLock()
        var signedIn: String?
        api.userTokens.provider = { [self] in
            lock.lock(); defer { lock.unlock() }
            return signedIn.map { token(for: $0) }
        }

        manager.connect { _ in }
        await wait("awaiting state") { manager.isAwaitingUserToken }

        lock.lock(); signedIn = "alice"; lock.unlock()
        api.userTokens.refreshUserToken()
        await wait("socket opened") { manager.opened == 1 }
        XCTAssertFalse(manager.isAwaitingUserToken)

        // Same user: nothing to do.
        api.userTokens.refreshUserToken()
        await settle()
        XCTAssertEqual(manager.opened, 1)

        lock.lock(); signedIn = "bob"; lock.unlock()
        api.userTokens.refreshUserToken()
        await wait("socket reopened") { manager.opened == 2 }
        manager.disconnect()
    }

    // MARK: - Disconnect

    func testDisconnectClearsTheAwaitingState() async {
        let (manager, api) = makeManager()
        manager.connect { _ in }
        await wait("awaiting state") { manager.isAwaitingUserToken }

        manager.disconnect()
        XCTAssertFalse(manager.isAwaitingUserToken)

        // A token that arrives after the app disconnected must not connect.
        api.userTokens.set(token(for: "alice"))
        await settle()
        XCTAssertEqual(api.calls, 1)
        XCTAssertEqual(manager.opened, 0)
    }

    // MARK: - Listeners added before the project id is known

    func testAListenerAddedWhileAwaitingMovesToTheProjectTopic() async {
        let (manager, api) = makeManager()
        manager.connect { _ in }
        await wait("awaiting state") { manager.isAwaitingUserToken }

        let early = manager.collectionTopic(databaseId: "db", collectionId: "todos")
        XCTAssertEqual(early, "rivium_sync/unknown/db/todos/changes")
        let received = Counter()
        let handle = manager.subscribe(topic: early) { _ in received.add() }

        api.userTokens.set(token(for: "alice"))
        await wait("socket opened") { manager.opened == 1 }

        let real = "rivium_sync/p1/db/todos/changes"
        XCTAssertEqual(manager.subscribedTopics, [real])
        manager.deliver("{}", topic: real)
        XCTAssertEqual(received.value, 1)

        // The handle still names the old topic; removing it must find the new one.
        manager.unsubscribe(handle: handle)
        XCTAssertEqual(manager.subscribedTopics, [])
        manager.deliver("{}", topic: real)
        XCTAssertEqual(received.value, 1)
        manager.disconnect()
    }

    func testAListenerAddedAfterConnectIsUnaffected() async {
        let (manager, api) = makeManager()
        manager.connect { _ in }
        await wait("awaiting state") { manager.isAwaitingUserToken }
        let early = manager.subscribe(topic: manager.collectionTopic(databaseId: "db", collectionId: "todos")) { _ in }

        api.userTokens.set(token(for: "alice"))
        await wait("socket opened") { manager.opened == 1 }

        // Same collection, added once connected: joins the moved entry.
        let real = manager.collectionTopic(databaseId: "db", collectionId: "todos")
        XCTAssertEqual(real, "rivium_sync/p1/db/todos/changes")
        let received = Counter()
        let late = manager.subscribe(topic: real) { _ in received.add() }
        XCTAssertEqual(manager.subscribedTopics, [real])

        manager.unsubscribe(handle: early)
        XCTAssertEqual(manager.subscribedTopics, [real])
        manager.deliver("{}", topic: real)
        XCTAssertEqual(received.value, 1)

        manager.unsubscribe(handle: late)
        XCTAssertEqual(manager.subscribedTopics, [])
        manager.disconnect()
    }

    // MARK: - Recognising the refusal

    func testRecognisesTheTokenRequiredAnswer() {
        let required = Data(#"{"statusCode":401,"error":"Unauthorized","code":"token_required","message":"x"}"#.utf8)
        let expired = Data(#"{"statusCode":401,"error":"Unauthorized","code":"token_expired","message":"x"}"#.utf8)

        XCTAssertTrue(ApiClient.isUserTokenRequired(status: 401, body: required))
        XCTAssertFalse(ApiClient.isUserTokenRequired(status: 401, body: expired))
        XCTAssertFalse(ApiClient.isUserTokenRequired(status: 403, body: required))
        XCTAssertFalse(ApiClient.isUserTokenRequired(status: 401, body: Data()))

        XCTAssertTrue(MqttManager.isUserTokenRequired(RiviumSyncError.networkError("x", UserTokenRequiredError())))
        XCTAssertFalse(MqttManager.isUserTokenRequired(RiviumSyncError.networkError("x", nil)))
        XCTAssertFalse(MqttManager.isUserTokenRequired(URLError(.cannotFindHost)))
    }

    func testReadsTheUserFromAToken() {
        XCTAssertEqual(UserTokenStore.user(of: token(for: "alice")), "alice")
        XCTAssertNil(UserTokenStore.user(of: nil))
        XCTAssertNil(UserTokenStore.user(of: "not-a-jwt"))
    }
}
