import Foundation

enum ProcessRunnerError: LocalizedError {
    case executableNotFound(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "\(name) не найден в PATH. Укажите путь к исполняемому файлу в настройках."
        case .processFailed(let message):
            return message.isEmpty ? "Команда завершилась с ошибкой." : message
        }
    }
}

enum ProcessRunner {
    static func findExecutable(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    @discardableResult
    static func run(executable: String, arguments: [String]) throws -> String {
        guard let resolvedPath = findExecutable(executable) else {
            throw ProcessRunnerError.executableNotFound(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let message = String(data: stderrData, encoding: .utf8) ?? ""
            throw ProcessRunnerError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
}
