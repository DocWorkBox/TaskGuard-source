import CodexProcessManagerCore
import Foundation

if CommandLine.arguments.contains("--scan-once") {
    do {
        let snapshot = try ProcessSnapshotProvider().scan(
            configuration: .testDefault,
            protectedPIDs: [ProcessInfo.processInfo.processIdentifier, getppid()]
        )
        print("groups=\(snapshot.groups.count)")
        print("suggested=\(snapshot.summary.suggestedCleanupCount)")
        print("ports=\(snapshot.summary.listeningPortCount)")
        for group in snapshot.groups.prefix(10) {
            print("\(group.risk.displayName)\t\(group.ownership.displayName)\t\(group.title)\tpid=\(group.processes.map { String($0.pid) }.joined(separator: ","))")
        }
        exit(0)
    } catch {
        fputs("scan failed: \(error)\n", stderr)
        exit(1)
    }
}

@discardableResult
func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
    if !condition() {
        failures.append(message)
        fputs("FAIL: \(message)\n", stderr)
        return false
    }
    return true
}

func require<T>(_ value: T?, _ message: String) -> T {
    guard let value else {
        failures.append(message)
        fatalError("Required value missing: \(message)")
    }
    return value
}

var failures: [String] = []

func withTemporarySessionIndex(_ content: String, run body: () -> Void) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-session-index-\(UUID().uuidString).jsonl")
    try? content.write(to: url, atomically: true, encoding: .utf8)

    let previous = getenv("CODEX_PROCESS_MANAGER_SESSION_INDEX").map { String(cString: $0) }
    setenv("CODEX_PROCESS_MANAGER_SESSION_INDEX", url.path, 1)
    defer {
        if let previous {
            setenv("CODEX_PROCESS_MANAGER_SESSION_INDEX", previous, 1)
        } else {
            unsetenv("CODEX_PROCESS_MANAGER_SESSION_INDEX")
        }
        try? FileManager.default.removeItem(at: url)
    }

    body()
}

func testParsesPsLineKeepingFullCommand() {
    let line = "12968 1201 zhaoke S 08:07 0.0 0.2 /Applications/Codex.app/Contents/Resources/node_repl --flag value"
    let process = require(ProcessParser.parsePSLine(line), "ps line should parse")

    expect(process.pid == 12968, "pid parsed")
    expect(process.ppid == 1201, "ppid parsed")
    expect(process.user == "zhaoke", "user parsed")
    expect(process.elapsed == "08:07", "elapsed parsed")
    expect(process.cpuPercent == 0.0, "cpu parsed")
    expect(process.memoryPercent == 0.2, "memory parsed")
    expect(
        process.commandLine == "/Applications/Codex.app/Contents/Resources/node_repl --flag value",
        "full command preserved"
    )
}

func testParsesListeningPortsFromLsofOutput() {
    let output = """
    COMMAND   PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
    node    4242 zhaoke   22u  IPv4 0xabc      0t0  TCP 127.0.0.1:4173 (LISTEN)
    Python  5151 zhaoke    4u  IPv6 0xdef      0t0  TCP *:8000 (LISTEN)
    """

    let ports = ProcessParser.parseListeningPorts(output)

    expect(ports[4242] == [4173], "node port parsed")
    expect(ports[5151] == [8000], "python port parsed")
}

func testExtractsThreadHintFromCodexTurnPayload() {
    let process = ManagedProcess(
        pid: 6924,
        ppid: 1,
        user: "zhaoke",
        state: "S",
        elapsed: "03:14:00",
        cpuPercent: 0,
        memoryPercent: 0,
        commandLine: #"SkyComputerUseClient turn-ended {"thread-id":"019e7e61-4c9a","turn-id":"019e7e61-4d04","cwd":"/Users/zhaoke/Documents/Codex/2026-05-31/ai"}"#,
        cwd: nil,
        listeningPorts: []
    )

    let hint = require(ThreadHintExtractor.extract(from: process), "thread hint should parse")

    expect(hint.threadId == "019e7e61-4c9a", "thread id parsed")
    expect(hint.turnId == "019e7e61-4d04", "turn id parsed")
    expect(hint.cwd == "/Users/zhaoke/Documents/Codex/2026-05-31/ai", "cwd parsed")
    expect(hint.source == .codexTurnPayload, "source parsed")
    expect(hint.confidence >= 0.9, "confidence high")
}

func testExtractsReadableThreadTitleFromCodexPayload() {
    let process = ManagedProcess(
        pid: 6925,
        ppid: 1,
        user: "zhaoke",
        state: "S",
        elapsed: "03:14:00",
        cpuPercent: 0,
        memoryPercent: 0,
        commandLine: #"SkyComputerUseClient turn-ended {"thread-id":"019e7e61-4c9a","cwd":"/Users/zhaoke/Documents/Codex/2026-05-31/ai","last-assistant-message":"{\"title\":\"整理AI上半年工作并确认范围\"}"}"#,
        cwd: nil,
        listeningPorts: []
    )

    let hint = require(ThreadHintExtractor.extract(from: process), "thread hint with title should parse")

    expect(hint.displayTitle == "整理AI上半年工作并确认范围", "thread title parsed from nested assistant title")
}

func testExtractsWorkingDirectoryWithSpacesFromCommandLineSession() {
    withTemporarySessionIndex("") {
        let process = ManagedProcess(
            pid: 50456,
            ppid: 1201,
            user: "zhaoke",
            state: "S",
            elapsed: "00:30:00",
            cpuPercent: 0,
            memoryPercent: 0,
            commandLine: "/Applications/Codex.app/Contents/Resources/node kernel.js --session-id 9533cd2a559e4d1cbca64040c557909c --working-dir /Users/zhaoke/Documents/New project --stdio",
            cwd: nil,
            listeningPorts: []
        )

        let hint = require(ThreadHintExtractor.extract(from: process), "command-line session hint should parse")

        expect(hint.cwd == "/Users/zhaoke/Documents/New project", "working dir with spaces preserved")
        expect(hint.displayTitle == "New project · 会话 9533cd2a", "session title falls back to project name and short id")
    }
}

func testUsesCodexSessionIndexForDisplayTitle() {
    let jsonl = #"{"id":"session-123","thread_name":"查证后台进程未关闭问题","updated_at":"2026-06-04T04:41:49Z"}"#
    withTemporarySessionIndex(jsonl) {
        let process = ManagedProcess(
            pid: 50457,
            ppid: 1201,
            user: "zhaoke",
            state: "S",
            elapsed: "00:30:00",
            cpuPercent: 0,
            memoryPercent: 0,
            commandLine: "/Applications/Codex.app/Contents/Resources/node kernel.js --session-id session-123 --working-dir /Users/zhaoke/Documents/New project",
            cwd: nil,
            listeningPorts: []
        )

        let hint = require(ThreadHintExtractor.extract(from: process), "session index title should parse")

        expect(hint.displayTitle == "查证后台进程未关闭问题", "session index title wins over fallback")
    }
}

func testTitlesCodexPluginCacheByPluginName() {
    let processes = [
        ManagedProcess.fixture(
            pid: 12969,
            ppid: 1201,
            commandLine: "node ./mcp/server.cjs --stdio",
            cwd: "/Users/zhaoke/.codex/plugins/cache/openai-curated-remote/data-analytics/0.1.35-cf2b8b6c00d3"
        )
    ]

    let groups = ServiceGrouper.group(
        processes: processes,
        configuration: .testDefault,
        protectedPIDs: []
    )

    expect(groups.first?.title == "Data Analytics 插件", "plugin cache title uses plugin id, not version folder")
}

func testTitlesProtectedCodexMainProcess() {
    let processes = [
        ManagedProcess.fixture(
            pid: 1161,
            ppid: 1,
            commandLine: "/Applications/Codex.app/Contents/MacOS/Codex",
            cwd: "/"
        )
    ]

    let groups = ServiceGrouper.group(
        processes: processes,
        configuration: .testDefault,
        protectedPIDs: [1161]
    )

    expect(groups.first?.title == "Codex Desktop 主进程", "codex main process has readable title")
}

func testTitlesCodexSupportProcessGroup() {
    let processes = [
        ManagedProcess.fixture(
            pid: 1201,
            ppid: 1161,
            commandLine: "/Applications/Codex.app/Contents/Resources/app-server",
            cwd: "/",
            listeningPorts: [3000]
        )
    ]

    let groups = ServiceGrouper.group(
        processes: processes,
        configuration: .testDefault,
        protectedPIDs: []
    )

    expect(groups.first?.title == "Codex Desktop 支撑进程", "codex support process has readable title")
}

func testGroupsCodexWorkspaceDevServerAsSuggestedCleanupWhenOrphanedAndOld() {
    let processes = [
        ManagedProcess.fixture(
            pid: 4000,
            ppid: 1,
            elapsed: "01:10:00",
            commandLine: "node /Users/zhaoke/Documents/Codex/demo/server.js",
            cwd: "/Users/zhaoke/Documents/Codex/demo",
            listeningPorts: [4173]
        )
    ]

    let groups = ServiceGrouper.group(
        processes: processes,
        configuration: .testDefault,
        protectedPIDs: []
    )

    expect(groups.count == 1, "one group created")
    expect(groups[0].ownership == .developmentService, "ownership is development service")
    expect(groups[0].risk == .suggestedCleanup, "risk is suggested cleanup")
    expect(groups[0].recommendedAction.isSelectedByDefault, "suggested group selected by default")
    expect(groups[0].recommendedAction.reason.contains("Codex 工作区"), "reason names Codex workspace")
}

func testProtectsCurrentCodexMainProcessAndWhitelistMatches() {
    let processes = [
        ManagedProcess.fixture(
            pid: 1161,
            ppid: 1,
            commandLine: "/Applications/Codex.app/Contents/MacOS/Codex",
            cwd: nil,
            listeningPorts: []
        ),
        ManagedProcess.fixture(
            pid: 5000,
            ppid: 1,
            commandLine: "node /Users/zhaoke/Documents/Codex/keep/server.js",
            cwd: "/Users/zhaoke/Documents/Codex/keep",
            listeningPorts: [5173]
        )
    ]
    var configuration = ScanConfiguration.testDefault
    configuration.whitelistPatterns = ["keep/server.js"]

    let groups = ServiceGrouper.group(
        processes: processes,
        configuration: configuration,
        protectedPIDs: [1161]
    )

    expect(groups.count == 2, "two protected groups")
    expect(groups.allSatisfy { $0.risk == .protected }, "all groups protected")
    expect(groups.allSatisfy { !$0.recommendedAction.isSelectedByDefault }, "protected groups not selected")
}

func testBuildsKillPlanOnlyFromSuggestedGroups() {
    let suggested = ServiceGroup.fixture(
        id: "suggested",
        risk: .suggestedCleanup,
        processes: [
            .fixture(pid: 7001, commandLine: "node server.js", listeningPorts: [4173])
        ]
    )
    let protected = ServiceGroup.fixture(
        id: "protected",
        risk: .protected,
        processes: [
            .fixture(pid: 7002, commandLine: "/Applications/Codex.app/Contents/MacOS/Codex")
        ]
    )

    let plan = KillPlanner.buildSuggestedPlan(from: [suggested, protected])

    expect(plan.targets.map(\.pid) == [7001], "kill plan only includes suggested pid")
    expect(plan.signalSequence == [.term], "kill plan starts with SIGTERM")
    expect(plan.requiresConfirmation, "kill plan requires confirmation")
    expect(!plan.warnings.isEmpty, "kill plan includes warnings")
}

func testManualKillPlanIncludesNeedsReviewButSkipsProtectedGroups() {
    let needsReview = ServiceGroup.fixture(
        id: "needs-review",
        risk: .needsReview,
        processes: [
            .fixture(pid: 7101, commandLine: "node maybe-server.js", listeningPorts: [4173])
        ]
    )
    let protected = ServiceGroup.fixture(
        id: "protected",
        risk: .protected,
        processes: [
            .fixture(pid: 7102, commandLine: "/Applications/Codex.app/Contents/MacOS/Codex")
        ]
    )

    let plan = KillPlanner.buildPlan(from: [needsReview, protected])

    expect(plan.targets.map(\.pid) == [7101], "manual kill plan includes needs-review pid only")
}

func testIgnoresProcessesOwnedByOtherUsers() {
    let processes = [
        ManagedProcess.fixture(
            pid: 9001,
            user: "root",
            commandLine: "/usr/sbin/systemstats --daemon",
            cwd: "/",
            listeningPorts: [5000]
        )
    ]

    let groups = ServiceGrouper.group(
        processes: processes,
        configuration: .testDefault,
        protectedPIDs: [],
        currentUser: "zhaoke"
    )

    expect(groups.isEmpty, "other-user processes are ignored instead of grouped")
}

func testIgnoresKnownAppHelpersEvenWhenTheyUseDevelopmentPorts() {
    let processes = [
        ManagedProcess.fixture(
            pid: 9002,
            commandLine: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
            cwd: "/",
            listeningPorts: [5000]
        ),
        ManagedProcess.fixture(
            pid: 9003,
            commandLine: "/Applications/QuarkCloudDrive.app/Contents/Frameworks/QuarkCloudDrive Helper.app/Contents/MacOS/QuarkCloudDrive Helper --utility-sub-type=node.quantum.mojom.NodeService",
            cwd: "/Applications/QuarkCloudDrive.app",
            listeningPorts: [9125]
        )
    ]

    let groups = ServiceGrouper.group(
        processes: processes,
        configuration: .testDefault,
        protectedPIDs: [],
        currentUser: NSUserName()
    )

    expect(groups.isEmpty, "system and app helper ports are not treated as dev services")
}

func testKeepsRealNodeDevServerWhenInCodexWorkspaceAndListening() {
    let processes = [
        ManagedProcess.fixture(
            pid: 9004,
            ppid: 1,
            elapsed: "01:00:00",
            commandLine: "node /Users/zhaoke/Documents/Codex/demo/server.js",
            cwd: "/Users/zhaoke/Documents/Codex/demo",
            listeningPorts: [4173]
        )
    ]

    let groups = ServiceGrouper.group(
        processes: processes,
        configuration: .testDefault,
        protectedPIDs: [],
        currentUser: NSUserName()
    )

    expect(groups.count == 1, "real Codex node dev server is still included")
    expect(groups.first?.ownership == .developmentService, "real node server is development service")
}

func testShellCommandRunnerHandlesLargeOutputWithoutPipeDeadlock() {
    do {
        let output = try ShellCommandRunner(timeoutSeconds: 5).run("/usr/bin/seq", arguments: ["1", "20000"])
        expect(output.contains("20000"), "large command output is fully read")
    } catch {
        failures.append("large command output should not deadlock: \(error)")
    }
}

extension ScanConfiguration {
    static var testDefault: ScanConfiguration {
        ScanConfiguration(
            scanIntervalSeconds: 5,
            devPortRange: 3000...9000,
            devCommandKeywords: ["node", "vite", "next", "webpack", "python3 -m http.server"],
            whitelistPatterns: [],
            terminateWaitSeconds: 3,
            showsCodexInternals: true
        )
    }
}

extension ManagedProcess {
    static func fixture(
        pid: Int32,
        ppid: Int32 = 1,
        user: String = NSUserName(),
        elapsed: String = "10:00",
        commandLine: String,
        cwd: String? = nil,
        listeningPorts: [Int] = []
    ) -> ManagedProcess {
        ManagedProcess(
            pid: pid,
            ppid: ppid,
            user: user,
            state: "S",
            elapsed: elapsed,
            cpuPercent: 0,
            memoryPercent: 0,
            commandLine: commandLine,
            cwd: cwd,
            listeningPorts: listeningPorts
        )
    }
}

extension ServiceGroup {
    static func fixture(
        id: String,
        risk: ServiceRisk,
        processes: [ManagedProcess]
    ) -> ServiceGroup {
        ServiceGroup(
            id: id,
            title: id,
            ownership: .developmentService,
            cwd: nil,
            threadHint: nil,
            processes: processes,
            listeningPorts: processes.flatMap(\.listeningPorts),
            risk: risk,
            confidence: 0.9,
            evidence: ["fixture"],
            recommendedAction: ActionRecommendation(
                title: "关闭",
                reason: "fixture",
                isSelectedByDefault: risk == .suggestedCleanup
            )
        )
    }
}

testParsesPsLineKeepingFullCommand()
testParsesListeningPortsFromLsofOutput()
testExtractsThreadHintFromCodexTurnPayload()
testExtractsReadableThreadTitleFromCodexPayload()
testExtractsWorkingDirectoryWithSpacesFromCommandLineSession()
testUsesCodexSessionIndexForDisplayTitle()
testTitlesCodexPluginCacheByPluginName()
testTitlesProtectedCodexMainProcess()
testTitlesCodexSupportProcessGroup()
testGroupsCodexWorkspaceDevServerAsSuggestedCleanupWhenOrphanedAndOld()
testProtectsCurrentCodexMainProcessAndWhitelistMatches()
testBuildsKillPlanOnlyFromSuggestedGroups()
testManualKillPlanIncludesNeedsReviewButSkipsProtectedGroups()
testIgnoresProcessesOwnedByOtherUsers()
testIgnoresKnownAppHelpersEvenWhenTheyUseDevelopmentPorts()
testKeepsRealNodeDevServerWhenInCodexWorkspaceAndListening()
testShellCommandRunnerHandlesLargeOutputWithoutPipeDeadlock()

if failures.isEmpty {
    print("All core behavior tests passed")
} else {
    fputs("\(failures.count) tests failed\n", stderr)
    exit(1)
}
