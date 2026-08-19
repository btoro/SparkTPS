import SwiftUI

@main
struct SparkTPSApp: App {
    @StateObject private var monitor = MetricsMonitor()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(monitor: monitor)
        } label: {
            Text(monitor.menuBarText)
                .monospacedDigit()
                .foregroundStyle(monitor.isIdleAlerting && monitor.flashPhase ? Color.red : Color.primary)
                .task { monitor.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
