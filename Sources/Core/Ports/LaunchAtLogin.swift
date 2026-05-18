// ABOUTME: Launch-at-login port. AppKit adapter wraps SMAppService.mainApp; tests
// ABOUTME: use RecordingLaunchAtLogin. Status enum decouples Core from ServiceManagement.

import Foundation

@MainActor
public protocol LaunchAtLogin: AnyObject {
    /// Whether the toggle should appear at all. False on platforms or
    /// configurations where SMAppService cannot find the bundle.
    var isAvailable: Bool { get }

    /// Current registration state, freshly read from the underlying service.
    var status: LaunchAtLoginStatus { get }

    /// Register (true) or unregister (false). Throws if the underlying
    /// service call fails. Callers surface the error in the UI and revert.
    func setEnabled(_ enabled: Bool) throws
}

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}
