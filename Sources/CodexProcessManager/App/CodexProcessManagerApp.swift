import SwiftUI

@main
struct CodexProcessManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences = AppPreferences()
    @StateObject private var monitor: ProcessMonitor

    init() {
        let preferences = AppPreferences()
        let monitor = ProcessMonitor(preferences: preferences)
        _preferences = StateObject(wrappedValue: preferences)
        _monitor = StateObject(wrappedValue: monitor)
        ApplicationController.shared.configure(preferences: preferences, monitor: monitor)
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(preferences)
                .environmentObject(monitor)
                .frame(width: 620, height: 520)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("打开详情") {
                    ApplicationController.shared.showMainWindow()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("立即刷新") {
                    Task { await monitor.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
