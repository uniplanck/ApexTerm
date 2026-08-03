import ApexTermCore
import SwiftUI

enum AppSettingsTab: Hashable {
    case general
    case profiles
    case keybindings
    case buttons
    case commands
    case remoteHosts
    case devSpace
}

struct AppSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("quickTerminalPinned") private var quickTerminalPinned = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            TabView(selection: $model.settingsTab) {
                generalSettings
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }
                    .tag(AppSettingsTab.general)

                TerminalProfilesSettingsView(model: model)
                    .tabItem {
                        Label("Profiles", systemImage: "person.crop.rectangle.stack")
                    }
                    .tag(AppSettingsTab.profiles)

                KeybindingsSettingsView(model: model)
                    .tabItem {
                        Label("Keybindings", systemImage: "keyboard")
                    }
                    .tag(AppSettingsTab.keybindings)

                UIControlCustomizationView(model: model)
                    .tabItem {
                        Label("Buttons", systemImage: "slider.horizontal.3")
                    }
                    .tag(AppSettingsTab.buttons)

                CommandPresetsSettingsView(model: model)
                    .tabItem {
                        Label("Commands", systemImage: "bolt.horizontal.circle")
                    }
                    .tag(AppSettingsTab.commands)

                RemoteHostSettingsView(model: model, embedded: true)
                    .tabItem {
                        Label("Remote Hosts", systemImage: "network")
                    }
                    .tag(AppSettingsTab.remoteHosts)

                DevSpaceSettingsView()
                    .tabItem {
                        Label("DevSpace", systemImage: "shippingbox")
                    }
                    .tag(AppSettingsTab.devSpace)
            }
            .padding(12)
        }
        .frame(minWidth: 720, minHeight: 520)
        .environment(\.locale, model.appLanguage.locale)
    }

    private var generalSettings: some View {
        Form {
            Section("Language") {
                Picker("Application language", selection: $model.languageCode) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text("Changes apply immediately to the main interface and Quick Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Interface appearance", selection: $model.interfaceAppearance) {
                    ForEach(ApexInterfaceAppearance.allCases) { appearance in
                        Text(LocalizedStringKey(appearance.title))
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                ColorPicker(
                    "Accent color",
                    selection: interfaceAccentColorBinding,
                    supportsOpacity: false
                )

                HStack {
                    Text("The accent color is used for selected tabs, panes, controls, and highlights.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use system accent") {
                        model.interfaceAccentColorHex = nil
                    }
                }
            }

            Section("Window Behavior") {
                Toggle("Compact Terminal Mode", isOn: $model.isCompactMode)
                Toggle("Pin Main Window Above Others", isOn: $model.isMainWindowPinned)
                Toggle("Pin Quick Terminal Above Others", isOn: $quickTerminalPinned)
            }

            Section("Terminal") {
                HStack {
                    Text("Terminal font size")
                    Spacer()
                    Text("\(Int(model.terminalFontSize.rounded())) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper(
                        "Terminal font size",
                        value: $model.terminalFontSize,
                        in: 9...24,
                        step: 1
                    )
                    .labelsHidden()
                }
                Slider(value: $model.terminalFontSize, in: 9...24, step: 1)

                Picker("Command transcript", selection: $model.commandTranscriptMode) {
                    ForEach(CommandTranscriptMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("command-transcript-mode-picker")

                Toggle(
                    "Start command output toggles closed",
                    isOn: $model.commandBlocksStartCollapsed
                )
                .disabled(model.commandTranscriptMode == .off)
                Toggle("Smart paste protection", isOn: $model.smartPasteProtectionEnabled)
                Toggle(
                    "Confirm before multi-line paste",
                    isOn: $model.multilinePasteConfirmationEnabled
                )
                .disabled(!model.smartPasteProtectionEnabled)
                Toggle("Secure keyboard entry", isOn: $model.secureKeyboardEntryEnabled)
                Toggle(
                    "Automatically copy command output",
                    isOn: $model.autoCopyCommandOutputEnabled
                )
                .accessibilityIdentifier("auto-copy-command-output-toggle")
                Toggle("Auto-collapse large outputs", isOn: $model.autoCollapseLargeOutputsEnabled)

                Stepper(
                    "Auto-collapse at \(model.autoCollapseLargeOutputLineThreshold) lines",
                    value: $model.autoCollapseLargeOutputLineThreshold,
                    in: 40...2_000,
                    step: 40
                )
                .disabled(!model.autoCollapseLargeOutputsEnabled)

                Text("Smart paste confirms trailing-newline and risky commands. Multi-line-only confirmation is off by default and can be enabled separately. Secure keyboard entry limits system-wide key event observation while enabled. Automatic output copy replaces the clipboard only when a completed command has non-empty output. Large outputs stay fully copyable while rendering a bounded preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ColorPicker(
                    "Input color",
                    selection: terminalColorBinding(
                        hex: $model.terminalInputColorHex,
                        fallback: TerminalAppearance.defaultInputColorHex
                    ),
                    supportsOpacity: false
                )

                ColorPicker(
                    "Output color",
                    selection: terminalColorBinding(
                        hex: $model.terminalOutputColorHex,
                        fallback: TerminalAppearance.defaultOutputColorHex
                    ),
                    supportsOpacity: false
                )

                HStack {
                    Text("Completed commands can be folded and copied as input, output, or both.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset colors") {
                        model.terminalInputColorHex = TerminalAppearance.defaultInputColorHex
                        model.terminalOutputColorHex = TerminalAppearance.defaultOutputColorHex
                    }
                }
            }

            Section("Sidebars") {
                HStack {
                    Text("Sidebar font size")
                    Spacer()
                    Text("\(Int(model.sidebarFontSize.rounded())) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper(
                        "Sidebar font size",
                        value: $model.sidebarFontSize,
                        in: 9...18,
                        step: 1
                    )
                    .labelsHidden()
                }
                Slider(value: $model.sidebarFontSize, in: 9...18, step: 1)

                Toggle("Collapse Left Sidebar", isOn: $model.isWorkspaceSidebarCollapsed)
                Toggle("Collapse Right Sidebar", isOn: $model.isRightSidebarCollapsed)
                Toggle("Show Command History", isOn: $model.isCommandHistoryVisible)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }

    private var interfaceAccentColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: model.interfaceAccentNSColor) },
            set: { color in
                model.interfaceAccentColorHex = NSColor(color).apexHex
            }
        )
    }

    private func terminalColorBinding(
        hex: Binding<String>,
        fallback: String
    ) -> Binding<Color> {
        Binding(
            get: {
                Color(nsColor: NSColor(apexHex: hex.wrappedValue)
                    ?? NSColor(apexHex: fallback)
                    ?? .textColor)
            },
            set: { color in
                hex.wrappedValue = NSColor(color).apexHex
            }
        )
    }
}
