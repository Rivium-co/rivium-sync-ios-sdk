import Foundation

/// Configuration for the RiviumSync Example App
///
/// Copy this file to Config.swift and replace the values with your own
/// API key and database ID from the AuthLeap dashboard.
enum AppConfig {
    // Your RiviumSync Project API Key (get from AuthLeap dashboard > Projects)
    static let apiKey = "rv_live_64e0ada5eeb66e3adf6136337802a5a34713ce4966372854"

    // Your database ID (create in RiviumSync console)
    static let databaseId = "test-sync"

    // Demo collection name
    static let todosCollection = "todos"
}
