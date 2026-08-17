import Foundation

enum KubeconfigService {
    static func fetchContexts(kubectlExecutable: String = "kubectl") throws -> [KubeContext] {
        let output = try ProcessRunner.run(
            executable: kubectlExecutable,
            arguments: ["config", "get-contexts", "-o", "name"]
        )
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { KubeContext(name: $0) }
    }
}
