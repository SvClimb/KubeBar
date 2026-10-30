import Foundation

struct NamedEntry: Codable, Identifiable, Hashable {
    var name: String
    /// Scopes this entry to a specific context (auto-discovered namespaces)
    /// or context+namespace (auto-discovered apps). Nil for manually added
    /// entries, which are always shown.
    var contextName: String? = nil
    var namespaceName: String? = nil

    var id: String {
        [contextName, namespaceName, name].compactMap { $0 }.joined(separator: "/")
    }

    /// e.g. "prod/backend" — nil for unscoped entries.
    var scopeLabel: String? {
        let parts = [contextName, namespaceName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }
}
