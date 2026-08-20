import Foundation
import Testing
@testable import SparkTPSCore

@Suite("SQLite metrics history")
struct MetricsStoreTests {
    @Test func recordsSamplesAndDailyPeak() async throws {
        let store = try MetricsStore(databaseURL: temporaryDatabaseURL(), calendar: calendar())
        let date = Date(timeIntervalSince1970: 1_750_000_000)

        _ = try await store.record(
            snapshot: snapshot(at: date),
            summary: summary(output: 12, input: 3)
        )
        let day = try await store.record(
            snapshot: snapshot(at: date.addingTimeInterval(6)),
            summary: summary(output: 27, input: 4)
        )

        #expect(try await store.sampleCount() == 2)
        #expect(day.peak == DailyTPSPeak(outputTPS: 27, inputTPS: 4, totalTPS: 31))
    }

    @Test func coalescesSamplesWithinFiveSecondBucketWithoutLosingPeak() async throws {
        let store = try MetricsStore(databaseURL: temporaryDatabaseURL(), calendar: calendar())
        let date = Date(timeIntervalSince1970: 1_750_000_000)

        _ = try await store.record(
            snapshot: snapshot(at: date),
            summary: summary(output: 42, input: 2)
        )
        let day = try await store.record(
            snapshot: snapshot(at: date.addingTimeInterval(1)),
            summary: summary(output: 10, input: 1)
        )

        #expect(try await store.sampleCount() == 1)
        #expect(day.peak.outputTPS == 42)
    }

    @Test func tracksTokenDeltasAcrossLaunchesAndCounterResets() async throws {
        let databaseURL = temporaryDatabaseURL()
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        var store: MetricsStore? = try MetricsStore(databaseURL: databaseURL, calendar: calendar())

        _ = try await store?.record(
            snapshot: snapshot(at: date, generation: 100, prompt: 50),
            summary: summary(output: 1, input: 1),
            source: "spark"
        )
        _ = try await store?.record(
            snapshot: snapshot(at: date.addingTimeInterval(6), generation: 130, prompt: 80),
            summary: summary(output: 1, input: 1),
            source: "spark"
        )
        store = nil

        let reopened = try MetricsStore(databaseURL: databaseURL, calendar: calendar())
        _ = try await reopened.record(
            snapshot: snapshot(at: date.addingTimeInterval(12), generation: 5, prompt: 4),
            summary: summary(output: 1, input: 1),
            source: "spark"
        )
        let day = try await reopened.record(
            snapshot: snapshot(at: date.addingTimeInterval(18), generation: 15, prompt: 14),
            summary: summary(output: 1, input: 1),
            source: "spark"
        )

        #expect(day.usage == DailyTokenUsage(inputTokens: 40, outputTokens: 40))
        let estimatedCost = day.usage.estimatedCost(inputPricePerMillion: 1, outputPricePerMillion: 6)
        #expect(abs(estimatedCost - 0.00028) < 0.0000001)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("history.sqlite")
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func summary(output: Double, input: Double) -> MetricsSummary {
        var summary = MetricsSummary()
        summary.outputTPS = output
        summary.inputTPS = input
        return summary
    }

    private func snapshot(
        at date: Date,
        generation: Double = 100,
        prompt: Double = 50
    ) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: date,
            engine: .sglang,
            modelNames: ["test"],
            generationTokens: generation,
            promptTokens: prompt,
            processedRequests: 2,
            activeRequests: 1,
            queuedRequests: 0,
            nativeGenerationTPS: nil
        )
    }
}
