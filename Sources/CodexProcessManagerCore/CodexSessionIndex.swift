import Foundation

enum CodexSessionIndex {
    private struct Entry: Decodable {
        let id: String
        let threadName: String

        enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
        }
    }

    private static let lock = NSLock()
    private static var cachedPath: String?
    private static var cachedModificationDate: Date?
    private static var cachedTitles: [String: String] = [:]

    static func title(for id: String) -> String? {
        guard !id.isEmpty else { return nil }
        refreshIfNeeded()

        lock.lock()
        defer { lock.unlock() }
        return cachedTitles[id]
    }

    private static func refreshIfNeeded() {
        let path = indexPath()
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date

        lock.lock()
        let shouldRefresh = path != cachedPath || modificationDate != cachedModificationDate
        lock.unlock()

        guard shouldRefresh else { return }

        let titles = loadTitles(from: path)

        lock.lock()
        cachedPath = path
        cachedModificationDate = modificationDate
        cachedTitles = titles
        lock.unlock()
    }

    private static func indexPath() -> String {
        if let override = ProcessInfo.processInfo.environment["CODEX_PROCESS_MANAGER_SESSION_INDEX"],
           !override.isEmpty {
            return override
        }
        return NSHomeDirectory() + "/.codex/session_index.jsonl"
    }

    private static func loadTitles(from path: String) -> [String: String] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }

        var titles: [String: String] = [:]
        let decoder = JSONDecoder()

        for line in content.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let entry = try? decoder.decode(Entry.self, from: data)
            else {
                continue
            }

            let title = entry.threadName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                titles[entry.id] = title
            }
        }

        return titles
    }
}
