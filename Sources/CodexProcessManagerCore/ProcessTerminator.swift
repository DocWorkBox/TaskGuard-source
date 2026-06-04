import Darwin
import Foundation

public enum TerminationStatus: String, Hashable {
    case terminated
    case stillRunning
    case failed
    case alreadyExited

    public var displayName: String {
        switch self {
        case .terminated: return "已退出"
        case .stillRunning: return "仍在运行"
        case .failed: return "关闭失败"
        case .alreadyExited: return "已不存在"
        }
    }
}

public struct TerminationResult: Hashable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let commandLine: String
    public let signal: KillSignal
    public let status: TerminationStatus
    public let message: String

    public init(
        pid: Int32,
        commandLine: String,
        signal: KillSignal,
        status: TerminationStatus,
        message: String
    ) {
        self.pid = pid
        self.commandLine = commandLine
        self.signal = signal
        self.status = status
        self.message = message
    }
}

public final class ProcessTerminator {
    public init() {}

    public func terminate(
        plan: KillPlan,
        waitSeconds: Double,
        auditLogger: AuditLogging
    ) async -> [TerminationResult] {
        await send(signal: .term, to: plan.targets, waitSeconds: waitSeconds, auditLogger: auditLogger)
    }

    public func forceKill(
        targets: [KillTarget],
        waitSeconds: Double,
        auditLogger: AuditLogging
    ) async -> [TerminationResult] {
        await send(signal: .kill, to: targets, waitSeconds: waitSeconds, auditLogger: auditLogger)
    }

    private func send(
        signal: KillSignal,
        to targets: [KillTarget],
        waitSeconds: Double,
        auditLogger: AuditLogging
    ) async -> [TerminationResult] {
        var results: [TerminationResult] = []
        let rawSignal = signal == .term ? SIGTERM : SIGKILL

        for target in targets {
            if !isAlive(target.pid) {
                let result = TerminationResult(
                    pid: target.pid,
                    commandLine: target.commandLine,
                    signal: signal,
                    status: .alreadyExited,
                    message: "进程已不存在。"
                )
                results.append(result)
                auditLogger.record(entry(for: target, signal: signal, result: result))
                continue
            }

            let killResult = Darwin.kill(target.pid, rawSignal)
            if killResult != 0 {
                let message = String(cString: strerror(errno))
                let result = TerminationResult(
                    pid: target.pid,
                    commandLine: target.commandLine,
                    signal: signal,
                    status: .failed,
                    message: message
                )
                results.append(result)
                auditLogger.record(entry(for: target, signal: signal, result: result))
                continue
            }
        }

        if waitSeconds > 0 {
            let nanos = UInt64(waitSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }

        for target in targets where !results.contains(where: { $0.pid == target.pid }) {
            let status: TerminationStatus = isAlive(target.pid) ? .stillRunning : .terminated
            let result = TerminationResult(
                pid: target.pid,
                commandLine: target.commandLine,
                signal: signal,
                status: status,
                message: status == .stillRunning ? "进程未响应 \(signal.rawValue)。" : "进程已退出。"
            )
            results.append(result)
            auditLogger.record(entry(for: target, signal: signal, result: result))
        }

        return results.sorted { $0.pid < $1.pid }
    }

    private func isAlive(_ pid: Int32) -> Bool {
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }

    private func entry(
        for target: KillTarget,
        signal: KillSignal,
        result: TerminationResult
    ) -> AuditEntry {
        AuditEntry(
            pid: target.pid,
            commandLine: target.commandLine,
            action: signal.rawValue,
            reason: target.reason,
            result: result.status.displayName
        )
    }
}
