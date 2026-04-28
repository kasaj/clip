import Foundation

/// Mirrors the logic of python/fetch.py:
/// - URL detection via the same regex pattern
/// - Normalize URL (add https:// if missing)
/// - Fetch HTML with a browser User-Agent
/// - Strip script/style/nav/footer/header/aside tags, strip remaining HTML tags,
///   collapse blank lines, trim to maxChars
enum WebFetcher {

    // MARK: - URL detection (matches python/fetch.py _URL_RE)

    private static let urlRegex = try! NSRegularExpression(
        pattern: #"^(https?://\S+|www\.\S+|[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}(/\S*)?)$"#,
        options: .caseInsensitive
    )

    static func isURL(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let range = NSRange(t.startIndex..., in: t)
        return urlRegex.firstMatch(in: t, range: range) != nil
    }

    // MARK: - URL extraction from arbitrary text

    /// Regex that finds http/https URLs embedded anywhere in text.
    private static let embeddedURLRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"')\]]+"#,
        options: .caseInsensitive
    )

    /// Returns all http/https URLs found inside `text`.
    static func extractURLs(from text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return embeddedURLRegex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            // Trim trailing punctuation that is unlikely to be part of the URL
            return String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)\"'"))
        }
    }

    /// True if `text` contains at least one http/https URL (not necessarily the whole string).
    static func containsAnyURL(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return embeddedURLRegex.firstMatch(in: text, range: range) != nil
    }

    // MARK: - Fetch

    /// Fetches a web page and returns its plain-text content (≤ maxChars).
    /// Throws URLError or HTTP errors on failure.
    static func fetch(_ raw: String, maxChars: Int = 12_000) async throws -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "https://" + s }
        guard let url = URL(string: s) else { throw URLError(.badURL) }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }

        // Detect encoding from Content-Type header or fall back to UTF-8
        var encoding: String.Encoding = .utf8
        if let ct = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
           let charsetRange = ct.range(of: "charset=", options: .caseInsensitive) {
            let charsetStr = String(ct[charsetRange.upperBound...])
                .components(separatedBy: ";").first?
                .trimmingCharacters(in: .whitespaces) ?? "utf-8"
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charsetStr as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
            }
        }
        let html = String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return extractText(from: html, maxChars: maxChars)
    }

    // MARK: - HTML → plain text

    private static func extractText(from html: String, maxChars: Int) -> String {
        var t = html

        // Remove noisy block-level tags and their content
        // (mirrors Python: soup(["script","style","nav","footer","header","aside"]) → decompose())
        for tag in ["script", "style", "nav", "footer", "header", "aside"] {
            t = t.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: " ", options: .regularExpression
            )
        }

        // Strip remaining tags (keep text nodes)
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&nbsp;",  " "),
            ("&amp;",   "&"),
            ("&lt;",    "<"),
            ("&gt;",    ">"),
            ("&quot;",  "\""),
            ("&#39;",   "'"),
            ("&apos;",  "'"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;","…"),
        ]
        for (entity, char) in entities { t = t.replacingOccurrences(of: entity, with: char) }

        // Collapse blank lines (mirrors Python: lines.strip() + filter non-empty)
        let lines = t.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return String(lines.joined(separator: "\n").prefix(maxChars))
    }
}
