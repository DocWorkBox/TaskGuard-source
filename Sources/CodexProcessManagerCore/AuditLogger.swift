import Foundation

public protocol AuditLogging {
    func record(_ entry: AuditEntry)
}

public struct AuditEntry: Hashable {
    public let timestamp: Date
    public let pid: Int32
    public let commandLine: String
    public let action: String
    public let reason: String
    public let result: String

    public init(
        timestamp: Date = Date(),
        pid: Int32,
        commandLine: String,
        action: String,
        reason: String,
        result: String
    ) {
        self.timestamp = timestamp
        self.pid = pid
        self.commandLine = commandLine
        self.action = action
        self.reason = reason
        self.result = result
    }
}

public final class FileAuditLogger: AuditLogging {
    public static let `default` = FileAuditLogger()

    public let fileURL: URL
    private let formatter: ISO8601DateFormatter

    public init(fileURL: URL? = nil) {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("CodexProcessManager")
        self.fileURL = fileURL ?? base.appendingPathComponent("audit.log")
        self.formatter = ISO8601DateFormatter()
    }

    public func record(_ entry: AuditEntry) {
        let line = [
            formatter.string(from: entry.timestamp),
            "pid=\(entry.pid)",
            "action=\(entry.action)",
            "result=\(entry.result)",
            "reason=\(entry.reason)",
            "command=\(entry.commandLine)"
        ].joined(separator: "\t") + "\n"

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } else {
                try line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Audit logging must never make process cleanup fail.
        }
    }
}
