import CodexProcessManagerCore
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @State private var showsCleanupConfirmation = false

    private var visibleGroups: [ServiceGroup] {
        Array(monitor.snapshot.groups.prefix(5))
    }

    private var longRunningGroups: [ServiceGroup] {
        monitor.snapshot.groups.filter {
            $0.risk != .protected && $0.longestElapsedSeconds >= 2 * 60 * 60
        }
    }

    private var totalCPU: Double {
        monitor.snapshot.groups.reduce(0) { $0 + $1.totalCPU }
    }

    private var totalMemory: Double {
        monitor.snapshot.groups.reduce(0) { $0 + $1.totalMemory }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            metrics
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            if !alerts.isEmpty {
                alertList
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            Divider()

            actionGrid
                .padding(14)

            Divider()

            recentGroups
                .padding(14)

            Divider()

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background(.regularMaterial)
        .confirmationDialog(
            "关闭建议清理项？",
            isPresented: $showsCleanupConfirmation
        ) {
            Button("关闭 \(monitor.suggestedPlan.targets.count) 个进程", role: .destructive) {
                Task {
                    await monitor.cleanSuggested()
                    ApplicationController.shared.closeStatusPopover()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将先发送 SIGTERM。未退出的进程会保留，需要再次确认后才能强制关闭。")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex TaskGuard")
                    .font(.headline)
                Text(monitor.lastError ?? monitor.lastActivity)
                    .font(.caption)
                    .foregroundStyle(monitor.lastError == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                ResourceUsageBadge(cpu: totalCPU, memory: totalMemory)

                if monitor.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            MenuMetric(title: "服务", value: "\(monitor.summary.serviceCount)")
            MenuMetric(title: "建议", value: "\(monitor.summary.suggestedCleanupCount)")
            MenuMetric(title: "端口", value: "\(monitor.summary.listeningPortCount)")
            MenuMetric(title: "高 CPU", value: "\(monitor.summary.highCPUCount)")
        }
    }

    private var alerts: [String] {
        var items: [String] = []
        if monitor.summary.suggestedCleanupCount > 0 {
            items.append("\(monitor.summary.suggestedCleanupCount) 组疑似残留可清理")
        }
        if monitor.summary.highCPUCount > 0 {
            items.append("\(monitor.summary.highCPUCount) 组进程 CPU 偏高")
        }
        if let longest = longRunningGroups.map(\.longestElapsedSeconds).max() {
            items.append("\(longRunningGroups.count) 组已运行超过 2 小时，最长 \(formatAlertDuration(longest))")
        }
        if monitor.isPaused {
            items.append("自动扫描已暂停")
        }
        return items
    }

    private var alertList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(alerts, id: \.self) { alert in
                Label(alert, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private var actionGrid: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                menuButton("打开详情", systemImage: "sidebar.right") {
                    ApplicationController.shared.showMainWindow()
                    ApplicationController.shared.closeStatusPopover()
                }

                menuButton("刷新", systemImage: "arrow.clockwise") {
                    Task { await monitor.refresh() }
                }
                .disabled(monitor.isRefreshing)
            }

            GridRow {
                menuButton(monitor.isPaused ? "恢复扫描" : "暂停扫描", systemImage: monitor.isPaused ? "play" : "pause") {
                    monitor.togglePause()
                }

                menuButton("清理建议项", systemImage: "trash") {
                    showsCleanupConfirmation = true
                }
                .disabled(monitor.suggestedPlan.isEmpty)
            }
        }
    }

    private func menuButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var recentGroups: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近服务组")
                .font(.subheadline.weight(.semibold))

            if visibleGroups.isEmpty {
                Text("暂无扫描结果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleGroups) { group in
                        Button {
                            monitor.selectedGroupID = group.id
                            ApplicationController.shared.showMainWindow()
                            ApplicationController.shared.closeStatusPopover()
                        } label: {
                            MenuGroupRow(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                ApplicationController.shared.showMainWindow()
                ApplicationController.shared.closeStatusPopover()
            } label: {
                footerLabel("打开", systemImage: "macwindow")
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Button {
                ApplicationController.shared.showSettingsWindow()
                ApplicationController.shared.closeStatusPopover()
            } label: {
                footerLabel("设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Button {
                ApplicationController.shared.quit()
            } label: {
                footerLabel("退出", systemImage: "power")
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func footerLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
            .contentShape(Rectangle())
    }

    private func formatAlertDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

private struct MenuMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct MenuGroupRow: View {
    let group: ServiceGroup

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            ResourceUsageBadge(cpu: group.totalCPU, memory: group.totalMemory)

            Text(group.risk.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(iconColor)
                .frame(width: 44, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = ["\(group.processCount) 进程"]
        if !group.listeningPorts.isEmpty {
            parts.append(":\(group.listeningPorts.map(String.init).joined(separator: ", :"))")
        }
        return parts.joined(separator: "  ")
    }

    private var iconName: String {
        switch group.ownership {
        case .codexThread: return "bubble.left.and.text.bubble.right"
        case .codexWorkspace: return "folder"
        case .codexInternal: return "gearshape.2"
        case .developmentService: return "terminal"
        case .listeningPort: return "network"
        case .unownedDevelopment: return "questionmark.app"
        case .protected: return "lock.shield"
        }
    }

    private var iconColor: Color {
        switch group.risk {
        case .suggestedCleanup: return .orange
        case .needsReview: return .blue
        case .protected: return .secondary
        }
    }
}

private struct ResourceUsageBadge: View {
    let cpu: Double
    let memory: Double

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            usageLine(title: "CPU", value: cpu)
            usageLine(title: "内存", value: memory)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 86, alignment: .trailing)
        .accessibilityLabel("CPU \(format(cpu))，内存 \(format(memory))")
    }

    private func usageLine(title: String, value: Double) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.tertiary)
            Text(format(value))
                .fontWeight(value >= 25 ? .semibold : .medium)
                .foregroundStyle(value >= 25 ? Color.orange : Color.secondary)
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}
