import AppKit
import CodexProcessManagerCore
import Foundation

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published private(set) var snapshot: ProcessSnapshot = .empty
    @Published private(set) var isRefreshing = false
    @Published var isPaused = false
    @Published var selectedGroupID: ServiceGroup.ID?
    @Published var lastError: String?
    @Published var lastActivity: String = "尚未扫描"
    @Published var lastTerminationResults: [TerminationResult] = []

    private let preferences: AppPreferences
    private let provider: ProcessSnapshotProvider
    private let resourceSampler: ResourceUsageSampling
    private let terminator: ProcessTerminator
    private let auditLogger: AuditLogging
    private var timer: Timer?
    private var resourceTimer: Timer?
    private var startupRefreshTask: Task<Void, Never>?
    private let resourceRefreshIntervalSeconds: TimeInterval = 2

    init(
        preferences: AppPreferences,
        provider: ProcessSnapshotProvider = ProcessSnapshotProvider(),
        resourceSampler: ResourceUsageSampling = ProcessResourceSampler(),
        terminator: ProcessTerminator = ProcessTerminator(),
        auditLogger: AuditLogging = FileAuditLogger.default
    ) {
        self.preferences = preferences
        self.provider = provider
        self.resourceSampler = resourceSampler
        self.terminator = terminator
        self.auditLogger = auditLogger
    }

    var summary: ProcessSummary {
        snapshot.summary
    }

    var suggestedPlan: KillPlan {
        KillPlanner.buildSuggestedPlan(from: snapshot.groups)
    }

    var selectedGroup: ServiceGroup? {
        guard let selectedGroupID else { return snapshot.groups.first }
        return snapshot.groups.first { $0.id == selectedGroupID } ?? snapshot.groups.first
    }

    func start() {
        guard timer == nil else { return }
        scheduleTimer()
        scheduleResourceTimer()
        scheduleStartupRefresh()
    }

    func stop() {
        startupRefreshTask?.cancel()
        startupRefreshTask = nil
        timer?.invalidate()
        timer = nil
        resourceTimer?.invalidate()
        resourceTimer = nil
    }

    func togglePause() {
        isPaused.toggle()
        lastActivity = isPaused ? "已暂停扫描" : "已恢复扫描"
    }

    func refresh(mode: ProcessScanMode = .full) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil

        let configuration = preferences.makeConfiguration()
        let protectedPIDs = protectedProcessIDs()
        let provider = provider

        do {
            let newSnapshot = try await Task.detached(priority: .background) {
                try provider.scan(
                    configuration: configuration,
                    protectedPIDs: protectedPIDs,
                    mode: mode
                )
            }.value

            snapshot = newSnapshot
            if selectedGroupID == nil || !newSnapshot.groups.contains(where: { $0.id == selectedGroupID }) {
                selectedGroupID = newSnapshot.groups.first?.id
            }
            refreshResourceUsage()
            lastActivity = mode == .fast
                ? "已快速扫描 \(newSnapshot.groups.count) 组服务"
                : "已扫描 \(newSnapshot.groups.count) 组服务"
        } catch {
            lastError = error.localizedDescription
            lastActivity = "扫描失败"
        }

        isRefreshing = false
    }

    func cleanSuggested() async {
        let plan = suggestedPlan
        guard !plan.isEmpty else {
            lastActivity = "没有建议清理项"
            return
        }

        let results = await terminator.terminate(
            plan: plan,
            waitSeconds: preferences.makeConfiguration().terminateWaitSeconds,
            auditLogger: auditLogger
        )
        lastTerminationResults = results
        lastActivity = terminationSummary(results)
        await refresh()
    }

    func closeSelectedGroup() async {
        guard let selectedGroup else {
            lastActivity = "没有选中的服务组"
            return
        }

        let plan = KillPlanner.buildPlan(from: [selectedGroup])
        guard !plan.isEmpty else {
            lastActivity = "当前服务组受保护，不能关闭"
            return
        }

        let results = await terminator.terminate(
            plan: plan,
            waitSeconds: preferences.makeConfiguration().terminateWaitSeconds,
            auditLogger: auditLogger
        )
        lastTerminationResults = results
        lastActivity = terminationSummary(results)
        await refresh()
    }

    func forceKillStillRunning() async {
        let targets = lastTerminationResults
            .filter { $0.status == .stillRunning }
            .map { KillTarget(pid: $0.pid, commandLine: $0.commandLine, reason: "用户确认强制关闭") }

        guard !targets.isEmpty else { return }

        let results = await terminator.forceKill(
            targets: targets,
            waitSeconds: 1,
            auditLogger: auditLogger
        )
        lastTerminationResults = results
        lastActivity = terminationSummary(results)
        await refresh()
    }

    func groups(for filter: SidebarFilter) -> [ServiceGroup] {
        switch filter {
        case .all:
            return snapshot.groups
        case .codexThreads:
            return snapshot.groups.filter { [.codexThread, .codexWorkspace, .codexInternal].contains($0.ownership) }
        case .development:
            return snapshot.groups.filter { [.developmentService, .unownedDevelopment].contains($0.ownership) }
        case .suggested:
            return snapshot.groups.filter { $0.risk == .suggestedCleanup }
        case .ports:
            return snapshot.groups.filter { !$0.listeningPorts.isEmpty }
        case .protected:
            return snapshot.groups.filter { $0.risk == .protected }
        }
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: max(60, preferences.scanIntervalSeconds), repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isPaused else { return }
                await self.refresh()
            }
        }
    }

    private func scheduleResourceTimer() {
        resourceTimer = Timer.scheduledTimer(withTimeInterval: resourceRefreshIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isPaused else { return }
                self.refreshResourceUsage()
            }
        }
    }

    private func refreshResourceUsage() {
        let pids = snapshot.groups.flatMap { group in
            group.processes.map(\.pid)
        }
        guard !pids.isEmpty else { return }

        let usageByPID = resourceSampler.sample(pids: pids)
        guard !usageByPID.isEmpty else { return }

        snapshot = snapshot.updatingResourceUsage(usageByPID)
    }

    private func scheduleStartupRefresh() {
        startupRefreshTask?.cancel()
        lastActivity = "等待首次扫描，可手动刷新"
        startupRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, !self.isPaused else { return }
                self.startupRefreshTask = nil
                Task { await self.refresh(mode: .fast) }
            }
        }
    }

    private func protectedProcessIDs() -> Set<Int32> {
        var ids: Set<Int32> = [
            ProcessInfo.processInfo.processIdentifier,
            getppid()
        ]

        ids.insert(NSRunningApplication.current.processIdentifier)

        return ids
    }

    private func terminationSummary(_ results: [TerminationResult]) -> String {
        let terminated = results.filter { $0.status == .terminated || $0.status == .alreadyExited }.count
        let stillRunning = results.filter { $0.status == .stillRunning }.count
        let failed = results.filter { $0.status == .failed }.count

        if stillRunning > 0 {
            return "已关闭 \(terminated) 个，\(stillRunning) 个仍在运行"
        }
        if failed > 0 {
            return "已关闭 \(terminated) 个，\(failed) 个失败"
        }
        return "已关闭 \(terminated) 个进程"
    }
}
