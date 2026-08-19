import Foundation

public struct IdleAlertTracker: Sendable {
    public private(set) var lastActivityAt: Date?
    public private(set) var isDismissedForCurrentIdlePeriod = false

    public init() {}

    public mutating func observe(
        activity: Bool,
        at now: Date,
        enabled: Bool,
        timeoutMinutes: Int
    ) -> Bool {
        if activity {
            lastActivityAt = now
            isDismissedForCurrentIdlePeriod = false
            return false
        }

        guard enabled else { return false }
        if lastActivityAt == nil {
            lastActivityAt = now
            return false
        }
        guard !isDismissedForCurrentIdlePeriod else { return false }

        let timeout = TimeInterval(max(1, timeoutMinutes) * 60)
        return now.timeIntervalSince(lastActivityAt!) >= timeout
    }

    public mutating func dismiss() {
        isDismissedForCurrentIdlePeriod = true
    }

    public mutating func reset(at now: Date) {
        lastActivityAt = now
        isDismissedForCurrentIdlePeriod = false
    }
}
