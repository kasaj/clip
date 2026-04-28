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
        // Simulate ⌘C so selected text lands in clipboard before the panel appears.
        // If clipboard changes → ContextResolver picks up the new content.
        // If nothing was selected → clipboard stays unchanged, old content is used.
        simulateCopy()

        Task { @MainActor in
            // Give the source app ~130 ms to process the copy event
            try? await Task.sleep(nanoseconds: 130_000_000)
            state.triggerRefresh()
            self.panel?.makeKeyAndOrderFront(nil)
        }
    }

    func hideOverlay() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func simulateCopy() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)  // 'c'
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
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

        let view = OverlayView(state: state, onClose: { [weak self] in self?.hideOverlay() })
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
