// ABOUTME: Owns the Preferences NSWindow, builds the row layout, and wires the
// ABOUTME: activation-hotkey recorder, launch-at-login switch, and fade duration to their ports.

import AppKit
import KeyboardShortcuts

@MainActor
public final class PreferencesController: NSObject {
    private let launchAtLogin: LaunchAtLogin
    private let fadeSettings: FadeSettings
    private let outlineSettings: OutlineSettings
    private let onOutlineChanged: () -> Void
    private let window: PreferencesWindow
    private let recorder: KeyboardShortcuts.RecorderCocoa
    private let launchSwitch: NSSwitch
    private let fadeField: NSTextField
    private let fadeStepper: NSStepper
    private let statusField: NSTextField
    private let outlineCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    private static let approvalHint = "Approve fiti in System Settings \u{2192} General \u{2192} Login Items."

    public init(launchAtLogin: LaunchAtLogin, fadeSettings: FadeSettings,
                outlineSettings: OutlineSettings,
                onOutlineChanged: @escaping () -> Void) {
        self.launchAtLogin = launchAtLogin
        self.fadeSettings = fadeSettings
        self.outlineSettings = outlineSettings
        self.onOutlineChanged = onOutlineChanged
        self.window = PreferencesWindow()
        self.recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleActivation)
        self.launchSwitch = NSSwitch()
        self.fadeField = NSTextField()
        self.fadeStepper = NSStepper()
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

        stack.addArrangedSubview(row(label: "Seconds before fade:", control: buildFadeControl()))

        outlineCheckbox.state = outlineSettings.outlineEnabled ? .on : .off
        outlineCheckbox.target = self
        outlineCheckbox.action = #selector(outlineToggled(_:))
        stack.addArrangedSubview(row(label: "Outline:", control: outlineCheckbox))

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

    /// A whole-seconds text field paired with a stepper, both reflecting and writing
    /// the fade window through the FadeSettings port. AppController reads the port live,
    /// so a change takes effect on the next fade tick with no further wiring.
    private func buildFadeControl() -> NSView {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: UserDefaultsFadeSettings.minSeconds)
        formatter.maximum = NSNumber(value: UserDefaultsFadeSettings.maxSeconds)

        fadeField.formatter = formatter
        fadeField.alignment = .right
        fadeField.target = self
        fadeField.action = #selector(fadeFieldChanged(_:))
        fadeField.translatesAutoresizingMaskIntoConstraints = false
        fadeField.widthAnchor.constraint(equalToConstant: 48).isActive = true

        fadeStepper.minValue = UserDefaultsFadeSettings.minSeconds
        fadeStepper.maxValue = UserDefaultsFadeSettings.maxSeconds
        fadeStepper.increment = 1
        fadeStepper.valueWraps = false
        fadeStepper.target = self
        fadeStepper.action = #selector(fadeStepperChanged(_:))

        syncFadeControls(from: fadeSettings.secondsBeforeFade)

        let row = NSStackView(views: [fadeField, fadeStepper])
        row.orientation = .horizontal
        row.spacing = 4
        return row
    }

    private func syncFadeControls(from seconds: Double) {
        fadeField.integerValue = Int(seconds)
        fadeStepper.doubleValue = seconds
    }

    @objc private func fadeFieldChanged(_ sender: NSTextField) {
        fadeSettings.secondsBeforeFade = Double(sender.integerValue)
        syncFadeControls(from: fadeSettings.secondsBeforeFade)
    }

    @objc private func fadeStepperChanged(_ sender: NSStepper) {
        fadeSettings.secondsBeforeFade = sender.doubleValue
        syncFadeControls(from: fadeSettings.secondsBeforeFade)
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

    @objc private func outlineToggled(_ sender: NSButton) {
        outlineSettings.outlineEnabled = (sender.state == .on)
        onOutlineChanged()
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

    internal func testOnly_setFadeField(to seconds: Int) {
        fadeField.integerValue = seconds
        fadeFieldChanged(fadeField)
    }

    internal func testOnly_stepFade(to seconds: Double) {
        fadeStepper.doubleValue = seconds
        fadeStepperChanged(fadeStepper)
    }

    internal func testOnly_setOutline(_ on: Bool) {
        outlineCheckbox.state = on ? .on : .off
        outlineToggled(outlineCheckbox)
    }

    // swiftlint:disable identifier_name
    internal var testOnly_recorder: KeyboardShortcuts.RecorderCocoa { recorder }
    internal var testOnly_window: PreferencesWindow { window }
    internal var testOnly_switch: NSSwitch { launchSwitch }
    internal var testOnly_statusField: NSTextField { statusField }
    internal var testOnly_fadeField: NSTextField { fadeField }
    internal var testOnly_fadeStepper: NSStepper { fadeStepper }
    internal var testOnly_outlineCheckbox: NSButton { outlineCheckbox }
    // swiftlint:enable identifier_name
}
