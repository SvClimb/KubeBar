import Foundation

enum TerminalLauncherError: LocalizedError {
    case missingSelection(String)
    case launchFailed(String)
    case noTemplateConfigured(String)

    var errorDescription: String? {
        switch self {
        case .missingSelection(let field):
            return "\(field) не выбран(а)."
        case .launchFailed(let message):
            return "Не удалось открыть терминал: \(message)"
        case .noTemplateConfigured(let profileName):
            return "Для терминала «\(profileName)» не настроен шаблон подготовки команды (вкладка «Терминал» в настройках)."
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
            throw TerminalLauncherError.missingSelection("Утилита")
        }
        guard let context = selection.contextName, !context.isEmpty else {
            throw TerminalLauncherError.missingSelection("Контекст")
        }
        guard let namespace = selection.namespaceName, !namespace.isEmpty else {
            throw TerminalLauncherError.missingSelection("Namespace")
        }
        if utility.commandTemplate.contains("{app}") {
            guard let app = selection.appName, !app.isEmpty else {
                throw TerminalLauncherError.missingSelection("App")
            }
        }

        var command = utility.commandTemplate
        command = command.replacingOccurrences(of: "{executable}", with: utility.executable)
        command = command.replacingOccurrences(of: "{context}", with: context)
        command = command.replacingOccurrences(of: "{namespace}", with: namespace)
        command = command.replacingOccurrences(of: "{app}", with: selection.appName ?? "")

        let normalized = command
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        return (utility, normalized)
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
        shellLine = shellLine.replacingOccurrences(of: "{{command}}", with: commandString)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", shellLine]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw TerminalLauncherError.launchFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw TerminalLauncherError.launchFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Stages a temp ZDOTDIR whose .zshrc sources the user's real ~/.zshenv and
    /// ~/.zshrc, then uses zsh's `print -z` to pre-fill the next interactive
    /// prompt with commandString without executing it.
    private static func makeZdotdirStaging(commandString: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KubeBar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let escapedCommand = commandString.replacingOccurrences(of: "'", with: "'\\''")
        let rcContents = """
        [ -f "$HOME/.zshenv" ] && source "$HOME/.zshenv"
        [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"
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
