import Testing
@testable import AppKit
@testable import Core

@MainActor
@Suite("RemoteControl WebSocket Adapter")
struct WebSocketAdapterTests {
    
    @Test("adapter maps parsed actions to port calls")
    func adapterMapsActions() {
        let port = RecordingRemoteControlPort()
        let pairingManager = PairingManager(currentPin: "1234")
        let adapter = WebSocketAdapter(port: port, pairingManager: pairingManager)
        
        // Test startStroke
        let startAction: RemoteAction = .startStroke(
            RemoteStartStroke(
                strokeId: "s1",
                tool: .pen,
                color: "#FF0000",
                width: 2.0,
                point: RemoteStrokePoint(x: 0.1, y: 0.2, pressure: 0.5, t: 123.0)
            )
        )
        adapter.remote_handleAction(startAction)
        
        #expect(port.started.count == 1)
        #expect(port.started[0].strokeId == "s1")
    }
    
    @Test("adapter maps appendPoints correctly")
    func adapterMapsAppendPoints() {
        let port = RecordingRemoteControlPort()
        let pairingManager = PairingManager(currentPin: "1234")
        let adapter = WebSocketAdapter(port: port, pairingManager: pairingManager)
        
        let appendAction: RemoteAction = .appendPoints(
            RemoteAppendPoints(
                strokeId: "s1",
                points: [
                    RemoteStrokePoint(x: 0.1, y: 0.2),
                    RemoteStrokePoint(x: 0.15, y: 0.25)
                ]
            )
        )
        adapter.remote_handleAction(appendAction)
        
        #expect(port.appended.count == 1)
        #expect(port.appended[0].points.count == 2)
    }
    
    @Test("adapter maps endStroke correctly")
    func adapterMapsEndStroke() {
        let port = RecordingRemoteControlPort()
        let pairingManager = PairingManager(currentPin: "1234")
        let adapter = WebSocketAdapter(port: port, pairingManager: pairingManager)
        
        adapter.remote_handleAction(.endStroke(strokeId: "s1"))
        
        #expect(port.ended.count == 1)
        #expect(port.ended[0] == "s1")
    }
    
    @Test("adapter maps undo/redo correctly")
    func adapterMapsUndoRedo() {
        let port = RecordingRemoteControlPort()
        let pairingManager = PairingManager(currentPin: "1234")
        let adapter = WebSocketAdapter(port: port, pairingManager: pairingManager)
        
        adapter.remote_handleAction(.undo)
        adapter.remote_handleAction(.redo)
        
        #expect(port.undoCount == 1)
        #expect(port.redoCount == 1)
    }
}
