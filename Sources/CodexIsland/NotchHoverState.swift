import Foundation

/// Pointer timing only. Pass a monotonic clock, such as systemUptime, and reset
/// the value when display geometry changes. Hidden surface bounds never open it.
struct NotchHoverState {
    private static let dwell: TimeInterval = 0.18
    private static let leaveGrace: TimeInterval = 0.35

    private var visible = false
    private var enteredAt: TimeInterval?
    private var leftAt: TimeInterval?
    private var suppressed = false

    mutating func sample(insideApproach: Bool, insideSurface: Bool,
                         mouseDown: Bool, now: TimeInterval) -> Bool {
        if suppressed {
            if !insideApproach && !insideSurface { suppressed = false }
            return false
        }

        if visible {
            if insideApproach || insideSurface {
                leftAt = nil
            } else {
                if leftAt == nil { leftAt = now }
                if let leftAt, now >= leftAt + Self.leaveGrace {
                    visible = false
                    self.leftAt = nil
                }
            }
            return visible
        }

        // Dragging through the notch must not reveal controls. After release,
        // require a fresh dwell instead of inheriting time spent dragging.
        guard insideApproach, !mouseDown else {
            enteredAt = nil
            return false
        }
        if enteredAt == nil { enteredAt = now }
        if let enteredAt, now >= enteredAt + Self.dwell {
            visible = true
            self.enteredAt = nil
        }
        return visible
    }

    mutating func suppressUntilExit() {
        visible = false
        enteredAt = nil
        leftAt = nil
        suppressed = true
    }
}
