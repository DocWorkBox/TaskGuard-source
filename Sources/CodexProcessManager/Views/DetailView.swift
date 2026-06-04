import CodexProcessManagerCore
import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @State private var showsCloseConfirmation = false

    let group: ServiceGroup?

    var body: some View {
        ScrollView {
            if let group {
                VStack(alignment: .leading, spacing: 18) {
                    header(group)
                    summary(group)
                    recommendation(group)
                    evidence(group)
                    processTree(group)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    "选择一个服务组",
                    systemImage: "sidebar.right",
                    description: Text("左侧选择范围，中间选择服务组后查看详情。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            }
        }
        .navigationTitle(group?.title ?? "详情")
    }

    private func header(_ group: ServiceGroup) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(group.title)
                    .font(.title2.weight(.semibold))
                Text(group.ownership.displayName)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                RiskBadge(risk: group.risk)
                if group.risk != .protected {
                    Button(role: .destructive) {
                        showsCloseConfirmation = true
                    } label: {
                        Label("关闭此组", systemImage: "xmark.octagon")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .help("关闭当前详情中的非保护服务组；会先发送 SIGTERM")
                }
            }
        }
        .confirmationDialog(
            "关闭当前服务组？",
            isPresented: $showsCloseConfirmation
        ) {
            Button("关闭当前组", role: .destructive) {
                Task { await monitor.closeSelectedGroup() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将先发送 SIGTERM。未退出的进程会保留，需要再次确认后才能强制关闭。")
        }
    }

    private func summary(_ group: ServiceGroup) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                MetricView(title: "进程", value: "\(group.processCount)")
                MetricView(title: "端口", value: group.listeningPorts.isEmpty ? "-" : group.listeningPorts.map(String.init).joined(separator: ", "))
                MetricView(title: "CPU", value: String(format: "%.1f%%", group.totalCPU))
                MetricView(title: "内存", value: String(format: "%.1f%%", group.totalMemory))
            }
            GridRow {
                MetricView(title: "最长运行", value: formatDuration(group.longestElapsedSeconds))
                MetricView(title: "置信度", value: "\(Int(group.confidence * 100))%")
                MetricView(title: "线程/会话", value: group.threadHint?.displayTitle ?? group.threadHint?.threadId ?? "-")
                MetricView(title: "来源", value: group.threadHint?.source.displayName ?? "-")
            }
        }
    }

    private func recommendation(_ group: ServiceGroup) -> some View {
        SectionBlock(title: "关闭建议", systemImage: "hand.raised") {
            VStack(alignment: .leading, spacing: 8) {
                Label(group.recommendedAction.title, systemImage: group.recommendedAction.isSelectedByDefault ? "checkmark.circle" : "circle")
                    .font(.headline)
                Text(group.recommendedAction.reason)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if group.risk != .protected {
                    Text("也可以使用右上角的“关闭此组”按钮。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func evidence(_ group: ServiceGroup) -> some View {
        SectionBlock(title: "关联依据", systemImage: "link") {
            VStack(alignment: .leading, spacing: 6) {
                if let cwd = group.cwd {
                    LabeledContent("工作目录", value: cwd)
                        .textSelection(.enabled)
                }

                if group.evidence.isEmpty {
                    Text("没有足够证据自动清理。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(group.evidence, id: \.self) { item in
                        Label(item, systemImage: "checkmark")
                    }
                }
            }
        }
    }

    private func processTree(_ group: ServiceGroup) -> some View {
        SectionBlock(title: "进程树", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(group.processes) { process in
                    ProcessDetailRow(process: process)
                    if process.pid != group.processes.last?.pid {
                        Divider()
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "-" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
                .lineLimit(1)
        }
        .frame(minWidth: 110, alignment: .leading)
    }
}

private struct SectionBlock<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProcessDetailRow: View {
    let process: ManagedProcess

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PID \(process.pid)")
                    .font(.headline.monospacedDigit())
                Text("PPID \(process.ppid)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if !process.listeningPorts.isEmpty {
                    Text(":\(process.listeningPorts.map(String.init).joined(separator: ", :"))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(process.commandLine)
                .font(.caption.monospaced())
                .textSelection(.enabled)

            if let cwd = process.cwd {
                Text(cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Text("用户 \(process.user)")
                Text("状态 \(process.state)")
                Text("运行 \(process.elapsed)")
                Text(String(format: "CPU %.1f%%", process.cpuPercent))
                Text(String(format: "内存 %.1f%%", process.memoryPercent))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
