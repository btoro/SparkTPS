import Foundation
import SparkTPSCore
import SwiftUI

@MainActor
final class MetricsMonitor: ObservableObject {
    enum ConnectionState: Equatable {
        case needsConfiguration
        case connecting
        case connected
        case offline(String)
    }

    @Published private(set) var connectionState: ConnectionState
    @Published private(set) var snapshot: MetricsSnapshot?
    @Published private(set) var summary = MetricsSummary()
    @Published private(set) var historyPoints: [HistoryPoint] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isIdleAlerting = false
    @Published private(set) var flashPhase = false
    @Published var endpoint: String
    @Published var idleAlertEnabled: Bool
    @Published var idleAlertMinutes: Int

    private let client = MetricsClient()
    private var history = MetricsHistory()
    private var idleAlertTracker = IdleAlertTracker()
    private var pollingTask: Task<Void, Never>?
    private var flashingTask: Task<Void, Never>?

    private static let endpointKey = "metricsEndpoint"
    private static let idleAlertEnabledKey = "idleAlertEnabled"
    private static let idleAlertMinutesKey = "idleAlertMinutes"

    init() {
        let savedEndpoint = UserDefaults.standard.string(forKey: Self.endpointKey) ?? ""
        endpoint = savedEndpoint
        idleAlertEnabled = UserDefaults.standard.object(forKey: Self.idleAlertEnabledKey) as? Bool ?? true
        let savedMinutes = UserDefaults.standard.integer(forKey: Self.idleAlertMinutesKey)
        idleAlertMinutes = savedMinutes > 0 ? savedMinutes : 10
        connectionState = savedEndpoint.isEmpty ? .needsConfiguration : .connecting
    }

    deinit {
        pollingTask?.cancel()
        flashingTask?.cancel()
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollingLoop()
        }
    }

    func saveEndpoint(_ newValue: String) {
        endpoint = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(endpoint, forKey: Self.endpointKey)
        history = MetricsHistory()
        historyPoints = []
        summary = MetricsSummary()
        snapshot = nil
        connectionState = endpoint.isEmpty ? .needsConfiguration : .connecting
        restart()
    }

    func saveIdleAlert(enabled: Bool, minutes: Int) {
        idleAlertEnabled = enabled
        idleAlertMinutes = min(max(minutes, 1), 120)
        UserDefaults.standard.set(idleAlertEnabled, forKey: Self.idleAlertEnabledKey)
        UserDefaults.standard.set(idleAlertMinutes, forKey: Self.idleAlertMinutesKey)
        idleAlertTracker.reset(at: Date())
        setIdleAlerting(false)
    }

    func toggleIdleAlert() {
        saveIdleAlert(enabled: !idleAlertEnabled, minutes: idleAlertMinutes)
    }

    func dismissIdleAlert() {
        guard isIdleAlerting else { return }
        idleAlertTracker.dismiss()
        setIdleAlerting(false)
    }

    func refreshNow() {
        restart()
    }

    var menuBarText: String {
        if isIdleAlerting, flashPhase {
            return "🟢 · 🔴 Idle \(idleAlertMinutes)m"
        }
        return regularMenuBarText
    }

    private var regularMenuBarText: String {
        switch connectionState {
        case .needsConfiguration:
            return "🟡 Setup"
        case .connecting:
            return "🟡 … t/s · …r"
        case .offline:
            return "🔴 — t/s · —r"
        case .connected:
            guard let snapshot else { return "🟡 … t/s · …r" }
            let health = snapshot.queuedRequests > 0 ? "🟠" : "🟢"
            return "\(health) \(formatTPS(summary.outputTPS)) t/s · \(snapshot.activeRequests)r"
        }
    }

    var statusSymbol: String {
        switch connectionState {
        case .needsConfiguration: return "gearshape"
        case .connecting: return "bolt"
        case .offline: return "bolt.slash"
        case .connected:
            return (snapshot?.queuedRequests ?? 0) > 0 ? "exclamationmark.bolt.fill" : "bolt.fill"
        }
    }

    private func restart() {
        pollingTask?.cancel()
        pollingTask = nil
        start()
    }

    private func pollingLoop() async {
        while !Task.isCancelled {
            guard !endpoint.isEmpty else {
                connectionState = .needsConfiguration
                return
            }

            do {
                let newSnapshot = try await client.fetch(from: endpoint)
                let previousSnapshot = snapshot
                snapshot = newSnapshot
                summary = history.append(newSnapshot)
                historyPoints = history.points
                lastUpdated = newSnapshot.timestamp
                connectionState = .connected
                updateIdleAlert(previous: previousSnapshot, current: newSnapshot)
            } catch is CancellationError {
                return
            } catch {
                connectionState = .offline(error.localizedDescription)
                setIdleAlerting(false)
            }

            let interval: UInt64
            if case .offline = connectionState {
                interval = 5_000_000_000
            } else {
                let busy = (snapshot?.activeRequests ?? 0) > 0
                    || (snapshot?.queuedRequests ?? 0) > 0
                    || summary.outputTPS >= 0.05
                interval = busy ? 1_000_000_000 : 5_000_000_000
            }
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    private func formatTPS(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    private func updateIdleAlert(previous: MetricsSnapshot?, current: MetricsSnapshot) {
        let countersAdvanced = if let previous {
            current.processedRequests > previous.processedRequests
                || current.generationTokens > previous.generationTokens
                || current.promptTokens > previous.promptTokens
                || (current.realtimeGenerationTokens ?? 0) > (previous.realtimeGenerationTokens ?? 0)
                || (current.realtimePromptTokens ?? 0) > (previous.realtimePromptTokens ?? 0)
        } else {
            false
        }
        let activity = current.activeRequests > 0
            || current.queuedRequests > 0
            || (current.nativeGenerationTPS ?? 0) >= 0.05
            || countersAdvanced
        let shouldAlert = idleAlertTracker.observe(
            activity: activity,
            at: current.timestamp,
            enabled: idleAlertEnabled,
            timeoutMinutes: idleAlertMinutes
        )
        setIdleAlerting(shouldAlert)
    }

    private func setIdleAlerting(_ alerting: Bool) {
        guard isIdleAlerting != alerting else { return }
        isIdleAlerting = alerting
        flashingTask?.cancel()
        flashingTask = nil
        flashPhase = false

        guard alerting else { return }
        flashPhase = true
        flashingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard !Task.isCancelled else { return }
                self?.flashPhase.toggle()
            }
        }
    }
}
