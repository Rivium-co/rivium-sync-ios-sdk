import Foundation

/// Configuration for the RiviumSync Example App
///
/// Replace these with your own API key and database ID from Rivium Console.
enum AppConfig {
    // Your project's API key (Rivium Console > your project > settings)
    static let apiKey = "rv_live_your_api_key"

    // Your database ID (create in RiviumSync console)
    static let databaseId = "your-database-id"

    // Demo collection name
    static let todosCollection = "todos"
}
