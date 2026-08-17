import Foundation

struct NamedEntry: Codable, Identifiable, Hashable {
    var name: String
    /// Scopes this entry to a specific context+namespace (used for
    /// auto-discovered apps). Nil for entries meant to always be shown,
    /// e.g. saved namespaces or manually added apps.
    var contextName: String? = nil
    var namespaceName: String? = nil

    var id: String {
        guard let contextName, let namespaceName else { return name }
        return "\(contextName)/\(namespaceName)/\(name)"
    }
}
