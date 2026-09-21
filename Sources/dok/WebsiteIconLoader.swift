import AppKit
import Foundation
import ImageIO

/// Best-effort website artwork. The saved page URL is never requested: discovery
/// starts at its origin, without the page path, query, fragment, or credentials.
enum WebsiteIconLoader {
    static let maximumHTMLBytes = 128 * 1_024
    static let maximumIconBytes = 512 * 1_024
    static let maximumPNGBytes = 128 * 1_024
    static let iconPixelSize = 128

    /// Returns a small, persistent PNG or nil so callers can keep the URL icon.
    /// Cancelling the calling task also cancels the active network request.
    static func fetch(for url: URL) async -> Data? {
        guard let origin = originURL(for: url), !Task.isCancelled else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        var candidates: [URL] = []

        if let page = await download(origin, maximumBytes: maximumHTMLBytes,
                                     allowsPrefix: true, deadline: deadline),
           page.mimeType == nil || page.mimeType == "text/html" || page.mimeType == "application/xhtml+xml" {
            let html = String(data: page.data, encoding: .utf8)
                ?? String(data: page.data, encoding: .isoLatin1)
                ?? ""
            candidates = Array(iconCandidates(in: html, baseURL: page.url).prefix(2))
        }

        let fallback = origin.appendingPathComponent("favicon.ico")
        if !candidates.contains(fallback) { candidates.append(fallback) }
        for candidate in candidates {
            guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            if let icon = await download(candidate, maximumBytes: maximumIconBytes,
                                         allowsPrefix: false, deadline: deadline),
               let png = pngData(from: icon.data) {
                return Task.isCancelled ? nil : png
            }
        }
        return nil
    }

    static func originURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Deliberately small HTML discovery, with relative href and <base> support.
    /// SVG/mask icons are skipped because persisted artwork must be a bitmap.
    static func iconCandidates(in html: String, baseURL: URL) -> [URL] {
        let boundedHTML = String(html.prefix(maximumHTMLBytes))
            .replacingOccurrences(of: "(?is)<!--.*?-->|<script\\b[^>]*>.*?</script\\s*>",
                                  with: "", options: .regularExpression)
        let documentBase = tags(named: "base", in: boundedHTML).first
            .flatMap { attributes(in: $0)["href"] }
            .flatMap { resourceURL(from: $0, relativeTo: baseURL) } ?? baseURL
        var candidates: [(url: URL, priority: Int, order: Int)] = []
        var seen = Set<URL>()

        for (order, tag) in tags(named: "link", in: boundedHTML).prefix(128).enumerated() {
            let values = attributes(in: tag)
            let relations = Set((values["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            let isTouchIcon = relations.contains("apple-touch-icon") || relations.contains("apple-touch-icon-precomposed")
            guard relations.contains("icon") || isTouchIcon,
                  let href = values["href"],
                  let url = resourceURL(from: href, relativeTo: documentBase),
                  url.pathExtension.lowercased() != "svg",
                  !(values["type"] ?? "").lowercased().contains("svg"),
                  seen.insert(url).inserted else { continue }
            let priority = isTouchIcon ? 2 : (url.pathExtension.lowercased() == "png" ? 1 : 0)
            candidates.append((url, priority, order))
        }
        return candidates.sorted {
            $0.priority == $1.priority ? $0.order < $1.order : $0.priority > $1.priority
        }.map(\.url)
    }

    static func pngData(from data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maximumIconBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        // ICO files can contain several sizes. Decode the largest valid frame,
        // using ImageIO's thumbnail path to avoid allocating a full-size bitmap.
        let frame = (0..<min(CGImageSourceGetCount(source), 32)).compactMap { index -> (Int, Int)? in
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8_192, height <= 8_192,
                  width * height <= 16_777_216 else { return nil }
            return (index, width * height)
        }.max { $0.1 < $1.1 }
        guard let frame,
              let image = CGImageSourceCreateThumbnailAtIndex(source, frame.0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: iconPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              png.count <= maximumPNGBytes else { return nil }
        return png
    }

    private static func tags(named name: String, in html: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: "<\(name)\\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>", options: .caseInsensitive) else { return [] }
        let source = html as NSString
        return expression.matches(in: html, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }

    private static func attributes(in tag: String) -> [String: String] {
        let pattern = #"([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let source = tag as NSString
        var result: [String: String] = [:]
        for match in expression.matches(in: tag, range: NSRange(location: 0, length: source.length)) {
            let name = source.substring(with: match.range(at: 1)).lowercased()
            guard result[name] == nil else { continue }
            for index in 2...4 where match.range(at: index).location != NSNotFound {
                result[name] = source.substring(with: match.range(at: index))
                break
            }
        }
        return result
    }

    private static func resourceURL(from href: String, relativeTo baseURL: URL) -> URL? {
        var decoded = href.trimmingCharacters(in: .whitespacesAndNewlines)
        for (entity, value) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            decoded = decoded.replacingOccurrences(of: entity, with: value)
        }
        guard !decoded.isEmpty,
              let url = URL(string: decoded, relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        components.user = nil
        components.password = nil
        components.fragment = nil
        return components.url
    }

    private struct Download {
        let data: Data
        let url: URL
        let mimeType: String?
    }

    private static func download(_ url: URL, maximumBytes: Int, allowsPrefix: Bool, deadline: TimeInterval) async -> Download? {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0, !Task.isCancelled else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = min(3, remaining)
        configuration.timeoutIntervalForResource = min(3, remaining)
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, timeoutInterval: min(3, remaining))
        request.setValue(allowsPrefix ? "text/html,application/xhtml+xml" : "image/*", forHTTPHeaderField: "Accept")

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                  allowsPrefix || response.expectedContentLength <= Int64(maximumBytes) else { return nil }
            var data = Data()
            data.reserveCapacity(min(maximumBytes, 16 * 1_024))
            for try await byte in bytes {
                if data.count == maximumBytes {
                    guard allowsPrefix else { return nil }
                    break
                }
                data.append(byte)
                if data.count % 4_096 == 0 {
                    try Task.checkCancellation()
                    guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
                }
            }
            guard !Task.isCancelled else { return nil }
            return Download(data: data, url: response.url ?? url, mimeType: response.mimeType?.lowercased())
        } catch {
            return nil
        }
    }

    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
        private var remainingRedirects = 2

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard remainingRedirects > 0, let url = request.url,
                  let sanitized = WebsiteIconLoader.resourceURL(from: url.absoluteString, relativeTo: url) else {
                completionHandler(nil)
                return
            }
            remainingRedirects -= 1
            var redirected = request
            redirected.url = sanitized
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
            redirected.setValue(nil, forHTTPHeaderField: "Cookie")
            completionHandler(redirected)
        }
    }
}
