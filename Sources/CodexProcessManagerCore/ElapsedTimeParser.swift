import Foundation

enum ElapsedTimeParser {
    static func seconds(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let daySplit = trimmed.split(separator: "-", maxSplits: 1).map(String.init)
        var days = 0
        var timePart = trimmed

        if daySplit.count == 2 {
            days = Int(daySplit[0]) ?? 0
            timePart = daySplit[1]
        }

        let parts = timePart.split(separator: ":").compactMap { Int($0) }
        let timeSeconds: Int
        switch parts.count {
        case 2:
            timeSeconds = parts[0] * 60 + parts[1]
        case 3:
            timeSeconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }

        return days * 24 * 3600 + timeSeconds
    }
}
