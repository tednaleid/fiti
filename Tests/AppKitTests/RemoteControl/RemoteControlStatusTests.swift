import Testing
@testable import AppKit
@testable import Core

@MainActor
@Suite("RemoteControl Status View")
struct RemoteControlStatusTests {
    
    @Test("status view shows connected state")
    func showsConnectedState() {
        let view = RemoteControlStatusView()
        view.setRemoteController(name: "iPad Air")
        
        #expect(view.isConnected)
        #expect(view.controllerName == "iPad Air")
    }
    
    @Test("status view updates on disconnection")
    func updatesOnDisconnect() {
        let view = RemoteControlStatusView()
        view.setRemoteController(name: "iPad Air")
        view.setRemoteController(name: nil)
        
        #expect(!view.isConnected)
        #expect(view.controllerName == nil)
    }
}
