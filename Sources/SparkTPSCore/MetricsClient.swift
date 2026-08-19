import Foundation

public enum MetricsClientError: LocalizedError {
    case invalidURL
    case badStatus(Int)
    case invalidText

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid HTTP or HTTPS metrics URL."
        case .badStatus(let code):
            "The metrics endpoint returned HTTP \(code)."
        case .invalidText:
            "The metrics response was not valid UTF-8 text."
        }
    }
}

public struct MetricsClient: Sendable {
    private let session: URLSession
    private let parser = PrometheusParser()

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 8
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpAdditionalHeaders = [
                "Accept": "text/plain",
                "Accept-Encoding": "gzip, deflate",
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    public func fetch(from endpoint: String, at timestamp: Date = Date()) async throws -> MetricsSnapshot {
        guard let url = normalizedURL(from: endpoint) else { throw MetricsClientError.invalidURL }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw MetricsClientError.badStatus(0) }
        guard (200..<300).contains(http.statusCode) else { throw MetricsClientError.badStatus(http.statusCode) }
        guard let text = String(data: data, encoding: .utf8) else { throw MetricsClientError.invalidText }
        return try parser.parse(text, timestamp: timestamp)
    }

    public func normalizedURL(from endpoint: String) -> URL? {
        var value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "http://" + value
        }
        guard var components = URLComponents(string: value),
              components.scheme == "http" || components.scheme == "https",
              components.host != nil else {
            return nil
        }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/metrics"
        }
        return components.url
    }
}
