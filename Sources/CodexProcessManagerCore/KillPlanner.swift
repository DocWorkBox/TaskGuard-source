import Foundation

public enum KillPlanner {
    public static func buildSuggestedPlan(from groups: [ServiceGroup]) -> KillPlan {
        let targets = groups
            .filter { $0.risk == .suggestedCleanup && $0.recommendedAction.isSelectedByDefault }
            .flatMap { group in
                group.processes.map {
                    KillTarget(
                        pid: $0.pid,
                        commandLine: $0.commandLine,
                        reason: group.recommendedAction.reason
                    )
                }
            }

        return buildPlan(targets: targets)
    }

    public static func buildPlan(from groups: [ServiceGroup]) -> KillPlan {
        let targets = groups
            .filter { $0.risk != .protected }
            .flatMap { group in
                group.processes.map {
                    KillTarget(
                        pid: $0.pid,
                        commandLine: $0.commandLine,
                        reason: group.recommendedAction.reason
                    )
                }
            }

        return buildPlan(targets: targets)
    }

    private static func buildPlan(targets: [KillTarget]) -> KillPlan {
        var seen: Set<Int32> = []
        let uniqueTargets = targets.filter { seen.insert($0.pid).inserted }.sorted { $0.pid < $1.pid }

        let warnings = uniqueTargets.isEmpty
            ? ["没有可关闭的建议项。"]
            : ["将先发送 SIGTERM；未退出的进程需要再次确认后才能强制关闭。"]

        return KillPlan(
            targets: uniqueTargets,
            signalSequence: [.term],
            warnings: warnings,
            requiresConfirmation: true
        )
    }
}
