import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var overlayWindowController: OverlayWindowController?
    private var settingsWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var hotkeyState = HotkeyState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in self?.showOverlay() }
        }
        hotkeyManager?.register()
        NotificationCenter.default.addObserver(
            forName: .hotkeyDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager?.reregister()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Clip")
            }
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()

        let headerItem = NSMenuItem()
        let headerView = NSHostingView(rootView: MenuHeaderView(hotkeyState: hotkeyState))
        headerView.frame = NSRect(x: 0, y: 0, width: 240, height: 40)
        headerItem.view = headerView
        menu.addItem(headerItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Clip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusMenu = menu
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            statusItem?.menu = statusMenu
            sender.performClick(nil)
            statusItem?.menu = nil
        } else {
            showOverlay()
        }
    }

    @objc private func openSettings() {
        overlayWindowController?.hideOverlay()
        // Always create a fresh SettingsView so it reads current ConfigStore state.
        // If the window is already visible just bring it to front; otherwise rebuild it
        // so a stale @State snapshot is never shown.
        if settingsWindowController?.window?.isVisible == true {
            settingsWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clip"
        window.isRestorable = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        settingsWindowController = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func showOverlay() {
        if overlayWindowController == nil {
            overlayWindowController = OverlayWindowController()
        }
        overlayWindowController?.showOverlay()
    }
}

private struct MenuHeaderView: View {
    @ObservedObject var hotkeyState: HotkeyState

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clip").font(.headline)
                Text(hotkeyState.displayString).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
