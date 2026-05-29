import Foundation
import Security

/// Manages pairing and authentication for remote control clients.
public final class PairingManager {
    private let keychainService = "com.fiti.remote-control"
    private var _currentPin: String = ""
    private let _tokenGenerator: () -> String
    private var _rememberedTokens: Set<String> = []
    private var _activeTokens: Set<String> = []
    private var _controllerName: String?

    public init(currentPin: String? = nil, tokenGenerator: @escaping () -> String = { UUID().uuidString }) {
        let pin = currentPin ?? String(format: "%04d", Int.random(in: 1000...9999))
        self._currentPin = pin
        self._tokenGenerator = tokenGenerator
        loadRememberedTokens()
    }

    public var currentPin: String {
        get { _currentPin }
        set { _currentPin = newValue }
    }

    public var controllerName: String? {
        get { _controllerName }
        set { _controllerName = newValue }
    }

    public func verifyPin(_ pin: String) -> Bool {
        return pin == currentPin
    }

    public func issueToken(clientId: String, remember: Bool) -> String {
        let token = _tokenGenerator()
        if remember {
            _rememberedTokens.insert(token)
            saveRememberedTokens()
        }
        return token
    }

    public func addAuthenticatedClient(token: String) {
        _activeTokens.insert(token)
    }

    public func removeAuthenticatedClient(token: String) {
        _activeTokens.remove(token)
    }

    public var isClientAuthenticated: Bool {
        // Check if any active token exists
        return !_activeTokens.isEmpty || !_rememberedTokens.isEmpty
    }

    public func setClientName(_ name: String) {
        _controllerName = name
    }

    // MARK: - Persistence (simplified for prototype)

    private func loadRememberedTokens() {
        // For production, use proper Keychain storage
        // For now, keep in memory
    }

    private func saveRememberedTokens() {
        // For production, use proper Keychain storage
        // For now, keep in memory
    }

    private func generateNewPin() -> String {
        return String(format: "%04d", Int.random(in: 1000...9999))
    }
}
