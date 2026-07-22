import AppKit
import ApplicationServices

struct DockNotificationBadgeSnapshot: Equatable {
    static let empty = DockNotificationBadgeSnapshot()

    fileprivate var byPath: [String: String] = [:]
    fileprivate var byBundleIdentifier: [String: String] = [:]
    fileprivate var byTitle: [String: String] = [:]

    func badge(for app: AppItem) -> String? {
        guard app.itemType == .app, app.isRunning else { return nil }

        if let badge = byPath[Self.normalizedPath(app.path)] {
            return badge
        }
        if !app.bundleIdentifier.isEmpty,
           let badge = byBundleIdentifier[app.bundleIdentifier] {
            return badge
        }
        return byTitle[Self.normalizedTitle(app.displayName)]
            ?? byTitle[Self.normalizedTitle(app.name)]
    }

    fileprivate mutating func insert(badge: String, url: URL?, title: String?) {
        guard !badge.isEmpty else { return }

        if let url {
            byPath[Self.normalizedPath(url.path)] = badge
            if let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
               !bundleIdentifier.isEmpty {
                byBundleIdentifier[bundleIdentifier] = badge
            }
        }
        if let title, !title.isEmpty {
            byTitle[Self.normalizedTitle(title)] = badge
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private static func normalizedTitle(_ title: String) -> String {
        var normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasSuffix(".app") {
            normalized.removeLast(4)
        }
        return normalized.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}

enum DockNotificationBadgeReader {
    static let timeout: TimeInterval = 0.1

    private static let queue = DispatchQueue(
        label: "com.qingshan.orbis.dock-notification-badges",
        qos: .userInitiated
    )

    private final class SnapshotBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValue: DockNotificationBadgeSnapshot = .empty

        func store(_ value: DockNotificationBadgeSnapshot) {
            lock.lock()
            storedValue = value
            lock.unlock()
        }

        func value() -> DockNotificationBadgeSnapshot {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
    }

    static func snapshot(timeout: TimeInterval = timeout) -> DockNotificationBadgeSnapshot {
        // Never request permission here. An untrusted app silently has no badges.
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.dock")
                .first else {
            return .empty
        }

        let box = SnapshotBox()
        let completion = DispatchSemaphore(value: 0)
        let deadline = Date().addingTimeInterval(timeout)

        queue.async {
            box.store(readDock(processIdentifier: dock.processIdentifier, deadline: deadline))
            completion.signal()
        }

        guard completion.wait(timeout: .now() + timeout) == .success else {
            return .empty
        }
        return box.value()
    }

    private static func readDock(
        processIdentifier: pid_t,
        deadline: Date
    ) -> DockNotificationBadgeSnapshot {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, Float(max(deadline.timeIntervalSinceNow, 0.001)))

        var snapshot = DockNotificationBadgeSnapshot.empty
        var pending: [(element: AXUIElement, depth: Int)] = [(application, 0)]
        var visited = 0

        while let next = pending.popLast(), Date() < deadline, visited < 512 {
            visited += 1
            AXUIElementSetMessagingTimeout(
                next.element,
                Float(max(deadline.timeIntervalSinceNow, 0.001))
            )

            let status = stringAttribute("AXStatusLabel", from: next.element)
            if let status, !status.isEmpty {
                snapshot.insert(
                    badge: status,
                    url: urlAttribute(kAXURLAttribute as String, from: next.element),
                    title: stringAttribute(kAXTitleAttribute as String, from: next.element)
                )
            }

            guard next.depth < 8,
                  let children = attribute(kAXChildrenAttribute as String, from: next.element)
                    as? [AXUIElement] else {
                continue
            }
            pending.append(contentsOf: children.map { ($0, next.depth + 1) })
        }

        return Date() < deadline ? snapshot : .empty
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        guard let value = attribute(name, from: element) else { return nil }
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func urlAttribute(_ name: String, from element: AXUIElement) -> URL? {
        guard let value = attribute(name, from: element) else { return nil }
        if let url = value as? URL {
            return url
        }
        if let string = value as? String {
            return URL(string: string) ?? URL(fileURLWithPath: string)
        }
        return nil
    }
}
