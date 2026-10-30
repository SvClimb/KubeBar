import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var configStore: ConfigStore

    private enum UtilitySheet: Identifiable {
        case add
        case edit(index: Int)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let index): return "edit-\(index)"
            }
        }
    }

    @State private var utilitySheet: UtilitySheet?
    @State private var newNamespace = ""
    @State private var newApp = ""
    @State private var newTerminalName = ""
    @State private var launchAtLogin = false
    @State private var historyError: String?
    /// Result of the last utilities import/export, shown under the list.
    @State private var transferStatus: (text: String, isError: Bool)?
    @State private var language = AppLanguage.current

    var body: some View {
        TabView {
            utilitiesTab.tabItem { Text("Utilities") }
            namespacesTab.tabItem { Text("Namespaces") }
            appsTab.tabItem { Text("Apps") }
            terminalTab.tabItem { Text("Terminal") }
            historyTab.tabItem { Text("History") }
            generalTab.tabItem { Text("General") }
        }
        .padding(20)
        .frame(width: 540, height: 440)
        .onAppear {
            launchAtLogin = LoginItemManager.isEnabled
        }
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Delete")
    }

    // MARK: - Утилиты

    private static let utilityTemplateExamples: [(name: LocalizedStringKey, template: String)] = [
        ("stern (default)", "{executable} --context {context} -n {namespace} {app}"),
        ("stern with timeout", "{executable} --context {context} -n {namespace} {app} --since 1h --timeout 30m"),
        ("kubectl logs", "{executable} --context {context} -n {namespace} logs -f deployment/{app}"),
        ("kubectl get pods", "{executable} --context {context} -n {namespace} get pods -l app={app} -o wide"),
        ("kubectl without app", "{executable} --context {context} -n {namespace}")
    ]

    private var utilitiesTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Each row is a separate command: a name (as shown in the menu), an executable or alias (e.g. “k”), and a template. Placeholders: {executable} {context} {namespace} {app} — remove {app} if the utility doesn’t need a pod/app. Need several variants of one utility (get pods, logs, custom flags)? Add another row with the same executable and a different name/template.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("Template examples") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.utilityTemplateExamples, id: \.template) { example in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(example.name)
                                .font(.caption.bold())
                            Text(example.template)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)

            List {
                ForEach(Array(configStore.utilities.enumerated()), id: \.element.id) { index, utility in
                    UtilityRow(
                        utility: utility,
                        canMoveUp: index > 0,
                        canMoveDown: index < configStore.utilities.count - 1,
                        onMoveUp: { moveUtility(from: index, to: index - 1) },
                        onMoveDown: { moveUtility(from: index, to: index + 1) },
                        onEdit: { utilitySheet = .edit(index: index) },
                        onDelete: {
                            configStore.utilities.remove(at: index)
                            configStore.save()
                        }
                    )
                }
            }

            if let transferStatus {
                Text(transferStatus.text)
                    .font(.caption)
                    .foregroundStyle(transferStatus.isError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Add utility") {
                    utilitySheet = .add
                }
                Spacer()
                Button("Import…") {
                    importUtilities()
                }
                .help("Load utility templates from a JSON file; utilities with the same name are replaced")
                Button("Export…") {
                    exportUtilities()
                }
                .disabled(configStore.utilities.isEmpty)
                .help("Save the utility templates to a JSON file")
            }
        }
        .sheet(item: $utilitySheet) { sheet in
            switch sheet {
            case .add:
                UtilityEditorView(
                    utility: Utility(name: "", executable: "", commandTemplate: "{executable} --context {context} -n {namespace} {app}"),
                    isNew: true,
                    existingNames: Set(configStore.utilities.map(\.name))
                ) { newUtility in
                    configStore.utilities.append(newUtility)
                    configStore.save()
                }
            case .edit(let index):
                if configStore.utilities.indices.contains(index) {
                    let otherNames = Set(
                        configStore.utilities.enumerated()
                            .filter { $0.offset != index }
                            .map { $0.element.name }
                    )
                    UtilityEditorView(utility: configStore.utilities[index], isNew: false, existingNames: otherNames) { updated in
                        configStore.utilities[index] = updated
                        configStore.save()
                    }
                }
            }
        }
    }

    private func exportUtilities() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "KubeBar-utilities.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try encoder.encode(configStore.utilities).write(to: url, options: .atomic)
            transferStatus = nil
        } catch {
            transferStatus = (String(localized: "Couldn't export utilities: \(error.localizedDescription)"), true)
        }
    }

    /// Merges utilities from a file written by `exportUtilities`: a utility
    /// with an existing name replaces it in place (names are unique ids),
    /// new ones are appended.
    private func importUtilities() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let imported: [Utility]
        do {
            imported = try JSONDecoder().decode([Utility].self, from: Data(contentsOf: url))
        } catch {
            transferStatus = (String(localized: "Couldn't import utilities: the file isn't a KubeBar utilities export."), true)
            return
        }

        var added = 0
        var replaced = 0
        for utility in imported where !utility.name.isEmpty {
            if let index = configStore.utilities.firstIndex(where: { $0.name == utility.name }) {
                configStore.utilities[index] = utility
                replaced += 1
            } else {
                configStore.utilities.append(utility)
                added += 1
            }
        }
        configStore.save()
        transferStatus = (String(localized: "Imported utilities: \(added) added, \(replaced) replaced."), false)
    }

    private func moveUtility(from: Int, to: Int) {
        guard configStore.utilities.indices.contains(from), configStore.utilities.indices.contains(to) else { return }
        configStore.utilities.swapAt(from, to)
        configStore.save()
    }

    @ViewBuilder
    private func scopeLabel(for entry: NamedEntry) -> some View {
        if let scope = entry.scopeLabel {
            Text(verbatim: "· \(scope)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Namespaces

    private var namespacesTab: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(configStore.savedNamespaces) { entry in
                    HStack {
                        Text(entry.name)
                        scopeLabel(for: entry)
                        Spacer()
                        deleteButton {
                            configStore.savedNamespaces.removeAll { $0.id == entry.id }
                            configStore.save()
                        }
                    }
                }
            }
            HStack {
                TextField("Namespace", text: $newNamespace)
                Button("Add") {
                    guard !newNamespace.isEmpty else { return }
                    configStore.addNamespace(newNamespace)
                    newNamespace = ""
                }
            }
        }
    }

    // MARK: - Apps

    private var appsTab: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(configStore.savedApps) { entry in
                    HStack {
                        Text(entry.name)
                        scopeLabel(for: entry)
                        Spacer()
                        deleteButton {
                            configStore.savedApps.removeAll { $0.id == entry.id }
                            configStore.save()
                        }
                    }
                }
            }
            HStack {
                TextField("App", text: $newApp)
                Button("Add") {
                    guard !newApp.isEmpty else { return }
                    configStore.addApp(newApp)
                    newApp = ""
                }
            }
        }
    }

    // MARK: - Терминал

    private var terminalTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("{{command}} is replaced with the assembled utility command; the line runs as is via /bin/zsh -lc. “Launch command” runs it right away; “Prepare command” opens the terminal with the command typed in but not run (empty = “Prepare” is unavailable for this profile).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Active terminal", selection: $configStore.selectedTerminalProfileName) {
                ForEach(configStore.terminalProfiles) { profile in
                    Text(profile.name).tag(profile.name)
                }
            }
            .onChange(of: configStore.selectedTerminalProfileName) { _, _ in
                configStore.save()
            }

            List {
                ForEach($configStore.terminalProfiles) { $profile in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Name", text: renameBinding($profile.name))
                            TextField("Launch command", text: $profile.launchTemplate)
                                .font(.system(.body, design: .monospaced))
                            TextField("Prepare command (without running)", text: $profile.prepareTemplate)
                                .font(.system(.body, design: .monospaced))
                        }
                        deleteButton {
                            configStore.terminalProfiles.removeAll { $0.id == profile.id }
                            configStore.save()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .onChange(of: configStore.terminalProfiles) { _, _ in
                configStore.save()
            }

            HStack {
                TextField("New profile name", text: $newTerminalName)
                Button("Add") {
                    guard !newTerminalName.isEmpty else { return }
                    configStore.terminalProfiles.append(
                        TerminalProfile(
                            name: newTerminalName,
                            launchTemplate: "open -na \"\(newTerminalName)\" --args -e {{command}}",
                            prepareTemplate: "printf '%s' '{{command}}' | pbcopy && open -na \"\(newTerminalName)\""
                        )
                    )
                    configStore.save()
                    newTerminalName = ""
                }
            }
        }
    }

    /// Keeps the active-terminal selection (stored by name) pointing at the
    /// profile while it's being renamed.
    private func renameBinding(_ name: Binding<String>) -> Binding<String> {
        Binding(
            get: { name.wrappedValue },
            set: { newName in
                if configStore.selectedTerminalProfileName == name.wrappedValue {
                    configStore.selectedTerminalProfileName = newName
                }
                name.wrappedValue = newName
            }
        )
    }

    // MARK: - История

    private var historyTab: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Last \(ConfigStore.maxHistoryEntries) commands. Right-click an entry to run it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    configStore.clearHistory()
                }
                .disabled(configStore.history.isEmpty)
            }

            if let historyError {
                Text(historyError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if configStore.history.isEmpty {
                Text("Nothing here yet — commands will appear after you run them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            List {
                ForEach(configStore.history) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.commandString)
                            .font(.system(.body, design: .monospaced))
                        HStack(spacing: 4) {
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            if entry.wasPrepared {
                                Text("· prepared")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Run again") {
                            relaunch(entry, mode: .execute)
                        }
                        Button("Prepare again") {
                            relaunch(entry, mode: .prepare)
                        }
                    }
                }
            }
        }
    }

    private func relaunch(_ entry: HistoryEntry, mode: TerminalLaunchMode) {
        guard let profile = configStore.selectedTerminalProfile else {
            historyError = String(localized: "No terminal selected on the Terminal tab.")
            return
        }
        do {
            try TerminalLauncher.launch(commandString: entry.commandString, terminalProfile: profile, mode: mode)
            historyError = nil
        } catch {
            historyError = error.localizedDescription
        }
    }

    // MARK: - Общие

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItemManager.setEnabled(newValue)
                }

            Picker("Language", selection: $language) {
                Text("System").tag(AppLanguage.system)
                // Language names stay in their own language, as in macOS.
                Text(verbatim: "Русский").tag(AppLanguage.russian)
                Text(verbatim: "English").tag(AppLanguage.english)
            }
            .fixedSize()
            .onChange(of: language) { _, newValue in
                AppLanguage.set(newValue)
            }

            if language != AppLanguage.atLaunch {
                HStack {
                    Text("The language changes after KubeBar restarts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Restart now") {
                        AppLanguage.relaunch()
                    }
                }
            }
            Spacer()
        }
    }
}

/// Read-only summary row for one utility template: name and executable are
/// each explicitly labeled so they stay distinguishable even when they
/// happen to be the same word (e.g. a utility named "kubectl" that also
/// runs the "kubectl" executable). Editing happens in `UtilityEditorView`.
private struct UtilityRow: View {
    let utility: Utility
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Reorder")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Name:").font(.caption).foregroundStyle(.secondary)
                    Text(utility.name).font(.headline)
                }
                HStack(spacing: 4) {
                    Text("Executable:").font(.caption).foregroundStyle(.secondary)
                    Text(utility.executable)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(utility.commandTemplate)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.vertical, 4)
    }
}
