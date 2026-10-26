import SwiftUI
import RiviumSync

/// Checks for the default "owner only" Security Rules (each document's `userId` must be the signed-in user): what
/// the server refuses, and that the SDK reports it instead of hiding it in the offline cache. Each button prints
/// PASS or FAIL with what it expected.
struct RulesView: View {
    @StateObject private var model = RulesModel()

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Signed in as \(model.userId)").font(.headline)
                }
                Section("Checks") {
                    check("1. Write with another user's id → 403, not queued") { await model.refusedWrite() }
                    check("2. List with no filter → queryNotAllowed") { await model.refusedList() }
                    check("3. Another user's todos → refused") { await model.otherUsersTodos() }
                    check("4. Typed equality: \"false\" ≠ false") { await model.typedEquality() }
                    check("5. set replaces, set merge keeps") { await model.setAndMerge() }
                    check("6. Listen to one document") { await model.listenDocument() }
                    check("7. Batch is all or nothing") { await model.batchAllOrNothing() }
                    check("8. Offline write the rules refuse is rolled back") { await model.offlineRefusedWrite() }
                    check("9. Listen to my todos (then change rules in Console)") { await model.listenMine() }
                    Button("Switch user") { model.switchUser() }
                    Button("Clear log") { model.log = [] }
                }
                Section("Log") {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Rules")
        }
        // `-runRulesChecks` (launch argument): run checks 1-8 at once, for a quick pass from the command line.
        .task {
            if ProcessInfo.processInfo.arguments.contains("-runRulesChecks") { await model.runAll() }
        }
    }

    private func check(_ label: String, _ action: @escaping () async -> Void) -> some View {
        Button(label) {
            Task {
                model.append("— \(label)")
                await action()
            }
        }
    }
}

@MainActor
final class RulesModel: ObservableObject, SyncEngine.SyncListener {
    @Published var log: [String] = []
    @Published var userId = AppConfig.userId

    private var documentListener: ListenerRegistration?
    private var queryListener: ListenerRegistration?
    private var rejected: CheckedContinuation<String?, Never>?

    private var collection: SyncCollection {
        RiviumSync.shared.database(AppConfig.databaseName).collection(AppConfig.todosCollection)
    }

    private var profileId: String { "profile_\(AppConfig.userId)" }

    init() {
        RiviumSync.shared.addSyncListener(self)
    }

    nonisolated func onDocumentRejected(documentId: String, operation: OperationType, error: Error) {
        Task { @MainActor in
            append("Sync: server refused queued \(operation) of \(documentId): \(error.localizedDescription)")
            rejected?.resume(returning: documentId)
            rejected = nil
        }
    }

    // MARK: - Checks

    func runAll() async {
        let checks: [(String, () async -> Void)] = [
            ("1. refused write", refusedWrite), ("2. refused list", refusedList), ("3. another user's todos", otherUsersTodos),
            ("4. typed equality", typedEquality), ("5. set / merge", setAndMerge), ("6. listen document", listenDocument),
            ("7. batch all or nothing", batchAllOrNothing), ("8. offline refused write", offlineRefusedWrite),
        ]
        for (label, check) in checks {
            append("— \(label)")
            await check()
        }
        append("Done.")
    }

    func refusedWrite() async {
        let pendingBefore = RiviumSync.shared.pendingCount
        do {
            _ = try await collection.add(data: ["title": "Not mine", "userId": DemoTokenMinter.otherUserId])
            result(false, "403 and nothing queued", "it was accepted")
        } catch {
            let status = (error as? RiviumSyncError)?.statusCode
            let queued = RiviumSync.shared.pendingCount - pendingBefore
            result(status == 403 && queued == 0, "403 and nothing queued", "status=\(String(describing: status)), queued \(queued), \(error.localizedDescription)")
        }
    }

    func refusedList() async {
        do {
            let docs = try await collection.getAll()
            result(false, "queryNotAllowed naming userId (not the cache)", "no error: \(docs.count) documents came back")
        } catch {
            let fields = (error as? RiviumSyncError)?.fields ?? []
            result(fields.contains("userId"), "queryNotAllowed naming userId (not the cache)", error.localizedDescription)
        }
    }

    func otherUsersTodos() async {
        do {
            let docs = try await collection.where("userId", .equal, DemoTokenMinter.otherUserId).get()
            result(false, "queryNotAllowed", "no error: \(docs.count) of another user's todos came back")
        } catch {
            result((error as? RiviumSyncError)?.code == "query_not_allowed", "queryNotAllowed", error.localizedDescription)
        }
    }

    func typedEquality() async {
        do {
            _ = try await collection.add(data: ["title": "Typed", "userId": AppConfig.userId, "completed": false])
            let asText = try await AppConfig.mine(collection).where("completed", .equal, "false").get().count
            let asBoolean = try await AppConfig.mine(collection).where("completed", .equal, false).get().count
            result(asText == 0 && asBoolean >= 1, "\"false\" finds 0, false finds 1+", "\"false\" found \(asText), false found \(asBoolean)")
        } catch {
            unexpected(error)
        }
    }

    func setAndMerge() async {
        do {
            _ = try await collection.set(documentId: profileId, data: ["userId": AppConfig.userId, "a": 1, "b": 2])
            _ = try await collection.set(documentId: profileId, data: ["userId": AppConfig.userId, "a": 9])
            let replaced = try await collection.get(documentId: profileId)
            _ = try await collection.set(documentId: profileId, data: ["c": 3], merge: true)
            let merged = try await collection.get(documentId: profileId)
            let shown = { (doc: SyncDocument?) in "a=\(String(describing: doc?.getInt("a"))) b=\(String(describing: doc?.getInt("b"))) c=\(String(describing: doc?.getInt("c"))) userId=\(doc?.getString("userId") ?? "nil")" }
            append("after set: \(shown(replaced))")
            append("after merge: \(shown(merged))")
            let ok = replaced?.getInt("b") == nil && merged?.getInt("a") == 9 && merged?.getInt("c") == 3 && merged?.getString("userId") == AppConfig.userId
            result(ok, "set drops b; merge keeps a + userId and adds c", "set: \(shown(replaced)); merge: \(shown(merged))")
        } catch {
            unexpected(error)
        }
    }

    func listenDocument() async {
        documentListener?.remove()
        let tick = Int(Date().timeIntervalSince1970 * 1000)
        do {
            _ = try await collection.set(documentId: profileId, data: ["userId": AppConfig.userId], merge: true)
            let heard = await withTimeout(seconds: 10) { (done: @escaping (Bool) -> Void) in
                self.documentListener = self.collection.listenDocument(documentId: self.profileId, callback: { doc in
                    Task { @MainActor in self.append("listenDocument: tick=\(String(describing: doc?.getInt("tick")))") }
                    if doc?.getInt("tick") == tick { done(true) }
                }, onError: { error in
                    Task { @MainActor in self.append("listenDocument stopped: \(error.localizedDescription)") }
                })
                Task { _ = try? await self.collection.set(documentId: self.profileId, data: ["tick": tick], merge: true) }
            }
            result(heard == true, "the listener hears tick=\(tick)", "nothing heard in 10 s")
        } catch {
            unexpected(error)
        }
    }

    func batchAllOrNothing() async {
        do {
            let before = try await AppConfig.mine(collection).get().count
            var failure: Error?
            do {
                try await RiviumSync.shared.batch()
                    .create(collection, data: ["title": "Batch ok", "userId": AppConfig.userId])
                    .create(collection, data: ["title": "Batch not mine", "userId": DemoTokenMinter.otherUserId])
                    .commit()
            } catch {
                failure = error
            }
            let after = try await AppConfig.mine(collection).get().count
            result(failure != nil && after == before, "refused, and the allowed create is not saved either",
                   "error=\(String(describing: failure?.localizedDescription)), my todos \(before) → \(after)")
        } catch {
            unexpected(error)
        }
    }

    func offlineRefusedWrite() async {
        let sync: RiviumSync = RiviumSync.shared
        do {
            sync.disconnect()
            let queued = try await collection.add(data: ["title": "Queued, not mine", "userId": DemoTokenMinter.otherUserId])
            append("Offline: queued \(queued.id); reconnecting")
            let id: String? = await withCheckedContinuation { continuation in
                rejected = continuation
                Task {
                    try? await sync.connect()
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    await MainActor.run {
                        self.rejected?.resume(returning: nil)
                        self.rejected = nil
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            let stillPending = sync.pendingCount
            result(id == queued.id && stillPending == 0, "rejected and removed from the queue",
                   "rejected=\(String(describing: id)), still pending=\(stillPending)")
        } catch {
            unexpected(error)
        }
    }

    func listenMine() async {
        queryListener?.remove()
        queryListener = AppConfig.mine(collection).listen(callback: { docs in
            Task { @MainActor in self.append("listen: \(docs.count) todos") }
        }, onError: { error in
            Task { @MainActor in self.append("listen stopped: \(error)") }
        })
        append("Listening. In the Console, publish rules that deny reading todos: expect \"listen stopped: listenerRevoked\". Publish the old rules again after.")
    }

    func switchUser() {
        DemoTokenMinter.switchUser()
        userId = AppConfig.userId
        append("Signed in as \(AppConfig.userId) (checks 1-3 now use the other user)")
    }

    // MARK: - Output

    func append(_ line: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.append("[\(time)] \(line)")
        print("RulesCheck: \(line)")
    }

    private func result(_ passed: Bool, _ expected: String, _ got: String) {
        append(passed ? "✓ PASS: \(expected)" : "✗ FAIL: expected \(expected); got \(got)")
    }

    private func unexpected(_ error: Error) {
        append("✗ FAIL: unexpected \(error)")
    }

    /// Waits until `start` calls its completion, or `seconds` pass (nil).
    private func withTimeout(seconds: Double, _ start: @escaping (@escaping (Bool) -> Void) -> Void) async -> Bool? {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var finished = false
            let finish: (Bool?) -> Void = { value in
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: value)
            }
            start { finish($0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finish(nil) }
        }
    }
}
