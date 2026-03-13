import Foundation

/// Represents a document in a RiviumSync collection
public struct SyncDocument {
    public let id: String
    public let data: [String: AnyCodable]
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval
    public let version: Int

    public init(id: String, data: [String: Any], createdAt: TimeInterval = Date().timeIntervalSince1970 * 1000, updatedAt: TimeInterval = Date().timeIntervalSince1970 * 1000, version: Int = 1) {
        self.id = id
        self.data = data.mapValues { AnyCodable($0) }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }

    // Internal init for decoded data
    internal init(id: String, decodedData: [String: AnyCodable], createdAt: TimeInterval, updatedAt: TimeInterval, version: Int) {
        self.id = id
        self.data = decodedData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }
    
    /// Get a value from document data
    public func get<T>(_ field: String) -> T? {
        return data[field]?.value as? T
    }
    
    /// Get a string value
    public func getString(_ field: String) -> String? {
        return data[field]?.value as? String
    }
    
    /// Get an integer value
    public func getInt(_ field: String) -> Int? {
        if let num = data[field]?.value as? NSNumber {
            return num.intValue
        }
        return nil
    }
    
    /// Get a double value
    public func getDouble(_ field: String) -> Double? {
        if let num = data[field]?.value as? NSNumber {
            return num.doubleValue
        }
        return nil
    }
    
    /// Get a boolean value
    public func getBool(_ field: String) -> Bool? {
        return data[field]?.value as? Bool
    }
    
    /// Get an array value
    public func getArray<T>(_ field: String) -> [T]? {
        return data[field]?.value as? [T]
    }
    
    /// Get a dictionary value
    public func getDictionary(_ field: String) -> [String: Any]? {
        return data[field]?.value as? [String: Any]
    }
    
    /// Check if field exists
    public func contains(_ field: String) -> Bool {
        return data[field] != nil
    }
    
    /// Check if document exists
    public var exists: Bool {
        return !id.isEmpty
    }
    
    /// Convert to dictionary
    public func toDict() -> [String: Any] {
        return [
            "id": id,
            "data": data.mapValues { $0.value },
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "version": version
        ]
    }
}

// MARK: - Codable
extension SyncDocument: Codable {
    enum CodingKeys: String, CodingKey {
        case id, data, createdAt, updatedAt, version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        data = try container.decode([String: AnyCodable].self, forKey: .data)
        createdAt = try container.decode(TimeInterval.self, forKey: .createdAt)
        updatedAt = try container.decode(TimeInterval.self, forKey: .updatedAt)
        version = try container.decode(Int.self, forKey: .version)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(data, forKey: .data)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(version, forKey: .version)
    }
}

/// Database info from server
public struct DatabaseInfo: Codable {
    public let id: String
    public let name: String
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval
}

/// Collection info from server
public struct CollectionInfo: Codable {
    public let id: String
    public let name: String
    public let databaseId: String
    public let documentCount: Int
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval
}

/// Type-erased Codable wrapper
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode value"))
        }
    }
}
