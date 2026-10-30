import Foundation

@MainActor
final class ConfigStore: ObservableObject {
    @Published var utilities: [Utility]
    @Published var savedNamespaces: [NamedEntry]
    @Published var savedApps: [NamedEntry]
    @Published var terminalProfiles: [TerminalProfile]
    @Published var selectedTerminalProfileName: String
    @Published var history: [HistoryEntry]
    @Published var lastSelection: LaunchSelection

    private struct PersistedConfig: Codable {
        var utilities: [Utility]
        var savedNamespaces: [NamedEntry]
        var savedApps: [NamedEntry]
        var terminalProfiles: [TerminalProfile]?
        var selectedTerminalProfileName: String?
        var history: [HistoryEntry]?
        var lastSelection: LaunchSelection
    }

    static let maxHistoryEntries = 10

    static let defaultUtilities: [Utility] = [
        Utility(name: "kubectl", executable: "kubectl", commandTemplate: "{executable} --context {context} -n {namespace}"),
        Utility(name: "stern", executable: "stern", commandTemplate: "{executable} --context {context} -n {namespace} {app}"),
        Utility(name: "kwatch", executable: "kwatch", commandTemplate: "{executable} --context {context} -n {namespace}")
    ]

    static let defaultTerminalProfiles: [TerminalProfile] = [
        TerminalProfile(
            name: "Ghostty",
            // Uses Ghostty's native AppleScript API (new window + input text
            // + send key) instead of `open -na Ghostty --args -e ...`: the
            // `-n` flag to `open` forces a brand new Ghostty *process*
            // instance every launch (visible as a second running app), while
            // AppleScript always talks to the single already-running
            // instance. As a bonus, typing into the window's default shell
            // means aliases (e.g. `k` for kubectl) just work, no /bin/zsh -ic
            // wrapping needed.
            launchTemplate: #"osascript -e 'tell application "Ghostty"' -e 'set t to focused terminal of selected tab of (new window)' -e 'input text "{{command}}" to t' -e 'send key "enter" to t' -e 'end tell'"#,
            prepareTemplate: #"osascript -e 'tell application "Ghostty"' -e 'set t to focused terminal of selected tab of (new window)' -e 'input text "{{command}}" to t' -e 'end tell'"#
        ),
        TerminalProfile(
            // When Terminal.app isn't already running, sending it a plain
            // `do script` Apple Event makes macOS launch it — but Terminal's
            // own launch sequence ALSO opens its configured default window,
            // independent of our do-script window, so a cold start produces
            // two windows. Fix: if it wasn't running, wait for that default
            // window to appear and reuse it via `do script ... in window 1`
            // instead of creating an extra one. If it was already running,
            // plain `do script` is correct (a fresh new window, existing
            // windows/tabs left untouched).
            name: "Terminal.app",
            launchTemplate: #"osascript -e 'tell application "Terminal"' -e 'set wasRunning to running' -e 'if wasRunning is false then' -e 'activate' -e 'delay 1' -e 'end if' -e 'if wasRunning is false then' -e 'do script "{{command}}" in window 1' -e 'else' -e 'do script "{{command}}"' -e 'end if' -e 'end tell'"#,
            prepareTemplate: #"osascript -e 'tell application "Terminal"' -e 'set wasRunning to running' -e 'if wasRunning is false then' -e 'activate' -e 'delay 1' -e 'end if' -e 'if wasRunning is false then' -e 'do script "exec env ZDOTDIR={{zdotdir}} /bin/zsh -i" in window 1' -e 'else' -e 'do script "exec env ZDOTDIR={{zdotdir}} /bin/zsh -i"' -e 'end if' -e 'end tell'"#
        ),
        TerminalProfile(
            // iTerm2's actual AppleScript application name is "iTerm", not
            // "iTerm2" (that's just the product/marketing name) — "iTerm2"
            // fails to resolve, so AppleScript falls back to a generic
            // dictionary and can't parse our custom command syntax at all.
            name: "iTerm2",
            launchTemplate: #"osascript -e 'tell application "iTerm" to create window with default profile command "{{command}}"'"#,
            prepareTemplate: #"osascript -e 'tell application "iTerm" to tell current session of (create window with default profile) to write text "{{command}}" newline no'"#
        )
    ]

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("KubeBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PersistedConfig.self, from: data) {
            utilities = decoded.utilities
            savedNamespaces = decoded.savedNamespaces
            savedApps = decoded.savedApps
            terminalProfiles = decoded.terminalProfiles ?? ConfigStore.defaultTerminalProfiles
            selectedTerminalProfileName = decoded.selectedTerminalProfileName ?? ConfigStore.defaultTerminalProfiles[0].name
            history = decoded.history ?? []
            lastSelection = decoded.lastSelection
        } else {
            // An unreadable config would be overwritten by the next save();
            // keep a copy so the user's templates aren't silently lost.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let backupURL = dir.appendingPathComponent("config.broken-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }
            utilities = ConfigStore.defaultUtilities
            savedNamespaces = []
            savedApps = []
            terminalProfiles = ConfigStore.defaultTerminalProfiles
            selectedTerminalProfileName = ConfigStore.defaultTerminalProfiles[0].name
            history = []
            lastSelection = LaunchSelection()
        }
    }

    func addNamespace(_ name: String) {
        guard !savedNamespaces.contains(where: { $0.name == name && $0.contextName == nil }) else { return }
        savedNamespaces.append(NamedEntry(name: name))
        save()
    }

    /// Replaces the auto-discovered namespaces of one context with a freshly
    /// fetched list, so namespaces of different clusters don't pile up in
    /// one picker. Unscoped entries with the same names (manually added, or
    /// fetched by versions that didn't scope namespaces) are folded into the
    /// scoped ones.
    func syncNamespaces(_ names: [String], contextName: String) {
        let fetched = Set(names)
        savedNamespaces.removeAll { $0.contextName == contextName || ($0.contextName == nil && fetched.contains($0.name)) }
        savedNamespaces += names.map { NamedEntry(name: $0, contextName: contextName) }
        save()
    }

    func addApp(_ name: String) {
        guard !savedApps.contains(where: { $0.name == name }) else { return }
        savedApps.append(NamedEntry(name: name))
        save()
    }

    /// Replaces the auto-discovered apps for one context+namespace with a
    /// freshly fetched list, instead of appending to it — otherwise apps
    /// from every namespace ever browsed pile up in the same picker.
    /// Manually added (unscoped) apps are left untouched.
    func syncApps(_ names: [String], contextName: String, namespaceName: String) {
        savedApps.removeAll { $0.contextName == contextName && $0.namespaceName == namespaceName }
        for name in names {
            savedApps.append(NamedEntry(name: name, contextName: contextName, namespaceName: namespaceName))
        }
        save()
    }

    func addHistoryEntry(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > ConfigStore.maxHistoryEntries {
            history = Array(history.prefix(ConfigStore.maxHistoryEntries))
        }
        save()
    }

    func clearHistory() {
        history = []
        save()
    }

    var selectedTerminalProfile: TerminalProfile? {
        terminalProfiles.first { $0.name == selectedTerminalProfileName }
    }

    func save() {
        let persisted = PersistedConfig(
            utilities: utilities,
            savedNamespaces: savedNamespaces,
            savedApps: savedApps,
            terminalProfiles: terminalProfiles,
            selectedTerminalProfileName: selectedTerminalProfileName,
            history: history,
            lastSelection: lastSelection
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
