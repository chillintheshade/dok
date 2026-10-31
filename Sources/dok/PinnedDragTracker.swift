import AppKit

enum PinnedDragEvent {
    case began
    case moved(dx: CGFloat, dy: CGFloat)
}

enum PinnedDragResult {
    case click
    case dragged
}

/// 区分点击和拖动：按下后移动不到阈值，松手算点击；超过就算拖动，这次不触发任何动作。
struct PinnedDragTracker {
    static let threshold: CGFloat = 4

    private var pressPoint: NSPoint?
    private var lastPoint: NSPoint = .zero
    private(set) var isDragging = false
    var isPressed: Bool { pressPoint != nil }

    mutating func press(at point: NSPoint) {
        pressPoint = point
        lastPoint = point
        isDragging = false
    }

    mutating func move(to point: NSPoint) -> PinnedDragEvent? {
        guard let start = pressPoint else { return nil }
        if !isDragging {
            guard hypot(point.x - start.x, point.y - start.y) > Self.threshold else { return nil }
            isDragging = true
            lastPoint = point
            return .began
        }
        let event = PinnedDragEvent.moved(dx: point.x - lastPoint.x, dy: point.y - lastPoint.y)
        lastPoint = point
        return event
    }

    mutating func release() -> PinnedDragResult {
        defer { cancel() }
        return isDragging ? .dragged : .click
    }

    mutating func cancel() {
        pressPoint = nil
        isDragging = false
    }

    /// 让内容留在某块屏幕的可见区域内。不在任何屏幕上时，回到最近的一块。
    static func clampedCenter(_ center: NSPoint,
                              radius: CGFloat,
                              bottomExtra: CGFloat = 0,
                              screens: [NSRect]) -> NSPoint {
        func distance(to rect: NSRect) -> CGFloat {
            hypot(max(rect.minX - center.x, 0, center.x - rect.maxX),
                  max(rect.minY - center.y, 0, center.y - rect.maxY))
        }
        guard let screen = screens.min(by: { distance(to: $0) < distance(to: $1) }) else { return center }
        return NSPoint(
            x: min(max(center.x, screen.minX + radius), max(screen.maxX - radius, screen.minX + radius)),
            y: min(max(center.y, screen.minY + radius + bottomExtra),
                   max(screen.maxY - radius, screen.minY + radius + bottomExtra))
        )
    }
}
