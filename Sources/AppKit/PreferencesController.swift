// ABOUTME: Owns the Preferences NSWindow, builds the two-row layout, and wires
// ABOUTME: the activation-hotkey recorder + launch-at-login switch to their ports.

import AppKit
import KeyboardShortcuts

@MainActor
public final class PreferencesController: NSObject {
    private let launchAtLogin: LaunchAtLogin
    private let window: PreferencesWindow
    private let recorder: KeyboardShortcuts.RecorderCocoa

    public init(launchAtLogin: LaunchAtLogin) {
        self.launchAtLogin = launchAtLogin
        self.window = PreferencesWindow()
        self.recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleActivation)
        super.init()
        buildContent()
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

    // MARK: - Test hooks
    // swiftlint:disable identifier_name
    internal var testOnly_recorder: KeyboardShortcuts.RecorderCocoa { recorder }
    internal var testOnly_window: PreferencesWindow { window }
    // swiftlint:enable identifier_name
}
