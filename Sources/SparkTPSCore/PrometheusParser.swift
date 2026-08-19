import Foundation

public enum InferenceEngine: String, Sendable {
    case sglang = "SGLang"
    case vllm = "vLLM"
    case unknown = "Unknown"
}

public struct MetricsSnapshot: Sendable, Equatable {
    public let timestamp: Date
    public let engine: InferenceEngine
    public let modelNames: [String]
    public let generationTokens: Double
    public let promptTokens: Double
    public let processedRequests: Double
    public let activeRequests: Int
    public let queuedRequests: Int
    public let nativeGenerationTPS: Double?
    public let realtimeGenerationTokens: Double?
    public let realtimePromptTokens: Double?

    public init(
        timestamp: Date,
        engine: InferenceEngine,
        modelNames: [String],
        generationTokens: Double,
        promptTokens: Double,
        processedRequests: Double,
        activeRequests: Int,
        queuedRequests: Int,
        nativeGenerationTPS: Double?,
        realtimeGenerationTokens: Double? = nil,
        realtimePromptTokens: Double? = nil
    ) {
        self.timestamp = timestamp
        self.engine = engine
        self.modelNames = modelNames
        self.generationTokens = generationTokens
        self.promptTokens = promptTokens
        self.processedRequests = processedRequests
        self.activeRequests = activeRequests
        self.queuedRequests = queuedRequests
        self.nativeGenerationTPS = nativeGenerationTPS
        self.realtimeGenerationTokens = realtimeGenerationTokens
        self.realtimePromptTokens = realtimePromptTokens
    }
}

public enum PrometheusParseError: LocalizedError {
    case unsupportedMetrics

    public var errorDescription: String? {
        switch self {
        case .unsupportedMetrics:
            "No supported SGLang or vLLM inference metrics were found."
        }
    }
}

public struct PrometheusParser: Sendable {
    public init() {}

    public func parse(_ text: String, timestamp: Date = Date()) throws -> MetricsSnapshot {
        var values: [String: Double] = [:]
        var models = Set<String>()
        var sawSGLang = false
        var sawVLLM = false
        var realtimeGenerationTokens: Double?
        var realtimePromptTokens: Double?

        for rawLine in text.split(whereSeparator: \Character.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let space = line.lastIndex(where: { $0 == " " || $0 == "\t" }) else { continue }

            let descriptor = String(line[..<space])
            let valueText = line[line.index(after: space)...]
            guard let value = Double(valueText), value.isFinite else { continue }

            let metricName = descriptor.split(separator: "{", maxSplits: 1).first.map(String.init) ?? descriptor
            guard metricName.hasPrefix("sglang:") || metricName.hasPrefix("vllm:") else { continue }

            sawSGLang = sawSGLang || metricName.hasPrefix("sglang:")
            sawVLLM = sawVLLM || metricName.hasPrefix("vllm:")
            values[metricName, default: 0] += value

            if metricName == "sglang:realtime_tokens_total" {
                switch label(named: "mode", in: descriptor) {
                case "decode":
                    realtimeGenerationTokens = (realtimeGenerationTokens ?? 0) + value
                case "prefill_compute":
                    realtimePromptTokens = (realtimePromptTokens ?? 0) + value
                default:
                    break
                }
            }

            if let model = label(named: "model_name", in: descriptor), !model.isEmpty {
                models.insert(model)
            }
        }

        let engine: InferenceEngine
        let prefix: String
        if sawSGLang {
            engine = .sglang
            prefix = "sglang:"
        } else if sawVLLM {
            engine = .vllm
            prefix = "vllm:"
        } else {
            throw PrometheusParseError.unsupportedMetrics
        }

        let generation = values[prefix + "generation_tokens_total"] ?? values[prefix + "generation_tokens"] ?? 0
        let prompt = values[prefix + "prompt_tokens_total"] ?? values[prefix + "prompt_tokens"] ?? 0

        let processed: Double
        let active: Double
        let queued: Double
        if engine == .sglang {
            processed = values["sglang:num_requests_total"] ?? values["sglang:num_requests"] ?? 0
            active = values["sglang:num_running_reqs"] ?? 0
            queued = values["sglang:num_queue_reqs"] ?? 0
        } else {
            processed = values["vllm:request_success_total"] ?? values["vllm:request_success"] ?? 0
            active = values["vllm:num_requests_running"] ?? 0
            queued = values["vllm:num_requests_waiting"] ?? 0
        }

        return MetricsSnapshot(
            timestamp: timestamp,
            engine: engine,
            modelNames: models.sorted(),
            generationTokens: generation,
            promptTokens: prompt,
            processedRequests: processed,
            activeRequests: max(0, Int(active.rounded())),
            queuedRequests: max(0, Int(queued.rounded())),
            nativeGenerationTPS: values["sglang:gen_throughput"],
            realtimeGenerationTokens: realtimeGenerationTokens,
            realtimePromptTokens: realtimePromptTokens
        )
    }

    private func label(named name: String, in descriptor: String) -> String? {
        let marker = name + "=\""
        guard let start = descriptor.range(of: marker)?.upperBound else { return nil }
        var result = ""
        var escaped = false
        var index = start

        while index < descriptor.endIndex {
            let character = descriptor[index]
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return result
            } else {
                result.append(character)
            }
            index = descriptor.index(after: index)
        }
        return nil
    }
}
