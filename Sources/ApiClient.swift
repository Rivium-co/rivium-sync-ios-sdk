import Foundation

/// HTTP API client for RiviumSync REST operations
internal class ApiClient {
    private let config: RiviumSyncConfig
    private let userId: String?
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Signed identity, when the app supplies one.
    internal let userTokens = UserTokenStore()

    /// `protocolClasses` lets tests answer requests without a network.
    init(config: RiviumSyncConfig, userId: String? = nil, protocolClasses: [AnyClass]? = nil) {
        self.config = config
        self.userId = userId

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = TimeInterval(config.connectionTimeout)
        if let protocolClasses = protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        self.session = URLSession(configuration: configuration)
    }
    
    internal func buildRequest(endpoint: String, method: String = "GET", body: [String: Any]? = nil) async throws -> URLRequest {
        guard let url = URL(string: "\(config.apiUrl)\(endpoint)") else {
            throw RiviumSyncError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.sdkHeaderValue, forHTTPHeaderField: RiviumSyncSDKInfo.headerName)

        // A signed token decides who the caller is; the plain userId header is
        // only a fallback, and a project with requireSignedTokens refuses it.
        if let token = await userTokens.current() {
            request.setValue(token, forHTTPHeaderField: "X-User-Token")
        } else if let userId = userId {
            request.setValue(userId, forHTTPHeaderField: "X-User-Id")
        }

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }
    
    /// Sends the request and decodes the answer, wrapped (`{ "data": … }`, what the Sync API sends) or bare.
    /// `bareKey` is a key only the bare object has (a document's `id`, the token's `token`): an object with it is
    /// the value itself, even though it has a `data` field of its own. nil when `data` is null or missing.
    private func execute<T: Decodable>(_ request: URLRequest, bareKey: String? = nil) async throws -> T? {
        let body = try await executeRaw(request)
        return try decodeUnwrapped(T.self, from: body, bareKey: bareKey)
    }

    internal func decodeUnwrapped<T: Decodable>(_ type: T.Type, from body: Data, bareKey: String?) throws -> T? {
        guard let value = Self.unwrap(body, bareKey: bareKey) else { return nil }
        do {
            return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
        } catch {
            RiviumSyncLogger.e("ApiClient: Failed to decode a \(body.count)-byte response", error: error)
            throw error
        }
    }

    /// The value of a response: what is under `data` for a wrapped answer, else the whole body.
    static func unwrap(_ body: Data, bareKey: String?) -> Any? {
        guard let json = try? JSONSerialization.jsonObject(with: body, options: .fragmentsAllowed) else { return nil }
        guard let dict = json as? [String: Any] else { return json }
        if let bareKey = bareKey, dict[bareKey] != nil { return dict }
        if dict.keys.contains("data") { return dict["data"] is NSNull ? nil : dict["data"] }
        return dict
    }

    /// A list answer: `{ data: [...], total }` or a bare array.
    private func executeList<T: Decodable>(_ request: URLRequest) async throws -> (items: [T], total: Int?) {
        let body = try await executeRaw(request)
        let items: [T] = try decodeUnwrapped([T].self, from: body, bareKey: nil) ?? []
        let total = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]).flatMap { ListenWire.int($0["total"]) }
        return (items, total)
    }

    /// Sends the request and answers the body of a 2xx response; anything else is thrown as a `RiviumSyncError`.
    private func executeRaw(_ request: URLRequest, retryOnExpiredToken: Bool = true) async throws -> Data {
        RiviumSyncLogger.d("ApiClient: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            RiviumSyncLogger.e("ApiClient: Invalid response type", error: nil)
            throw RiviumSyncError.invalidResponse("Invalid response type")
        }

        // An expired token is transient: get a fresh one and try once more, so
        // the caller never sees it.
        if httpResponse.statusCode == 401,
           retryOnExpiredToken,
           request.value(forHTTPHeaderField: "X-User-Token") != nil,
           let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           body["code"] as? String == "token_expired" {
            RiviumSyncLogger.d("ApiClient: user token expired - refreshing and retrying once")
            userTokens.invalidate()
            if let refreshed = await userTokens.current() {
                var retried = request
                retried.setValue(refreshed, forHTTPHeaderField: "X-User-Token")
                return try await executeRaw(retried, retryOnExpiredToken: false)
            }
        }

        RiviumSyncLogger.d("ApiClient: Response status \(httpResponse.statusCode)")

        // Never log bodies: they carry user tokens, the realtime token and the
        // app's own data, and debug logs end up in bug reports and crash tools.
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Self.error(status: httpResponse.statusCode, body: data)
        }
        return data
    }

    /// The error for a non-2xx answer. A query the security rules cannot allow is a typed
    /// `queryNotAllowed`; everything else stays a `networkError` carrying the status and code.
    static func error(status: Int, body: Data) -> RiviumSyncError {
        let errorDict = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let code = errorDict?["code"] as? String
        if status == 403, code == "query_not_allowed" {
            let message = errorDict?["message"] as? String ?? "This query is not allowed by the security rules."
            let fields = (errorDict?["fields"] as? [Any])?.compactMap { $0 as? String } ?? []
            return .queryNotAllowed(message, fields: fields)
        }
        // Marks "sign the user in first" so realtime can wait for a token
        // instead of retrying; the error the caller sees is unchanged.
        let cause: Error = isUserTokenRequired(status: status, body: body)
            ? UserTokenRequiredError() : HttpStatusError(status: status, code: code)
        if let errorDict = errorDict {
            let message = errorDict["message"] as? String ?? errorDict["error"] as? String ?? "Request failed"
            // The server's short error message only.
            RiviumSyncLogger.e("ApiClient: Request failed (\(status)): \(message.prefix(200))", error: nil)
            return .networkError(message, cause)
        }
        RiviumSyncLogger.e("ApiClient: Request failed (\(status)), \(body.count) bytes", error: nil)
        return .networkError("Request failed with status \(status)", cause)
    }

    /// True for the answer a project with "Require signed user tokens" gives a
    /// request that carried no token.
    static func isUserTokenRequired(status: Int, body: Data) -> Bool {
        return status == 401 && (String(data: body, encoding: .utf8)?.contains("token_required") ?? false)
    }

    // MARK: - MQTT Token

    /// Fetch a short-lived JWT token for MQTT authentication.
    func fetchMqttToken() async throws -> MqttTokenResponse {
        let request = try await buildRequest(endpoint: "/connections/token", method: "POST")
        guard let token: MqttTokenResponse = try await execute(request, bareKey: "token") else {
            throw RiviumSyncError.invalidResponse("No realtime token in the answer")
        }
        return token
    }

    // MARK: - Database Operations

    func listDatabases() async throws -> [DatabaseInfo] {
        let request = try await buildRequest(endpoint: "/databases")
        let databases: [DatabaseInfo]? = try await execute(request)
        return databases ?? []
    }

    func createDatabase(name: String) async throws -> DatabaseInfo {
        let request = try await buildRequest(endpoint: "/databases", method: "POST", body: ["name": name])
        guard let data: DatabaseInfo = try await execute(request, bareKey: "id") else {
            throw RiviumSyncError.databaseError("Failed to create database")
        }
        return data
    }

    func deleteDatabase(databaseId: String) async throws {
        let request = try await buildRequest(endpoint: "/databases/\(databaseId)", method: "DELETE")
        _ = try await executeRaw(request)
    }

    // MARK: - Collection Operations
    
    func listCollections(databaseId: String) async throws -> [CollectionInfo] {
        let request = try await buildRequest(endpoint: "/databases/\(databaseId)/collections")
        let collections: [CollectionInfo]? = try await execute(request)
        return collections ?? []
    }
    
    func createCollection(databaseId: String, name: String) async throws -> CollectionInfo {
        let request = try await buildRequest(endpoint: "/databases/\(databaseId)/collections", method: "POST", body: ["name": name])
        guard let data: CollectionInfo = try await execute(request, bareKey: "id") else {
            throw RiviumSyncError.collectionError("Failed to create collection")
        }
        return data
    }
    
    func deleteCollection(collectionId: String) async throws {
        let request = try await buildRequest(endpoint: "/collections/\(collectionId)", method: "DELETE")
        _ = try await executeRaw(request)
    }
    
    // MARK: - Document Operations
    
    func addDocument(databaseId: String, collectionId: String, data: [String: Any]) async throws -> SyncDocument {
        let request = try await buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk",
            method: "POST",
            body: ["data": data]
        )
        guard let doc: DocumentResponse = try await execute(request, bareKey: "id") else {
            throw RiviumSyncError.documentError("Failed to add document")
        }
        return doc.toSyncDocument()
    }
    
    func getDocument(databaseId: String, collectionId: String, documentId: String) async throws -> SyncDocument? {
        let request = try await buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/\(documentId)"
        )
        do {
            let doc: DocumentResponse? = try await execute(request, bareKey: "id")
            return doc?.toSyncDocument()
        } catch RiviumSyncError.networkError(let msg, _) where msg.contains("404") || msg.lowercased().contains("not found") {
            return nil
        }
    }
    
    func getAllDocuments(databaseId: String, collectionId: String) async throws -> [SyncDocument] {
        try await fetchCollection(databaseId: databaseId, collectionId: collectionId).documents
    }

    /// Every document in a collection, across as many pages as it takes. The
    /// server answers 100 at a time unless asked otherwise, and this used to make
    /// one request - so getAll() quietly stopped at the first 100.
    func fetchCollection(databaseId: String, collectionId: String) async throws -> CollectionSnapshot {
        var documents: [SyncDocument] = []
        var total: Int?
        while true {
            let (page, pageTotal) = try await fetchPage(
                databaseId: databaseId, collectionId: collectionId,
                skip: documents.count, limit: Self.pageSize
            )
            documents += page
            total = pageTotal
            // Stop on a short or empty page, or once we have everything.
            if page.count < Self.pageSize { break }
            guard let total = total, documents.count < total else { break }
        }
        RiviumSyncLogger.d("getAllDocuments fetched \(documents.count) of \(total.map(String.init) ?? "?")")
        let complete = total.map { documents.count >= $0 } ?? false
        return CollectionSnapshot(documents: documents, complete: complete)
    }

    static let pageSize = 100

    /// One page of a collection plus the server's total. Separate so the paging
    /// loop above can be tested without a network.
    func fetchPage(
        databaseId: String,
        collectionId: String,
        skip: Int,
        limit: Int
    ) async throws -> (documents: [SyncDocument], total: Int?) {
        let request = try await buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk" +
                "?skip=\(skip)&limit=\(limit)"
        )
        let (items, total): ([DocumentResponse], Int?) = try await executeList(request)
        return (items.map { $0.toSyncDocument() }, total)
    }
    
    func updateDocument(databaseId: String, collectionId: String, documentId: String, data: [String: Any]) async throws -> SyncDocument {
        let request = try await buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/\(documentId)",
            method: "PATCH",
            body: ["data": data]
        )
        guard let doc: DocumentResponse = try await execute(request, bareKey: "id") else {
            throw RiviumSyncError.documentError("Failed to update document")
        }
        return doc.toSyncDocument()
    }
    
    /// set: `merge` false replaces the document, true merges into it.
    func setDocument(databaseId: String, collectionId: String, documentId: String, data: [String: Any], merge: Bool) async throws -> SyncDocument {
        let request = try await buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/\(documentId)",
            method: "PUT",
            body: ["data": data, "merge": merge]
        )
        guard let doc: DocumentResponse = try await execute(request, bareKey: "id") else {
            throw RiviumSyncError.documentError("Failed to set document")
        }
        return doc.toSyncDocument()
    }
    
    func deleteDocument(databaseId: String, collectionId: String, documentId: String) async throws {
        let request = try await buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/\(documentId)",
            method: "DELETE"
        )
        _ = try await executeRaw(request)
    }
    
    func queryDocuments(databaseId: String, collectionId: String, query: QueryParams) async throws -> [SyncDocument] {
        let request = try await buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/query",
            method: "POST",
            body: query.toDict()
        )
        let (items, _): ([DocumentResponse], Int?) = try await executeList(request)
        return items.map { $0.toSyncDocument() }
    }

    // MARK: - Listeners

    /// POST …/listen: start a server-routed listener. A 403 that is not `query_not_allowed`
    /// becomes a `permissionError` with the server's message; a 404 (an older backend) stays a
    /// `networkError` whose cause says 404.
    func listen(databaseId: String, collectionId: String, body: [String: Any]) async throws -> ListenAnswer {
        let request = try await buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/listen",
            method: "POST",
            body: body
        )
        let data: Data
        do {
            data = try await executeRaw(request)
        } catch RiviumSyncError.networkError(let message, let cause as HttpStatusError) where cause.status == 403 {
            throw RiviumSyncError.permissionError(message)
        }
        guard let answer = ListenAnswer.parse(data) else {
            throw RiviumSyncError.invalidResponse("Unexpected answer to listen")
        }
        return answer
    }

    /// DELETE …/listen/{id}: stop a server-routed listener. Best effort.
    func unlisten(databaseId: String, subscriptionId: String) async {
        do {
            let request = try await buildRequest(endpoint: "/databases/\(databaseId)/listen/\(subscriptionId)", method: "DELETE")
            _ = try await executeRaw(request)
        } catch {
            RiviumSyncLogger.d("ApiClient: stopping a listener failed (ignored): \(error.localizedDescription)")
        }
    }

    // MARK: - Batch Operations

    /// Execute a batch of operations atomically
    func executeBatch(operations: [[String: Any]]) async throws {
        let request = try await buildRequest(
            endpoint: "/batch/sdk",
            method: "POST",
            body: ["operations": operations]
        )
        _ = try await executeRaw(request)
    }
}

// MARK: - Response Types


/// The HTTP status (and the server's `code`, when it sent one) of a refused request; the
/// cause of a `networkError`.
internal struct HttpStatusError: Error {
    let status: Int
    let code: String?

    /// True when `error` is a request the server answered with `status`.
    static func isStatus(_ status: Int, _ error: Error) -> Bool {
        if case RiviumSyncError.networkError(_, let cause as HttpStatusError) = error {
            return cause.status == status
        }
        return false
    }
}

/// The project requires a signed user token and the request carried none.
/// Not a network failure: nothing changes until the app supplies a token.
internal struct UserTokenRequiredError: Error {}

/// MQTT token response from /connections/token
/// A whole collection as read from the server. `complete` is true only when the
/// pages added up to the server's own total, which is what makes it safe to drop
/// cached rows that were not returned.
internal struct CollectionSnapshot {
    let documents: [SyncDocument]
    let complete: Bool
}

internal struct MqttTokenResponse: Decodable {
    let token: String
    let expiresIn: String?
    /// Project the API key belongs to; realtime topics are namespaced by it.
    let projectId: String?
    let mqtt: MqttConnectionInfo?
}

internal struct MqttConnectionInfo: Decodable {
    let host: String?
    let port: Int?
    let useTls: Bool?
}

private struct DocumentResponse: Decodable {
    let id: String
    let data: [String: AnyCodable]
    let createdAt: String  // ISO date string
    let updatedAt: String  // ISO date string
    let version: Int?

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func parseDate(_ dateString: String) -> TimeInterval {
        if let date = DocumentResponse.isoFormatter.date(from: dateString) {
            return date.timeIntervalSince1970 * 1000
        }
        if let date = DocumentResponse.isoFormatterNoFraction.date(from: dateString) {
            return date.timeIntervalSince1970 * 1000
        }
        return Date().timeIntervalSince1970 * 1000
    }

    func toSyncDocument() -> SyncDocument {
        return SyncDocument(
            id: id,
            data: data.mapValues { $0.value },
            createdAt: parseDate(createdAt),
            updatedAt: parseDate(updatedAt),
            version: version ?? 1
        )
    }
}

/// Query parameters for document queries
internal struct QueryParams {
    var filters: [[String: Any]] = []
    var orderByField: String?
    var orderDirection: String = "asc"
    var limitCount: Int?
    var offsetCount: Int?
    
    func toDict() -> [String: Any] {
        var dict: [String: Any] = [:]
        
        if !filters.isEmpty {
            dict["filters"] = filters
        }
        if let orderBy = orderByField {
            dict["orderBy"] = ["field": orderBy, "direction": orderDirection]
        }
        if let limit = limitCount {
            dict["limit"] = limit
        }
        if let offset = offsetCount {
            dict["offset"] = offset
        }
        
        return dict
    }
}
