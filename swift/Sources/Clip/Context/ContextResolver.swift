import AppKit
import Vision

enum ContextResult {
    case text(String, isOCR: Bool)
    case textWithImage(String, Data, mimeType: String)  // OCR text + source image for vision
    case image(Data, mimeType: String)                  // clipboard image with no extractable text
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
        if var text = pasteboard.string(forType: .string), !text.isEmpty {
            // Browsers and native apps copy both plain text and styled representations.
            // Plain text contains only visible characters — hyperlinks are stripped.
            // Extract href URLs from two sources and merge them:
            //   1. HTML pasteboard type — regex on href= attributes (Chrome, Firefox, web views)
            //   2. RTFD/RTF pasteboard type — NSAttributedString .link attributes
            //      (Safari, Mail, Pages, Word, and other macOS-native apps use RTF)
            var discovered: [String] = []

            // ── Method 1: HTML href= regex ─────────────────────────────────
            let htmlStr: String? = {
                if let data = pasteboard.data(forType: .html) {
                    return String(data: data, encoding: .utf8)
                        ?? String(data: data, encoding: .utf16)       // Safari sometimes uses UTF-16
                        ?? String(data: data, encoding: .isoLatin1)   // last-resort byte-safe decode
                }
                return pasteboard.string(forType: .html)
            }()
            if let html = htmlStr {
                discovered += WebFetcher.extractHrefURLs(from: html)
            }

            // ── Method 2: RTFD / RTF .link attributes ──────────────────────
            discovered += extractLinksFromRichText(pasteboard: pasteboard)

            // Append URLs that are new (not already visible in plain text), deduplicated
            var seen = Set<String>()
            let newURLs = discovered.filter { seen.insert($0).inserted && !text.contains($0) }
            if !newURLs.isEmpty {
                text += "\n" + newURLs.joined(separator: "\n")
            }

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
    /// If OCR succeeds, also attach the source image so the user can optionally send both.
    private static func resolveImage(_ image: NSImage) async -> ContextResult {
        if let ocrText = await tryOCR(on: image) {
            // OCR succeeded — build image result too so user can attach it alongside text
            let imgResult = imageResult(from: image)
            if case .image(let data, let mimeType) = imgResult {
                return .textWithImage(ocrText, data, mimeType: mimeType)
            }
            return .text(ocrText, isOCR: true)
        }
        // OCR found nothing — return raw image so vision models can process it
        return imageResult(from: image)
    }

    /// Returns the OCR text string if text was found, nil otherwise.
    private static func tryOCR(on image: NSImage) async -> String? {
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
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }

    /// Reads RTFD or RTF from the pasteboard and returns every http/https URL
    /// stored in `.link` attributes.  This covers Safari, Mail, Pages, Word, and
    /// any other macOS-native app that places styled text (not HTML) on the clipboard.
    private static func extractLinksFromRichText(pasteboard: NSPasteboard) -> [String] {
        let candidates: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
            (.rtfd, .rtfd),
            (.rtf,  .rtf)
        ]
        for (pbType, docType) in candidates {
            guard let data = pasteboard.data(forType: pbType) else { continue }
            guard let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: docType],
                documentAttributes: nil
            ) else { continue }

            var urls: [String] = []
            attr.enumerateAttribute(.link,
                                    in: NSRange(location: 0, length: attr.length),
                                    options: []) { value, _, _ in
                if let url = value as? URL, url.scheme?.hasPrefix("http") == true {
                    urls.append(url.absoluteString)
                } else if let str = value as? String, str.hasPrefix("http") {
                    urls.append(str)
                }
            }
            if !urls.isEmpty { return urls }   // first rich-text type that has links wins
        }
        return []
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
