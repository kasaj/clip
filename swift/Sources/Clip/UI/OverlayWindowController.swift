import AppKit
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    @Published var refreshID = UUID()

    func triggerRefresh() {
        refreshID = UUID()
    }
}

@MainActor
final class OverlayWindowController: NSObject {
    private var panel: NSPanel?
    let state = OverlayState()

    func showOverlay() {
        if panel == nil {
            panel = makePanel()
            panel?.center()
        }

        // ① Capture which app is currently frontmost (before Clip activates)
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // ② Simulate ⌘C → sends to source app while it still has focus
        simulateCopy(toPID: targetPID)

        Task { @MainActor in
            // ③ Give the source app ~150 ms to process the copy event
            try? await Task.sleep(nanoseconds: 150_000_000)
            // ④ Now activate Clip so buttons, keyboard focus, etc. all work
            NSApp.activate(ignoringOtherApps: true)
            state.triggerRefresh()
            self.panel?.makeKeyAndOrderFront(nil)
        }
    }

    func hideOverlay() {
        SpeechPlayer.shared.stop()
        panel?.orderOut(nil)
    }

    // MARK: - Private

    /// Post ⌘C to a specific PID so it goes to the right app even if
    /// CGEvent routing has already shifted.
    private func simulateCopy(toPID pid: pid_t?) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)  // 'c'
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        up?.flags = .maskCommand

        if let pid {
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 500),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.isRestorable = false
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = nil   // follow system light/dark mode

        let view = OverlayView(state: state, onClose: { [weak self] in self?.hideOverlay() })
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
