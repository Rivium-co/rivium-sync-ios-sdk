import Foundation

/// Represents a pending operation queued for sync
public struct PendingOperation {
    public let id: String
    public let documentId: String
    public let databaseId: String
    public let collectionId: String
    public let operationType: OperationType
    public var data: [String: AnyCodable]?
    public var baseVersion: Int?
    public var createdAt: Int64
    public var status: String // "pending", "processing", "failed"
    public var retryCount: Int
    public var lastError: String?

    public init(
        id: String = UUID().uuidString,
        documentId: String,
        databaseId: String,
        collectionId: String,
        operationType: OperationType,
        data: [String: AnyCodable]? = nil,
        baseVersion: Int? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        status: String = "pending",
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.databaseId = databaseId
        self.collectionId = collectionId
        self.operationType = operationType
        self.data = data
        self.baseVersion = baseVersion
        self.createdAt = createdAt
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
    }

    /// Create a CREATE operation
    public static func create(
        documentId: String,
        databaseId: String,
        collectionId: String,
        data: [String: Any]
    ) -> PendingOperation {
        return PendingOperation(
            documentId: documentId,
            databaseId: databaseId,
            collectionId: collectionId,
            operationType: .create,
            data: data.mapValues { AnyCodable($0) }
        )
    }

    /// Create an UPDATE operation
    public static func update(
        documentId: String,
        databaseId: String,
        collectionId: String,
        data: [String: Any],
        baseVersion: Int
    ) -> PendingOperation {
        return PendingOperation(
            documentId: documentId,
            databaseId: databaseId,
            collectionId: collectionId,
            operationType: .update,
            data: data.mapValues { AnyCodable($0) },
            baseVersion: baseVersion
        )
    }

    /// Create a DELETE operation
    public static func delete(
        documentId: String,
        databaseId: String,
        collectionId: String,
        baseVersion: Int
    ) -> PendingOperation {
        return PendingOperation(
            documentId: documentId,
            databaseId: databaseId,
            collectionId: collectionId,
            operationType: .delete,
            baseVersion: baseVersion
        )
    }

    /// Get data as [String: Any]
    public func getData() -> [String: Any]? {
        return data?.mapValues { $0.value }
    }
}

// MARK: - Codable
extension PendingOperation: Codable {
    enum CodingKeys: String, CodingKey {
        case id, documentId, databaseId, collectionId, operationType
        case data, baseVersion, createdAt, status, retryCount, lastError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        documentId = try container.decode(String.self, forKey: .documentId)
        databaseId = try container.decode(String.self, forKey: .databaseId)
        collectionId = try container.decode(String.self, forKey: .collectionId)
        operationType = try container.decode(OperationType.self, forKey: .operationType)
        data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .data)
        baseVersion = try container.decodeIfPresent(Int.self, forKey: .baseVersion)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        status = try container.decode(String.self, forKey: .status)
        retryCount = try container.decode(Int.self, forKey: .retryCount)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(documentId, forKey: .documentId)
        try container.encode(databaseId, forKey: .databaseId)
        try container.encode(collectionId, forKey: .collectionId)
        try container.encode(operationType, forKey: .operationType)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(baseVersion, forKey: .baseVersion)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(status, forKey: .status)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }
}
