import AppKit
import ApplicationServices

/// 从 QQ 音乐播放栏的辅助功能描述读取曲名与歌手。
///
/// QQ 音乐约 0.7s 后才把新曲目报告给系统（MediaRemote），自己的播放栏约 0.3s 就已更新，
/// 描述形如 `歌曲名：宏愿 - 歌手名：周柏豪`。这里只用于切歌后提前拿到曲名；
/// 封面、进度、播放状态仍以 MediaRemote 为准。读不到（无辅助功能权限、QQ 改版、
/// 英文界面）时返回 nil，调用方照常等待 MediaRemote，不会出错。
final class QQMusicTitleReader {
    static let bundleIdentifier = "com.tencent.QQMusicMac"

    private static let titlePrefix = "歌曲名："
    private static let artistSeparator = " - 歌手名："
    /// 实测播放栏位于 应用 → 窗口 → 子元素 → 子元素（深度 3）。
    private static let searchDepth = 4
    /// QQ 每个元素的辅助功能调用约 6ms，限制遍历规模并放到后台。
    private static let searchLimit = 400
    private static let readTimeout: Float = 0.05

    private var element: AXUIElement?
    private var elementPID: pid_t = 0
    private var isSearching = false
    private let queue = DispatchQueue(label: "dok.qqmusic.title", qos: .userInitiated)

    /// 后台定位并缓存播放栏元素；已缓存且仍有效时不重复遍历。
    func prepare() {
        guard AXIsProcessTrusted(), !isSearching,
              let app = NSRunningApplication.runningApplications(
                  withBundleIdentifier: Self.bundleIdentifier
              ).first(where: { !$0.isTerminated }) else { return }
        let pid = app.processIdentifier
        if elementPID == pid, read() != nil { return }

        isSearching = true
        queue.async { [weak self] in
            let found = Self.locate(in: AXUIElementCreateApplication(pid))
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSearching = false
                self.element = found
                self.elementPID = pid
            }
        }
    }

    /// 读取当前曲名与歌手（单次约 0.1ms）。元素失效时丢弃缓存并返回 nil。
    func read() -> (title: String, artist: String)? {
        guard let element else { return nil }
        guard let text = Self.description(of: element), let parsed = Self.parse(text) else {
            self.element = nil
            return nil
        }
        return parsed
    }

    static func parse(_ text: String) -> (title: String, artist: String)? {
        guard text.hasPrefix(titlePrefix),
              let separator = text.range(of: artistSeparator) else { return nil }
        let titleStart = text.index(text.startIndex, offsetBy: titlePrefix.count)
        guard titleStart <= separator.lowerBound else { return nil }
        let title = String(text[titleStart..<separator.lowerBound])
        guard !title.isEmpty else { return nil }
        return (title, String(text[separator.upperBound...]))
    }

    private static func locate(in root: AXUIElement) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(root, 0.25)
        var frontier = [root]
        var visited = 0
        for _ in 0...searchDepth {
            var next: [AXUIElement] = []
            for element in frontier {
                visited += 1
                guard visited <= searchLimit else { return nil }
                if let text = description(of: element), parse(text) != nil {
                    AXUIElementSetMessagingTimeout(element, readTimeout)
                    return element
                }
                var value: AnyObject?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
                   let children = value as? [AXUIElement] {
                    next.append(contentsOf: children)
                }
            }
            frontier = next
        }
        return nil
    }

    private static func description(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
