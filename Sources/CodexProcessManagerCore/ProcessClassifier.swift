import Foundation

enum ProcessClassifier {
    static func isCodexMain(_ process: ManagedProcess) -> Bool {
        process.commandLine.contains("/Applications/Codex.app/Contents/MacOS/Codex")
    }

    static func isCodexInternal(_ process: ManagedProcess) -> Bool {
        let command = process.commandLine
        return command.contains("/Applications/Codex.app/")
            || command.contains("node_repl")
            || command.contains("mcp/server.cjs --stdio")
            || command.contains("codex app-server --listen stdio://")
            || command.contains("SkyComputerUseClient")
            || command.contains("Codex Computer Use")
            || command.contains("codex_chronicle")
    }

    static func isOldCodexHelper(_ process: ManagedProcess) -> Bool {
        process.ppid == 1
            && process.commandLine.contains("browser_crashpad_handler")
            && process.commandLine.contains("Codex_Mac")
            && (process.elapsedSeconds ?? 0) >= 30 * 60
    }

    static func isDevelopmentCommand(
        _ process: ManagedProcess,
        configuration: ScanConfiguration
    ) -> Bool {
        let command = process.commandLine.lowercased()
        let executable = process.executableName.lowercased()

        if executable == "node" || command.hasPrefix("node ") || command.contains("/node ") {
            return belongsToCodexWorkspace(process)
                || hasDevelopmentPort(process, configuration: configuration)
                || command.contains("/documents/codex/")
        }

        return configuration.devCommandKeywords
            .map { $0.lowercased() }
            .filter { $0 != "node" }
            .contains { command.contains($0) }
    }

    static func hasDevelopmentPort(
        _ process: ManagedProcess,
        configuration: ScanConfiguration
    ) -> Bool {
        process.listeningPorts.contains { configuration.devPortRange.contains($0) }
    }

    static func belongsToCodexWorkspace(_ process: ManagedProcess) -> Bool {
        if let cwd = process.cwd, cwd.contains("/Documents/Codex/") {
            return true
        }
        return process.commandLine.contains("/Documents/Codex/")
    }

    static func isWhitelisted(
        _ process: ManagedProcess,
        configuration: ScanConfiguration
    ) -> Bool {
        let haystack = [
            process.commandLine,
            process.cwd ?? "",
            process.executableName
        ].joined(separator: "\n").lowercased()

        return configuration.whitelistPatterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .contains { haystack.contains($0) }
    }

    static func isRelevant(
        _ process: ManagedProcess,
        configuration: ScanConfiguration,
        protectedPIDs: Set<Int32>,
        currentUser: String
    ) -> Bool {
        if process.user != currentUser {
            return false
        }
        if protectedPIDs.contains(process.pid) {
            return true
        }
        if isCodexMain(process) || isCodexInternal(process) || isOldCodexHelper(process) {
            return configuration.showsCodexInternals || isOldCodexHelper(process)
        }
        if isKnownNonDevelopmentAppHelper(process) {
            return false
        }
        if isWhitelisted(process, configuration: configuration) {
            return true
        }
        if isBundledApplicationProcess(process),
           !belongsToCodexWorkspace(process),
           !isDevelopmentCommand(process, configuration: configuration) {
            return false
        }
        if isDevelopmentCommand(process, configuration: configuration) {
            return true
        }
        if hasDevelopmentPort(process, configuration: configuration) {
            return true
        }
        if belongsToCodexWorkspace(process) && process.isListening {
            return true
        }
        return false
    }

    private static func isKnownNonDevelopmentAppHelper(_ process: ManagedProcess) -> Bool {
        let command = process.commandLine
        if command.hasPrefix("/System/Library/") || command.hasPrefix("/usr/libexec/") {
            return true
        }

        let appHelperMarkers = [
            "/Applications/Google Chrome.app/",
            "/Applications/QuarkCloudDrive.app/",
            "/Applications/微力同步.app/",
            "/Applications/VerySync.app/",
            "/Applications/Syncthing.app/",
            "/Applications/Dropbox.app/",
            "/Applications/Google Drive.app/",
            "/Applications/OneDrive.app/",
            "/Applications/QQMusic.app/",
            "/Applications/WeChat.app/",
            "/Applications/Adobe ",
            "/Applications/Utilities/Adobe ",
            "/System/Applications/",
            "Google Chrome Helper",
            "WebKit.WebContent",
            "WebKit.Networking",
            "node.quantum.mojom.NodeService",
            "Creative Cloud Content Manager.node"
        ]

        return appHelperMarkers.contains { command.contains($0) }
    }

    private static func isBundledApplicationProcess(_ process: ManagedProcess) -> Bool {
        process.commandLine.contains(".app/Contents/")
    }
}
