import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @State private var filter: SidebarFilter = .all
    @State private var showsCleanupConfirmation = false
    @State private var showsSelectedGroupConfirmation = false
    @State private var showsForceKillConfirmation = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $filter)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } content: {
            GroupListView(
                groups: monitor.groups(for: filter),
                selectedGroupID: $monitor.selectedGroupID
            )
            .navigationSplitViewColumnWidth(min: 330, ideal: 380)
        } detail: {
            DetailView(group: monitor.selectedGroup)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await monitor.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .immediateTooltip(monitor.isRefreshing ? "正在扫描进程和监听端口" : "立即重新扫描 Codex 相关进程、开发服务和监听端口")
                .disabled(monitor.isRefreshing)
                .help(monitor.isRefreshing ? "正在扫描进程和监听端口" : "立即重新扫描 Codex 相关进程、开发服务和监听端口")

                Button {
                    monitor.togglePause()
                } label: {
                    Label(monitor.isPaused ? "恢复" : "暂停", systemImage: monitor.isPaused ? "play" : "pause")
                }
                .immediateTooltip(monitor.isPaused ? "恢复按设置间隔自动扫描" : "暂停自动扫描；手动刷新仍可使用")
                .help(monitor.isPaused ? "恢复按设置间隔自动扫描" : "暂停自动扫描；手动刷新仍可使用")

                Button {
                    showsCleanupConfirmation = true
                } label: {
                    Label("清理建议项", systemImage: "trash")
                }
                .immediateTooltip(monitor.suggestedPlan.isEmpty ? "当前没有高置信建议清理项" : "关闭默认勾选的高置信无用进程；执行前会再次确认")
                .disabled(monitor.suggestedPlan.isEmpty)
                .help(monitor.suggestedPlan.isEmpty ? "当前没有高置信建议清理项" : "关闭默认勾选的高置信无用进程；执行前会再次确认")

                Button {
                    showsSelectedGroupConfirmation = true
                } label: {
                    Label("关闭当前组", systemImage: "xmark.octagon")
                }
                .immediateTooltip(canCloseSelectedGroup ? "关闭当前选中的非保护服务组；执行前会再次确认" : "当前没有可关闭的服务组，或选中项受保护")
                .disabled(!canCloseSelectedGroup)
                .help(canCloseSelectedGroup ? "关闭当前选中的非保护服务组；执行前会再次确认" : "当前没有可关闭的服务组，或选中项受保护")

                Button {
                    ApplicationController.shared.showSettingsWindow()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .immediateTooltip("打开扫描间隔、识别规则、白名单和关闭流程设置")
                .help("打开扫描间隔、识别规则、白名单和关闭流程设置")
            }
        }
        .safeAreaInset(edge: .bottom) {
            StatusBarView(showsForceKillConfirmation: $showsForceKillConfirmation)
        }
        .confirmationDialog(
            "关闭建议清理项？",
            isPresented: $showsCleanupConfirmation
        ) {
            Button("关闭 \(monitor.suggestedPlan.targets.count) 个进程", role: .destructive) {
                Task { await monitor.cleanSuggested() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将先发送 SIGTERM。未退出的进程会保留，需要再次确认后才能强制关闭。")
        }
        .confirmationDialog(
            "关闭当前服务组？",
            isPresented: $showsSelectedGroupConfirmation
        ) {
            Button("关闭当前组", role: .destructive) {
                Task { await monitor.closeSelectedGroup() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只关闭当前选中的非保护服务组。将先发送 SIGTERM，未退出时可再强制关闭。")
        }
        .confirmationDialog(
            "强制关闭未退出进程？",
            isPresented: $showsForceKillConfirmation
        ) {
            Button("发送 SIGKILL", role: .destructive) {
                Task { await monitor.forceKillStillRunning() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会处理刚才 SIGTERM 后仍在运行的进程。")
        }
        .task {
            monitor.start()
        }
    }

    private var canCloseSelectedGroup: Bool {
        guard let group = monitor.selectedGroup else { return false }
        return group.risk != .protected
    }
}

private struct StatusBarView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @Binding var showsForceKillConfirmation: Bool

    private var stillRunningCount: Int {
        monitor.lastTerminationResults.filter { $0.status == .stillRunning }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("V\(appVersion)")
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if monitor.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(monitor.lastError ?? monitor.lastActivity)
                .lineLimit(1)
                .foregroundStyle(monitor.lastError == nil ? Color.secondary : Color.red)

            Spacer()

            Text("服务 \(monitor.summary.serviceCount)")
            Text("建议 \(monitor.summary.suggestedCleanupCount)")
            Text("端口 \(monitor.summary.listeningPortCount)")

            if stillRunningCount > 0 {
                Button("强制关闭 \(stillRunningCount) 个") {
                    showsForceKillConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .immediateTooltip("对刚才 SIGTERM 后仍未退出的进程发送 SIGKILL")
                .help("对刚才 SIGTERM 后仍未退出的进程发送 SIGKILL")
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
