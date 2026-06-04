import AppKit
import Combine
import Darwin
import SwiftUI

@MainActor
final class ApplicationController: NSObject, NSWindowDelegate {
    static let shared = ApplicationController()

    private weak var preferences: AppPreferences?
    private weak var monitor: ProcessMonitor?
    private var statusItem: NSStatusItem?
    private var statusBadgeLayer: CALayer?
    private var statusPopover: NSPopover?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func configure(preferences: AppPreferences, monitor: ProcessMonitor) {
        self.preferences = preferences
        self.monitor = monitor
    }

    func launch() {
        installLowImpactScheduling()
        NSApp.setActivationPolicy(.regular)
        installApplicationIcon()
        installStatusItem()
        installStatusObservers()
        showMainWindow()
        monitor?.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installLowImpactScheduling() {
        _ = setpriority(PRIO_PROCESS, 0, 20)
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
        if notification.object as? NSWindow === mainWindow {
            mainWindow = nil
            if settingsWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        } else if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
            if mainWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
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
            installStatusBadge(on: button)
        }

        statusItem = item
        updateStatusItem()
    }

    private func installStatusBadge(on button: NSStatusBarButton) {
        button.wantsLayer = true

        let badge = CALayer()
        badge.cornerRadius = 4
        badge.borderWidth = 1.5
        badge.borderColor = NSColor.windowBackgroundColor.cgColor
        button.layer?.addSublayer(badge)
        statusBadgeLayer = badge
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

        button.title = ""
        button.imagePosition = .imageOnly
        statusItem?.length = 28

        if let monitor {
            let summary = monitor.summary
            updateStatusBadge(hasSuggestedCleanup: summary.suggestedCleanupCount > 0)
            button.toolTip = "Codex TaskGuard：服务 \(summary.serviceCount)，建议 \(summary.suggestedCleanupCount)，端口 \(summary.listeningPortCount)"
        } else {
            updateStatusBadge(hasSuggestedCleanup: false)
            button.toolTip = "Codex TaskGuard"
        }
    }

    private func updateStatusBadge(hasSuggestedCleanup: Bool) {
        guard let button = statusItem?.button, let badge = statusBadgeLayer else { return }

        let badgeSize: CGFloat = 8
        let x = button.bounds.maxX - badgeSize - 3
        let y = button.bounds.midY + 2
        badge.frame = CGRect(x: x, y: y, width: badgeSize, height: badgeSize)
        badge.backgroundColor = (hasSuggestedCleanup ? NSColor.systemOrange : NSColor.systemGreen).cgColor
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
        guard let preferences, let monitor else { return }
        NSApp.setActivationPolicy(.regular)

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = SettingsView()
            .environmentObject(preferences)
            .environmentObject(monitor)
            .frame(width: 620, height: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.center()
        window.contentViewController = NSHostingController(rootView: content)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
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
