import Foundation

// MARK: - Tracking State

/// The current tracking state as reported by Early
public enum TrackingState: Equatable {
    case idle
    case tracking(entry: TrackingEntry)
}

// MARK: - Early API Models

/// An active time tracking entry from Early
public struct TrackingEntry: Codable, Equatable {
    public let id: Int
    public let activityId: Int
    public let activityName: String
    public let startedAt: Date
    public let note: TrackingNote?

    enum CodingKeys: String, CodingKey {
        case id
        case activityId
        case activityName
        case startedAt
        case note
    }
}

/// Note attached to a tracking entry
public struct TrackingNote: Codable, Equatable {
    public let text: String?
    public let tags: [TrackingTag]

    public init(text: String? = nil, tags: [TrackingTag] = []) {
        self.text = text
        self.tags = tags
    }
}

/// Tag associated with a tracking entry note
public struct TrackingTag: Codable, Equatable {
    public let id: Int
    public let key: String
    public let label: String
    public let color: String?

    public init(id: Int, key: String, label: String, color: String? = nil) {
        self.id = id
        self.key = key
        self.label = label
        self.color = color
    }
}

// MARK: - Auth Models

struct SignInRequest: Codable {
    let apiKey: String
    let apiSecret: String
}

struct SignInResponse: Codable {
    let token: String
}

// MARK: - Error Types

public enum EarlyAPIError: LocalizedError, Equatable {
    case invalidCredentials
    case networkError(String)
    case decodingError(String)
    case unauthorized
    case notTracking  // 204 No Content
    case unknown(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Early API key or secret. Check your credentials in Preferences."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .decodingError(let msg):
            return "Failed to decode Early API response: \(msg)"
        case .unauthorized:
            return "Early API token expired or invalid."
        case .notTracking:
            return "No active tracking entry."
        case .unknown(let code):
            return "Unexpected Early API response: HTTP \(code)"
        }
    }
}
