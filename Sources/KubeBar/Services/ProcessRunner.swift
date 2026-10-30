import Foundation

enum ProcessRunnerError: LocalizedError {
    case executableNotFound(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return String(localized: "\(name) was not found in PATH. Set the full path to the executable in settings.")
        case .processFailed(let message):
            return message.isEmpty ? String(localized: "The command failed.") : message
        }
    }
}

enum ProcessRunner {
    /// GUI apps launched via Finder or a login item get PATH from launchd,
    /// which is typically just "/usr/bin:/bin:/usr/sbin:/sbin" — missing
    /// Homebrew and /usr/local/bin even though a login shell's PATH (what
    /// the user sees in Terminal) includes them. Always check these too,
    /// on top of whatever PATH the process actually has.
    private static let fallbackSearchDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    /// The user's login-shell PATH, merged with the app's own PATH and the
    /// fallback dirs. Used both to resolve executables and as the PATH of
    /// every spawned process: kubeconfig `exec` credential plugins
    /// (gke-gcloud-auth-plugin, aws, kubelogin, tsh, …) are looked up by
    /// kubectl itself through PATH, so with launchd's bare PATH they're not
    /// found and every cloud cluster fails to authenticate.
    /// Computed once, lazily — the first caller is always off the main thread.
    static let searchPath: String = {
        let processPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var dirs: [String] = []
        for dir in (loginShellPath() + ":" + processPath).split(separator: ":").map(String.init) + fallbackSearchDirs
        where !dir.isEmpty && !dirs.contains(dir) {
            dirs.append(dir)
        }
        return dirs.joined(separator: ":")
    }()

    private static func loginShellPath() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "print -rn -- $PATH"]
        process.standardInput = FileHandle.nullDevice
        guard let output = try? collectOutput(of: process), output.status == 0 else { return "" }
        return String(data: output.stdout, encoding: .utf8) ?? ""
    }

    static func findExecutable(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for dir in searchPath.split(separator: ":") {
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
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        process.environment = environment
        // No terminal to answer interactive auth prompts — fail fast instead.
        process.standardInput = FileHandle.nullDevice

        let output: (status: Int32, stdout: Data, stderr: Data)
        do {
            output = try collectOutput(of: process)
        } catch {
            throw ProcessRunnerError.processFailed(error.localizedDescription)
        }

        if output.status != 0 {
            let message = String(data: output.stderr, encoding: .utf8) ?? ""
            throw ProcessRunnerError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return String(data: output.stdout, encoding: .utf8) ?? ""
    }

    /// Runs the process to completion, draining stdout and stderr while it
    /// runs. Reading only after `waitUntilExit()` deadlocks once a pipe's
    /// ~64 KB buffer fills (e.g. listing workloads of a large namespace):
    /// the child blocks on write and never exits.
    static func collectOutput(of process: Process) throws -> (status: Int32, stdout: Data, stderr: Data) {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        nonisolated(unsafe) var stderrData = Data()
        let stderrDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            stderrDone.signal()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        stderrDone.wait()
        process.waitUntilExit()

        return (process.terminationStatus, stdoutData, stderrData)
    }
}
