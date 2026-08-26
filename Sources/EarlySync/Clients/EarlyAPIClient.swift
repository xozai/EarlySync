import Foundation

// MARK: - EarlyAPIClient

/// Handles all communication with the Early REST API v4.
///
/// Responsibilities:
/// - Sign in with API key/secret and cache the bearer token
/// - Automatically re-authenticate on 401 responses
/// - Fetch the current active tracking entry
/// - Decode responses and surface typed errors
///
/// Thread safety: all async methods may be called from any actor context;
/// token state is guarded by an actor-isolated property.
public actor EarlyAPIClient {

    // MARK: - Configuration

    private let baseURL = URL(string: "https://api.early.app/api/v4")!
    private let session: URLSession

    /// ISO 8601 date decoder matching Early's format: "2024-08-05T06:01:00.000"
    /// Early's API omits the timezone component, so we use DateFormatter
    /// rather than ISO8601DateFormatter (which requires a timezone).
    private static let dateDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Formatter with fractional seconds
        let fmtFrac = DateFormatter()
        fmtFrac.locale = Locale(identifier: "en_US_POSIX")
        fmtFrac.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        // Formatter without fractional seconds (fallback)
        let fmtPlain = DateFormatter()
        fmtPlain.locale = Locale(identifier: "en_US_POSIX")
        fmtPlain.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fmtFrac.date(from: string) { return date }
            if let date = fmtPlain.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode Early date: \(string)"
            )
        }
        return decoder
    }()

    // MARK: - State

    private var cachedToken: String? {
        get { KeychainService.shared.earlyToken }
        set { KeychainService.shared.earlyToken = newValue }
    }

    // MARK: - Init

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public Interface

    /// Fetches the current tracking state from Early.
    ///
    /// Returns `.tracking(entry:)` if an entry is active, or `.idle` if nothing is tracked.
    /// Automatically refreshes the token on 401.
    ///
    /// - Throws: `EarlyAPIError` for auth failures, network errors, or decode issues.
    public func fetchTrackingState() async throws -> TrackingState {
        // Ensure we have a token
        if cachedToken == nil {
            try await signIn()
        }

        do {
            return try await fetchCurrentEntry()
        } catch EarlyAPIError.unauthorized {
            // Token expired — refresh and retry once
            cachedToken = nil
            try await signIn()
            return try await fetchCurrentEntry()
        }
    }

    /// Signs in with credentials from Keychain, caching the returned token.
    /// - Throws: `EarlyAPIError.invalidCredentials` if API key/secret are missing or rejected.
    public func signIn() async throws {
        guard
            let apiKey = KeychainService.shared.earlyAPIKey,
            let apiSecret = KeychainService.shared.earlyAPISecret
        else {
            throw EarlyAPIError.invalidCredentials
        }

        let endpoint = baseURL.appendingPathComponent("/developer/sign-in")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = SignInRequest(apiKey: apiKey, apiSecret: apiSecret)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performRequest(request, requiresAuth: false)

        guard let http = response as? HTTPURLResponse else {
            throw EarlyAPIError.networkError("Non-HTTP response")
        }
        switch http.statusCode {
        case 200:
            let signIn = try decodeJSON(SignInResponse.self, from: data)
            cachedToken = signIn.token
        case 401, 403:
            throw EarlyAPIError.invalidCredentials
        default:
            throw EarlyAPIError.unknown(http.statusCode)
        }
    }

    // MARK: - Private

    private func fetchCurrentEntry() async throws -> TrackingState {
        let endpoint = baseURL.appendingPathComponent("/time-entries/tracked")
        let request = try authorizedRequest(url: endpoint)

        let (data, response) = try await performRequest(request, requiresAuth: true)

        guard let http = response as? HTTPURLResponse else {
            throw EarlyAPIError.networkError("Non-HTTP response")
        }

        switch http.statusCode {
        case 200:
            let entry = try decodeJSON(TrackingEntry.self, from: data)
            return .tracking(entry: entry)
        case 204:
            // No active entry
            return .idle
        case 401:
            throw EarlyAPIError.unauthorized
        default:
            throw EarlyAPIError.unknown(http.statusCode)
        }
    }

    private func authorizedRequest(url: URL, method: String = "GET") throws -> URLRequest {
        guard let token = cachedToken else {
            throw EarlyAPIError.unauthorized
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performRequest(
        _ request: URLRequest,
        requiresAuth: Bool
    ) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw EarlyAPIError.networkError(error.localizedDescription)
        }
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try Self.dateDecoder.decode(type, from: data)
        } catch {
            throw EarlyAPIError.decodingError(error.localizedDescription)
        }
    }
}
