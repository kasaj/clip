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

        // ① Try Accessibility API first — synchronous, no keyboard event needed.
        //    Works when Accessibility permission is granted AND the source app supports AX.
        if let selectedText = ContextResolver.captureSelectedText(), !selectedText.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedText, forType: .string)
        } else {
            // ② Inject ⌘C into the HID stream via .cghidEventTap — no Accessibility needed.
            //    Source app is still frontmost so it receives the event naturally.
            //    If nothing is selected the app ignores Cmd+C and clipboard stays unchanged.
            simulateCopy()
        }

        Task { @MainActor in
            // ④ Give the source app ~150 ms to process the copy event
            try? await Task.sleep(nanoseconds: 150_000_000)
            // ⑤ Now activate Clip so buttons, keyboard focus, etc. all work
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

    /// Simulate ⌘C by injecting into the HID event stream.
    /// Using .cghidEventTap (not postToPid) so it works without Accessibility permission —
    /// the source app is still frontmost when this is called, so it receives the event.
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
        panel.appearance = nil   // follow system light/dark mode

        // Hide the native traffic-light buttons — close/minimise/zoom
        // are meaningless for a floating tool panel; we use our own ✕ button.
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let view = OverlayView(state: state, onClose: { [weak self] in self?.hideOverlay() })
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
