import Foundation

/// Represents a document cached locally for offline support
public struct CachedDocument {
    public let id: String
    public let databaseId: String
    public let collectionId: String
    public var data: [String: AnyCodable]
    public var createdAt: Int64
    public var updatedAt: Int64
    public var version: Int
    public var syncStatus: SyncStatus
    public var baseVersion: Int?
    public var retryCount: Int
    public var lastError: String?
    public var localUpdatedAt: Int64

    public init(
        id: String,
        databaseId: String,
        collectionId: String,
        data: [String: AnyCodable],
        createdAt: Int64,
        updatedAt: Int64,
        version: Int,
        syncStatus: SyncStatus,
        baseVersion: Int? = nil,
        retryCount: Int = 0,
        lastError: String? = nil,
        localUpdatedAt: Int64? = nil
    ) {
        self.id = id
        self.databaseId = databaseId
        self.collectionId = collectionId
        self.data = data
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.syncStatus = syncStatus
        self.baseVersion = baseVersion
        self.retryCount = retryCount
        self.lastError = lastError
        self.localUpdatedAt = localUpdatedAt ?? Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// Convert to SyncDocument
    public func toSyncDocument() -> SyncDocument {
        return SyncDocument(
            id: id,
            data: data.mapValues { $0.value },
            createdAt: TimeInterval(createdAt),
            updatedAt: TimeInterval(updatedAt),
            version: version
        )
    }

    /// Create from SyncDocument
    public static func fromSyncDocument(
        _ doc: SyncDocument,
        databaseId: String,
        collectionId: String,
        syncStatus: SyncStatus,
        baseVersion: Int? = nil
    ) -> CachedDocument {
        return CachedDocument(
            id: doc.id,
            databaseId: databaseId,
            collectionId: collectionId,
            data: doc.data,
            createdAt: Int64(doc.createdAt),
            updatedAt: Int64(doc.updatedAt),
            version: doc.version,
            syncStatus: syncStatus,
            baseVersion: baseVersion
        )
    }

    /// Get data as [String: Any]
    public func getData() -> [String: Any] {
        return data.mapValues { $0.value }
    }
}

// MARK: - Codable
extension CachedDocument: Codable {
    enum CodingKeys: String, CodingKey {
        case id, databaseId, collectionId, data, createdAt, updatedAt
        case version, syncStatus, baseVersion, retryCount, lastError, localUpdatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        databaseId = try container.decode(String.self, forKey: .databaseId)
        collectionId = try container.decode(String.self, forKey: .collectionId)
        data = try container.decode([String: AnyCodable].self, forKey: .data)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
        version = try container.decode(Int.self, forKey: .version)
        syncStatus = try container.decode(SyncStatus.self, forKey: .syncStatus)
        baseVersion = try container.decodeIfPresent(Int.self, forKey: .baseVersion)
        retryCount = try container.decode(Int.self, forKey: .retryCount)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        localUpdatedAt = try container.decode(Int64.self, forKey: .localUpdatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(databaseId, forKey: .databaseId)
        try container.encode(collectionId, forKey: .collectionId)
        try container.encode(data, forKey: .data)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(version, forKey: .version)
        try container.encode(syncStatus, forKey: .syncStatus)
        try container.encodeIfPresent(baseVersion, forKey: .baseVersion)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encode(localUpdatedAt, forKey: .localUpdatedAt)
    }
}
