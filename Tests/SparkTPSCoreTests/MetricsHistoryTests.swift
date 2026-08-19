import Foundation
import Testing
@testable import SparkTPSCore

@Test func calculatesRollingRatesAndRequestCounts() {
    var history = MetricsHistory()
    let origin = Date(timeIntervalSince1970: 10_000)

    _ = history.append(snapshot(at: origin, generation: 100, prompt: 1_000, requests: 10, active: 1))
    _ = history.append(snapshot(at: origin.addingTimeInterval(2), generation: 140, prompt: 1_200, requests: 11, active: 2))
    let summary = history.append(snapshot(at: origin.addingTimeInterval(5), generation: 200, prompt: 1_500, requests: 13, active: 1))

    #expect(summary.outputTPS == 20)
    #expect(summary.inputTPS == 100)
    #expect(summary.processedLastMinute == 3)
    #expect(summary.minuteOutputPeak == 20)
}

@Test func resetsHistoryWhenEngineCountersReset() {
    var history = MetricsHistory()
    let origin = Date(timeIntervalSince1970: 20_000)

    _ = history.append(snapshot(at: origin, generation: 500, prompt: 900, requests: 20, active: 0))
    let summary = history.append(snapshot(at: origin.addingTimeInterval(1), generation: 10, prompt: 20, requests: 1, active: 1))

    #expect(summary.outputTPS == 0)
    #expect(summary.processedLastMinute == 0)
    #expect(history.points.isEmpty)
}

@Test func smoothsNativeSGLangTPSAndUsesRealtimePrefillCounter() {
    var history = MetricsHistory()
    let origin = Date(timeIntervalSince1970: 30_000)

    _ = history.append(liveSnapshot(at: origin, nativeTPS: 30, realtimePrompt: 1_000))
    _ = history.append(liveSnapshot(at: origin.addingTimeInterval(1), nativeTPS: 60, realtimePrompt: 1_100))
    let summary = history.append(
        liveSnapshot(at: origin.addingTimeInterval(2), nativeTPS: 45, realtimePrompt: 1_300)
    )

    #expect(summary.outputTPS == 45)
    #expect(summary.inputTPS == 150)
    #expect(summary.minuteOutputPeak == 60)
}

private func snapshot(
    at date: Date,
    generation: Double,
    prompt: Double,
    requests: Double,
    active: Int
) -> MetricsSnapshot {
    MetricsSnapshot(
        timestamp: date,
        engine: .sglang,
        modelNames: ["test"],
        generationTokens: generation,
        promptTokens: prompt,
        processedRequests: requests,
        activeRequests: active,
        queuedRequests: 0,
        nativeGenerationTPS: nil
    )
}

private func liveSnapshot(at date: Date, nativeTPS: Double, realtimePrompt: Double) -> MetricsSnapshot {
    MetricsSnapshot(
        timestamp: date,
        engine: .sglang,
        modelNames: ["test"],
        generationTokens: 0,
        promptTokens: 0,
        processedRequests: 0,
        activeRequests: 1,
        queuedRequests: 0,
        nativeGenerationTPS: nativeTPS,
        realtimeGenerationTokens: nil,
        realtimePromptTokens: realtimePrompt
    )
}
