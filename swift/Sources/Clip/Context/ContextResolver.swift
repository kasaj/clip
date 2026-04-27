import AppKit
import Vision

enum ContextResult {
    case text(String, isOCR: Bool)
    case error(ContextError)
}

enum ContextError: Error, LocalizedError {
    case empty, ocrFailed
    var errorDescription: String? {
        switch self {
        case .empty:     "Zkopíruj text nebo obrázek do schránky (⌘C)"
        case .ocrFailed: "Text nebyl rozpoznán"
        }
    }
}

enum ContextResolver {

    // MARK: - Clipboard

    static func resolve() async -> ContextResult {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text, isOCR: false)
        }
        if let image = NSImage(pasteboard: pasteboard) {
            return await performOCR(on: image)
        }
        return .error(.empty)
    }

    // MARK: - Selected text (Accessibility API)
    // Must be called BEFORE the overlay window steals focus.

    /// Synchronous — call on main thread at hotkey time, before panel appears.
    static func captureSelectedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard let appEl = focusedApp else { return nil }
        var focusedEl: AnyObject?
        AXUIElementCopyAttributeValue(appEl as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedEl)
        guard let el = focusedEl else { return nil }
        var text: AnyObject?
        AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextAttribute as CFString, &text)
        let result = text as? String
        return (result?.isEmpty == false) ? result : nil
    }

    // MARK: - OCR

    private static func performOCR(on image: NSImage) async -> ContextResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .error(.ocrFailed)
        }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty
                else { continuation.resume(returning: .error(.ocrFailed)); return }
                let text = observations
                    .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text.isEmpty ? .error(.ocrFailed) : .text(text, isOCR: true))
            }
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }
}
