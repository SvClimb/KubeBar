import SwiftUI

/// A dedicated window for creating/editing a single utility template.
/// Pulled out of the settings list because editing a long command template
/// inline, in a single-line `TextField`, made it hard to see and edit the
/// whole string.
struct UtilityEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    /// Names already taken by other utilities (excludes this utility's own
    /// current name when editing) — `Utility.id` is its name, so two
    /// entries sharing a name break list identity and name-based lookups
    /// like `TerminalLauncher.buildCommand` silently pick the first match.
    let existingNames: Set<String>
    @State private var name: String
    @State private var executable: String
    @State private var commandTemplate: String

    let onSave: (Utility) -> Void

    init(utility: Utility, isNew: Bool, existingNames: Set<String>, onSave: @escaping (Utility) -> Void) {
        self.isNew = isNew
        self.existingNames = existingNames
        _name = State(initialValue: utility.name)
        _executable = State(initialValue: utility.executable)
        _commandTemplate = State(initialValue: utility.commandTemplate)
        self.onSave = onSave
    }

    private static let placeholders: [(token: String, hint: LocalizedStringKey)] = [
        ("{executable}", "the utility’s executable"),
        ("{context}", "the selected kubectl context"),
        ("{namespace}", "the selected namespace"),
        ("{app}", "the selected app/pod — remove it if the utility doesn’t need one")
    ]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedExecutable: String { executable.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTemplate: String { commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isDuplicateName: Bool {
        existingNames.contains { $0.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && !trimmedExecutable.isEmpty && !trimmedTemplate.isEmpty && !isDuplicateName
    }

    private var preview: String {
        let draft = Utility(name: trimmedName.isEmpty ? "?" : trimmedName, executable: executable, commandTemplate: commandTemplate)
        return TerminalLauncher.previewCommand(
            selection: LaunchSelection(utilityName: draft.name, contextName: nil, namespaceName: nil, appName: nil),
            utilities: [draft]
        ) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            (isNew ? Text("New utility") : Text("Edit utility"))
                .font(.headline)

            labeledField("Name (as shown in the menu)") {
                TextField("e.g. kubectl logs", text: $name)
                if isDuplicateName {
                    Text("A utility with this name already exists")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            labeledField("Executable or path") {
                TextField("e.g. kubectl", text: $executable)
            }

            labeledField("Command template") {
                TextEditor(text: $commandTemplate)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Insert placeholder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Self.placeholders, id: \.token) { placeholder in
                        Button(placeholder.token) {
                            insertPlaceholder(placeholder.token)
                        }
                        .help(placeholder.hint)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            labeledField("Preview") {
                Text(preview)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(Utility(name: trimmedName, executable: trimmedExecutable, commandTemplate: trimmedTemplate))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func insertPlaceholder(_ token: String) {
        if !commandTemplate.isEmpty && !commandTemplate.hasSuffix(" ") {
            commandTemplate += " "
        }
        commandTemplate += token
    }
}
