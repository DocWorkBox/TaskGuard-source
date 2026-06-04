import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var monitor: ProcessMonitor

    var body: some View {
        Form {
            Section("扫描") {
                HStack {
                    Slider(value: $preferences.scanIntervalSeconds, in: 60...600, step: 5) {
                        Text("扫描间隔")
                    }
                    Text("\(Int(preferences.scanIntervalSeconds)) 秒")
                        .frame(width: 56, alignment: .trailing)
                        .monospacedDigit()
                }

                Toggle("显示 Codex 内部支撑进程", isOn: $preferences.showsCodexInternals)

                HStack {
                    Text("开发端口范围")
                    TextField("3000-9000", text: $preferences.portRangeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }

            Section("识别规则") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("开发命令关键字")
                    TextEditor(text: $preferences.commandKeywordsText)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("白名单关键字或路径")
                    TextEditor(text: $preferences.whitelistText)
                        .font(.body.monospaced())
                        .frame(minHeight: 90)
                    Text("命令行、工作目录或可执行名包含这些内容时不会自动建议关闭。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("关闭流程") {
                HStack {
                    Slider(value: $preferences.terminateWaitSeconds, in: 1...10, step: 1) {
                        Text("SIGTERM 等待")
                    }
                    Text("\(Int(preferences.terminateWaitSeconds)) 秒")
                        .frame(width: 56, alignment: .trailing)
                        .monospacedDigit()
                }
            }

            Section {
                HStack {
                    Button("恢复默认") {
                        preferences.reset()
                    }

                    Spacer()

                    Button("应用并刷新") {
                        Task { await monitor.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
