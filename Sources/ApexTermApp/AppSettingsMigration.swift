import ApexTermCore
import Foundation

@MainActor
enum AppSettingsMigration {
    static func legacyDocument(
        defaults: UserDefaults = .standard
    ) -> ApexSettingsDocument {
        let terminalFontSize = bounded(
            defaults.double(forKey: "apexterm.font.terminal"),
            defaultValue: 13,
            range: 9...24
        )
        let sidebarFontSize = bounded(
            defaults.double(forKey: "apexterm.font.sidebar"),
            defaultValue: 12,
            range: 9...18
        )
        let uiControls: UIControlCustomization = {
            guard let data = defaults.data(
                forKey: "apexterm.ui.controlCustomization"
            ),
            let decoded = try? JSONDecoder().decode(
                UIControlCustomization.self,
                from: data
            ) else {
                return UIControlCustomization()
            }
            return decoded
        }()
        let legacyCommandBlocksEnabled = bool(
            defaults,
            key: "apexterm.terminal.commandBlocksEnabled",
            defaultValue: true
        )
        let transcriptMode = defaults.string(
            forKey: "apexterm.terminal.commandTranscriptMode"
        ).flatMap(CommandTranscriptMode.init(rawValue:))
            ?? (legacyCommandBlocksEnabled ? .on : .off)
        let profile = ApexTerminalProfile(
            id: ApexSettingsDocument.defaultProfileID,
            name: "Default",
            terminalFontSize: terminalFontSize,
            sidebarFontSize: sidebarFontSize,
            inputColorHex: defaults.string(
                forKey: "apexterm.terminal.inputColor"
            ) ?? TerminalAppearance.defaultInputColorHex,
            outputColorHex: defaults.string(
                forKey: "apexterm.terminal.outputColor"
            ) ?? TerminalAppearance.defaultOutputColorHex,
            commandBlocksEnabled: legacyCommandBlocksEnabled,
            commandTranscriptMode: transcriptMode,
            smartPasteProtectionEnabled: bool(
                defaults,
                key: "apexterm.terminal.smartPasteProtectionEnabled",
                defaultValue: true
            ),
            secureKeyboardEntryEnabled: defaults.bool(
                forKey: "apexterm.terminal.secureKeyboardEntryEnabled"
            )
        )
        let threshold = defaults.integer(
            forKey: "apexterm.terminal.autoCollapseLargeOutputLineThreshold"
        )
        let general = ApexGeneralSettings(
            languageCode: defaults.string(forKey: AppLanguage.defaultsKey)
                ?? AppLanguage.system.rawValue,
            compactMode: defaults.bool(forKey: "apexterm.compactMode"),
            pinMainWindow: defaults.bool(forKey: "apexterm.mainWindowPinned"),
            collapseLeftSidebar: defaults.bool(
                forKey: "apexterm.sidebar.leftCollapsed"
            ),
            collapseRightSidebar: defaults.bool(
                forKey: "apexterm.sidebar.rightCollapsed"
            ),
            showCommandHistory: defaults.object(
                forKey: "apexterm.commandHistory.visible"
            ) as? Bool ?? true,
            confirmMultilinePaste: defaults.bool(
                forKey: "apexterm.terminal.multilinePasteConfirmationEnabled"
            ),
            autoCopyCommandOutput: defaults.bool(
                forKey: "apexterm.terminal.autoCopyCommandOutputEnabled"
            ),
            autoCollapseLargeOutputs: bool(
                defaults,
                key: "apexterm.terminal.autoCollapseLargeOutputsEnabled",
                defaultValue: true
            ),
            autoCollapseLineThreshold: threshold == 0 ? 160 : threshold
        )

        return ApexSettingsDocument(
            activeProfileID: profile.id,
            profiles: [profile],
            keybindings: ApexSettingsDocument.defaultKeybindings,
            general: general,
            uiControls: uiControls
        )
    }

    private static func bool(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Bool
    ) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    private static func bounded(
        _ value: Double,
        defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        let resolved = value == 0 ? defaultValue : value
        return min(max(resolved, range.lowerBound), range.upperBound)
    }
}
