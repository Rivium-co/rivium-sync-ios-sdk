import Foundation

/// HTTP API client for RiviumSync REST operations
internal class ApiClient {
    private let config: RiviumSyncConfig
    private let userId: String?
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: RiviumSyncConfig, userId: String? = nil) {
        self.config = config
        self.userId = userId
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = TimeInterval(config.connectionTimeout)
        self.session = URLSession(configuration: configuration)
    }
    
    private func buildRequest(endpoint: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: "\(config.apiUrl)\(endpoint)") else {
            throw RiviumSyncError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let userId = userId {
            request.setValue(userId, forHTTPHeaderField: "X-User-Id")
        }

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }
    
    private func executeRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        RiviumSyncLogger.d("ApiClient: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            RiviumSyncLogger.e("ApiClient: Invalid response type", error: nil)
            throw RiviumSyncError.invalidResponse("Invalid response type")
        }

        RiviumSyncLogger.d("ApiClient: Response status \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode"
            RiviumSyncLogger.e("ApiClient: Error response body: \(responseBody)", error: nil)
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let message = errorDict["message"] as? String ?? errorDict["error"] as? String ?? "Request failed"
                throw RiviumSyncError.networkError(message, nil)
            }
            throw RiviumSyncError.networkError("Request failed with status \(httpResponse.statusCode)", nil)
        }

        do {
            let result = try decoder.decode(T.self, from: data)
            return result
        } catch {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode"
            RiviumSyncLogger.e("ApiClient: Failed to decode response: \(responseBody)", error: error)
            throw error
        }
    }
    
    // MARK: - MQTT Token

    /// Fetch a short-lived JWT token for MQTT authentication.
    func fetchMqttToken() async throws -> MqttTokenResponse {
        let request = try buildRequest(endpoint: "/connections/token", method: "POST")
        return try await executeRequest(request)
    }

    // MARK: - Database Operations

    func listDatabases() async throws -> [DatabaseInfo] {
        let request = try buildRequest(endpoint: "/databases")
        let response: ApiResponse<[DatabaseInfo]> = try await executeRequest(request)
        return response.data ?? []
    }

    func createDatabase(name: String) async throws -> DatabaseInfo {
        let request = try buildRequest(endpoint: "/databases", method: "POST", body: ["name": name])
        let response: ApiResponse<DatabaseInfo> = try await executeRequest(request)
        guard let data = response.data else {
            throw RiviumSyncError.databaseError("Failed to create database")
        }
        return data
    }

    func deleteDatabase(databaseId: String) async throws {
        let request = try buildRequest(endpoint: "/databases/\(databaseId)", method: "DELETE")
        let _: ApiResponse<EmptyData> = try await executeRequest(request)
    }

    // MARK: - Collection Operations
    
    func listCollections(databaseId: String) async throws -> [CollectionInfo] {
        let request = try buildRequest(endpoint: "/databases/\(databaseId)/collections")
        let response: ApiResponse<[CollectionInfo]> = try await executeRequest(request)
        return response.data ?? []
    }
    
    func createCollection(databaseId: String, name: String) async throws -> CollectionInfo {
        let request = try buildRequest(endpoint: "/databases/\(databaseId)/collections", method: "POST", body: ["name": name])
        let response: ApiResponse<CollectionInfo> = try await executeRequest(request)
        guard let data = response.data else {
            throw RiviumSyncError.collectionError("Failed to create collection")
        }
        return data
    }
    
    func deleteCollection(collectionId: String) async throws {
        let request = try buildRequest(endpoint: "/collections/\(collectionId)", method: "DELETE")
        let _: ApiResponse<EmptyData> = try await executeRequest(request)
    }
    
    // MARK: - Document Operations
    
    func addDocument(databaseId: String, collectionId: String, data: [String: Any]) async throws -> SyncDocument {
        let request = try buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk",
            method: "POST",
            body: ["data": data]
        )
        let response: ApiResponse<DocumentResponse> = try await executeRequest(request)
        guard let doc = response.data else {
            throw RiviumSyncError.documentError("Failed to add document")
        }
        return doc.toSyncDocument()
    }
    
    func getDocument(databaseId: String, collectionId: String, documentId: String) async throws -> SyncDocument? {
        let request = try buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/\(documentId)"
        )
        do {
            let response: ApiResponse<DocumentResponse> = try await executeRequest(request)
            return response.data?.toSyncDocument()
        } catch RiviumSyncError.networkError(let msg, _) where msg.contains("404") || msg.lowercased().contains("not found") {
            return nil
        }
    }
    
    func getAllDocuments(databaseId: String, collectionId: String) async throws -> [SyncDocument] {
        let request = try buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk"
        )
        let response: ListResponse<DocumentResponse> = try await executeRequest(request)
        return response.data.map { $0.toSyncDocument() }
    }
    
    func updateDocument(databaseId: String, collectionId: String, documentId: String, data: [String: Any]) async throws -> SyncDocument {
        let request = try buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/\(documentId)",
            method: "PATCH",
            body: ["data": data]
        )
        let response: ApiResponse<DocumentResponse> = try await executeRequest(request)
        guard let doc = response.data else {
            throw RiviumSyncError.documentError("Failed to update document")
        }
        return doc.toSyncDocument()
    }
    
    func setDocument(databaseId: String, collectionId: String, documentId: String, data: [String: Any]) async throws -> SyncDocument {
        let request = try buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/\(documentId)",
            method: "PUT",
            body: ["data": data]
        )
        let response: ApiResponse<DocumentResponse> = try await executeRequest(request)
        guard let doc = response.data else {
            throw RiviumSyncError.documentError("Failed to set document")
        }
        return doc.toSyncDocument()
    }
    
    func deleteDocument(databaseId: String, collectionId: String, documentId: String) async throws {
        let request = try buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/\(documentId)",
            method: "DELETE"
        )
        let _: ApiResponse<EmptyData> = try await executeRequest(request)
    }
    
    func queryDocuments(databaseId: String, collectionId: String, query: QueryParams) async throws -> [SyncDocument] {
        let request = try buildRequest(
            endpoint: "/databases/\(databaseId)/collections/\(collectionId)/documents/sdk/query",
            method: "POST",
            body: query.toDict()
        )
        let response: ListResponse<DocumentResponse> = try await executeRequest(request)
        return response.data.map { $0.toSyncDocument() }
    }

    // MARK: - Batch Operations

    /// Execute a batch of operations atomically
    func executeBatch(operations: [[String: Any]]) async throws {
        let request = try buildRequest(
            endpoint: "/batch/sdk",
            method: "POST",
            body: ["operations": operations]
        )
        let _: ApiResponse<EmptyData> = try await executeRequest(request)
    }
}

// MARK: - Response Types

private struct ApiResponse<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
    let message: String?
    let error: String?
}

/// Response wrapper for list endpoints that return {data: [...], total: N}
private struct ListResponse<T: Decodable>: Decodable {
    let data: [T]
    let total: Int?
    let skip: Int?
    let limit: Int?
}

private struct EmptyData: Decodable {}

/// MQTT token response from /connections/token
internal struct MqttTokenResponse: Decodable {
    let token: String
    let expiresIn: String?
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
