import Foundation

public enum ProcessParser {
    public static func parsePSLine(_ line: String) -> ManagedProcess? {
        let parts = line.split(
            separator: " ",
            maxSplits: 7,
            omittingEmptySubsequences: true
        ).map(String.init)

        guard parts.count == 8,
              let pid = Int32(parts[0]),
              let ppid = Int32(parts[1]),
              let cpu = Double(parts[5]),
              let memory = Double(parts[6])
        else {
            return nil
        }

        return ManagedProcess(
            pid: pid,
            ppid: ppid,
            user: parts[2],
            state: parts[3],
            elapsed: parts[4],
            cpuPercent: cpu,
            memoryPercent: memory,
            commandLine: parts[7],
            cwd: nil,
            listeningPorts: []
        )
    }

    public static func parsePSOutput(_ output: String) -> [ManagedProcess] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parsePSLine(String($0)) }
    }

    public static func parseListeningPorts(_ output: String) -> [Int32: [Int]] {
        var result: [Int32: Set<Int>] = [:]

        for line in output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            guard !line.hasPrefix("COMMAND") else { continue }

            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 2, let pid = Int32(columns[1]) else { continue }
            guard let tcpRange = line.range(of: "TCP ") else { continue }

            let endpointPart = line[tcpRange.upperBound...]
                .replacingOccurrences(of: " (LISTEN)", with: "")
                .split(separator: " ", maxSplits: 1)
                .first
                .map(String.init) ?? ""
            guard let port = parsePort(from: endpointPart) else { continue }

            result[pid, default: []].insert(port)
        }

        return result.mapValues { Array($0).sorted() }
    }

    public static func parseCwd(_ lsofFieldOutput: String) -> String? {
        for line in lsofFieldOutput.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.hasPrefix("n") {
                return String(line.dropFirst())
            }
        }
        return nil
    }

    private static func parsePort(from endpoint: String) -> Int? {
        guard let lastColon = endpoint.lastIndex(of: ":") else { return nil }
        let candidate = endpoint[endpoint.index(after: lastColon)...]
        return Int(candidate)
    }
}
