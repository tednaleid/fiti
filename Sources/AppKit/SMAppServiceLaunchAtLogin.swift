// ABOUTME: Real LaunchAtLogin adapter wrapping SMAppService.mainApp. Side effects
// ABOUTME: persist in the user's launchd; not unit-tested. Manual smoke test only.

import Foundation
import ServiceManagement

@MainActor
public final class SMAppServiceLaunchAtLogin: LaunchAtLogin {
    public init() {}

    public var isAvailable: Bool {
        SMAppService.mainApp.status != .notFound
    }

    public var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
