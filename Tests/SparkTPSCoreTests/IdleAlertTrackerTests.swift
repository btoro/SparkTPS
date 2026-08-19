import Foundation
import Testing
@testable import SparkTPSCore

@Test func alertsAfterConfiguredIdlePeriod() {
    var tracker = IdleAlertTracker()
    let start = Date(timeIntervalSince1970: 1_000)

    let initiallyAlerting = tracker.observe(activity: false, at: start, enabled: true, timeoutMinutes: 10)
    let beforeThreshold = tracker.observe(
        activity: false,
        at: start.addingTimeInterval(599),
        enabled: true,
        timeoutMinutes: 10
    )
    let atThreshold = tracker.observe(
        activity: false,
        at: start.addingTimeInterval(600),
        enabled: true,
        timeoutMinutes: 10
    )
    #expect(!initiallyAlerting)
    #expect(!beforeThreshold)
    #expect(atThreshold)
}

@Test func dismissalLastsUntilActivityResumes() {
    var tracker = IdleAlertTracker()
    let start = Date(timeIntervalSince1970: 2_000)

    _ = tracker.observe(activity: false, at: start, enabled: true, timeoutMinutes: 1)
    let firstAlert = tracker.observe(
        activity: false,
        at: start.addingTimeInterval(60),
        enabled: true,
        timeoutMinutes: 1
    )
    #expect(firstAlert)
    tracker.dismiss()
    let afterDismissal = tracker.observe(
        activity: false,
        at: start.addingTimeInterval(120),
        enabled: true,
        timeoutMinutes: 1
    )
    #expect(!afterDismissal)

    let resumed = tracker.observe(
        activity: true,
        at: start.addingTimeInterval(121),
        enabled: true,
        timeoutMinutes: 1
    )
    let nextBeforeThreshold = tracker.observe(
        activity: false,
        at: start.addingTimeInterval(180),
        enabled: true,
        timeoutMinutes: 1
    )
    let nextAlert = tracker.observe(
        activity: false,
        at: start.addingTimeInterval(181),
        enabled: true,
        timeoutMinutes: 1
    )
    #expect(!resumed)
    #expect(!nextBeforeThreshold)
    #expect(nextAlert)
}

@Test func disabledAlertNeverFires() {
    var tracker = IdleAlertTracker()
    let start = Date(timeIntervalSince1970: 3_000)

    let initiallyAlerting = tracker.observe(activity: false, at: start, enabled: false, timeoutMinutes: 1)
    let laterAlerting = tracker.observe(
        activity: false,
        at: start.addingTimeInterval(3_600),
        enabled: false,
        timeoutMinutes: 1
    )
    #expect(!initiallyAlerting)
    #expect(!laterAlerting)
}
