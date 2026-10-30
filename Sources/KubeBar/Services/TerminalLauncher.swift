import Foundation

enum SelectionField {
    case utility, context, namespace, app
}

enum TerminalLauncherError: LocalizedError {
    case missingSelection(SelectionField)
    case launchFailed(String)
    case noTemplateConfigured(String)

    var errorDescription: String? {
        switch self {
        case .missingSelection(.utility):
            return String(localized: "Select a utility.")
        case .missingSelection(.context):
            return String(localized: "Select a context.")
        case .missingSelection(.namespace):
            return String(localized: "Select a namespace.")
        case .missingSelection(.app):
            return String(localized: "Select an app.")
        case .launchFailed(let message):
            return String(localized: "Couldn't open the terminal: \(message)")
        case .noTemplateConfigured(let profileName):
            return String(localized: "Terminal “\(profileName)” has no prepare template configured (Terminal tab in settings).")
        }
    }
}

enum TerminalLaunchMode {
    /// Runs the command immediately.
    case execute
    /// Opens the terminal with the command staged but not executed.
    case prepare
}

enum TerminalLauncher {
    /// Expands the utility's command template into the final command string,
    /// e.g. "stern --context prod -n backend my-app".
    static func buildCommand(selection: LaunchSelection, utilities: [Utility]) throws -> (utility: Utility, commandString: String) {
        guard let utilityName = selection.utilityName,
              let utility = utilities.first(where: { $0.name == utilityName }) else {
            throw TerminalLauncherError.missingSelection(.utility)
        }
        guard let context = selection.contextName, !context.isEmpty else {
            throw TerminalLauncherError.missingSelection(.context)
        }
        guard let namespace = selection.namespaceName, !namespace.isEmpty else {
            throw TerminalLauncherError.missingSelection(.namespace)
        }
        if utility.commandTemplate.contains("{app}") {
            guard let app = selection.appName, !app.isEmpty else {
                throw TerminalLauncherError.missingSelection(.app)
            }
        }

        let command = render(utility, context: context, namespace: namespace, app: selection.appName ?? "")
        return (utility, command)
    }

    /// Best-effort preview of the command the current selection would
    /// produce. Unlike `buildCommand`, this never throws — any field not
    /// chosen yet is rendered as a `‹placeholder›` so the user can see the
    /// command's shape before finishing their selection.
    static func previewCommand(selection: LaunchSelection, utilities: [Utility]) -> String? {
        guard let utilityName = selection.utilityName,
              let utility = utilities.first(where: { $0.name == utilityName }) else {
            return nil
        }

        return render(
            utility,
            context: nonEmpty(selection.contextName) ?? String(localized: "‹context›"),
            namespace: nonEmpty(selection.namespaceName) ?? "‹namespace›",
            app: nonEmpty(selection.appName) ?? "‹app›"
        )
    }

    /// Substitutes the placeholders and collapses runs of spaces left by
    /// empty values (e.g. no {app}).
    private static func render(_ utility: Utility, context: String, namespace: String, app: String) -> String {
        utility.commandTemplate
            .replacingOccurrences(of: "{executable}", with: utility.executable)
            .replacingOccurrences(of: "{context}", with: context)
            .replacingOccurrences(of: "{namespace}", with: namespace)
            .replacingOccurrences(of: "{app}", with: app)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func launch(commandString: String, terminalProfile: TerminalProfile, mode: TerminalLaunchMode = .execute) throws {
        let template = mode == .execute ? terminalProfile.launchTemplate : terminalProfile.prepareTemplate
        guard !template.isEmpty else {
            throw TerminalLauncherError.noTemplateConfigured(terminalProfile.name)
        }

        var shellLine = template
        if shellLine.contains("{{zdotdir}}") {
            let zdotdir = try makeZdotdirStaging(commandString: commandString)
            shellLine = shellLine.replacingOccurrences(of: "{{zdotdir}}", with: zdotdir.path)
        }
        // All built-in profile templates embed {{command}} inside an
        // AppleScript double-quoted string (`do script "{{command}}"` etc.),
        // which itself sits inside a single-quoted `-e '...'` osascript
        // argument for zsh. A command containing a literal `"` (e.g. stern's
        // `--template='... "@timestamp" ...'`) breaks the AppleScript string,
        // and a literal `'` (the template flag's own quoting) breaks the zsh
        // one, spilling the Go template's `{`/`}`/`[`/`]` into zsh as
        // unquoted glob syntax. Escape for the inner AppleScript layer first,
        // then the outer zsh layer.
        let escapedCommand = shellSingleQuoteEscape(appleScriptStringEscape(commandString))
        shellLine = shellLine.replacingOccurrences(of: "{{command}}", with: escapedCommand)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", shellLine]

        let output: (status: Int32, stdout: Data, stderr: Data)
        do {
            output = try ProcessRunner.collectOutput(of: process)
        } catch {
            throw TerminalLauncherError.launchFailed(error.localizedDescription)
        }

        if output.status != 0 {
            let message = String(data: output.stderr, encoding: .utf8) ?? ""
            throw TerminalLauncherError.launchFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Escapes a string for safe embedding inside a single-quoted shell
    /// argument: close the quote, insert an escaped literal quote, reopen.
    private static func shellSingleQuoteEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    /// Escapes a string for safe embedding inside an AppleScript
    /// double-quoted string literal.
    private static func appleScriptStringEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Stages a temp ZDOTDIR whose .zshrc sources the user's real ~/.zshenv and
    /// .zshrc, then uses zsh's `print -z` to pre-fill the next interactive
    /// prompt with commandString without executing it. ZDOTDIR is unset
    /// first so it doesn't leak into the session: otherwise every nested
    /// `zsh` re-runs this file (re-staging the command), and rc files that
    /// write to `${ZDOTDIR:-$HOME}` (e.g. compinit's .zcompdump) write into
    /// the temp dir. Users who set their own ZDOTDIR in ~/.zshenv get their
    /// .zshrc from there.
    private static func makeZdotdirStaging(commandString: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KubeBar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let escapedCommand = shellSingleQuoteEscape(commandString)
        let rcContents = """
        unset ZDOTDIR
        [ -f "$HOME/.zshenv" ] && source "$HOME/.zshenv"
        [ -f "${ZDOTDIR:-$HOME}/.zshrc" ] && source "${ZDOTDIR:-$HOME}/.zshrc"
        clear
        print -z '\(escapedCommand)'
        """
        try rcContents.write(
            to: dir.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )
        return dir
    }
}
