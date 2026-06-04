import Foundation

public protocol CommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> String
}

public final class ShellCommandRunner: CommandRunning {
    private let timeoutSeconds: TimeInterval
    private let niceValue: Int?

    public convenience init() {
        self.init(timeoutSeconds: 5, niceValue: nil)
    }

    public init(timeoutSeconds: TimeInterval, niceValue: Int? = nil) {
        self.timeoutSeconds = timeoutSeconds
        self.niceValue = niceValue
    }

    public func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.qualityOfService = .background

        if let niceValue, executable != "/usr/bin/nice" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
            process.arguments = ["-n", "\(niceValue)", executable] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        var outputData = Data()
        var errorData = Data()
        let dataLock = NSLock()
        let completed = DispatchSemaphore(value: 0)

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            dataLock.lock()
            outputData.append(data)
            dataLock.unlock()
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            dataLock.lock()
            errorData.append(data)
            dataLock.unlock()
        }

        process.terminationHandler = { _ in
            completed.signal()
        }

        try process.run()

        let waitResult = completed.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw ProcessScanError.commandTimedOut(executable: executable, timeoutSeconds: timeoutSeconds)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        dataLock.lock()
        let finalOutputData = outputData
        let finalErrorData = errorData
        dataLock.unlock()

        let output = String(data: finalOutputData, encoding: .utf8) ?? ""
        let error = String(data: finalErrorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ProcessScanError.commandFailed(
                executable: executable,
                status: process.terminationStatus,
                stderr: error
            )
        }

        return output
    }
}

public enum ProcessScanError: Error, LocalizedError {
    case commandFailed(executable: String, status: Int32, stderr: String)
    case commandTimedOut(executable: String, timeoutSeconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(executable, status, stderr):
            return "\(executable) failed with status \(status): \(stderr)"
        case let .commandTimedOut(executable, timeoutSeconds):
            return "\(executable) timed out after \(Int(timeoutSeconds)) seconds"
        }
    }
}

public enum ProcessScanMode: Hashable {
    case fast
    case full
}

public final class ProcessSnapshotProvider {
    private let runner: CommandRunning
    private let cwdLookupCooldownSeconds: TimeInterval
    private var cwdCache: [Int32: CwdCacheEntry] = [:]

    public init(
        runner: CommandRunning = ShellCommandRunner(timeoutSeconds: 5, niceValue: 20),
        cwdLookupCooldownSeconds: TimeInterval = 60
    ) {
        self.runner = runner
        self.cwdLookupCooldownSeconds = cwdLookupCooldownSeconds
    }

    public func scan(
        configuration: ScanConfiguration,
        protectedPIDs: Set<Int32>,
        currentUser: String = NSUserName(),
        mode: ProcessScanMode = .full
    ) throws -> ProcessSnapshot {
        let psOutput = try runner.run(
            "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,user=,stat=,etime=,pcpu=,pmem=,command="]
        )
        let lsofOutput: String
        if mode == .full {
            lsofOutput = (try? runner.run(
                "/usr/sbin/lsof",
                arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"]
            )) ?? ""
        } else {
            lsofOutput = ""
        }

        let portsByPID = ProcessParser.parseListeningPorts(lsofOutput)
        var processes = ProcessParser.parsePSOutput(psOutput).map { process in
            var copy = process
            copy.listeningPorts = portsByPID[process.pid] ?? []
            return copy
        }

        if mode == .full {
            let cwdByPID = readCwdsIfNeeded(
                for: processes,
                configuration: configuration,
                protectedPIDs: protectedPIDs,
                currentUser: currentUser,
                now: Date()
            )
            processes = processes.map { process in
                var copy = process
                copy.cwd = cwdByPID[process.pid] ?? copy.cwd
                return copy
            }
        }

        let groups = ServiceGrouper.group(
            processes: processes,
            configuration: configuration,
            protectedPIDs: protectedPIDs,
            currentUser: currentUser
        )

        return ProcessSnapshot(scannedAt: Date(), groups: groups)
    }

    private func readCwdsIfNeeded(
        for processes: [ManagedProcess],
        configuration: ScanConfiguration,
        protectedPIDs: Set<Int32>,
        currentUser: String,
        now: Date
    ) -> [Int32: String] {
        let candidates = processes.filter {
            shouldLookupCwd(
                for: $0,
                configuration: configuration,
                protectedPIDs: protectedPIDs,
                currentUser: currentUser
            )
        }
        var result: [Int32: String] = [:]
        var candidatePIDs: Set<Int32> = []

        for process in candidates.sorted(by: { $0.pid < $1.pid }) {
            candidatePIDs.insert(process.pid)

            if let cached = cwdCache[process.pid],
               cached.commandLine == process.commandLine,
               now.timeIntervalSince(cached.checkedAt) < cwdLookupCooldownSeconds {
                if let cwd = cached.cwd {
                    result[process.pid] = cwd
                }
                continue
            }

            let cwd: String?
            if let output = try? runner.run(
                "/usr/sbin/lsof",
                arguments: ["-a", "-p", "\(process.pid)", "-d", "cwd", "-Fn"]
            ) {
                cwd = ProcessParser.parseCwd(output)
            } else {
                cwd = nil
            }

            cwdCache[process.pid] = CwdCacheEntry(
                commandLine: process.commandLine,
                cwd: cwd,
                checkedAt: now
            )
            if let cwd {
                result[process.pid] = cwd
            }
        }

        cwdCache = cwdCache.filter { candidatePIDs.contains($0.key) }
        return result
    }

    private func shouldLookupCwd(
        for process: ManagedProcess,
        configuration: ScanConfiguration,
        protectedPIDs: Set<Int32>,
        currentUser: String
    ) -> Bool {
        guard process.user == currentUser else { return false }
        guard !protectedPIDs.contains(process.pid) else { return false }
        guard process.cwd == nil else { return false }
        guard ThreadHintExtractor.extract(from: process)?.cwd == nil else { return false }
        guard !process.commandLine.contains("/Documents/Codex/") else { return false }
        guard !process.commandLine.contains(".app/Contents/") else { return false }

        return ProcessClassifier.isCodexInternal(process)
            || ProcessClassifier.isDevelopmentCommand(process, configuration: configuration)
            || ProcessClassifier.hasDevelopmentPort(process, configuration: configuration)
    }

    private struct CwdCacheEntry {
        let commandLine: String
        let cwd: String?
        let checkedAt: Date
    }
}
