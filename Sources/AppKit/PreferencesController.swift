// ABOUTME: Owns the Preferences NSWindow, builds the two-row layout, and wires
// ABOUTME: the activation-hotkey recorder + launch-at-login switch to their ports.

import AppKit
import KeyboardShortcuts

@MainActor
public final class PreferencesController: NSObject {
    private let launchAtLogin: LaunchAtLogin
    private let window: PreferencesWindow
    private let recorder: KeyboardShortcuts.RecorderCocoa
    private let launchSwitch: NSSwitch
    private let statusField: NSTextField

    private static let approvalHint = "Approve fiti in System Settings \u{2192} General \u{2192} Login Items."

    public init(launchAtLogin: LaunchAtLogin) {
        self.launchAtLogin = launchAtLogin
        self.window = PreferencesWindow()
        self.recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleActivation)
        self.launchSwitch = NSSwitch()
        self.statusField = NSTextField(labelWithString: "")
        super.init()
        statusField.font = .systemFont(ofSize: 11)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byWordWrapping
        statusField.maximumNumberOfLines = 2
        statusField.isHidden = true
        buildContent()
        syncFromStatus()
    }

    public func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(row(label: "Activation hotkey:", control: recorder))

        launchSwitch.target = self
        launchSwitch.action = #selector(launchSwitchToggled(_:))
        stack.addArrangedSubview(row(label: "Launch at login:", control: launchSwitch))

        stack.addArrangedSubview(statusField)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        window.contentView = container
    }

    private func row(label text: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let label = NSTextField(labelWithString: text)
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    private func syncFromStatus() {
        switch launchAtLogin.status {
        case .enabled:
            launchSwitch.state = .on
            setStatusText(nil)
        case .requiresApproval:
            launchSwitch.state = .on
            setStatusText(Self.approvalHint)
        case .disabled, .unavailable:
            launchSwitch.state = .off
            setStatusText(nil)
        }
    }

    private func setStatusText(_ text: String?) {
        if let text {
            statusField.stringValue = text
            statusField.isHidden = false
        } else {
            statusField.stringValue = ""
            statusField.isHidden = true
        }
    }

    @objc private func launchSwitchToggled(_ sender: NSSwitch) {
        let wantsEnabled = sender.state == .on
        do {
            try launchAtLogin.setEnabled(wantsEnabled)
            syncFromStatus()
        } catch {
            sender.state = wantsEnabled ? .off : .on
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Failed to update launch-at-login: \(error.localizedDescription)"
            setStatusText(message)
        }
    }

    // MARK: - Test hooks

    internal func testOnly_toggleSwitch(to state: NSControl.StateValue) {
        launchSwitch.state = state
        launchSwitchToggled(launchSwitch)
    }

    // swiftlint:disable identifier_name
    internal var testOnly_recorder: KeyboardShortcuts.RecorderCocoa { recorder }
    internal var testOnly_window: PreferencesWindow { window }
    internal var testOnly_switch: NSSwitch { launchSwitch }
    internal var testOnly_statusField: NSTextField { statusField }
    // swiftlint:enable identifier_name
}
