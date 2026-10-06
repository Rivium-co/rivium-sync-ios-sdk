import Foundation

/// Configuration for the RiviumSync Example App
///
/// Replace these with your own API key and database name from Rivium Console.
enum AppConfig {
    // Your project's API key (Rivium Console > your project > settings)
    static let apiKey = "rv_live_your_api_key"

    // Your database NAME as shown in Rivium Console (not its UUID).
    // Realtime updates only arrive when you address the database by name.
    static let databaseName = "my-app"

    // Demo collection name
    static let todosCollection = "todos"
}
