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

    /// All previous "prepare" template generations we've shipped, per
    /// built-in profile name — kept only so init() can detect and upgrade
    /// profiles that still have an old value untouched.
    private static let legacyPrepareTemplates: [String: [String]] = [
        "Ghostty": [
            "printf '%s' '{{command}}' | pbcopy && open -na Ghostty",
            "open -na Ghostty --args -e env ZDOTDIR={{zdotdir}} /bin/zsh -i"
        ],
        "Terminal.app": [
            "printf '%s' '{{command}}' | pbcopy && open -a Terminal",
            #"osascript -e 'tell application "Terminal" to do script "exec env ZDOTDIR={{zdotdir}} /bin/zsh -i"'"#
        ],
        "iTerm2": [
            #"osascript -e 'tell application "iTerm2" to tell current session of (create window with default profile) to write text "{{command}}" newline no'"#
        ]
    ]

    /// All previous "launch" template generations we've shipped, per
    /// built-in profile name — kept only so init() can detect and upgrade
    /// profiles untouched since.
    private static let legacyLaunchTemplates: [String: [String]] = [
        "Ghostty": [
            "open -na Ghostty --args -e {{command}}",
            "open -na Ghostty --args -e /bin/zsh -ic '{{command}}'"
        ],
        "iTerm2": [
            #"osascript -e 'tell application "iTerm2" to create window with default profile command "{{command}}"'"#
        ],
        "Terminal.app": [
            #"osascript -e 'tell application "Terminal" to do script "{{command}}"'"#
        ]
    ]

    /// Upgrades a previously-saved built-in profile (Ghostty/Terminal.app/
    /// iTerm2) whose launch/prepare template predates a feature (missing
    /// prepareTemplate) or still matches an old default we've since improved.
    private static func backfillPrepareTemplateIfNeeded(_ profile: TerminalProfile) -> TerminalProfile {
        guard let defaultMatch = defaultTerminalProfiles.first(where: { $0.name == profile.name }) else {
            return profile
        }
        var updated = profile

        let prepareIsMissing = profile.prepareTemplate.isEmpty
        let prepareIsLegacy = (legacyPrepareTemplates[profile.name] ?? []).contains(profile.prepareTemplate)
        if prepareIsMissing || prepareIsLegacy {
            updated.prepareTemplate = defaultMatch.prepareTemplate
        }

        if (legacyLaunchTemplates[profile.name] ?? []).contains(profile.launchTemplate) {
            updated.launchTemplate = defaultMatch.launchTemplate
        }

        return updated
    }

    private let fileURL: URL

    /// One-time migration from the app's old name ("SternLogger") so
    /// existing saved namespaces/apps/history survive the rename to KubeBar.
    private static func migrateFromLegacyAppNameIfNeeded(appSupport: URL, newFileURL: URL) {
        guard !FileManager.default.fileExists(atPath: newFileURL.path) else { return }
        let legacyFileURL = appSupport
            .appendingPathComponent("SternLogger", isDirectory: true)
            .appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else { return }
        try? FileManager.default.copyItem(at: legacyFileURL, to: newFileURL)
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("KubeBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")

        ConfigStore.migrateFromLegacyAppNameIfNeeded(appSupport: appSupport, newFileURL: fileURL)

        var needsResave = false

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PersistedConfig.self, from: data) {
            utilities = decoded.utilities
            savedNamespaces = decoded.savedNamespaces
            savedApps = decoded.savedApps
            let loadedProfiles = decoded.terminalProfiles ?? ConfigStore.defaultTerminalProfiles
            let backfilledProfiles = loadedProfiles.map(ConfigStore.backfillPrepareTemplateIfNeeded)
            terminalProfiles = backfilledProfiles
            needsResave = backfilledProfiles != loadedProfiles
            selectedTerminalProfileName = decoded.selectedTerminalProfileName ?? ConfigStore.defaultTerminalProfiles[0].name
            history = decoded.history ?? []
            lastSelection = decoded.lastSelection
        } else {
            utilities = ConfigStore.defaultUtilities
            savedNamespaces = []
            savedApps = []
            terminalProfiles = ConfigStore.defaultTerminalProfiles
            selectedTerminalProfileName = ConfigStore.defaultTerminalProfiles[0].name
            history = []
            lastSelection = LaunchSelection()
        }

        if needsResave {
            save()
        }
    }

    func addNamespace(_ name: String) {
        guard !savedNamespaces.contains(where: { $0.name == name }) else { return }
        savedNamespaces.append(NamedEntry(name: name))
        save()
    }

    func addApp(_ name: String) {
        guard !savedApps.contains(where: { $0.name == name }) else { return }
        savedApps.append(NamedEntry(name: name))
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
