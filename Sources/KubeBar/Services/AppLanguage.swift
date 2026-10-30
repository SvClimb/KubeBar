import AppKit

/// UI language override, stored as `AppleLanguages` in the app's own
/// defaults domain — the same key System Settings → Language & Region →
/// Applications writes, so the two stay in sync. Bundle lookups read it
/// only at launch, hence the restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }

    /// Read from the app's persistent domain only: `UserDefaults.standard`
    /// would fall through to the global domain and report the system list.
    static var current: AppLanguage {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: bundleID)?["AppleLanguages"] as? [String],
              let first = languages.first else {
            return .system
        }
        return first.hasPrefix("ru") ? .russian : first.hasPrefix("en") ? .english : .system
    }

    /// The language the running process was started with.
    static let atLaunch = current

    static func set(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Starts a fresh copy of the app once this one has quit.
    @MainActor
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
