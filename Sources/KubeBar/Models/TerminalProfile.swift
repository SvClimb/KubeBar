import Foundation

struct TerminalProfile: Identifiable, Hashable {
    var id: String { name }
    var name: String
    /// Shell line executed via `/bin/zsh -lc` that runs the command right away.
    /// Placeholder {{command}} is replaced with the fully assembled utility
    /// command (e.g. "stern --context prod -n backend my-app").
    var launchTemplate: String
    /// Shell line that opens the terminal with the command staged but NOT
    /// executed, so the user can review/edit and press Enter themselves.
    /// Empty string means this profile doesn't support "prepare" mode.
    var prepareTemplate: String = ""
}

extension TerminalProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, launchTemplate, prepareTemplate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        launchTemplate = try container.decode(String.self, forKey: .launchTemplate)
        prepareTemplate = try container.decodeIfPresent(String.self, forKey: .prepareTemplate) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(launchTemplate, forKey: .launchTemplate)
        try container.encode(prepareTemplate, forKey: .prepareTemplate)
    }
}
