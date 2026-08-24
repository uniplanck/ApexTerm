import ApexTermCore
import AppKit
import SwiftUI

struct TerminalProfilesSettingsView: View {
    @ObservedObject var model: AppModel

    private var activeProfile: ApexTerminalProfile {
        model.terminalProfiles.first(where: {
            $0.id == model.activeTerminalProfileID
        }) ?? model.terminalProfiles[0]
    }

    var body: some View {
        Form {
            Section("Active Profile") {
                Picker(
                    "Profile",
                    selection: Binding(
                        get: { model.activeTerminalProfileID },
                        set: { model.selectTerminalProfile(id: $0) }
                    )
                ) {
                    ForEach(model.terminalProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)

                TextField(
                    "Profile name",
                    text: Binding(
                        get: { activeProfile.name },
                        set: {
                            model.renameTerminalProfile(
                                id: activeProfile.id,
                                name: $0
                            )
                        }
                    )
                )

                HStack {
                    Button("New") {
                        model.addTerminalProfile()
                    }
                    Button("Duplicate") {
                        model.duplicateActiveTerminalProfile()
                    }
                    Button("Delete", role: .destructive) {
                        model.deleteTerminalProfile(id: activeProfile.id)
                    }
                    .disabled(model.terminalProfiles.count <= 1)
                    Spacer()
                }
            }

            Section("Profile Values") {
                LabeledContent("Terminal font") {
                    Text("\(Int(activeProfile.terminalFontSize.rounded())) pt")
                        .monospacedDigit()
                }
                LabeledContent("Sidebar font") {
                    Text("\(Int(activeProfile.sidebarFontSize.rounded())) pt")
                        .monospacedDigit()
                }
                LabeledContent("Command blocks") {
                    Text(activeProfile.commandBlocksEnabled ? "On" : "Off")
                }
                LabeledContent("Smart paste") {
                    Text(activeProfile.smartPasteProtectionEnabled ? "On" : "Off")
                }
                LabeledContent("Secure keyboard entry") {
                    Text(activeProfile.secureKeyboardEntryEnabled ? "On" : "Off")
                }

                Text("Terminal controls in General edit the active profile. Switching profiles immediately applies its terminal appearance and safety settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }
}

struct KeybindingsSettingsView: View {
    @ObservedObject var model: AppModel
    private let registry = ApexActionRegistry()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keyboard Shortcuts")
                        .font(.headline)
                    Text("Click a shortcut, then press the key combination you want. Esc cancels. Delete clears.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset Defaults") {
                    model.resetKeybindings()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            List {
                ForEach(model.configuredKeybindings) { binding in
                    KeybindingEditorRow(
                        model: model,
                        binding: binding,
                        action: registry.action(id: binding.actionID)
                    )
                }
            }
        }
    }
}

private struct KeybindingEditorRow: View {
    @ObservedObject var model: AppModel
    let binding: ApexKeybinding
    let action: ApexActionDescriptor?

    private var currentBinding: ApexKeybinding {
        model.configuredKeybindings.first(where: { $0.id == binding.id }) ?? binding
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action?.title ?? binding.actionID)
                    .font(.system(size: 13, weight: .medium))
                Text(action?.subtitle ?? binding.actionID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderField(
                displayName: currentBinding.chord.displayName,
                isEnabled: currentBinding.isEnabled,
                accessibilityLabel: action?.title ?? binding.actionID,
                accessibilityIdentifier: "shortcut-recorder-\(binding.actionID)",
                onRecord: { key, modifiers in
                    model.assignKeybinding(
                        id: binding.id,
                        key: key,
                        modifiers: modifiers
                    )
                },
                onClear: {
                    model.setKeybindingEnabled(false, id: binding.id)
                }
            )
            .frame(width: 170, height: 28)
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    let displayName: String
    let isEnabled: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let onRecord: (String, Set<ApexKeyModifier>) -> Bool
    let onClear: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(frame: .zero)
        button.onRecord = onRecord
        button.onClear = onClear
        button.configure(
            displayName: displayName,
            isEnabled: isEnabled,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier
        )
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onRecord = onRecord
        button.onClear = onClear
        button.configure(
            displayName: displayName,
            isEnabled: isEnabled,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

@MainActor
private final class ShortcutRecorderButton: NSButton {
    var onRecord: ((String, Set<ApexKeyModifier>) -> Bool)?
    var onClear: (() -> Void)?

    private var localKeyMonitor: Any?
    private var isRecording = false
    private var configuredDisplayName = ""
    private var configuredIsEnabled = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(beginRecording)
        bezelStyle = .rounded
        controlSize = .small
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        focusRingType = .default
        setButtonType(.momentaryPushIn)
        toolTip = "Click, then press the shortcut you want. Esc cancels. Delete clears."
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        displayName: String,
        isEnabled: Bool,
        accessibilityLabel: String,
        accessibilityIdentifier: String
    ) {
        configuredDisplayName = displayName
        configuredIsEnabled = isEnabled
        identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        setAccessibilityIdentifier(accessibilityIdentifier)
        setAccessibilityLabel("Shortcut for \(accessibilityLabel)")
        setAccessibilityValue(isEnabled ? displayName : "Not set")
        refreshTitleIfIdle()
    }

    @objc private func beginRecording() {
        guard !isRecording else { return }
        guard window?.makeFirstResponder(self) == true else {
            NSSound.beep()
            return
        }
        isRecording = true
        title = "Press shortcut…"
        setAccessibilityValue("Recording shortcut")
        installKeyMonitor()
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if isRecording {
            stopRecording()
        }
        return result
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, isRecording {
            stopRecording()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.isRecording else { return event }
            self.capture(event)
            return nil
        }
    }

    private func capture(_ event: NSEvent) {
        switch event.keyCode {
        case 53:
            stopRecordingAndReleaseFocus()
            return
        case 51, 117:
            onClear?()
            configuredIsEnabled = false
            stopRecordingAndReleaseFocus()
            return
        default:
            break
        }

        guard let key = Self.keyName(for: event) else {
            NSSound.beep()
            return
        }
        let modifiers = Self.modifiers(for: event.modifierFlags)
        guard onRecord?(key, modifiers) == true else {
            NSSound.beep()
            title = "Already in use"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.isRecording else { return }
                self.title = "Press shortcut…"
            }
            return
        }

        let chord = ApexKeyChord(key: key, modifiers: modifiers)
        configuredDisplayName = chord.displayName
        configuredIsEnabled = true
        stopRecordingAndReleaseFocus()
    }

    private func stopRecordingAndReleaseFocus() {
        stopRecording()
        _ = window?.makeFirstResponder(nil)
    }

    private func stopRecording() {
        isRecording = false
        removeKeyMonitor()
        refreshTitleIfIdle()
    }

    private func removeKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func refreshTitleIfIdle() {
        guard !isRecording else { return }
        title = configuredIsEnabled ? configuredDisplayName : "Not set"
    }

    private static func modifiers(
        for flags: NSEvent.ModifierFlags
    ) -> Set<ApexKeyModifier> {
        var result: Set<ApexKeyModifier> = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.function) { result.insert(.function) }
        return result
    }

    private static func keyName(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 36, 76: return "return"
        case 48: return "tab"
        case 49: return "space"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 115: return "home"
        case 119: return "end"
        case 116: return "pageup"
        case 121: return "pagedown"
        case 122: return "f1"
        case 120: return "f2"
        case 99: return "f3"
        case 118: return "f4"
        case 96: return "f5"
        case 97: return "f6"
        case 98: return "f7"
        case 100: return "f8"
        case 101: return "f9"
        case 109: return "f10"
        case 103: return "f11"
        case 111: return "f12"
        default:
            guard let characters = event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .controlCharacters),
                !characters.isEmpty else {
                return nil
            }
            return String(characters.prefix(1)).lowercased()
        }
    }
}
