import Foundation

public struct HistoryPoint: Identifiable, Sendable, Equatable {
    public let id: Date
    public let timestamp: Date
    public let outputTPS: Double
    public let inputTPS: Double
    public let activeRequests: Int

    public init(timestamp: Date, outputTPS: Double, inputTPS: Double, activeRequests: Int) {
        self.id = timestamp
        self.timestamp = timestamp
        self.outputTPS = outputTPS
        self.inputTPS = inputTPS
        self.activeRequests = activeRequests
    }
}

public struct MetricsSummary: Sendable, Equatable {
    public var outputTPS: Double = 0
    public var inputTPS: Double = 0
    public var minuteOutputAverage: Double = 0
    public var minuteOutputPeak: Double = 0
    public var processedLastMinute: Int = 0

    public init() {}
}

public struct MetricsHistory: Sendable {
    private var snapshots: [MetricsSnapshot] = []
    public private(set) var points: [HistoryPoint] = []

    public init() {}

    @discardableResult
    public mutating func append(_ snapshot: MetricsSnapshot) -> MetricsSummary {
        if let previous = snapshots.last, countersReset(from: previous, to: snapshot) {
            snapshots.removeAll(keepingCapacity: true)
            points.removeAll(keepingCapacity: true)
        }

        if let previous = snapshots.last {
            let elapsed = snapshot.timestamp.timeIntervalSince(previous.timestamp)
            if elapsed > 0 {
                let outputTPS = snapshot.nativeGenerationTPS
                    ?? counterRate(from: previous, to: snapshot, kind: .generation)
                points.append(
                    HistoryPoint(
                        timestamp: snapshot.timestamp,
                        outputTPS: max(0, outputTPS),
                        inputTPS: counterRate(from: previous, to: snapshot, kind: .prompt),
                        activeRequests: snapshot.activeRequests
                    )
                )
            }
        }

        snapshots.append(snapshot)
        trim(relativeTo: snapshot.timestamp)
        return summary(at: snapshot.timestamp)
    }

    public func summary(at now: Date) -> MetricsSummary {
        var result = MetricsSummary()
        guard let newest = snapshots.last else { return result }

        let recentNativeTPS = snapshots
            .filter { now.timeIntervalSince($0.timestamp) <= 5 }
            .compactMap(\.nativeGenerationTPS)
        if recentNativeTPS.isEmpty {
            result.outputTPS = rate(kind: .generation, over: 5, at: now)
        } else {
            result.outputTPS = recentNativeTPS.reduce(0, +) / Double(recentNativeTPS.count)
        }
        result.inputTPS = rate(kind: .prompt, over: 5, at: now)
        result.minuteOutputAverage = rate(kind: .generation, over: 60, at: now)
        if result.minuteOutputAverage == 0 {
            let minuteNativeTPS = snapshots
                .filter { now.timeIntervalSince($0.timestamp) <= 60 }
                .compactMap(\.nativeGenerationTPS)
            if !minuteNativeTPS.isEmpty {
                result.minuteOutputAverage = minuteNativeTPS.reduce(0, +) / Double(minuteNativeTPS.count)
            }
        }
        result.minuteOutputPeak = points
            .filter { now.timeIntervalSince($0.timestamp) <= 60 }
            .map(\.outputTPS)
            .max() ?? 0

        if let oldest = snapshots.first(where: { now.timeIntervalSince($0.timestamp) <= 60 }) {
            result.processedLastMinute = Int(nonnegativeDelta(newest.processedRequests, oldest.processedRequests).rounded())
        }
        return result
    }

    private enum CounterKind {
        case generation
        case prompt
    }

    private func rate(kind: CounterKind, over window: TimeInterval, at now: Date) -> Double {
        guard let newest = snapshots.last else { return 0 }
        let cutoff = now.addingTimeInterval(-window)
        let oldest = snapshots.last(where: { $0.timestamp <= cutoff }) ?? snapshots.first
        guard let oldest, newest.timestamp > oldest.timestamp else { return 0 }
        return counterRate(from: oldest, to: newest, kind: kind)
    }

    private func counterRate(from old: MetricsSnapshot, to new: MetricsSnapshot, kind: CounterKind) -> Double {
        let elapsed = new.timestamp.timeIntervalSince(old.timestamp)
        guard elapsed > 0 else { return 0 }

        let oldValue: Double
        let newValue: Double
        switch kind {
        case .generation:
            oldValue = old.realtimeGenerationTokens ?? old.generationTokens
            newValue = new.realtimeGenerationTokens ?? new.generationTokens
        case .prompt:
            oldValue = old.realtimePromptTokens ?? old.promptTokens
            newValue = new.realtimePromptTokens ?? new.promptTokens
        }
        return nonnegativeDelta(newValue, oldValue) / elapsed
    }

    private func countersReset(from old: MetricsSnapshot, to new: MetricsSnapshot) -> Bool {
        let standardCountersReset = new.generationTokens < old.generationTokens
            || new.promptTokens < old.promptTokens
            || new.processedRequests < old.processedRequests
        let realtimeGenerationReset: Bool
        if let oldValue = old.realtimeGenerationTokens, let newValue = new.realtimeGenerationTokens {
            realtimeGenerationReset = newValue < oldValue
        } else {
            realtimeGenerationReset = false
        }
        let realtimePromptReset: Bool
        if let oldValue = old.realtimePromptTokens, let newValue = new.realtimePromptTokens {
            realtimePromptReset = newValue < oldValue
        } else {
            realtimePromptReset = false
        }
        return standardCountersReset || realtimeGenerationReset || realtimePromptReset
    }

    private mutating func trim(relativeTo now: Date) {
        snapshots.removeAll { now.timeIntervalSince($0.timestamp) > 65 }
        points.removeAll { now.timeIntervalSince($0.timestamp) > 60 }
    }

    private func nonnegativeDelta(_ new: Double, _ old: Double) -> Double {
        max(0, new - old)
    }
}
