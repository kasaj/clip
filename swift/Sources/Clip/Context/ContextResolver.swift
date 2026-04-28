import AppKit
import Vision

enum ContextResult {
    case text(String, isOCR: Bool)
    case image(Data, mimeType: String)   // clipboard image with no extractable text
    case error(ContextError)
}

enum ContextError: Error, LocalizedError {
    case empty, ocrFailed
    var errorDescription: String? {
        switch self {
        case .empty:     "Clipboard is empty — copy text or an image first"
        case .ocrFailed: "Could not recognise text in image"
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
            return await resolveImage(image)
        }
        return .error(.empty)
    }

    // MARK: - Selected text (Accessibility API)

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

    // MARK: - Image handling

    /// Try OCR first; if no text is found, return the image itself for vision models.
    private static func resolveImage(_ image: NSImage) async -> ContextResult {
        if let ocrResult = await tryOCR(on: image) {
            return ocrResult
        }
        // OCR found nothing — return raw image so vision models can process it
        return imageResult(from: image)
    }

    /// Returns `.text(ocrText, isOCR: true)` if text was found, nil otherwise.
    private static func tryOCR(on image: NSImage) async -> ContextResult? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty
                else { continuation.resume(returning: nil); return }
                let text = observations
                    .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                if text.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: .text(text, isOCR: true))
                }
            }
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }

    /// Convert NSImage → JPEG Data for vision API.
    private static func imageResult(from image: NSImage) -> ContextResult {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg,
                                               properties: [.compressionFactor: 0.85])
        else { return .error(.ocrFailed) }
        return .image(jpeg, mimeType: "image/jpeg")
    }
}
