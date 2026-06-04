import Foundation

public enum ServiceGrouper {
    public static func group(
        processes: [ManagedProcess],
        configuration: ScanConfiguration,
        protectedPIDs: Set<Int32>,
        currentUser: String = NSUserName()
    ) -> [ServiceGroup] {
        let relevant = processes.filter {
            ProcessClassifier.isRelevant(
                $0,
                configuration: configuration,
                protectedPIDs: protectedPIDs,
                currentUser: currentUser
            )
        }

        var buckets: [String: [ManagedProcess]] = [:]
        for process in relevant {
            buckets[groupKey(for: process, configuration: configuration), default: []].append(process)
        }

        return buckets.map { key, members in
            buildGroup(
                key: key,
                processes: members,
                allPIDs: Set(processes.map(\.pid)),
                configuration: configuration,
                protectedPIDs: protectedPIDs,
                currentUser: currentUser
            )
        }
        .sorted { lhs, rhs in
            if lhs.risk != rhs.risk { return lhs.risk < rhs.risk }
            if lhs.ownership != rhs.ownership { return lhs.ownership.displayName < rhs.ownership.displayName }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static func groupKey(
        for process: ManagedProcess,
        configuration: ScanConfiguration
    ) -> String {
        if let hint = ThreadHintExtractor.extract(from: process), let threadId = hint.threadId {
            return "thread:\(threadId)"
        }

        if ProcessClassifier.isWhitelisted(process, configuration: configuration) {
            return "protected:\(process.pid)"
        }

        if ProcessClassifier.isCodexMain(process) || ProcessClassifier.isOldCodexHelper(process) {
            return "codex-process:\(process.pid)"
        }

        if let cwd = process.cwd, !cwd.isEmpty {
            return "cwd:\(cwd)"
        }

        if ProcessClassifier.isCodexInternal(process) {
            return "codex-internal:\(process.ppid)"
        }

        if !process.listeningPorts.isEmpty {
            return "ports:\(process.listeningPorts.map(String.init).joined(separator: ","))"
        }

        return "process:\(process.pid)"
    }

    private static func buildGroup(
        key: String,
        processes: [ManagedProcess],
        allPIDs: Set<Int32>,
        configuration: ScanConfiguration,
        protectedPIDs: Set<Int32>,
        currentUser: String
    ) -> ServiceGroup {
        let threadHint = processes.compactMap(ThreadHintExtractor.extract(from:)).max {
            $0.confidence < $1.confidence
        }
        let cwd = threadHint?.cwd ?? processes.compactMap(\.cwd).first
        let ports = processes.flatMap(\.listeningPorts)
        let ownership = ownershipFor(processes: processes, cwd: cwd, threadHint: threadHint, configuration: configuration)
        let analysis = analyzeRisk(
            processes: processes,
            allPIDs: allPIDs,
            configuration: configuration,
            protectedPIDs: protectedPIDs,
            currentUser: currentUser
        )

        return ServiceGroup(
            id: key,
            title: title(for: ownership, cwd: cwd, threadHint: threadHint, processes: processes),
            ownership: analysis.risk == .protected ? .protected : ownership,
            cwd: cwd,
            threadHint: threadHint,
            processes: processes,
            listeningPorts: ports,
            risk: analysis.risk,
            confidence: analysis.confidence,
            evidence: analysis.evidence,
            recommendedAction: analysis.recommendation
        )
    }

    private static func ownershipFor(
        processes: [ManagedProcess],
        cwd: String?,
        threadHint: ThreadHint?,
        configuration: ScanConfiguration
    ) -> ServiceOwnership {
        if threadHint?.threadId != nil {
            return .codexThread
        }
        if processes.contains(where: ProcessClassifier.isCodexInternal) {
            return .codexInternal
        }
        if processes.contains(where: { ProcessClassifier.isDevelopmentCommand($0, configuration: configuration) }) {
            return .developmentService
        }
        if processes.contains(where: { ProcessClassifier.hasDevelopmentPort($0, configuration: configuration) }) {
            return .developmentService
        }
        if processes.contains(where: { ProcessClassifier.belongsToCodexWorkspace($0) }) || cwd?.contains("/Documents/Codex/") == true {
            return .codexWorkspace
        }
        if processes.contains(where: \.isListening) {
            return .listeningPort
        }
        return .unownedDevelopment
    }

    private static func analyzeRisk(
        processes: [ManagedProcess],
        allPIDs: Set<Int32>,
        configuration: ScanConfiguration,
        protectedPIDs: Set<Int32>,
        currentUser: String
    ) -> (
        risk: ServiceRisk,
        confidence: Double,
        evidence: [String],
        recommendation: ActionRecommendation
    ) {
        var evidence: [String] = []

        if processes.contains(where: { protectedPIDs.contains($0.pid) }) {
            evidence.append("当前 App 或显式保护 PID")
            return protected(evidence: evidence)
        }

        if processes.contains(where: { $0.user != currentUser }) {
            evidence.append("非当前用户进程")
            return protected(evidence: evidence)
        }

        if processes.contains(where: ProcessClassifier.isCodexMain) {
            evidence.append("Codex 主进程")
            return protected(evidence: evidence)
        }

        if processes.contains(where: { ProcessClassifier.isWhitelisted($0, configuration: configuration) }) {
            evidence.append("命中白名单")
            return protected(evidence: evidence)
        }

        let hasOldCodexHelper = processes.contains(where: ProcessClassifier.isOldCodexHelper)
        if hasOldCodexHelper {
            evidence.append("旧版本 Codex crashpad/helper 已脱离主进程")
            return suggested(reason: "旧 Codex helper 已脱离主进程，可优先关闭。", evidence: evidence, confidence: 0.92)
        }

        let hasMissingParentCodexInternal = processes.contains {
            ProcessClassifier.isCodexInternal($0) && $0.ppid > 1 && !allPIDs.contains($0.ppid)
        }
        if hasMissingParentCodexInternal {
            evidence.append("Codex 支撑进程父进程不存在")
            return suggested(reason: "Codex 支撑进程已无活动父会话。", evidence: evidence, confidence: 0.88)
        }

        let orphaned = processes.allSatisfy { $0.ppid <= 1 || !allPIDs.contains($0.ppid) }
        let oldEnough = processes.contains { ($0.elapsedSeconds ?? 0) >= 30 * 60 }
        let codexWorkspace = processes.contains(where: ProcessClassifier.belongsToCodexWorkspace)
        let devServer = processes.contains {
            ProcessClassifier.isDevelopmentCommand($0, configuration: configuration)
                || ProcessClassifier.hasDevelopmentPort($0, configuration: configuration)
        }

        if orphaned && oldEnough && codexWorkspace && devServer {
            evidence.append("父进程不存在或已脱离")
            evidence.append("运行超过 30 分钟")
            evidence.append("位于 Codex 工作区并监听开发端口")
            return suggested(reason: "Codex 工作区里的开发服务已长时间孤立运行。", evidence: evidence, confidence: 0.9)
        }

        if devServer {
            evidence.append("命中开发服务命令或端口")
        }
        if !processes.flatMap(\.listeningPorts).isEmpty {
            evidence.append("存在监听端口")
        }
        if codexWorkspace {
            evidence.append("位于 Codex 工作区")
        }
        if processes.contains(where: ProcessClassifier.isCodexInternal) {
            evidence.append("Codex 支撑进程仍有活动父进程")
        }

        let reason = evidence.isEmpty ? "没有足够证据自动清理。" : "需要人工确认后关闭。"
        return (
            .needsReview,
            evidence.isEmpty ? 0.35 : 0.65,
            evidence,
            ActionRecommendation(title: "手动选择", reason: reason, isSelectedByDefault: false)
        )
    }

    private static func protected(evidence: [String]) -> (
        risk: ServiceRisk,
        confidence: Double,
        evidence: [String],
        recommendation: ActionRecommendation
    ) {
        (
            .protected,
            1.0,
            evidence,
            ActionRecommendation(title: "受保护", reason: evidence.joined(separator: "，"), isSelectedByDefault: false)
        )
    }

    private static func suggested(
        reason: String,
        evidence: [String],
        confidence: Double
    ) -> (
        risk: ServiceRisk,
        confidence: Double,
        evidence: [String],
        recommendation: ActionRecommendation
    ) {
        (
            .suggestedCleanup,
            confidence,
            evidence,
            ActionRecommendation(title: "建议关闭", reason: reason, isSelectedByDefault: true)
        )
    }

    private static func title(
        for ownership: ServiceOwnership,
        cwd: String?,
        threadHint: ThreadHint?,
        processes: [ManagedProcess]
    ) -> String {
        DisplayNameResolver.title(
            for: ownership,
            cwd: cwd,
            threadHint: threadHint,
            processes: processes
        )
    }
}
