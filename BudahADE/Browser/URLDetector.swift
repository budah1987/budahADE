import Foundation

/// Detects localhost and loopback URLs in text (stdout, chat, terminal output).
/// Used by DevServerManager to populate BrowserState.detectedURLs.
enum URLDetector {

    // http(s)://localhost or 127.0.0.1, optional port and path
    private static let schemePattern = try! NSRegularExpression(
        pattern: #"https?://(?:localhost|127\.0\.0\.1)(?::\d{1,5})?(?:/\S*)?"#
    )

    // bare localhost:PORT — requires at least 2-digit port to reduce false positives
    // negative lookbehind: not preceded by word char, colon, or slash
    private static let barePattern = try! NSRegularExpression(
        pattern: #"(?<![:\w/])localhost:(\d{2,5})(?:/\S*)?"#
    )

    /// Extract all unique localhost URLs from text. Preserves order, deduplicates by lowercased string.
    static func detect(in text: String) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()

        func add(_ raw: String) {
            let key = raw.lowercased()
            guard !seen.contains(key), let url = URL(string: raw) else { return }
            seen.insert(key)
            found.append(url)
        }

        let range = NSRange(text.startIndex..., in: text)

        schemePattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let r = Range(match.range, in: text) else { return }
            add(String(text[r]))
        }

        barePattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let r = Range(match.range, in: text) else { return }
            add("http://\(text[r])")
        }

        return found
    }
}
