import Foundation

public enum ApexKeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
    case function
}

public struct ApexKeyChord: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var modifiers: Set<ApexKeyModifier>

    public init(
        key: String,
        modifiers: Set<ApexKeyModifier> = []
    ) {
        self.key = Self.normalizedKey(key)
        self.modifiers = modifiers
    }

    public var displayName: String {
        let orderedModifiers: [(ApexKeyModifier, String)] = [
            (.control, "⌃"),
            (.option, "⌥"),
            (.shift, "⇧"),
            (.command, "⌘"),
            (.function, "fn")
        ]
        let prefix = orderedModifiers
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined()
        return prefix + Self.displayKey(key)
    }

    public static func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func displayKey(_ key: String) -> String {
        switch key {
        case "return", "enter": "↩"
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        case "space": "Space"
        case "tab": "⇥"
        case "escape", "esc": "⎋"
        case "backtick": "`"
        default: key.uppercased()
        }
    }
}

public enum ApexKeybindingScope: String, Codable, CaseIterable, Sendable {
    case global
    case terminal
    case agentChat
    case workspace
}

public struct ApexKeybinding: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var actionID: String
    public var chord: ApexKeyChord
    public var scope: ApexKeybindingScope
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        actionID: String,
        chord: ApexKeyChord,
        scope: ApexKeybindingScope = .global,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.actionID = actionID
        self.chord = chord
        self.scope = scope
        self.isEnabled = isEnabled
    }
}

public enum CommandTranscriptMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case on
    case off
    case ex

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .on: "On"
        case .off: "Off"
        case .ex: "Ex"
        }
    }

    public var systemImage: String {
        switch self {
        case .on: "rectangle.split.1x2"
        case .off: "rectangle.bottomhalf.filled"
        case .ex: "rectangle.topthird.inset.filled"
        }
    }

    public var showsTranscript: Bool { self != .off }
    public var recordLimit: Int { self == .ex ? 1 : 100 }

    public var next: Self {
        switch self {
        case .on: .off
        case .off: .ex
        case .ex: .on
        }
    }
}

public enum ApexInterfaceAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public struct TerminalCommandPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var command: String

    public init(
        id: UUID = UUID(),
        name: String,
        command: String
    ) {
        self.id = id
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.command = String(command.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000))
    }

    public var isValid: Bool {
        !name.isEmpty && !command.isEmpty
    }
}

public struct ApexTerminalProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var shellExecutable: String?
    public var defaultWorkingDirectory: String?
    public var terminalFontSize: Double
    public var sidebarFontSize: Double
    public var inputColorHex: String
    public var outputColorHex: String
    public var environment: [String: String]
    public var commandBlocksEnabled: Bool
    public var commandTranscriptMode: CommandTranscriptMode?
    public var smartPasteProtectionEnabled: Bool
    public var secureKeyboardEntryEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        shellExecutable: String? = nil,
        defaultWorkingDirectory: String? = nil,
        terminalFontSize: Double = 13,
        sidebarFontSize: Double = 12,
        inputColorHex: String,
        outputColorHex: String,
        environment: [String: String] = [:],
        commandBlocksEnabled: Bool = true,
        commandTranscriptMode: CommandTranscriptMode? = .on,
        smartPasteProtectionEnabled: Bool = true,
        secureKeyboardEntryEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.shellExecutable = shellExecutable
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.terminalFontSize = min(max(terminalFontSize, 9), 24)
        self.sidebarFontSize = min(max(sidebarFontSize, 9), 18)
        self.inputColorHex = inputColorHex
        self.outputColorHex = outputColorHex
        self.environment = environment
        self.commandBlocksEnabled = commandBlocksEnabled
        self.commandTranscriptMode = commandTranscriptMode
        self.smartPasteProtectionEnabled = smartPasteProtectionEnabled
        self.secureKeyboardEntryEnabled = secureKeyboardEntryEnabled
    }
}

public struct ApexGeneralSettings: Codable, Equatable, Sendable {
    public var languageCode: String
    public var interfaceAppearance: ApexInterfaceAppearance?
    public var accentColorHex: String?
    public var compactMode: Bool
    public var pinMainWindow: Bool
    public var collapseLeftSidebar: Bool
    public var collapseRightSidebar: Bool
    public var showCommandHistory: Bool
    public var confirmMultilinePaste: Bool
    public var autoCopyCommandOutput: Bool
    public var autoCollapseLargeOutputs: Bool
    public var autoCollapseLineThreshold: Int

    public init(
        languageCode: String = "system",
        interfaceAppearance: ApexInterfaceAppearance? = nil,
        accentColorHex: String? = nil,
        compactMode: Bool = false,
        pinMainWindow: Bool = false,
        collapseLeftSidebar: Bool = false,
        collapseRightSidebar: Bool = false,
        showCommandHistory: Bool = true,
        confirmMultilinePaste: Bool = false,
        autoCopyCommandOutput: Bool = false,
        autoCollapseLargeOutputs: Bool = true,
        autoCollapseLineThreshold: Int = 160
    ) {
        self.languageCode = languageCode
        self.interfaceAppearance = interfaceAppearance
        self.accentColorHex = accentColorHex
        self.compactMode = compactMode
        self.pinMainWindow = pinMainWindow
        self.collapseLeftSidebar = collapseLeftSidebar
        self.collapseRightSidebar = collapseRightSidebar
        self.showCommandHistory = showCommandHistory
        self.confirmMultilinePaste = confirmMultilinePaste
        self.autoCopyCommandOutput = autoCopyCommandOutput
        self.autoCollapseLargeOutputs = autoCollapseLargeOutputs
        self.autoCollapseLineThreshold = min(max(autoCollapseLineThreshold, 40), 2_000)
    }
}

public struct ApexSettingsDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var activeProfileID: UUID
    public var profiles: [ApexTerminalProfile]
    public var keybindings: [ApexKeybinding]
    public var general: ApexGeneralSettings
    public var uiControls: UIControlCustomization
    public var commandPresets: [TerminalCommandPreset]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        activeProfileID: UUID,
        profiles: [ApexTerminalProfile],
        keybindings: [ApexKeybinding] = Self.defaultKeybindings,
        general: ApexGeneralSettings = ApexGeneralSettings(),
        uiControls: UIControlCustomization = UIControlCustomization(),
        commandPresets: [TerminalCommandPreset] = []
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles.isEmpty
            ? [Self.defaultProfile]
            : Self.uniqueProfiles(profiles)
        self.activeProfileID = self.profiles.contains(where: { $0.id == activeProfileID })
            ? activeProfileID
            : self.profiles[0].id
        self.keybindings = Self.normalizedKeybindings(keybindings)
        self.general = general
        self.uiControls = uiControls
        self.commandPresets = Self.normalizedCommandPresets(commandPresets)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case activeProfileID
        case profiles
        case keybindings
        case general
        case uiControls
        case commandPresets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? Self.currentSchemaVersion,
            activeProfileID: try container.decode(UUID.self, forKey: .activeProfileID),
            profiles: try container.decode([ApexTerminalProfile].self, forKey: .profiles),
            keybindings: try container.decodeIfPresent([ApexKeybinding].self, forKey: .keybindings)
                ?? Self.defaultKeybindings,
            general: try container.decodeIfPresent(ApexGeneralSettings.self, forKey: .general)
                ?? ApexGeneralSettings(),
            uiControls: try container.decodeIfPresent(UIControlCustomization.self, forKey: .uiControls)
                ?? UIControlCustomization(),
            commandPresets: try container.decodeIfPresent(
                [TerminalCommandPreset].self,
                forKey: .commandPresets
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(activeProfileID, forKey: .activeProfileID)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(keybindings, forKey: .keybindings)
        try container.encode(general, forKey: .general)
        try container.encode(uiControls, forKey: .uiControls)
        try container.encode(commandPresets, forKey: .commandPresets)
    }

    public var activeProfile: ApexTerminalProfile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

    public mutating func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
    }

    public func keybinding(
        for actionID: String,
        scope: ApexKeybindingScope? = nil
    ) -> ApexKeybinding? {
        keybindings.first {
            $0.isEnabled
                && $0.actionID == actionID
                && (scope == nil || $0.scope == scope)
        }
    }

    public static let defaultProfileID = UUID(
        uuidString: "A0000000-0000-0000-0000-000000000001"
    )!

    public static let defaultProfile = ApexTerminalProfile(
        id: defaultProfileID,
        name: "Default",
        inputColorHex: "#B5DFFF",
        outputColorHex: "#EBEDEF"
    )

    public static let defaultKeybindings: [ApexKeybinding] = [
        binding("search.universal", "k", [.command]),
        binding("workspace.new", "n", [.command, .shift]),
        binding("command.palette", "p", [.command, .shift]),
        binding("terminal.quick", "backtick", [.control]),
        binding("tab.next", "tab", [.control]),
        binding("tab.previous", "tab", [.control, .shift]),
        ApexKeybinding(
            id: stableBindingID(actionID: "tab.moveLeft"),
            actionID: "tab.moveLeft",
            chord: ApexKeyChord(key: "left", modifiers: [.control, .command]),
            isEnabled: false
        ),
        ApexKeybinding(
            id: stableBindingID(actionID: "tab.moveRight"),
            actionID: "tab.moveRight",
            chord: ApexKeyChord(key: "right", modifiers: [.control, .command]),
            isEnabled: false
        ),
        binding("tab.select.1", "1", [.command]),
        binding("tab.select.2", "2", [.command]),
        binding("tab.select.3", "3", [.command]),
        binding("tab.select.4", "4", [.command]),
        binding("tab.select.5", "5", [.command]),
        binding("tab.select.6", "6", [.command]),
        binding("tab.select.7", "7", [.command]),
        binding("tab.select.8", "8", [.command]),
        binding("tab.select.9", "9", [.command]),
        binding("terminal.latestOutput.copy", "c", [.command, .option]),
        binding("terminal.transcript.cycle", "t", [.command, .option]),
        binding("history.toggle", "h", [.command, .control]),
        binding("sidebar.toggleLeft", "[", [.command, .option]),
        binding("sidebar.toggleRight", "]", [.command, .option]),
        binding("agent.new.local", "a", [.command, .shift]),
        binding("history.timeline", "y", [.command, .shift]),
        binding("history.search", "r", [.command, .shift]),
        binding("pane.split.vertical", "d", [.command]),
        binding("pane.split.horizontal", "d", [.command, .shift]),
        binding("pane.close", "w", [.command, .option]),
        binding("pane.maximize", "return", [.command, .shift]),
        binding("pane.next", "right", [.command, .option]),
        binding("pane.previous", "left", [.command, .option]),
        binding("pane.select.1", "1", [.control, .option]),
        binding("pane.select.2", "2", [.control, .option]),
        binding("pane.select.3", "3", [.control, .option]),
        binding("pane.select.4", "4", [.control, .option]),
        binding("terminal.find", "f", [.command]),
        binding(
            "terminal.secureInput.toggle",
            "k",
            [.command, .option, .shift]
        ),
        binding("agent.toggleRail", "a", [.command, .option]),
        binding("terminal.compact.toggle", "m", [.command, .option])
    ]

    private static func binding(
        _ actionID: String,
        _ key: String,
        _ modifiers: Set<ApexKeyModifier>
    ) -> ApexKeybinding {
        ApexKeybinding(
            id: stableBindingID(actionID: actionID),
            actionID: actionID,
            chord: ApexKeyChord(key: key, modifiers: modifiers)
        )
    }

    private static func stableBindingID(actionID: String) -> UUID {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in actionID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let suffix = String(format: "%012llX", hash & 0xFFFFFFFFFFFF)
        return UUID(uuidString: "A1000000-0000-0000-0000-\(suffix)")!
    }

    private static func uniqueProfiles(
        _ profiles: [ApexTerminalProfile]
    ) -> [ApexTerminalProfile] {
        var seen: Set<UUID> = []
        return profiles.filter { seen.insert($0.id).inserted }
    }

    private static func normalizedKeybindings(
        _ bindings: [ApexKeybinding]
    ) -> [ApexKeybinding] {
        var seenIDs: Set<UUID> = []
        var seenChords: Set<String> = []
        return bindings.filter { binding in
            guard !binding.actionID.isEmpty,
                  !binding.chord.key.isEmpty,
                  seenIDs.insert(binding.id).inserted else {
                return false
            }
            guard binding.isEnabled else { return true }
            let chordKey = "\(binding.scope.rawValue):\(binding.chord.displayName)"
            return seenChords.insert(chordKey).inserted
        }
    }

    private static func normalizedCommandPresets(
        _ presets: [TerminalCommandPreset]
    ) -> [TerminalCommandPreset] {
        var seenIDs: Set<UUID> = []
        return presets.compactMap { preset in
            let normalized = TerminalCommandPreset(
                id: preset.id,
                name: preset.name,
                command: preset.command
            )
            guard normalized.isValid,
                  seenIDs.insert(normalized.id).inserted else {
                return nil
            }
            return normalized
        }
    }
}
