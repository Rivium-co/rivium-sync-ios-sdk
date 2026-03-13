import Foundation

/// Errors for RiviumSync SDK
public enum RiviumSyncError: Error, LocalizedError {
    case notInitialized
    case networkError(String, Error?)
    case authenticationError(String)
    case databaseError(String)
    case collectionError(String)
    case documentError(String)
    case connectionError(String, Error?)
    case timeoutError(String)
    case permissionError(String)
    case invalidResponse(String)
    case batchWriteError(String)
    case transactionError(String)
    case unknown(Error?)
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "RiviumSync SDK not initialized. Call RiviumSync.initialize() first."
        case .networkError(let message, _):
            return "Network error: \(message)"
        case .authenticationError(let message):
            return "Authentication error: \(message)"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .collectionError(let message):
            return "Collection error: \(message)"
        case .documentError(let message):
            return "Document error: \(message)"
        case .connectionError(let message, _):
            return "Connection error: \(message)"
        case .timeoutError(let message):
            return "Timeout error: \(message)"
        case .permissionError(let message):
            return "Permission error: \(message)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .batchWriteError(let message):
            return "Batch write error: \(message)"
        case .transactionError(let message):
            return "Transaction error: \(message)"
        case .unknown(let error):
            return error?.localizedDescription ?? "Unknown error"
        }
    }
}
