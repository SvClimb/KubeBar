import Foundation

enum KubeQueryService {
    static func fetchNamespaces(context: String, kubectlExecutable: String = "kubectl") throws -> [String] {
        let output = try ProcessRunner.run(
            executable: kubectlExecutable,
            arguments: ["--context", context, "get", "namespaces", "-o", "name"]
        )
        return parseNames(output)
    }

    /// Fetches workload (app) names — Deployments/StatefulSets/DaemonSets — rather
    /// than pod names, since pod names carry a ReplicaSet/random suffix that stern
    /// doesn't need: it matches its positional argument as a substring/regex
    /// against pod names, so the plain app name already matches every replica.
    static func fetchApps(context: String, namespace: String, kubectlExecutable: String = "kubectl") throws -> [String] {
        let output = try ProcessRunner.run(
            executable: kubectlExecutable,
            arguments: ["--context", context, "-n", namespace, "get", "deployments,statefulsets,daemonsets", "-o", "name"]
        )
        return parseNames(output)
    }

    private static func parseNames(_ output: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // kubectl prints "<kind>[.group]/<name>" (e.g. "deployment.apps/foo") — keep just the name.
            let name = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
            if seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }
}
