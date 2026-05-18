// ABOUTME: In-memory LaunchAtLogin double for tests. Configurable errorToThrow
// ABOUTME: and simulateApprovalRequired flags drive the controller's failure paths.

import Foundation

@MainActor
public final class RecordingLaunchAtLogin: LaunchAtLogin {
    public var isAvailable: Bool = true
    public private(set) var status: LaunchAtLoginStatus = .disabled
    public var errorToThrow: Error?
    public var simulateApprovalRequired = false

    public init() {}

    public func setEnabled(_ enabled: Bool) throws {
        if let errorToThrow { throw errorToThrow }
        if enabled {
            status = simulateApprovalRequired ? .requiresApproval : .enabled
        } else {
            status = .disabled
        }
    }
}

public enum RecordingLaunchAtLoginError: Error, Equatable {
    case synthetic
}
