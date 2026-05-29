import Foundation

/// Lightweight WebSocket server placeholder for remote control.
/// 
/// NOTE: This is a stub implementation for planning purposes.
/// A production implementation would use Network.framework NWListener
/// or a lightweight HTTP/WS server library.
/// 
/// The actual implementation would:
/// 1. Create NWListener on a specified port
/// 2. Accept WebSocket upgrade handshake
/// 3. Parse incoming text messages as JSON
/// 4. Call handleReceivedMessage for each message
/// 5. Send responses back through the connection
public final class WebSocketServer {
    private let serverPort: UInt16
    private var isRunning = false

    private weak var controlPort: RemoteControlPort?
    private let pairingManager: PairingManager
    private var onRemoteAction: ((RemoteAction) -> Void)?

    public init(serverPort: UInt16, controlPort: RemoteControlPort, pairingManager: PairingManager) {
        self.serverPort = serverPort
        self.controlPort = controlPort
        self.pairingManager = pairingManager
    }

    /// Start the WebSocket server (stub - actual implementation uses Network.framework)
    public func start() async throws {
        print("Remote control WebSocket server starting on port \(serverPort)")
        // TODO: Implement with NWListener for production
        isRunning = true
    }

    /// Stop the server
    public func stop() {
        isRunning = false
        print("Remote control WebSocket server stopped")
    }

    // Check if the server is running (public accessor for private isRunning)
    public var running: Bool {
        isRunning
    }

    /// Process incoming JSON message - called by actual server implementation
    public func handleReceivedMessage(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            print("Invalid UTF-8 received")
            return
        }

        do {
            let action = try parseRemoteAction(from: data)

            // Pairing handshake handling
            if case .pairing(let clientId, let pin, let remember) = action {
                handlePairing(clientId: clientId, pin: pin, remember: remember)
                return
            }

            // Auth check for non-pairing messages
            guard pairingManager.isClientAuthenticated else {
                print("Authentication required")
                return
            }

            // Forward to port
            onRemoteAction?(action)
            controlPort?.remote_handleAction(action)

        } catch {
            print("Parse error: \(error)")
        }
    }

    private func handlePairing(clientId: String, pin: String, remember: Bool) {
        if pairingManager.verifyPin(pin) {
            let token = pairingManager.issueToken(clientId: clientId, remember: remember)
            pairingManager.addAuthenticatedClient(token: token)
            pairingManager.setClientName(clientId)
            print("Pairing successful for \(clientId)")
        } else {
            print("Invalid PIN from \(clientId)")
        }
    }
}
