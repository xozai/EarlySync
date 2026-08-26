import Foundation

// MARK: - EarlyAuthService

/// High-level service for managing Early API authentication.
///
/// Wraps `EarlyAPIClient` sign-in, credential validation, and token lifecycle.
/// Intended as the single source of truth for auth state in the UI layer.
@MainActor
public final class EarlyAuthService: ObservableObject {

    public enum AuthState: Equatable {
        case unauthenticated        // no credentials stored
        case authenticating         // sign-in in progress
        case authenticated          // token valid and cached
        case failed(EarlyAPIError)  // last sign-in attempt failed
    }

    // MARK: - Published

    @Published public private(set) var authState: AuthState

    // MARK: - Dependencies

    private let apiClient: EarlyAPIClient
    private let keychain: KeychainService

    // MARK: - Init

    public init(
        apiClient: EarlyAPIClient = EarlyAPIClient(),
        keychain: KeychainService = .shared
    ) {
        self.apiClient = apiClient
        self.keychain = keychain

        // Start in appropriate state based on stored credentials
        if keychain.earlyToken != nil {
            self.authState = .authenticated
        } else if keychain.hasEarlyCredentials() {
            self.authState = .unauthenticated  // have creds but no token yet
        } else {
            self.authState = .unauthenticated
        }
    }

    // MARK: - Public API

    /// Store credentials and sign in. Updates `authState` throughout.
    public func signIn(apiKey: String, apiSecret: String) async {
        // Save credentials to keychain
        keychain.earlyAPIKey = apiKey.trimmingCharacters(in: .whitespaces)
        keychain.earlyAPISecret = apiSecret.trimmingCharacters(in: .whitespaces)

        authState = .authenticating
        do {
            try await apiClient.signIn()
            authState = .authenticated
        } catch let error as EarlyAPIError {
            authState = .failed(error)
        } catch {
            authState = .failed(.networkError(error.localizedDescription))
        }
    }

    /// Re-authenticate using stored credentials (e.g. after token expiry)
    public func reauthenticate() async {
        guard keychain.hasEarlyCredentials() else {
            authState = .unauthenticated
            return
        }
        authState = .authenticating
        do {
            try await apiClient.signIn()
            authState = .authenticated
        } catch let error as EarlyAPIError {
            authState = .failed(error)
        } catch {
            authState = .failed(.networkError(error.localizedDescription))
        }
    }

    /// Sign out and clear all stored credentials
    public func signOut() {
        keychain.clearAll()
        authState = .unauthenticated
    }

    /// True if we have a valid (or presumed valid) token
    public var isAuthenticated: Bool {
        authState == .authenticated
    }
}
