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

        // Activate Clip and refresh the overlay — clipboard is read as-is.
        // No Cmd+C simulation; the user copies text manually before invoking Clip.
        NSApp.activate(ignoringOtherApps: true)
        state.triggerRefresh()
        panel?.makeKeyAndOrderFront(nil)
    }

    func hideOverlay() {
        SpeechPlayer.shared.stop()
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false   // never deallocate via close
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = nil   // follow system light/dark mode

        // Safety net: intercept any close attempt and hide instead.
        panel.delegate = self

        // Hide the native traffic-light buttons — close/minimise/zoom
        // are meaningless for a floating tool panel; we use our own ✕ button.
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let view = OverlayView(state: state, onClose: { [weak self] in self?.hideOverlay() })
            .ignoresSafeArea()
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}

// MARK: - NSWindowDelegate (overlay panel)

extension OverlayWindowController: NSWindowDelegate {
    /// Intercept any close attempt on the main overlay panel.
    /// The panel is hidden (orderOut) rather than destroyed so the app never quits.
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in sender.orderOut(nil) }
        return false
    }
}
