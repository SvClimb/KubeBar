import Foundation

struct NamedEntry: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
}
