import AppKit
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    @Published var refreshID = UUID()
    /// Selected text captured at hotkey time, before overlay steals focus.
    var capturedSelectedText: String?

    func triggerRefresh(selectedText: String? = nil) {
        capturedSelectedText = selectedText
        refreshID = UUID()
    }
}

@MainActor
final class OverlayWindowController: NSObject {
    private var panel: NSPanel?
    let state = OverlayState()
    var onOpenSettings: (() -> Void)?

    func showOverlay() {
        if panel == nil {
            panel = makePanel()
            panel?.center()
        }
        // Capture selected text BEFORE panel takes focus (accessibility reads active app)
        let selectedText = ContextResolver.captureSelectedText()
        state.triggerRefresh(selectedText: selectedText)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hideOverlay() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .hudWindow, .resizable],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.isRestorable = false
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = OverlayView(state: state, onClose: { [weak self] in
            self?.hideOverlay()
        }, onOpenSettings: { [weak self] in
            self?.hideOverlay()
            self?.onOpenSettings?()
        })
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
