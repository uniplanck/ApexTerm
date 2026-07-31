import ApexTermCore
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
                    Text("Changes apply immediately to the macOS menu commands.")
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

    @State private var key: String
    @State private var modifiers: Set<ApexKeyModifier>

    init(
        model: AppModel,
        binding: ApexKeybinding,
        action: ApexActionDescriptor?
    ) {
        self.model = model
        self.binding = binding
        self.action = action
        _key = State(initialValue: binding.chord.key)
        _modifiers = State(initialValue: binding.chord.modifiers)
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: {
                        model.configuredKeybindings.first(where: {
                            $0.id == binding.id
                        })?.isEnabled ?? false
                    },
                    set: {
                        model.setKeybindingEnabled($0, id: binding.id)
                    }
                )
            )
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(action?.title ?? binding.actionID)
                    .font(.system(size: 13, weight: .medium))
                Text(action?.subtitle ?? binding.actionID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                modifierToggle(.control, label: "⌃")
                modifierToggle(.option, label: "⌥")
                modifierToggle(.shift, label: "⇧")
                modifierToggle(.command, label: "⌘")
            }

            TextField("Key", text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)
                .onSubmit(commit)
                .onChange(of: key) { _, _ in
                    commit()
                }

            Text(ApexKeyChord(key: key, modifiers: modifiers).displayName)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .onChange(of: binding.chord) { _, newValue in
            key = newValue.key
            modifiers = newValue.modifiers
        }
    }

    private func modifierToggle(
        _ modifier: ApexKeyModifier,
        label: String
    ) -> some View {
        Toggle(
            label,
            isOn: Binding(
                get: { modifiers.contains(modifier) },
                set: { enabled in
                    if enabled {
                        modifiers.insert(modifier)
                    } else {
                        modifiers.remove(modifier)
                    }
                    commit()
                }
            )
        )
        .toggleStyle(.button)
        .frame(width: 34)
    }

    private func commit() {
        model.updateKeybinding(
            id: binding.id,
            key: key,
            modifiers: modifiers
        )
    }
}
