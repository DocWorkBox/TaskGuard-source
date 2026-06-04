import AppKit
import Combine
import SwiftUI

@MainActor
final class ApplicationController: NSObject, NSWindowDelegate {
    static let shared = ApplicationController()

    private weak var preferences: AppPreferences?
    private weak var monitor: ProcessMonitor?
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var mainWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func configure(preferences: AppPreferences, monitor: ProcessMonitor) {
        self.preferences = preferences
        self.monitor = monitor
    }

    func launch() {
        NSApp.setActivationPolicy(.regular)
        installApplicationIcon()
        installStatusItem()
        installStatusObservers()
        showMainWindow()
        monitor?.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMainWindow() {
        guard let preferences, let monitor else { return }
        NSApp.setActivationPolicy(.regular)

        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = ContentView()
            .environmentObject(preferences)
            .environmentObject(monitor)
            .frame(minWidth: 1080, minHeight: 680)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex TaskGuard"
        window.center()
        window.contentViewController = NSHostingController(rootView: content)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        mainWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === mainWindow else { return }
        mainWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func installApplicationIcon() {
        if let icon = NSImage(named: "TaskGuardIcon") {
            NSApp.applicationIconImage = icon
        } else if let fallback = NSImage(systemSymbolName: "checkmark.shield", accessibilityDescription: "Codex TaskGuard") {
            NSApp.applicationIconImage = fallback
        }
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true

        let image = NSImage(
            systemSymbolName: "checkmark.shield",
            accessibilityDescription: "Codex TaskGuard"
        )
        image?.isTemplate = true

        if let button = item.button {
            button.image = image
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Codex TaskGuard"
        }

        statusItem = item
        updateStatusItem()
    }

    private func installStatusObservers() {
        guard cancellables.isEmpty, let monitor else { return }

        monitor.$snapshot
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        monitor.$isRefreshing
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        monitor.$isPaused
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        monitor.$lastError
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        if let monitor {
            let summary = monitor.summary
            let prefix: String
            if monitor.lastError != nil {
                prefix = "!"
            } else if monitor.isPaused {
                prefix = "||"
            } else if monitor.isRefreshing {
                prefix = "..."
            } else {
                prefix = "\(summary.serviceCount)"
            }

            if summary.suggestedCleanupCount > 0 {
                button.title = " TG \(prefix)/\(summary.suggestedCleanupCount)"
            } else {
                button.title = " TG \(prefix)"
            }
            button.sizeToFit()
            statusItem?.length = max(58, min(96, button.intrinsicContentSize.width + 12))
            button.toolTip = "Codex TaskGuard：服务 \(summary.serviceCount)，建议 \(summary.suggestedCleanupCount)，端口 \(summary.listeningPortCount)"
        } else {
            button.title = " TG"
            button.sizeToFit()
            statusItem?.length = 58
            button.toolTip = "Codex TaskGuard"
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        toggleStatusPopover()
    }

    private func toggleStatusPopover() {
        guard let button = statusItem?.button else { return }

        if let popover = statusPopover, popover.isShown {
            popover.performClose(nil)
            return
        }

        guard let preferences, let monitor else { return }

        let content = MenuBarContentView()
            .environmentObject(preferences)
            .environmentObject(monitor)
            .frame(width: 360)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 460)
        popover.contentViewController = NSHostingController(rootView: content)
        statusPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func closeStatusPopover() {
        statusPopover?.performClose(nil)
    }

    func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc func cleanSuggestedFromMenuBar() {
        Task {
            await monitor?.cleanSuggested()
            closeStatusPopover()
        }
    }

    @objc private func openDetails() {
        showMainWindow()
        closeStatusPopover()
    }

    @objc private func refreshNow() {
        Task { await monitor?.refresh() }
    }

    @objc private func togglePause() {
        monitor?.togglePause()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
