import Foundation

struct Utility: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var executable: String
    /// Placeholders: {executable} {context} {namespace} {app}. Omit {app} if this
    /// utility profile doesn't need an app/pod picked (e.g. plain kubectl).
    var commandTemplate: String
}
