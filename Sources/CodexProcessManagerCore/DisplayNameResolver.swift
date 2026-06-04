import Foundation

enum DisplayNameResolver {
    static func title(
        for ownership: ServiceOwnership,
        cwd: String?,
        threadHint: ThreadHint?,
        processes: [ManagedProcess]
    ) -> String {
        if let threadHint {
            if let displayTitle = threadHint.displayTitle, !displayTitle.isEmpty {
                return displayTitle
            }

            if threadHint.source == .commandLine,
               let sessionTitle = sessionTitle(cwd: threadHint.cwd ?? cwd, id: threadHint.threadId) {
                return sessionTitle
            }

            if let threadId = threadHint.threadId {
                return "线程 \(shortIdentifier(threadId))"
            }
        }

        if processes.contains(where: ProcessClassifier.isCodexMain) {
            return "Codex Desktop 主进程"
        }

        if processes.contains(where: isCodexProcessManager) {
            return "Codex TaskGuard"
        }

        if let pluginTitle = pluginTitle(from: cwd ?? processes.compactMap(\.cwd).first) {
            return pluginTitle
        }

        if let cwd, let projectTitle = projectTitle(from: cwd) {
            return projectTitle
        }

        if processes.contains(where: ProcessClassifier.isCodexInternal) {
            return "Codex Desktop 支撑进程"
        }

        if processes.contains(where: \.isListening) {
            return ownership == .protected ? "受保护应用服务" : ownership.displayName
        }

        if let first = processes.first {
            if ProcessClassifier.isOldCodexHelper(first) {
                return "旧 Codex helper \(first.pid)"
            }
            return "\(ownership.displayName) \(first.pid)"
        }

        return ownership.displayName
    }

    static func sessionTitle(cwd: String?, id: String?) -> String? {
        let shortID = id.map(shortIdentifier)
        guard let cwd, let project = projectTitle(from: cwd) else {
            return shortID.map { "会话 \($0)" }
        }

        if let shortID {
            return "\(project) · 会话 \(shortID)"
        }
        return "\(project) 会话"
    }

    private static func pluginTitle(from path: String?) -> String? {
        guard let path else { return nil }
        let components = path.split(separator: "/").map(String.init)
        guard let cacheIndex = components.firstIndex(of: "cache"),
              cacheIndex > 0,
              components[cacheIndex - 1] == "plugins",
              components.indices.contains(cacheIndex + 2)
        else {
            return nil
        }

        let source = components[cacheIndex + 1]
        guard source.contains("openai") else { return nil }

        let pluginID = components[cacheIndex + 2]
        return "\(titleCaseKebab(pluginID)) 插件"
    }

    private static func projectTitle(from path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        let name = URL(fileURLWithPath: expanded).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "/" else { return nil }
        return name
    }

    private static func titleCaseKebab(_ value: String) -> String {
        value
            .split(separator: "-")
            .map { token in
                let lower = token.lowercased()
                guard let first = lower.first else { return "" }
                return first.uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func shortIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return trimmed }
        return String(trimmed.prefix(8))
    }

    private static func isCodexProcessManager(_ process: ManagedProcess) -> Bool {
        process.commandLine.contains("CodexProcessManager.app/")
            || process.commandLine.contains("Codex TaskGuard.app/")
            || process.commandLine.contains("/CodexProcessManager")
    }
}
