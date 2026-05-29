import Foundation

/// Lightweight adapter that maps RemoteAction messages into RemoteControlPort calls.
/// This can be embedded in a WebSocket server or used directly for testing.
public final class WebSocketAdapter {
    private weak var port: RemoteControlPort?
    private let pairingManager: PairingManager

    public init(port: RemoteControlPort, pairingManager: PairingManager) {
        self.port = port
        self.pairingManager = pairingManager
    }

    /// Handle an incoming RemoteAction - routes to the port.
    public func remote_handleAction(_ action: RemoteAction) {
        switch action {
        case .startStroke(let s):
            port?.remote_startStroke(s)
        case .appendPoints(let a):
            port?.remote_appendPoints(a)
        case .endStroke(let id):
            port?.remote_endStroke(strokeId: id)
        case .undo:
            port?.remote_undo()
        case .redo:
            port?.remote_redo()
        case .pairing:
            // Pairing is handled by PairingManager, not forwarded to port
            break
        }
    }

    /// Validate that a message can be processed (checks pairing/auth state).
    public func canProcess(_ action: RemoteAction) -> Bool {
        switch action {
        case .pairing:
            return true // Pairing always allowed
        default:
            return pairingManager.isClientAuthenticated
        }
    }
}
