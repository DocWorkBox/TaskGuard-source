import Foundation

public struct ManagedProcess: Identifiable, Hashable {
    public var id: Int32 { pid }

    public let pid: Int32
    public let ppid: Int32
    public let user: String
    public let state: String
    public let elapsed: String
    public let cpuPercent: Double
    public let memoryPercent: Double
    public let commandLine: String
    public var cwd: String?
    public var listeningPorts: [Int]

    public init(
        pid: Int32,
        ppid: Int32,
        user: String,
        state: String,
        elapsed: String,
        cpuPercent: Double,
        memoryPercent: Double,
        commandLine: String,
        cwd: String?,
        listeningPorts: [Int]
    ) {
        self.pid = pid
        self.ppid = ppid
        self.user = user
        self.state = state
        self.elapsed = elapsed
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.commandLine = commandLine
        self.cwd = cwd
        self.listeningPorts = listeningPorts.sorted()
    }

    public var executableName: String {
        let firstToken = commandLine.split(separator: " ", maxSplits: 1).first.map(String.init) ?? commandLine
        if firstToken.hasPrefix("/") {
            return URL(fileURLWithPath: firstToken).lastPathComponent
        }
        return firstToken
    }

    public var commandSummary: String {
        let maxLength = 96
        guard commandLine.count > maxLength else { return commandLine }
        return String(commandLine.prefix(maxLength - 1)) + "…"
    }

    public var isListening: Bool {
        !listeningPorts.isEmpty
    }

    public var elapsedSeconds: Int? {
        ElapsedTimeParser.seconds(from: elapsed)
    }
}

public enum ThreadHintSource: String, CaseIterable, Hashable {
    case codexTurnPayload
    case commandLine
    case workingDirectory

    public var displayName: String {
        switch self {
        case .codexTurnPayload: return "Codex turn payload"
        case .commandLine: return "command line"
        case .workingDirectory: return "working directory"
        }
    }
}

public struct ThreadHint: Hashable {
    public let threadId: String?
    public let turnId: String?
    public let displayTitle: String?
    public let cwd: String?
    public let source: ThreadHintSource
    public let confidence: Double

    public init(
        threadId: String?,
        turnId: String?,
        displayTitle: String?,
        cwd: String?,
        source: ThreadHintSource,
        confidence: Double
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.displayTitle = displayTitle
        self.cwd = cwd
        self.source = source
        self.confidence = confidence
    }
}

public enum ServiceOwnership: String, CaseIterable, Hashable, Identifiable {
    case codexThread
    case codexWorkspace
    case codexInternal
    case developmentService
    case listeningPort
    case unownedDevelopment
    case protected

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codexThread: return "Codex 线程"
        case .codexWorkspace: return "Codex 工作区"
        case .codexInternal: return "Codex 支撑进程"
        case .developmentService: return "开发服务"
        case .listeningPort: return "监听端口"
        case .unownedDevelopment: return "未归属开发服务"
        case .protected: return "受保护"
        }
    }
}

public enum ServiceRisk: String, CaseIterable, Hashable, Comparable {
    case suggestedCleanup
    case needsReview
    case protected

    public var displayName: String {
        switch self {
        case .suggestedCleanup: return "建议清理"
        case .needsReview: return "需确认"
        case .protected: return "受保护"
        }
    }

    public static func < (lhs: ServiceRisk, rhs: ServiceRisk) -> Bool {
        let order: [ServiceRisk] = [.suggestedCleanup, .needsReview, .protected]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public struct ActionRecommendation: Hashable {
    public let title: String
    public let reason: String
    public let isSelectedByDefault: Bool

    public init(title: String, reason: String, isSelectedByDefault: Bool) {
        self.title = title
        self.reason = reason
        self.isSelectedByDefault = isSelectedByDefault
    }
}

public struct ServiceGroup: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let ownership: ServiceOwnership
    public let cwd: String?
    public let threadHint: ThreadHint?
    public let processes: [ManagedProcess]
    public let listeningPorts: [Int]
    public let risk: ServiceRisk
    public let confidence: Double
    public let evidence: [String]
    public let recommendedAction: ActionRecommendation

    public init(
        id: String,
        title: String,
        ownership: ServiceOwnership,
        cwd: String?,
        threadHint: ThreadHint?,
        processes: [ManagedProcess],
        listeningPorts: [Int],
        risk: ServiceRisk,
        confidence: Double,
        evidence: [String],
        recommendedAction: ActionRecommendation
    ) {
        self.id = id
        self.title = title
        self.ownership = ownership
        self.cwd = cwd
        self.threadHint = threadHint
        self.processes = processes.sorted { $0.pid < $1.pid }
        self.listeningPorts = Array(Set(listeningPorts)).sorted()
        self.risk = risk
        self.confidence = confidence
        self.evidence = evidence
        self.recommendedAction = recommendedAction
    }

    public var processCount: Int {
        processes.count
    }

    public var primaryProcess: ManagedProcess? {
        processes.first
    }

    public var totalCPU: Double {
        processes.reduce(0) { $0 + $1.cpuPercent }
    }

    public var totalMemory: Double {
        processes.reduce(0) { $0 + $1.memoryPercent }
    }

    public var longestElapsedSeconds: Int {
        processes.compactMap(\.elapsedSeconds).max() ?? 0
    }
}

public enum KillSignal: String, Hashable {
    case term = "SIGTERM"
    case kill = "SIGKILL"
}

public struct KillTarget: Identifiable, Hashable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let commandLine: String
    public let reason: String

    public init(pid: Int32, commandLine: String, reason: String) {
        self.pid = pid
        self.commandLine = commandLine
        self.reason = reason
    }
}

public struct KillPlan: Hashable {
    public let targets: [KillTarget]
    public let signalSequence: [KillSignal]
    public let warnings: [String]
    public let requiresConfirmation: Bool

    public init(
        targets: [KillTarget],
        signalSequence: [KillSignal],
        warnings: [String],
        requiresConfirmation: Bool
    ) {
        self.targets = targets
        self.signalSequence = signalSequence
        self.warnings = warnings
        self.requiresConfirmation = requiresConfirmation
    }

    public var isEmpty: Bool {
        targets.isEmpty
    }
}

public struct ScanConfiguration: Equatable {
    public var scanIntervalSeconds: Double
    public var devPortRange: ClosedRange<Int>
    public var devCommandKeywords: [String]
    public var whitelistPatterns: [String]
    public var terminateWaitSeconds: Double
    public var showsCodexInternals: Bool

    public init(
        scanIntervalSeconds: Double,
        devPortRange: ClosedRange<Int>,
        devCommandKeywords: [String],
        whitelistPatterns: [String],
        terminateWaitSeconds: Double,
        showsCodexInternals: Bool
    ) {
        self.scanIntervalSeconds = scanIntervalSeconds
        self.devPortRange = devPortRange
        self.devCommandKeywords = devCommandKeywords
        self.whitelistPatterns = whitelistPatterns
        self.terminateWaitSeconds = terminateWaitSeconds
        self.showsCodexInternals = showsCodexInternals
    }

    public static var `default`: ScanConfiguration {
        ScanConfiguration(
            scanIntervalSeconds: 5,
            devPortRange: 3000...9000,
            devCommandKeywords: [
                "npm run dev",
                "pnpm dev",
                "yarn dev",
                "vite",
                "next dev",
                "webpack",
                "tsx",
                "ts-node",
                "python3 -m http.server",
                "python -m http.server"
            ],
            whitelistPatterns: [],
            terminateWaitSeconds: 4,
            showsCodexInternals: true
        )
    }
}

public struct ProcessSnapshot: Hashable {
    public let scannedAt: Date
    public let groups: [ServiceGroup]
    public let summary: ProcessSummary

    public init(scannedAt: Date, groups: [ServiceGroup]) {
        self.scannedAt = scannedAt
        self.groups = groups
        self.summary = ProcessSummary(groups: groups)
    }

    public static var empty: ProcessSnapshot {
        ProcessSnapshot(scannedAt: Date(), groups: [])
    }
}

public struct ProcessSummary: Hashable {
    public let serviceCount: Int
    public let suggestedCleanupCount: Int
    public let protectedCount: Int
    public let highCPUCount: Int
    public let listeningPortCount: Int

    public init(groups: [ServiceGroup]) {
        serviceCount = groups.count
        suggestedCleanupCount = groups.filter { $0.risk == .suggestedCleanup }.count
        protectedCount = groups.filter { $0.risk == .protected }.count
        highCPUCount = groups.filter { $0.totalCPU >= 25 }.count
        listeningPortCount = Set(groups.flatMap(\.listeningPorts)).count
    }
}
