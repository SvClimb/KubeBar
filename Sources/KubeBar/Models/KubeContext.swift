import Foundation

struct KubeContext: Identifiable, Hashable {
    var id: String { name }
    var name: String
}
