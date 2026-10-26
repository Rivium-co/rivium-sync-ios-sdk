import Foundation

/// Which failures the offline cache may hide, as in Firestore: only those where the server could not answer for good.
///
/// Transient (read from the cache, queue the write, retry later): no answer at all (no network, timeout), 401 (the
/// user token is not there yet or is being refreshed), 408, 429 and 5xx.
///
/// Anything else is the server's final answer (403 the security rules refused, 400 / 413 / 422 invalid, 404 not
/// found): reads and writes report it to the app, nothing is queued, and a queued write that gets it is rolled back.
internal enum SyncErrors {
    static func isTransient(_ error: Error) -> Bool {
        if let status = httpStatus(error) {
            return status == 401 || status == 408 || status == 429 || status >= 500
        }
        switch error as? RiviumSyncError {
        case .some(.networkError), .some(.connectionError), .some(.timeoutError):
            return true // No answer from the server.
        case .some:
            return false // The SDK's own errors (bad answer, not initialized), and refused queries: retrying does not help.
        case .none:
            return true // URLError and the like: the request did not get through.
        }
    }

    /// The HTTP status the server answered with, when it answered.
    static func httpStatus(_ error: Error) -> Int? {
        switch error as? RiviumSyncError {
        case .some(.networkError(_, let cause as HttpStatusError)): return cause.status
        case .some(.networkError(_, is UserTokenRequiredError)): return 401
        case .some(.queryNotAllowed): return 403
        case .some(.batchWriteError(_, let cause?)): return httpStatus(cause)
        default: return nil
        }
    }
}
