import SwiftUI

/// Small status indicator shown in the toolbar when a remote controller is active.
public struct RemoteControlStatusView: View {
    @State private var isConnected: Bool = false
    @State private var controllerName: String? = nil
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isConnected ? "arrow.right.circle.fill" : "arrow.right.circle")
                .foregroundColor(isConnected ? .green : .orange)
            
            if let name = controllerName {
                Text(name)
                    .font(.caption)
                    .foregroundColor(isConnected ? .green : .orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isConnected ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    /// Call this from the controller to update the status.
    public func setRemoteController(name: String?) {
        controllerName = name
        isConnected = name != nil
    }
    
    public func clearRemoteController() {
        controllerName = nil
        isConnected = false
    }
    
    // Public getters for testing
    public var isConnectedPublic: Bool { isConnected }
    public var controllerNamePublic: String? { controllerName }
}

// MARK: - Previews
#if DEBUG
struct RemoteControlStatusView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            RemoteControlStatusView()
                .onAppear {
                    let view = RemoteControlStatusView()
                    view.setRemoteController(name: "iPad Air")
                }
            
            RemoteControlStatusView()
        }
        .padding()
        .background(Color.gray)
    }
}
#endif
