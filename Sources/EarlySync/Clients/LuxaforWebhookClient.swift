import Foundation

// MARK: - LuxaforWebhookClient

/// Sends HTTP requests to the Luxafor webhook API to control the LED light.
///
/// - Retries once on failure (2s delay) before giving up
/// - Reads the Luxafor userId from `KeychainService.shared.luxaforUserId`
/// - Degrades gracefully (logs and returns) if no userId is configured, rather than crashing
public actor LuxaforWebhookClient {

    // MARK: - Configuration

    private let endpoint = URL(string: "https://api.luxafor.co.uk/webhook/v1/actions/solid_color")!
    private let session: URLSession
    private let retryDelayNanoseconds: UInt64 = 2_000_000_000

    // MARK: - Init

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public Interface

    /// Sets the Luxafor light to the given color.
    /// No-ops (with a log) if `luxaforUserId` isn't configured yet.
    public func setColor(_ color: LuxaforColor) async {
        guard let userId = KeychainService.shared.luxaforUserId, !userId.isEmpty else {
            log("luxaforUserId not configured — skipping setColor(\(color.rawValue))")
            return
        }

        let actionFields: WebhookRequest.ActionFields
        if color == .off {
            actionFields = WebhookRequest.ActionFields(color: "custom", customColor: color.hexColor)
        } else {
            actionFields = WebhookRequest.ActionFields(color: color.rawValue, customColor: nil)
        }
        let request = WebhookRequest(userId: userId, actionFields: actionFields)

        await sendWithRetry(request)
    }

    /// Turns the Luxafor light off.
    public func off() async {
        await setColor(.off)
    }

    // MARK: - Private

    private func sendWithRetry(_ body: WebhookRequest) async {
        do {
            try await send(body)
        } catch {
            log("webhook request failed (\(error.localizedDescription)) — retrying once")
            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            do {
                try await send(body)
            } catch {
                log("webhook request failed after retry: \(error.localizedDescription)")
            }
        }
    }

    private func send(_ body: WebhookRequest) async throws {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw LuxaforWebhookError.networkError("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LuxaforWebhookError.badStatus(http.statusCode)
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[LuxaforWebhookClient] \(message)\n".utf8))
    }
}

// MARK: - WebhookRequest

struct WebhookRequest: Encodable {
    let userId: String
    let actionFields: ActionFields

    struct ActionFields: Encodable {
        let color: String
        let customColor: String?

        enum CodingKeys: String, CodingKey {
            case color
            case customColor = "custom_color"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(color, forKey: .color)
            if let customColor {
                try container.encode(customColor, forKey: .customColor)
            }
        }
    }
}

// MARK: - LuxaforWebhookError

public enum LuxaforWebhookError: Error, Equatable {
    case networkError(String)
    case badStatus(Int)
}
