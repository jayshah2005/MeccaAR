import Foundation

/// Resolves the Neon connection details and the SQL-over-HTTP endpoint used by
/// `NeonClient`. The connection string is read from the app's Info.plist key
/// `NeonConnectionString` (a Neon pooled `postgresql://` URL).
struct NeonConfiguration: Sendable {
    let connectionString: String
    let sqlEndpoint: URL

    enum ConfigurationError: LocalizedError {
        case missingConnectionString
        case invalidConnectionString

        var errorDescription: String? {
            switch self {
            case .missingConnectionString:
                return "No Neon connection string is configured. Set `NeonConnectionString` in Info.plist."
            case .invalidConnectionString:
                return "The configured Neon connection string is not a valid postgresql:// URL."
            }
        }
    }

    init(connectionString: String) throws {
        let trimmed = connectionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConfigurationError.missingConnectionString
        }
        guard
            let components = URLComponents(string: trimmed),
            let host = components.host,
            !host.isEmpty
        else {
            throw ConfigurationError.invalidConnectionString
        }

        self.connectionString = trimmed

        var endpoint = URLComponents()
        endpoint.scheme = "https"
        endpoint.host = host
        endpoint.path = "/sql"
        guard let url = endpoint.url else {
            throw ConfigurationError.invalidConnectionString
        }
        self.sqlEndpoint = url
    }

    static func fromInfoPlist(
        bundle: Bundle = .main
    ) throws -> NeonConfiguration {
        let value = bundle.object(forInfoDictionaryKey: "NeonConnectionString") as? String ?? ""
        return try NeonConfiguration(connectionString: value)
    }
}
