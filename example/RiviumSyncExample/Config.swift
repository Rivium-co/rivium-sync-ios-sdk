import Foundation
import RiviumSync

/// Configuration for the RiviumSync Example App
///
/// Put your own values in `RiviumSyncExample/Local.plist` (not checked in; copy `Local.example.plist`):
///
/// - `apiKey`: your project's API key (Rivium Console > your project > settings)
/// - `databaseName`: your database NAME as shown in Rivium Console (not its UUID). Realtime updates only arrive
///   when you address the database by name.
/// - `serverSecret` (debug builds only): lets `DemoTokenMinter` stand in for your backend and sign user tokens.
/// - `demoUserId`: the user the demo signs in as (default `ios-demo-user`).
enum AppConfig {
    private static let local: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Local", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }()

    private static func value(_ key: String) -> String? {
        (local[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static let apiKey = value("apiKey") ?? "rv_live_your_api_key"

    static let databaseName = value("databaseName") ?? "my-app"

    static let demoUserId = value("demoUserId") ?? "ios-demo-user"

    #if DEBUG
    static let serverSecret = value("serverSecret")
    static let emulatorHost = value("emulatorHost")
    #else
    static let serverSecret: String? = nil
    static let emulatorHost: String? = nil
    #endif

    // Demo collection name
    static let todosCollection = "todos"

    // The signed-in user (the demo minter signs tokens for it). Documents carry it as `userId`,
    // which the default "owner only" Security Rules check: newData.userId === auth.uid.
    static var userId: String { DemoTokenMinter.currentUserId }

    // The signed-in user's documents. Security Rules are not filters: a list or listener must filter on the field
    // the rules read (here userId), or the server refuses it with `queryNotAllowed`.
    static func mine(_ collection: SyncCollection) -> SyncQuery {
        collection.where("userId", .equal, userId)
    }
}
