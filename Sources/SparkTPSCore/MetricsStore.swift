import CSQLite
import Foundation

public struct DailyTPSPeak: Sendable, Equatable {
    public let outputTPS: Double
    public let inputTPS: Double
    public let totalTPS: Double

    public init(outputTPS: Double = 0, inputTPS: Double = 0, totalTPS: Double = 0) {
        self.outputTPS = outputTPS
        self.inputTPS = inputTPS
        self.totalTPS = totalTPS
    }
}

public struct DailyTokenUsage: Sendable, Equatable {
    public let inputTokens: Double
    public let outputTokens: Double

    public init(inputTokens: Double = 0, outputTokens: Double = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    public func estimatedCost(inputPricePerMillion: Double, outputPricePerMillion: Double) -> Double {
        inputTokens / 1_000_000 * inputPricePerMillion
            + outputTokens / 1_000_000 * outputPricePerMillion
    }
}

public struct MetricsDaySummary: Sendable, Equatable {
    public let peak: DailyTPSPeak
    public let usage: DailyTokenUsage

    public init(peak: DailyTPSPeak = DailyTPSPeak(), usage: DailyTokenUsage = DailyTokenUsage()) {
        self.peak = peak
        self.usage = usage
    }
}

public actor MetricsStore {
    public static let detailRetentionDays = 30
    public static let sampleInterval: TimeInterval = 5

    private let connection: SQLiteConnection
    private let calendar: Calendar
    private var lastPrunedDay: String?

    public init(databaseURL: URL, calendar: Calendar = .current) throws {
        self.calendar = calendar
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let handle { sqlite3_close(handle) }
            throw MetricsStoreError.database(message)
        }
        connection = SQLiteConnection(handle)

        try Self.execute("PRAGMA journal_mode=WAL", on: handle)
        try Self.execute("PRAGMA synchronous=NORMAL", on: handle)
        try Self.execute(
            """
            CREATE TABLE IF NOT EXISTS tps_samples (
                bucket_start INTEGER PRIMARY KEY,
                observed_at REAL NOT NULL,
                output_tps REAL NOT NULL,
                input_tps REAL NOT NULL,
                active_requests INTEGER NOT NULL,
                queued_requests INTEGER NOT NULL,
                processed_requests REAL NOT NULL
            )
            """,
            on: handle
        )
        try Self.execute(
            """
            CREATE TABLE IF NOT EXISTS daily_tps (
                day TEXT PRIMARY KEY,
                peak_output_tps REAL NOT NULL,
                peak_input_tps REAL NOT NULL,
                peak_total_tps REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """,
            on: handle
        )
        try Self.execute(
            """
            CREATE TABLE IF NOT EXISTS token_samples (
                bucket_start INTEGER PRIMARY KEY,
                input_tokens REAL NOT NULL,
                output_tokens REAL NOT NULL
            )
            """,
            on: handle
        )
        try Self.execute(
            """
            CREATE TABLE IF NOT EXISTS daily_usage (
                day TEXT PRIMARY KEY,
                input_tokens REAL NOT NULL,
                output_tokens REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """,
            on: handle
        )
        try Self.execute(
            """
            CREATE TABLE IF NOT EXISTS token_state (
                source TEXT PRIMARY KEY,
                input_counter REAL NOT NULL,
                output_counter REAL NOT NULL,
                input_kind TEXT NOT NULL,
                output_kind TEXT NOT NULL,
                observed_at REAL NOT NULL
            )
            """,
            on: handle
        )
    }

    @discardableResult
    public func record(
        snapshot: MetricsSnapshot,
        summary: MetricsSummary,
        source: String = "default"
    ) throws -> MetricsDaySummary {
        let observedAt = snapshot.timestamp.timeIntervalSince1970
        let bucket = Int64(floor(observedAt / Self.sampleInterval) * Self.sampleInterval)
        let day = dayKey(for: snapshot.timestamp)
        let counters = tokenCounters(from: snapshot)
        let tokenDelta = try tokenDelta(current: counters, source: source)

        try withStatement(
            """
            INSERT INTO tps_samples (
                bucket_start, observed_at, output_tps, input_tps,
                active_requests, queued_requests, processed_requests
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(bucket_start) DO UPDATE SET
                observed_at = excluded.observed_at,
                output_tps = excluded.output_tps,
                input_tps = excluded.input_tps,
                active_requests = excluded.active_requests,
                queued_requests = excluded.queued_requests,
                processed_requests = excluded.processed_requests
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, bucket)
            sqlite3_bind_double(statement, 2, observedAt)
            sqlite3_bind_double(statement, 3, summary.outputTPS)
            sqlite3_bind_double(statement, 4, summary.inputTPS)
            sqlite3_bind_int(statement, 5, Int32(snapshot.activeRequests))
            sqlite3_bind_int(statement, 6, Int32(snapshot.queuedRequests))
            sqlite3_bind_double(statement, 7, snapshot.processedRequests)
        }

        try withStatement(
            """
            INSERT INTO daily_tps (
                day, peak_output_tps, peak_input_tps, peak_total_tps, updated_at
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(day) DO UPDATE SET
                peak_output_tps = MAX(peak_output_tps, excluded.peak_output_tps),
                peak_input_tps = MAX(peak_input_tps, excluded.peak_input_tps),
                peak_total_tps = MAX(peak_total_tps, excluded.peak_total_tps),
                updated_at = excluded.updated_at
            """
        ) { statement in
            bind(day, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, summary.outputTPS)
            sqlite3_bind_double(statement, 3, summary.inputTPS)
            sqlite3_bind_double(statement, 4, summary.outputTPS + summary.inputTPS)
            sqlite3_bind_double(statement, 5, observedAt)
        }

        try withStatement(
            """
            INSERT INTO token_samples (bucket_start, input_tokens, output_tokens)
            VALUES (?, ?, ?)
            ON CONFLICT(bucket_start) DO UPDATE SET
                input_tokens = input_tokens + excluded.input_tokens,
                output_tokens = output_tokens + excluded.output_tokens
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, bucket)
            sqlite3_bind_double(statement, 2, tokenDelta.inputTokens)
            sqlite3_bind_double(statement, 3, tokenDelta.outputTokens)
        }

        try withStatement(
            """
            INSERT INTO daily_usage (day, input_tokens, output_tokens, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(day) DO UPDATE SET
                input_tokens = input_tokens + excluded.input_tokens,
                output_tokens = output_tokens + excluded.output_tokens,
                updated_at = excluded.updated_at
            """
        ) { statement in
            bind(day, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, tokenDelta.inputTokens)
            sqlite3_bind_double(statement, 3, tokenDelta.outputTokens)
            sqlite3_bind_double(statement, 4, observedAt)
        }

        try withStatement(
            """
            INSERT INTO token_state (
                source, input_counter, output_counter, input_kind, output_kind, observed_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(source) DO UPDATE SET
                input_counter = excluded.input_counter,
                output_counter = excluded.output_counter,
                input_kind = excluded.input_kind,
                output_kind = excluded.output_kind,
                observed_at = excluded.observed_at
            """
        ) { statement in
            bind(source, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, counters.input)
            sqlite3_bind_double(statement, 3, counters.output)
            bind(counters.inputKind, to: statement, at: 4)
            bind(counters.outputKind, to: statement, at: 5)
            sqlite3_bind_double(statement, 6, observedAt)
        }

        if lastPrunedDay != day {
            try pruneDetail(before: snapshot.timestamp)
            lastPrunedDay = day
        }
        return MetricsDaySummary(
            peak: try peak(on: snapshot.timestamp),
            usage: try usage(on: snapshot.timestamp)
        )
    }

    public func peak(on date: Date = Date()) throws -> DailyTPSPeak {
        var result = DailyTPSPeak()
        try withStatement(
            "SELECT peak_output_tps, peak_input_tps, peak_total_tps FROM daily_tps WHERE day = ?",
            stepAfterBind: false
        ) { statement in
            bind(dayKey(for: date), to: statement, at: 1)
            if sqlite3_step(statement) == SQLITE_ROW {
                result = DailyTPSPeak(
                    outputTPS: sqlite3_column_double(statement, 0),
                    inputTPS: sqlite3_column_double(statement, 1),
                    totalTPS: sqlite3_column_double(statement, 2)
                )
            }
        }
        return result
    }

    public func usage(on date: Date = Date()) throws -> DailyTokenUsage {
        var result = DailyTokenUsage()
        try withStatement(
            "SELECT input_tokens, output_tokens FROM daily_usage WHERE day = ?",
            stepAfterBind: false
        ) { statement in
            bind(dayKey(for: date), to: statement, at: 1)
            if sqlite3_step(statement) == SQLITE_ROW {
                result = DailyTokenUsage(
                    inputTokens: sqlite3_column_double(statement, 0),
                    outputTokens: sqlite3_column_double(statement, 1)
                )
            }
        }
        return result
    }

    public func sampleCount() throws -> Int {
        var count = 0
        try withStatement("SELECT COUNT(*) FROM tps_samples", stepAfterBind: false) { statement in
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(statement, 0))
            }
        }
        return count
    }

    private func pruneDetail(before now: Date) throws {
        let cutoff = now.addingTimeInterval(-Double(Self.detailRetentionDays) * 86_400).timeIntervalSince1970
        try withStatement("DELETE FROM tps_samples WHERE observed_at < ?") { statement in
            sqlite3_bind_double(statement, 1, cutoff)
        }
        try withStatement("DELETE FROM token_samples WHERE bucket_start < ?") { statement in
            sqlite3_bind_int64(statement, 1, Int64(cutoff))
        }
    }

    private func tokenCounters(from snapshot: MetricsSnapshot) -> TokenCounters {
        TokenCounters(
            input: snapshot.realtimePromptTokens ?? snapshot.promptTokens,
            output: snapshot.realtimeGenerationTokens ?? snapshot.generationTokens,
            inputKind: snapshot.realtimePromptTokens == nil ? "standard" : "realtime",
            outputKind: snapshot.realtimeGenerationTokens == nil ? "standard" : "realtime"
        )
    }

    private func tokenDelta(current: TokenCounters, source: String) throws -> DailyTokenUsage {
        var previous: TokenCounters?
        try withStatement(
            "SELECT input_counter, output_counter, input_kind, output_kind FROM token_state WHERE source = ?",
            stepAfterBind: false
        ) { statement in
            bind(source, to: statement, at: 1)
            if sqlite3_step(statement) == SQLITE_ROW {
                previous = TokenCounters(
                    input: sqlite3_column_double(statement, 0),
                    output: sqlite3_column_double(statement, 1),
                    inputKind: columnText(statement, at: 2),
                    outputKind: columnText(statement, at: 3)
                )
            }
        }
        guard let previous else { return DailyTokenUsage() }
        let input = current.inputKind == previous.inputKind && current.input >= previous.input
            ? current.input - previous.input
            : 0
        let output = current.outputKind == previous.outputKind && current.output >= previous.output
            ? current.output - previous.output
            : 0
        return DailyTokenUsage(inputTokens: input, outputTokens: output)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw MetricsStoreError.database(message)
        }
    }

    private func withStatement(
        _ sql: String,
        stepAfterBind: Bool = true,
        bind: (OpaquePointer) throws -> Void
    ) throws {
        let database = connection.handle
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MetricsStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement)
        guard stepAfterBind else { return }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw MetricsStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func columnText(_ statement: OpaquePointer, at index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }
}

public enum MetricsStoreError: Error, LocalizedError {
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .database(let message): "SQLite: \(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer

    init(_ handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }
}

private struct TokenCounters {
    let input: Double
    let output: Double
    let inputKind: String
    let outputKind: String
}
