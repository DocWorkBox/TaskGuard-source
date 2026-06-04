import Foundation

public protocol CommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> String
}

public final class ShellCommandRunner: CommandRunning {
    private let timeoutSeconds: TimeInterval

    public convenience init() {
        self.init(timeoutSeconds: 5)
    }

    public init(timeoutSeconds: TimeInterval) {
        self.timeoutSeconds = timeoutSeconds
    }

    public func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

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

public final class ProcessSnapshotProvider {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ShellCommandRunner()) {
        self.runner = runner
    }

    public func scan(
        configuration: ScanConfiguration,
        protectedPIDs: Set<Int32>,
        currentUser: String = NSUserName()
    ) throws -> ProcessSnapshot {
        let psOutput = try runner.run(
            "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,user=,stat=,etime=,pcpu=,pmem=,command="]
        )
        let lsofOutput = (try? runner.run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"]
        )) ?? ""

        let portsByPID = ProcessParser.parseListeningPorts(lsofOutput)
        var processes = ProcessParser.parsePSOutput(psOutput).map { process in
            var copy = process
            copy.listeningPorts = portsByPID[process.pid] ?? []
            return copy
        }

        let cwdCandidates = processes.filter {
            ProcessClassifier.isCodexInternal($0)
                || ProcessClassifier.isDevelopmentCommand($0, configuration: configuration)
                || ProcessClassifier.hasDevelopmentPort($0, configuration: configuration)
                || ProcessClassifier.belongsToCodexWorkspace($0)
        }.map(\.pid)

        let cwdByPID = readCwds(for: cwdCandidates)
        processes = processes.map { process in
            var copy = process
            copy.cwd = cwdByPID[process.pid] ?? copy.cwd
            return copy
        }

        let groups = ServiceGrouper.group(
            processes: processes,
            configuration: configuration,
            protectedPIDs: protectedPIDs,
            currentUser: currentUser
        )

        return ProcessSnapshot(scannedAt: Date(), groups: groups)
    }

    private func readCwds(for pids: [Int32]) -> [Int32: String] {
        var result: [Int32: String] = [:]

        for pid in Array(Set(pids)).sorted() {
            guard let output = try? runner.run(
                "/usr/sbin/lsof",
                arguments: ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
            ),
            let cwd = ProcessParser.parseCwd(output)
            else {
                continue
            }
            result[pid] = cwd
        }

        return result
    }
}
