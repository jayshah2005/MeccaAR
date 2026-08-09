import Foundation

/// Minimal client for Neon's SQL-over-HTTP endpoint. It POSTs `{query, params}`
/// to `https://<host>/sql` with the connection string in a header, so the app
/// can talk to Postgres directly without a TCP driver or a separate backend.
///
/// Responses are requested as raw text (`Neon-Raw-Text-Output`), so every cell
/// arrives as a JSON string (or null) and is parsed on the Swift side.
actor NeonClient {
    private let configuration: NeonConfiguration
    private let session: URLSession

    init(configuration: NeonConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// A single scalar bound to a query parameter. Everything is sent as text
    /// (or null) and cast to the right type inside the SQL statement.
    enum Param: Sendable {
        case text(String)
        case null

        static func double(_ value: Double) -> Param { .text(String(value)) }
        static func int(_ value: Int) -> Param { .text(String(value)) }
        static func uuid(_ value: UUID) -> Param { .text(value.uuidString.lowercased()) }
        static func optionalDouble(_ value: Double?) -> Param {
            value.map { .double($0) } ?? .null
        }

        static func timestamp(_ value: Date) -> Param {
            .text(ISO8601DateFormatter().string(from: value))
        }
    }

    func execute(_ query: String, _ params: [Param] = []) async throws -> [NeonRow] {
        var request = URLRequest(url: configuration.sqlEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.connectionString, forHTTPHeaderField: "Neon-Connection-String")
        request.setValue("true", forHTTPHeaderField: "Neon-Raw-Text-Output")
        request.setValue("false", forHTTPHeaderField: "Neon-Array-Mode")

        let jsonParams: [Any] = params.map { param in
            switch param {
            case .text(let value): return value
            case .null: return NSNull()
            }
        }
        let body: [String: Any] = ["query": query, "params": jsonParams]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NeonError.transport
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw NeonError.server(message)
        }

        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawRows = object["rows"] as? [[String: Any]]
        else {
            throw NeonError.decoding
        }

        return rawRows.map { NeonRow(storage: $0) }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["message"] as? String
            ?? object["error"] as? String
    }
}

enum NeonError: LocalizedError {
    case transport
    case server(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .transport:
            return "Could not reach the Neon database."
        case .server(let message):
            return "Neon error: \(message)"
        case .decoding:
            return "Received an unexpected response from Neon."
        }
    }
}

/// A row of raw-text cells keyed by column name, with typed accessors.
struct NeonRow: Sendable {
    private let storage: [String: String]

    init(storage: [String: Any]) {
        var mapped: [String: String] = [:]
        for (key, value) in storage where !(value is NSNull) {
            if let string = value as? String {
                mapped[key] = string
            } else if let number = value as? NSNumber {
                mapped[key] = number.stringValue
            }
        }
        self.storage = mapped
    }

    func string(_ column: String) -> String? { storage[column] }

    func double(_ column: String) -> Double? {
        storage[column].flatMap(Double.init)
    }

    func int(_ column: String) -> Int? {
        storage[column].flatMap { Int($0) ?? Double($0).map(Int.init) }
    }

    /// Postgres emits booleans as "t"/"f"; ints as "1"/"0".
    func bool(_ column: String) -> Bool {
        switch storage[column]?.lowercased() {
        case "t", "true", "1": return true
        default: return false
        }
    }

    func uuid(_ column: String) -> UUID? {
        storage[column].flatMap(UUID.init(uuidString:))
    }

    /// Interprets a column selected as `extract(epoch from ...)` seconds.
    func date(epochColumn column: String) -> Date? {
        double(column).map { Date(timeIntervalSince1970: $0) }
    }
}
