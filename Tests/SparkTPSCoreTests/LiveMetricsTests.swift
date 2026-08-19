import Foundation
import Testing
@testable import SparkTPSCore

@Test func parsesLiveMetricsEndpointWhenConfigured() async throws {
    guard let endpoint = ProcessInfo.processInfo.environment["SPARKTPS_LIVE_METRICS_URL"],
          !endpoint.isEmpty else {
        return
    }

    let snapshot = try await MetricsClient().fetch(from: endpoint)
    #expect(snapshot.engine != .unknown)
    #expect(!snapshot.modelNames.isEmpty)
    #expect(snapshot.generationTokens >= 0)
    #expect(snapshot.promptTokens >= 0)
    #expect(snapshot.processedRequests >= 0)
    #expect(snapshot.activeRequests >= 0)
    #expect(snapshot.queuedRequests >= 0)
}
