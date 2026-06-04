import Darwin
import Foundation

public protocol ResourceUsageSampling: AnyObject {
    func sample(pids: [Int32]) -> [Int32: ProcessResourceUsage]
}

public final class ProcessResourceSampler: ResourceUsageSampling {
    private var previousSamples: [Int32: ResourceSample] = [:]
    private let physicalMemoryBytes: Double

    public init(physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        self.physicalMemoryBytes = max(1, Double(physicalMemoryBytes))
    }

    public func sample(pids: [Int32]) -> [Int32: ProcessResourceUsage] {
        let now = Date()
        let uniquePIDs = Array(Set(pids))
        var usages: [Int32: ProcessResourceUsage] = [:]
        var livePIDs: Set<Int32> = []

        for pid in uniquePIDs {
            guard let sample = readSample(pid: pid, now: now) else { continue }
            livePIDs.insert(pid)

            guard let previous = previousSamples[pid] else {
                previousSamples[pid] = sample
                continue
            }

            let elapsed = max(0.001, sample.checkedAt.timeIntervalSince(previous.checkedAt))
            let cpuDelta = max(0, sample.totalCPUTime - previous.totalCPUTime)
            let cpuPercent = (cpuDelta / elapsed) * 100
            let memoryPercent = max(0, Double(sample.residentMemoryBytes) / physicalMemoryBytes * 100)
            usages[pid] = ProcessResourceUsage(
                pid: pid,
                cpuPercent: cpuPercent,
                memoryPercent: memoryPercent
            )
            previousSamples[pid] = sample
        }

        previousSamples = previousSamples.filter { livePIDs.contains($0.key) }
        return usages
    }

    private func readSample(pid: Int32, now: Date) -> ResourceSample? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPointer)
            }
        }
        guard result == 0 else { return nil }

        let userSeconds = Double(info.ri_user_time) / 1_000_000_000
        let systemSeconds = Double(info.ri_system_time) / 1_000_000_000

        return ResourceSample(
            totalCPUTime: userSeconds + systemSeconds,
            residentMemoryBytes: info.ri_resident_size,
            checkedAt: now
        )
    }

    private struct ResourceSample {
        let totalCPUTime: Double
        let residentMemoryBytes: UInt64
        let checkedAt: Date
    }
}
