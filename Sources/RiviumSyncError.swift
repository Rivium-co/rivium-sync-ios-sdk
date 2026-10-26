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
    /// A batch was refused or could not be sent. The second value is the server's answer (or the network error), so
    /// `statusCode` tells a refusal by your security rules (403) from a failed request.
    case batchWriteError(String, Error? = nil)
    case transactionError(String)
    /// The security rules do not allow this query or query listener: rules are
    /// not filters, so add the filters the rules need. `fields` names them
    /// when the server says which (may be empty). Code `query_not_allowed`.
    case queryNotAllowed(String, fields: [String])
    /// The server ended a listener because the user may no longer read what it
    /// listens to. The listener has stopped and is not restarted. Code
    /// `listener_revoked`.
    case listenerRevoked(String)
    case unknown(Error?)

    /// The server's machine-readable error code, for the errors that carry one
    /// (`query_not_allowed`, `listener_revoked`); nil otherwise.
    public var code: String? {
        switch self {
        case .queryNotAllowed: return "query_not_allowed"
        case .listenerRevoked: return "listener_revoked"
        default: return nil
        }
    }

    /// The HTTP status the server answered with (403 when your security rules refused the request), or nil when
    /// the server could not be reached.
    public var statusCode: Int? { SyncErrors.httpStatus(self) }

    /// For `query_not_allowed`: the fields to filter on, when the server names them.
    public var fields: [String] {
        if case .queryNotAllowed(_, let fields) = self { return fields }
        return []
    }
    
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
        case .batchWriteError(let message, _):
            return "Batch write error: \(message)"
        case .transactionError(let message):
            return "Transaction error: \(message)"
        case .queryNotAllowed(let message, _):
            return message
        case .listenerRevoked(let message):
            return message
        case .unknown(let error):
            return error?.localizedDescription ?? "Unknown error"
        }
    }
}
