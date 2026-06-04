import CodexProcessManagerCore
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    @Published var scanIntervalSeconds: Double {
        didSet { defaults.set(scanIntervalSeconds, forKey: Keys.scanIntervalSeconds) }
    }

    @Published var portRangeText: String {
        didSet { defaults.set(portRangeText, forKey: Keys.portRangeText) }
    }

    @Published var commandKeywordsText: String {
        didSet { defaults.set(commandKeywordsText, forKey: Keys.commandKeywordsText) }
    }

    @Published var whitelistText: String {
        didSet { defaults.set(whitelistText, forKey: Keys.whitelistText) }
    }

    @Published var terminateWaitSeconds: Double {
        didSet { defaults.set(terminateWaitSeconds, forKey: Keys.terminateWaitSeconds) }
    }

    @Published var showsCodexInternals: Bool {
        didSet { defaults.set(showsCodexInternals, forKey: Keys.showsCodexInternals) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let defaultConfig = ScanConfiguration.default

        scanIntervalSeconds = defaults.object(forKey: Keys.scanIntervalSeconds) as? Double
            ?? defaultConfig.scanIntervalSeconds
        portRangeText = defaults.string(forKey: Keys.portRangeText)
            ?? "\(defaultConfig.devPortRange.lowerBound)-\(defaultConfig.devPortRange.upperBound)"
        commandKeywordsText = defaults.string(forKey: Keys.commandKeywordsText)
            ?? defaultConfig.devCommandKeywords.joined(separator: "\n")
        whitelistText = defaults.string(forKey: Keys.whitelistText) ?? ""
        terminateWaitSeconds = defaults.object(forKey: Keys.terminateWaitSeconds) as? Double
            ?? defaultConfig.terminateWaitSeconds
        showsCodexInternals = defaults.object(forKey: Keys.showsCodexInternals) as? Bool
            ?? defaultConfig.showsCodexInternals
    }

    func makeConfiguration() -> ScanConfiguration {
        ScanConfiguration(
            scanIntervalSeconds: max(2, scanIntervalSeconds),
            devPortRange: parsePortRange(portRangeText),
            devCommandKeywords: lines(from: commandKeywordsText),
            whitelistPatterns: lines(from: whitelistText),
            terminateWaitSeconds: max(1, terminateWaitSeconds),
            showsCodexInternals: showsCodexInternals
        )
    }

    func reset() {
        let defaultConfig = ScanConfiguration.default
        scanIntervalSeconds = defaultConfig.scanIntervalSeconds
        portRangeText = "\(defaultConfig.devPortRange.lowerBound)-\(defaultConfig.devPortRange.upperBound)"
        commandKeywordsText = defaultConfig.devCommandKeywords.joined(separator: "\n")
        whitelistText = ""
        terminateWaitSeconds = defaultConfig.terminateWaitSeconds
        showsCodexInternals = defaultConfig.showsCodexInternals
    }

    private func parsePortRange(_ text: String) -> ClosedRange<Int> {
        let separators = CharacterSet(charactersIn: "-–—, ")
        let numbers = text
            .components(separatedBy: separators)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        guard let lower = numbers.first, let upper = numbers.dropFirst().first else {
            return ScanConfiguration.default.devPortRange
        }

        return min(lower, upper)...max(lower, upper)
    }

    private func lines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private enum Keys {
        static let scanIntervalSeconds = "scanIntervalSeconds"
        static let portRangeText = "portRangeText"
        static let commandKeywordsText = "commandKeywordsText"
        static let whitelistText = "whitelistText"
        static let terminateWaitSeconds = "terminateWaitSeconds"
        static let showsCodexInternals = "showsCodexInternals"
    }
}
