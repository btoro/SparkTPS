import Charts
import SparkTPSCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: MetricsMonitor
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if monitor.connectionState == .needsConfiguration || showingSettings {
                EndpointSettingsView(monitor: monitor, isExpanded: $showingSettings)
            } else {
                metricsContent
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { monitor.dismissIdleAlert() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: monitor.statusSymbol)
                .font(.title2)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("SparkTPS")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                monitor.toggleIdleAlert()
            } label: {
                Image(systemName: monitor.idleAlertEnabled ? "bell.fill" : "bell.slash")
                    .foregroundStyle(monitor.idleAlertEnabled ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(monitor.idleAlertEnabled ? "Disable idle alert" : "Enable idle alert")
            .accessibilityLabel(monitor.idleAlertEnabled ? "Idle alert on" : "Idle alert off")
            if case .offline = monitor.connectionState {
                Button("Retry") { monitor.refreshNow() }
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var metricsContent: some View {
        if let snapshot = monitor.snapshot {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    MetricCard(title: "Output TPS", value: format(monitor.summary.outputTPS), tint: .blue)
                    MetricCard(title: "Input TPS", value: format(monitor.summary.inputTPS), tint: .purple)
                    MetricCard(
                        title: "Total TPS",
                        value: format(monitor.summary.outputTPS + monitor.summary.inputTPS),
                        tint: .indigo
                    )
                }

                HStack(spacing: 10) {
                    MetricCard(title: "Active", value: "\(snapshot.activeRequests)", tint: .green)
                    MetricCard(title: "Queued", value: "\(snapshot.queuedRequests)", tint: .orange)
                    MetricCard(title: "Processed 1m", value: "\(monitor.summary.processedLastMinute)", tint: .teal)
                }

                HStack {
                    SmallStat(title: "1m average", value: "\(format(monitor.summary.minuteOutputAverage)) t/s")
                    Spacer()
                    SmallStat(title: "1m peak", value: "\(format(monitor.summary.minuteOutputPeak)) t/s")
                    Spacer()
                    SmallStat(title: "Engine total", value: integer(snapshot.processedRequests))
                }

                historyChart

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.modelNames.joined(separator: ", "))
                        .font(.caption)
                        .lineLimit(2)
                    Text("\(snapshot.engine.rawValue) · aggregate engine throughput")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if case .offline(let message) = monitor.connectionState {
            VStack(spacing: 8) {
                Image(systemName: "network.slash")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Spark unavailable")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
        } else {
            HStack {
                ProgressView()
                Text("Reading inference metrics…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
        }
    }

    @ViewBuilder
    private var historyChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last 60 seconds")
                    .font(.caption.weight(.semibold))
                Spacer()
                Label("Output", systemImage: "circle.fill")
                    .foregroundStyle(.blue)
                Label("Input", systemImage: "circle.fill")
                    .foregroundStyle(.purple)
            }
            .font(.caption2)

            Chart(monitor.historyPoints) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Output TPS", point.outputTPS),
                    series: .value("Series", "Output")
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Input TPS", point.inputTPS),
                    series: .value("Series", "Input")
                )
                .foregroundStyle(.purple)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 105)
        }
    }

    private var footer: some View {
        HStack {
            if let updated = monitor.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(showingSettings ? "Done" : "Settings") {
                showingSettings.toggle()
            }
            .buttonStyle(.borderless)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }

    private var statusText: String {
        switch monitor.connectionState {
        case .needsConfiguration: "Connect to your Spark metrics endpoint"
        case .connecting: "Connecting…"
        case .connected:
            (monitor.snapshot?.queuedRequests ?? 0) > 0 ? "Serving with queued work" : "Connected"
        case .offline(let message): message
        }
    }

    private var statusColor: Color {
        switch monitor.connectionState {
        case .needsConfiguration, .connecting: .secondary
        case .offline: .red
        case .connected:
            (monitor.snapshot?.queuedRequests ?? 0) > 0 ? .orange : .green
        }
    }

    private func format(_ value: Double) -> String {
        if value >= 1_000 { return String(format: "%.1fk", value / 1_000) }
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    private func integer(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct SmallStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }
}
