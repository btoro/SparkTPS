import Foundation
import Testing
@testable import SparkTPSCore

@Test func parsesAndAggregatesSGLangMetrics() throws {
    let text = """
    # HELP sglang:generation_tokens_total Number of generation tokens processed.
    sglang:generation_tokens_total{is_streaming="false",model_name="qwen"} 100
    sglang:generation_tokens_total{is_streaming="true",model_name="qwen"} 250
    sglang:prompt_tokens_total{is_streaming="false",model_name="qwen"} 400
    sglang:prompt_tokens_total{is_streaming="true",model_name="qwen"} 600
    sglang:num_requests_total{is_streaming="false",model_name="qwen"} 4
    sglang:num_requests_total{is_streaming="true",model_name="qwen"} 6
    sglang:num_running_reqs{model_name="qwen"} 2
    sglang:num_queue_reqs{model_name="qwen"} 1
    sglang:gen_throughput{model_name="qwen"} 42.5
    sglang:realtime_tokens_total{mode="decode",model_name="qwen"} 345
    sglang:realtime_tokens_total{mode="prefill_compute",model_name="qwen"} 987
    sglang:realtime_tokens_total{mode="prefill_cache",model_name="qwen"} 222
    """

    let snapshot = try PrometheusParser().parse(text, timestamp: Date(timeIntervalSince1970: 1))
    #expect(snapshot.engine == .sglang)
    #expect(snapshot.modelNames == ["qwen"])
    #expect(snapshot.generationTokens == 350)
    #expect(snapshot.promptTokens == 1_000)
    #expect(snapshot.processedRequests == 10)
    #expect(snapshot.activeRequests == 2)
    #expect(snapshot.queuedRequests == 1)
    #expect(snapshot.nativeGenerationTPS == 42.5)
    #expect(snapshot.realtimeGenerationTokens == 345)
    #expect(snapshot.realtimePromptTokens == 987)
}

@Test func parsesVLLMMetrics() throws {
    let text = """
    vllm:generation_tokens_total{model_name="llama"} 700
    vllm:prompt_tokens_total{model_name="llama"} 1200
    vllm:request_success_total{finished_reason="stop",model_name="llama"} 8
    vllm:request_success_total{finished_reason="length",model_name="llama"} 2
    vllm:num_requests_running{model_name="llama"} 3
    vllm:num_requests_waiting{model_name="llama"} 4
    """

    let snapshot = try PrometheusParser().parse(text)
    #expect(snapshot.engine == .vllm)
    #expect(snapshot.generationTokens == 700)
    #expect(snapshot.promptTokens == 1_200)
    #expect(snapshot.processedRequests == 10)
    #expect(snapshot.activeRequests == 3)
    #expect(snapshot.queuedRequests == 4)
}

@Test func normalizesEndpointURL() {
    let client = MetricsClient()
    #expect(client.normalizedURL(from: "spark.local:8000")?.absoluteString == "http://spark.local:8000/metrics")
    #expect(client.normalizedURL(from: "https://spark.example/metrics")?.absoluteString == "https://spark.example/metrics")
    #expect(client.normalizedURL(from: "not a host") == nil)
}
