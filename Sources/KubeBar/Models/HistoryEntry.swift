import Foundation

struct HistoryEntry: Identifiable, Hashable {
    var id = UUID()
    var timestamp: Date
    var utilityName: String
    var contextName: String
    var namespaceName: String
    var appName: String?
    var commandString: String
    var wasPrepared: Bool = false
}

extension HistoryEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, utilityName, contextName, namespaceName, appName, commandString, wasPrepared
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        utilityName = try container.decode(String.self, forKey: .utilityName)
        contextName = try container.decode(String.self, forKey: .contextName)
        namespaceName = try container.decode(String.self, forKey: .namespaceName)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        commandString = try container.decode(String.self, forKey: .commandString)
        wasPrepared = try container.decodeIfPresent(Bool.self, forKey: .wasPrepared) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(utilityName, forKey: .utilityName)
        try container.encode(contextName, forKey: .contextName)
        try container.encode(namespaceName, forKey: .namespaceName)
        try container.encodeIfPresent(appName, forKey: .appName)
        try container.encode(commandString, forKey: .commandString)
        try container.encode(wasPrepared, forKey: .wasPrepared)
    }
}
