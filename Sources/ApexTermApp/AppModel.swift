import ApexTermCore
import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private var workspaceDomain: WorkspaceDomainStore
    @Published private(set) var settingsDocument: ApexSettingsDocument

    private(set) var workspaces: [Workspace] {
        get { workspaceDomain.workspaces }
        set {
            var domain = workspaceDomain
            domain.workspaces = newValue
            workspaceDomain = domain
        }
    }

    private(set) var sessions: [TerminalSession] {
        get { workspaceDomain.sessions }
        set {
            var domain = workspaceDomain
            domain.sessions = newValue
            workspaceDomain = domain
        }
    }

    var selectedWorkspaceID: UUID? {
        get { workspaceDomain.selectedWorkspaceID }
        set {
            var domain = workspaceDomain
            domain.selectedWorkspaceID = newValue
            workspaceDomain = domain
        }
    }

    var selectedSessionID: UUID? {
        get { workspaceDomain.selectedSessionID }
        set {
            var domain = workspaceDomain
            domain.selectedSessionID = newValue
            workspaceDomain = domain
        }
    }

    @Published private(set) var sshProfiles: [SSHHostProfile] = []
    @Published private(set) var remoteHostEntries: [RemoteHostEntry] = []
    @Published private(set) var deletedRemoteHostAliases: [String] = []
    @Published private(set) var remoteHostActionMessage: String?
    @Published var isRemoteHostSettingsPresented = false
    @Published var isTmuxSessionManagerPresented = false
    @Published private(set) var tmuxEndpointStates: [TmuxEndpointState] = []
    @Published private(set) var isTmuxRefreshing = false
    @Published private(set) var isTmuxActionRunning = false
    @Published private(set) var tmuxActionMessage: String?
    @Published var isSettingsPresented = false
    @Published var settingsTab: AppSettingsTab = .general
    @Published var terminalTitle = "01"
    @Published var currentDirectory: String?
    @Published var isAgentRailVisible = true
    @Published var isCommandPalettePresented = false
    @Published var isUniversalSearchPresented = false
    @Published var isCommandTimelinePresented = false
    @Published var isCommandHistorySearchPresented = false
    @Published private(set) var commandHistorySearchInitialQuery = ""
    @Published private(set) var commandHistorySearchSessionID: UUID?
    @Published var maximizedSessionID: UUID?
    @Published private(set) var agentRuns: [AgentRun] = []
    @Published private(set) var agentChatTabs: [AgentChatTab] = []
    @Published private(set) var mainTabOrder: [MainTabReference]
    @Published var selectedAgentChatID: UUID?
    @Published private(set) var agentChatFocusRequestGeneration: UInt64 = 0
    @Published private(set) var commandStatusBySession: [UUID: String] = [:]
    @Published private(set) var shellPromptReadySessionIDs: Set<UUID> = []
    @Published private(set) var remoteInteractiveSessionIDs: Set<UUID> = []
    @Published private(set) var activeCommandBySession: [UUID: String] = [:]
    @Published private(set) var conversationSendPendingSessionIDs: Set<UUID> = []
    @Published private(set) var commandTranscriptModeOverrides: [UUID: CommandTranscriptMode] = [:]
    @Published var terminalConversationDrafts: [UUID: String] = [:]
    @Published private(set) var scheduledTerminalCommands: [ScheduledTerminalCommand] = []
    @Published private(set) var commandHistory: [CommandExecutionRecord] = []
    @Published private(set) var collapsedCommandIDs: Set<UUID> = []
    @Published private(set) var commandPresets: [TerminalCommandPreset] = []
    @Published var isCommandHistoryVisible = true {
        didSet {
            UserDefaults.standard.set(
                isCommandHistoryVisible,
                forKey: "apexterm.commandHistory.visible"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var isWorkspaceSidebarCollapsed = false {
        didSet {
            UserDefaults.standard.set(
                isWorkspaceSidebarCollapsed,
                forKey: "apexterm.sidebar.leftCollapsed"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var isRightSidebarCollapsed = false {
        didSet {
            UserDefaults.standard.set(
                isRightSidebarCollapsed,
                forKey: "apexterm.sidebar.rightCollapsed"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var isMainWindowPinned = false {
        didSet {
            UserDefaults.standard.set(
                isMainWindowPinned,
                forKey: "apexterm.mainWindowPinned"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var uiControlCustomization: UIControlCustomization = {
        guard let data = UserDefaults.standard.data(forKey: "apexterm.ui.controlCustomization"),
              let decoded = try? JSONDecoder().decode(UIControlCustomization.self, from: data) else {
            return UIControlCustomization()
        }
        return decoded
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(uiControlCustomization) {
                UserDefaults.standard.set(data, forKey: "apexterm.ui.controlCustomization")
            }
            synchronizeSettingsDocument()
        }
    }
    @Published var terminalFontSize: Double = {
        let stored = UserDefaults.standard.double(forKey: "apexterm.font.terminal")
        return stored == 0 ? 13 : min(max(stored, 9), 24)
    }() {
        didSet {
            UserDefaults.standard.set(terminalFontSize, forKey: "apexterm.font.terminal")
            synchronizeSettingsDocument()
        }
    }
    @Published var sidebarFontSize: Double = {
        let stored = UserDefaults.standard.double(forKey: "apexterm.font.sidebar")
        return stored == 0 ? 12 : min(max(stored, 9), 18)
    }() {
        didSet {
            UserDefaults.standard.set(sidebarFontSize, forKey: "apexterm.font.sidebar")
            synchronizeSettingsDocument()
        }
    }
    @Published var secureKeyboardEntryEnabled = UserDefaults.standard.bool(
        forKey: "apexterm.terminal.secureKeyboardEntryEnabled"
    ) {
        didSet {
            UserDefaults.standard.set(
                secureKeyboardEntryEnabled,
                forKey: "apexterm.terminal.secureKeyboardEntryEnabled"
            )
            _ = SecureKeyboardEntryController.shared.setEnabled(
                secureKeyboardEntryEnabled
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var isCompactMode = UserDefaults.standard.bool(forKey: "apexterm.compactMode") {
        didSet {
            UserDefaults.standard.set(isCompactMode, forKey: "apexterm.compactMode")
            synchronizeSettingsDocument()
        }
    }
    @Published var terminalCommandBlocksEnabled = UserDefaults.standard.object(
        forKey: "apexterm.terminal.commandBlocksEnabled"
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(
                terminalCommandBlocksEnabled,
                forKey: "apexterm.terminal.commandBlocksEnabled"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var commandTranscriptMode: CommandTranscriptMode = {
        if let rawValue = UserDefaults.standard.string(
            forKey: "apexterm.terminal.commandTranscriptMode"
        ), let mode = CommandTranscriptMode(rawValue: rawValue) {
            return mode
        }
        let legacyEnabled = UserDefaults.standard.object(
            forKey: "apexterm.terminal.commandBlocksEnabled"
        ) as? Bool ?? true
        return legacyEnabled ? .on : .off
    }() {
        didSet {
            UserDefaults.standard.set(
                commandTranscriptMode.rawValue,
                forKey: "apexterm.terminal.commandTranscriptMode"
            )
            if commandTranscriptMode == .ex {
                collapsedCommandIDs.formUnion(commandHistory.map(\.id))
            }
            if commandTranscriptMode != .off && !terminalCommandBlocksEnabled {
                terminalCommandBlocksEnabled = true
            }
            synchronizeSettingsDocument()
        }
    }
    @Published var commandBlocksStartCollapsed = UserDefaults.standard.object(
        forKey: "apexterm.terminal.commandBlocksStartCollapsed"
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(
                commandBlocksStartCollapsed,
                forKey: "apexterm.terminal.commandBlocksStartCollapsed"
            )
        }
    }
    @Published var conversationCollapsedLineLimit: Int = {
        let stored = UserDefaults.standard.integer(
            forKey: "apexterm.terminal.conversationCollapsedLineLimit"
        )
        return min(max(stored == 0 ? 3 : stored, 1), 8)
    }() {
        didSet {
            UserDefaults.standard.set(
                min(max(conversationCollapsedLineLimit, 1), 8),
                forKey: "apexterm.terminal.conversationCollapsedLineLimit"
            )
        }
    }
    @Published var smartPasteProtectionEnabled = UserDefaults.standard.object(
        forKey: "apexterm.terminal.smartPasteProtectionEnabled"
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(
                smartPasteProtectionEnabled,
                forKey: "apexterm.terminal.smartPasteProtectionEnabled"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var multilinePasteConfirmationEnabled = UserDefaults.standard.bool(
        forKey: "apexterm.terminal.multilinePasteConfirmationEnabled"
    ) {
        didSet {
            UserDefaults.standard.set(
                multilinePasteConfirmationEnabled,
                forKey: "apexterm.terminal.multilinePasteConfirmationEnabled"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var autoCopyCommandOutputEnabled = UserDefaults.standard.bool(
        forKey: "apexterm.terminal.autoCopyCommandOutputEnabled"
    ) {
        didSet {
            UserDefaults.standard.set(
                autoCopyCommandOutputEnabled,
                forKey: "apexterm.terminal.autoCopyCommandOutputEnabled"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var autoCollapseLargeOutputsEnabled = UserDefaults.standard.object(
        forKey: "apexterm.terminal.autoCollapseLargeOutputsEnabled"
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(
                autoCollapseLargeOutputsEnabled,
                forKey: "apexterm.terminal.autoCollapseLargeOutputsEnabled"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var autoCollapseLargeOutputLineThreshold = max(
        40,
        UserDefaults.standard.integer(forKey: "apexterm.terminal.autoCollapseLargeOutputLineThreshold") == 0
            ? 160
            : UserDefaults.standard.integer(forKey: "apexterm.terminal.autoCollapseLargeOutputLineThreshold")
    ) {
        didSet {
            UserDefaults.standard.set(
                autoCollapseLargeOutputLineThreshold,
                forKey: "apexterm.terminal.autoCollapseLargeOutputLineThreshold"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var terminalInputColorHex = UserDefaults.standard.string(
        forKey: "apexterm.terminal.inputColor"
    ) ?? TerminalAppearance.defaultInputColorHex {
        didSet {
            UserDefaults.standard.set(
                terminalInputColorHex,
                forKey: "apexterm.terminal.inputColor"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var terminalOutputColorHex = UserDefaults.standard.string(
        forKey: "apexterm.terminal.outputColor"
    ) ?? TerminalAppearance.defaultOutputColorHex {
        didSet {
            UserDefaults.standard.set(
                terminalOutputColorHex,
                forKey: "apexterm.terminal.outputColor"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var mainWindowName = UserDefaults.standard.string(forKey: "apexterm.mainWindowName") ?? "Main Window" {
        didSet { UserDefaults.standard.set(mainWindowName, forKey: "apexterm.mainWindowName") }
    }
    @Published var languageCode = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey) ?? AppLanguage.system.rawValue {
        didSet {
            UserDefaults.standard.set(languageCode, forKey: AppLanguage.defaultsKey)
            synchronizeSettingsDocument()
        }
    }
    @Published var interfaceAppearance = ApexInterfaceAppearance(
        rawValue: UserDefaults.standard.string(forKey: "apexterm.interface.appearance") ?? ""
    ) ?? .system {
        didSet {
            UserDefaults.standard.set(
                interfaceAppearance.rawValue,
                forKey: "apexterm.interface.appearance"
            )
            synchronizeSettingsDocument()
        }
    }
    @Published var interfaceAccentColorHex = UserDefaults.standard.string(
        forKey: "apexterm.interface.accentColor"
    ) {
        didSet {
            if let interfaceAccentColorHex,
               !interfaceAccentColorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserDefaults.standard.set(
                    interfaceAccentColorHex,
                    forKey: "apexterm.interface.accentColor"
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: "apexterm.interface.accentColor"
                )
            }
            synchronizeSettingsDocument()
        }
    }
    @Published private(set) var persistenceMessage: String?
    @Published private(set) var transientNotice: String?

    private var transientNoticeGeneration: UInt64 = 0
    private let store: WorkspaceStore
    private let settingsStore: ApexSettingsStore
    private let commandBoundaryIndex = CommandBoundaryIndex()
    private let agentRunRegistry = AgentRunRegistry()
    private let automationStatusStore = AutomationStatusStore()
    private var automationServer: UnixAutomationServer?
    private var automationSocketURL: URL?
    private var nonInteractiveSSHAliases: Set<String> = []
    private var baseSSHProfiles: [SSHHostProfile] = []
    private var remoteHostConfiguration: RemoteHostConfiguration
    private let remoteHostConfigurationURL: URL
    private let eventStore: ApexEventStore?
    private let commandHistoryRecorder: CommandHistoryRecorder
    private let agentChatStoreURL: URL
    private let agentTransport: any AgentTransport = GagCLIAgentTransport()
    private var agentChatTasks: [UUID: Task<Void, Never>] = [:]
    private var directAutomationRequests: [UUID: DirectTerminalAutomationRequest] = [:]
    private var agentChatSaveTask: Task<Void, Never>?
    private var settingsSaveTask: Task<Void, Never>?
    private var scheduledCommandLoopTask: Task<Void, Never>?
    private var isApplyingSettingsDocument = false
    private var metadataSaveTask: Task<Void, Never>?
    private var tmuxRefreshTask: Task<Void, Never>?
    private var tmuxActionTask: Task<Void, Never>?
    private var agentChatCallbacks: [UUID: URL] = [:]
    private var deliveredAgentChatCallbacks: Set<UUID> = []
    private var agentEventFingerprints: [UUID: String] = [:]
    private static let mainTabOrderDefaultsKey = "apexterm.mainTabOrder.v1"
    private static let scheduledCommandsDefaultsKey = "apexterm.scheduledTerminalCommands.v1"

    init() {
        let supportDirectory = ApexTermPaths.supportDirectory()
        let workspaceFileURL = supportDirectory.appendingPathComponent("workspaces.json")
        let settingsFileURL = supportDirectory.appendingPathComponent("settings.json")
        let legacySettingsDocument = AppSettingsMigration.legacyDocument()
        let settingsFileExisted = FileManager.default.fileExists(
            atPath: settingsFileURL.path
        )
        var initialSettingsDocument = legacySettingsDocument
        var settingsPersistenceMessage: String?
        do {
            initialSettingsDocument = try ApexSettingsStore.loadSynchronously(
                from: settingsFileURL,
                defaults: legacySettingsDocument
            )
            if !settingsFileExisted {
                try ApexSettingsStore.saveSynchronously(
                    initialSettingsDocument,
                    to: settingsFileURL
                )
            }
            settingsPersistenceMessage = nil
        } catch let error as ApexSettingsStoreError {
            initialSettingsDocument = legacySettingsDocument
            switch error {
            case .unsupportedSchema:
                settingsPersistenceMessage = "Settings schema is newer; existing file was preserved"
            case .corruptFile:
                try? ApexSettingsStore.saveSynchronously(
                    legacySettingsDocument,
                    to: settingsFileURL
                )
                settingsPersistenceMessage = "Corrupt settings data was quarantined"
            }
        } catch {
            initialSettingsDocument = legacySettingsDocument
            try? ApexSettingsStore.saveSynchronously(
                legacySettingsDocument,
                to: settingsFileURL
            )
            settingsPersistenceMessage = "Settings recovery used migrated local preferences"
        }
        let remoteHostConfigurationURL = supportDirectory.appendingPathComponent("remote-hosts.json")
        let eventStore = try? ApexEventStore(
            fileURL: supportDirectory.appendingPathComponent("events.sqlite")
        )
        let commandHistoryRecorder = CommandHistoryRecorder(
            fileURL: supportDirectory.appendingPathComponent("command-history.json"),
            eventStore: eventStore
        )
        let agentChatStoreURL = supportDirectory.appendingPathComponent("agent-chat-tabs.json")
        let loadedAgentChatTabs = (try? AgentChatStore.load(from: agentChatStoreURL)) ?? []
        let loadedMainTabOrder = Self.loadMainTabOrder()
        let loadedRemoteHostConfiguration =
            (try? RemoteHostConfigurationStore.load(from: remoteHostConfigurationURL))
            ?? RemoteHostConfiguration()
        let fallbackDocument = Self.makeInitialDocument()
        let initialDocument: WorkspaceDocument
        let initialPersistenceMessage: String?

        do {
            let loadResult = try WorkspaceStore.loadResultSynchronously(
                from: workspaceFileURL
            )
            let loaded = loadResult.document
            if loaded.workspaces.isEmpty {
                try WorkspaceStore.saveSynchronously(
                    fallbackDocument,
                    to: workspaceFileURL
                )
                initialDocument = fallbackDocument
                initialPersistenceMessage = nil
            } else {
                initialDocument = loaded
                if let sourceVersion = loadResult.migratedFromSchemaVersion {
                    do {
                        try WorkspaceStore.saveSynchronously(
                            loaded,
                            to: workspaceFileURL
                        )
                        initialPersistenceMessage = "Workspace data upgraded from schema v\(sourceVersion) to v\(WorkspaceDocument.currentSchemaVersion)"
                    } catch {
                        initialPersistenceMessage = "Workspace data was upgraded in memory but could not be persisted"
                    }
                } else {
                    initialPersistenceMessage = nil
                }
            }
        } catch let error as WorkspaceStoreError {
            initialDocument = fallbackDocument
            switch error {
            case .unsupportedSchema:
                initialPersistenceMessage = "Workspace schema is newer; existing file was preserved"
            case .corruptFile:
                try? WorkspaceStore.saveSynchronously(
                    fallbackDocument,
                    to: workspaceFileURL
                )
                initialPersistenceMessage = "Corrupt workspace data was quarantined"
            }
        } catch {
            initialDocument = fallbackDocument
            try? WorkspaceStore.saveSynchronously(
                fallbackDocument,
                to: workspaceFileURL
            )
            initialPersistenceMessage = "Workspace recovery used a new local document"
        }

        var normalizedInitialDocument = initialDocument
        let sessionStatesChanged = normalizedInitialDocument.resetTransientSessionStates()
        let localShellTitlesChanged = Self.normalizeLocalShellTitles(
            in: &normalizedInitialDocument
        )
        if sessionStatesChanged || localShellTitlesChanged {
            try? WorkspaceStore.saveSynchronously(
                normalizedInitialDocument,
                to: workspaceFileURL
            )
        }

        self.workspaceDomain = WorkspaceDomainStore(
            document: normalizedInitialDocument
        )
        self.settingsDocument = initialSettingsDocument
        self.store = WorkspaceStore(fileURL: workspaceFileURL)
        self.settingsStore = ApexSettingsStore(fileURL: settingsFileURL)
        self.remoteHostConfigurationURL = remoteHostConfigurationURL
        self.remoteHostConfiguration = loadedRemoteHostConfiguration
        self.eventStore = eventStore
        self.commandHistoryRecorder = commandHistoryRecorder
        self.commandHistory = commandHistoryRecorder.snapshot()
        self.scheduledTerminalCommands = Self.loadScheduledTerminalCommands()
        self.agentChatStoreURL = agentChatStoreURL
        self.agentChatTabs = loadedAgentChatTabs
        self.mainTabOrder = MainTabOrder.normalized(
            loadedMainTabOrder,
            workspaceIDs: normalizedInitialDocument.workspaces.map(\.id),
            agentChatIDs: loadedAgentChatTabs.map(\.id)
        )
        let startupMessages = [
            settingsPersistenceMessage,
            initialPersistenceMessage
        ].compactMap { $0 }
        self.persistenceMessage = startupMessages.isEmpty
            ? nil
            : startupMessages.joined(separator: " · ")
        applySettingsDocument(initialSettingsDocument)
        if self.commandBlocksStartCollapsed {
            self.collapsedCommandIDs = Set(self.commandHistory.map(\.id))
        }

        loadSSHProfiles()
        normalizeGeneratedRemoteWorkspaces()
        refreshAutomationStatus()
        startAutomationServer(in: supportDirectory)
        resumeAgentChatMonitoring()
        persistMainTabOrder()
        _ = SecureKeyboardEntryController.shared.setEnabled(
            secureKeyboardEntryEnabled
        )
        resumeScheduledTerminalCommands()
    }

    var terminalProfiles: [ApexTerminalProfile] {
        settingsDocument.profiles
    }

    var activeTerminalProfileID: UUID {
        settingsDocument.activeProfileID
    }

    var configuredKeybindings: [ApexKeybinding] {
        var bindings = settingsDocument.keybindings
        let configuredActionIDs = Set(bindings.map(\.actionID))
        bindings.append(contentsOf: ApexSettingsDocument.defaultKeybindings.filter {
            !configuredActionIDs.contains($0.actionID)
        })
        return bindings
    }

    func selectTerminalProfile(id: UUID) {
        var document = settingsDocument
        document.selectProfile(id)
        guard document.activeProfileID != settingsDocument.activeProfileID else {
            return
        }
        applySettingsDocument(document)
        scheduleSettingsPersist(immediate: true)
    }

    func keybindingChord(
        for actionID: String,
        scope: ApexKeybindingScope = .global
    ) -> ApexKeyChord? {
        if let configured = settingsDocument.keybindings.first(where: {
            $0.actionID == actionID && $0.scope == scope
        }) {
            return configured.isEnabled ? configured.chord : nil
        }
        return ApexSettingsDocument.defaultKeybindings.first(where: {
            $0.actionID == actionID && $0.scope == scope && $0.isEnabled
        })?.chord
    }

    func setKeybindingEnabled(_ enabled: Bool, id: UUID) {
        var document = settingsDocument
        guard let index = materializeKeybinding(id: id, in: &document) else {
            return
        }
        let binding = document.keybindings[index]
        if enabled,
           hasEnabledKeybindingConflict(
               chord: binding.chord,
               scope: binding.scope,
               excluding: id
           ) {
            persistenceMessage = "Shortcut \(binding.chord.displayName) is already in use"
            return
        }
        document.keybindings[index].isEnabled = enabled
        settingsDocument = document
        persistenceMessage = nil
        scheduleSettingsPersist()
    }

    func updateKeybinding(
        id: UUID,
        key: String,
        modifiers: Set<ApexKeyModifier>
    ) {
        var document = settingsDocument
        guard let index = materializeKeybinding(id: id, in: &document) else {
            return
        }
        let chord = ApexKeyChord(key: key, modifiers: modifiers)
        guard !chord.key.isEmpty else { return }
        let existing = document.keybindings[index]
        if existing.isEnabled,
           hasEnabledKeybindingConflict(
               chord: chord,
               scope: existing.scope,
               excluding: id
           ) {
            persistenceMessage = "Shortcut \(chord.displayName) is already in use"
            return
        }
        document.keybindings[index].chord = chord
        settingsDocument = ApexSettingsDocument(
            schemaVersion: document.schemaVersion,
            activeProfileID: document.activeProfileID,
            profiles: document.profiles,
            keybindings: document.keybindings,
            general: document.general,
            uiControls: document.uiControls
        )
        persistenceMessage = nil
        scheduleSettingsPersist(immediate: true)
    }

    @discardableResult
    func assignKeybinding(
        id: UUID,
        key: String,
        modifiers: Set<ApexKeyModifier>
    ) -> Bool {
        var document = settingsDocument
        guard let index = materializeKeybinding(id: id, in: &document) else {
            return false
        }
        let chord = ApexKeyChord(key: key, modifiers: modifiers)
        guard !chord.key.isEmpty else { return false }
        let existing = document.keybindings[index]
        if hasEnabledKeybindingConflict(
            chord: chord,
            scope: existing.scope,
            excluding: id
        ) {
            persistenceMessage = "Shortcut \(chord.displayName) is already in use"
            return false
        }
        document.keybindings[index].chord = chord
        document.keybindings[index].isEnabled = true
        settingsDocument = ApexSettingsDocument(
            schemaVersion: document.schemaVersion,
            activeProfileID: document.activeProfileID,
            profiles: document.profiles,
            keybindings: document.keybindings,
            general: document.general,
            uiControls: document.uiControls
        )
        persistenceMessage = nil
        scheduleSettingsPersist(immediate: true)
        return true
    }

    private func materializeKeybinding(
        id: UUID,
        in document: inout ApexSettingsDocument
    ) -> Int? {
        if let index = document.keybindings.firstIndex(where: { $0.id == id }) {
            return index
        }
        guard let fallback = ApexSettingsDocument.defaultKeybindings.first(where: {
            $0.id == id
        }) else {
            return nil
        }
        document.keybindings.append(fallback)
        return document.keybindings.count - 1
    }

    private func hasEnabledKeybindingConflict(
        chord: ApexKeyChord,
        scope: ApexKeybindingScope,
        excluding id: UUID
    ) -> Bool {
        configuredKeybindings.contains {
            $0.id != id
                && $0.isEnabled
                && $0.scope == scope
                && $0.chord == chord
        }
    }

    func addTerminalProfile() {
        var document = settingsDocument
        var profile = document.activeProfile
        profile.id = UUID()
        profile.name = uniqueTerminalProfileName(base: "Profile")
        document.profiles.append(profile)
        document.activeProfileID = profile.id
        applySettingsDocument(document)
        scheduleSettingsPersist(immediate: true)
    }

    func duplicateActiveTerminalProfile() {
        var document = settingsDocument
        var profile = document.activeProfile
        profile.id = UUID()
        profile.name = uniqueTerminalProfileName(
            base: "\(profile.name) Copy"
        )
        document.profiles.append(profile)
        document.activeProfileID = profile.id
        applySettingsDocument(document)
        scheduleSettingsPersist(immediate: true)
    }

    func renameTerminalProfile(id: UUID, name: String) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let index = settingsDocument.profiles.firstIndex(where: {
                  $0.id == id
              }) else { return }
        var document = settingsDocument
        document.profiles[index].name = String(normalized.prefix(80))
        settingsDocument = document
        scheduleSettingsPersist(immediate: true)
    }

    func deleteTerminalProfile(id: UUID) {
        guard settingsDocument.profiles.count > 1,
              settingsDocument.profiles.contains(where: { $0.id == id }) else {
            return
        }
        var document = settingsDocument
        document.profiles.removeAll { $0.id == id }
        if document.activeProfileID == id {
            document.activeProfileID = document.profiles[0].id
            applySettingsDocument(document)
        } else {
            settingsDocument = document
        }
        scheduleSettingsPersist(immediate: true)
    }

    private func uniqueTerminalProfileName(base: String) -> String {
        let names = Set(settingsDocument.profiles.map { $0.name.lowercased() })
        guard names.contains(base.lowercased()) else { return base }
        for suffix in 2...999 {
            let candidate = "\(base) \(suffix)"
            if !names.contains(candidate.lowercased()) {
                return candidate
            }
        }
        return "\(base) \(UUID().uuidString.prefix(6))"
    }

    func resetKeybindings() {
        var document = settingsDocument
        document.keybindings = ApexSettingsDocument.defaultKeybindings
        settingsDocument = document
        scheduleSettingsPersist(immediate: true)
    }

    private func applySettingsDocument(_ document: ApexSettingsDocument) {
        isApplyingSettingsDocument = true
        defer { isApplyingSettingsDocument = false }

        settingsDocument = document
        let profile = document.activeProfile
        terminalFontSize = profile.terminalFontSize
        sidebarFontSize = profile.sidebarFontSize
        terminalInputColorHex = profile.inputColorHex
        terminalOutputColorHex = profile.outputColorHex
        terminalCommandBlocksEnabled = profile.commandBlocksEnabled
        commandTranscriptMode = profile.commandTranscriptMode
            ?? (profile.commandBlocksEnabled ? .on : .off)
        smartPasteProtectionEnabled = profile.smartPasteProtectionEnabled
        secureKeyboardEntryEnabled = profile.secureKeyboardEntryEnabled

        languageCode = document.general.languageCode
        interfaceAppearance = document.general.interfaceAppearance ?? .system
        interfaceAccentColorHex = document.general.accentColorHex
        isCompactMode = document.general.compactMode
        isMainWindowPinned = document.general.pinMainWindow
        isWorkspaceSidebarCollapsed = document.general.collapseLeftSidebar
        isRightSidebarCollapsed = document.general.collapseRightSidebar
        isCommandHistoryVisible = document.general.showCommandHistory
        multilinePasteConfirmationEnabled = document.general.confirmMultilinePaste
        autoCopyCommandOutputEnabled = document.general.autoCopyCommandOutput
        autoCollapseLargeOutputsEnabled = document.general.autoCollapseLargeOutputs
        autoCollapseLargeOutputLineThreshold = document.general.autoCollapseLineThreshold
        uiControlCustomization = document.uiControls
        commandPresets = document.commandPresets
    }

    private func synchronizeSettingsDocument() {
        guard !isApplyingSettingsDocument else { return }

        var document = settingsDocument
        guard let profileIndex = document.profiles.firstIndex(where: {
            $0.id == document.activeProfileID
        }) else { return }

        document.profiles[profileIndex].terminalFontSize = min(
            max(terminalFontSize, 9),
            24
        )
        document.profiles[profileIndex].sidebarFontSize = min(
            max(sidebarFontSize, 9),
            18
        )
        document.profiles[profileIndex].inputColorHex = terminalInputColorHex
        document.profiles[profileIndex].outputColorHex = terminalOutputColorHex
        document.profiles[profileIndex].commandBlocksEnabled = terminalCommandBlocksEnabled
        document.profiles[profileIndex].commandTranscriptMode = commandTranscriptMode
        document.profiles[profileIndex].smartPasteProtectionEnabled = smartPasteProtectionEnabled
        document.profiles[profileIndex].secureKeyboardEntryEnabled = secureKeyboardEntryEnabled

        document.general.languageCode = languageCode
        document.general.interfaceAppearance = interfaceAppearance
        document.general.accentColorHex = interfaceAccentColorHex
        document.general.compactMode = isCompactMode
        document.general.pinMainWindow = isMainWindowPinned
        document.general.collapseLeftSidebar = isWorkspaceSidebarCollapsed
        document.general.collapseRightSidebar = isRightSidebarCollapsed
        document.general.showCommandHistory = isCommandHistoryVisible
        document.general.confirmMultilinePaste = multilinePasteConfirmationEnabled
        document.general.autoCopyCommandOutput = autoCopyCommandOutputEnabled
        document.general.autoCollapseLargeOutputs = autoCollapseLargeOutputsEnabled
        document.general.autoCollapseLineThreshold = min(
            max(autoCollapseLargeOutputLineThreshold, 40),
            2_000
        )
        document.uiControls = uiControlCustomization
        document.commandPresets = commandPresets

        guard document != settingsDocument else { return }
        settingsDocument = document
        scheduleSettingsPersist()
    }

    private func scheduleSettingsPersist(immediate: Bool = false) {
        settingsSaveTask?.cancel()
        let snapshot = settingsDocument
        settingsSaveTask = Task { [weak self, settingsStore] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !Task.isCancelled else { return }
            do {
                try await settingsStore.save(snapshot)
            } catch {
                await MainActor.run { [weak self] in
                    self?.persistenceMessage = "Settings save failed"
                }
            }
            await MainActor.run { [weak self] in
                self?.settingsSaveTask = nil
            }
        }
    }

    var appLanguage: AppLanguage {
        AppLanguage.resolve(languageCode)
    }

    var interfaceAccentNSColor: NSColor {
        interfaceAccentColorHex
            .flatMap(NSColor.init(apexHex:))
            ?? .controlAccentColor
    }

    var terminalAppearance: TerminalAppearance {
        TerminalAppearance(
            inputColorHex: terminalInputColorHex,
            outputColorHex: terminalOutputColorHex
        )
    }

    var selectedWorkspace: Workspace? {
        workspaceDomain.selectedWorkspace
    }

    var selectedSession: TerminalSession? {
        workspaceDomain.selectedSession
    }

    var selectedAgentChat: AgentChatTab? {
        agentChatTabs.first { $0.id == selectedAgentChatID }
    }

    var orderedMainTabs: [MainTabReference] {
        mainTabOrder
    }

    var visibleTopBarControls: [UIControlID] {
        uiControlCustomization.topBarOrder.filter {
            $0.isTopBarReorderable && uiControlCustomization.isVisible($0)
        }
    }

    var visibleMainToolbarControls: [UIControlID] {
        uiControlCustomization.mainToolbarOrder.filter {
            $0.isMainToolbarSurfaceAvailable && uiControlCustomization.isVisible($0)
        }
    }

    func isUIControlVisible(_ control: UIControlID) -> Bool {
        uiControlCustomization.isVisible(control)
    }

    func setUIControlVisible(_ control: UIControlID, visible: Bool) {
        var customization = uiControlCustomization
        customization.setVisible(visible, for: control)
        uiControlCustomization = customization
    }

    func moveMainToolbarControl(_ control: UIControlID, before target: UIControlID) {
        var customization = uiControlCustomization
        customization.moveMainToolbarControl(control, before: target)
        uiControlCustomization = customization
    }

    func moveTopBarControl(
        _ control: UIControlID,
        relativeTo target: UIControlID,
        after: Bool
    ) {
        var customization = uiControlCustomization
        customization.moveTopBarControl(control, relativeTo: target, after: after)
        uiControlCustomization = customization
    }

    func resetTopBarCustomization() {
        var customization = uiControlCustomization
        customization.resetTopBar()
        uiControlCustomization = customization
    }

    func resetMainToolbarCustomization() {
        var customization = uiControlCustomization
        customization.resetMainToolbar()
        uiControlCustomization = customization
    }

    func session(id: UUID) -> TerminalSession? {
        sessions.first { $0.id == id }
    }

    func remoteProfile(alias: String) -> SSHHostProfile? {
        sshProfiles.first { $0.alias == alias }
            ?? remoteHostEntries.first { $0.profile.alias == alias }?.profile
    }

    func createAgentChatTab(target: GagTarget = .local) {
        let number = agentChatTabs.count + 1
        let tab = AgentChatTab(title: number == 1 ? "Agent Chat" : "Agent Chat \(number)", target: target)
        agentChatTabs.append(tab)
        mainTabOrder.append(.agentChat(tab.id))
        selectedAgentChatID = tab.id
        requestAgentChatFocus()
        persistMainTabOrder()
        scheduleAgentChatSave(immediate: true)
    }

    private func createAgentChatFromExternalURL(
        prompt: String,
        title: String?,
        target: GagTarget,
        callbackURL: URL?
    ) {
        createAgentChatTab(target: target)
        guard let id = selectedAgentChatID,
              let index = agentChatTabs.firstIndex(where: { $0.id == id }) else { return }
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        agentChatTabs[index].title = normalizedTitle.isEmpty ? Self.agentChatTitle(from: prompt) : String(normalizedTitle.prefix(80))
        agentChatTabs[index].draft = prompt
        agentChatTabs[index].updatedAt = Date()
        if let callbackURL {
            agentChatCallbacks[id] = callbackURL
        }
        scheduleAgentChatSave(immediate: true)
        sendAgentChat(id: id)
    }

    func selectAgentChat(id: UUID) {
        guard agentChatTabs.contains(where: { $0.id == id }),
              selectedAgentChatID != id else { return }
        selectedAgentChatID = id
        requestAgentChatFocus()
    }

    func closeAgentChatTab(id: UUID) {
        agentChatTasks[id]?.cancel()
        agentChatTasks[id] = nil
        agentEventFingerprints[id] = nil
        guard let index = agentChatTabs.firstIndex(where: { $0.id == id }) else { return }
        agentChatTabs.remove(at: index)
        mainTabOrder.removeAll { $0 == .agentChat(id) }
        persistMainTabOrder()
        if selectedAgentChatID == id {
            if agentChatTabs.isEmpty {
                selectedAgentChatID = nil
            } else {
                selectedAgentChatID = agentChatTabs[min(index, agentChatTabs.count - 1)].id
                requestAgentChatFocus()
            }
        }
        scheduleAgentChatSave(immediate: true)
    }

    private func requestAgentChatFocus() {
        agentChatFocusRequestGeneration &+= 1
    }

    func reorderMainTab(
        dragged: MainTabReference,
        relativeTo target: MainTabReference,
        after: Bool
    ) {
        let reordered = MainTabOrder.moving(
            dragged,
            relativeTo: target,
            after: after,
            in: mainTabOrder
        )
        guard reordered != mainTabOrder else { return }
        mainTabOrder = reordered
        selectMainTab(dragged)
        persistMainTabOrder()
    }

    func moveMainTab(_ tab: MainTabReference, offset: Int) {
        guard offset != 0,
              let sourceIndex = mainTabOrder.firstIndex(of: tab) else { return }
        let destination = min(max(0, sourceIndex + offset), mainTabOrder.count - 1)
        guard destination != sourceIndex else { return }
        let item = mainTabOrder.remove(at: sourceIndex)
        mainTabOrder.insert(item, at: destination)
        selectMainTab(tab)
        persistMainTabOrder()
    }

    func selectMainTab(_ tab: MainTabReference) {
        switch tab.kind {
        case .workspace:
            guard let workspace = workspaces.first(where: { $0.id == tab.uuid }) else { return }
            selectWorkspace(workspace)
        case .agentChat:
            selectAgentChat(id: tab.uuid)
        }
    }

    private var selectedMainTabReference: MainTabReference? {
        if let selectedAgentChatID {
            return .agentChat(selectedAgentChatID)
        }
        if let selectedWorkspaceID {
            return .workspace(selectedWorkspaceID)
        }
        return nil
    }

    func moveSelectedMainTab(offset: Int) {
        guard let selectedMainTabReference else { return }
        moveMainTab(selectedMainTabReference, offset: offset)
    }

    func selectAdjacentMainTab(offset: Int) {
        guard !mainTabOrder.isEmpty, offset != 0 else { return }
        let currentIndex = selectedMainTabReference.flatMap(mainTabOrder.firstIndex(of:)) ?? 0
        let count = mainTabOrder.count
        let targetIndex = ((currentIndex + offset) % count + count) % count
        selectMainTab(mainTabOrder[targetIndex])
    }

    func selectMainTab(number: Int) {
        let index = number - 1
        guard mainTabOrder.indices.contains(index) else { return }
        selectMainTab(mainTabOrder[index])
    }

    func renameAgentChatTab(id: UUID, to value: String) {
        guard let index = agentChatTabs.firstIndex(where: { $0.id == id }) else { return }
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        agentChatTabs[index].title = String(title.prefix(80))
        agentChatTabs[index].updatedAt = Date()
        scheduleAgentChatSave(immediate: true)
    }

    func updateAgentChatDraft(id: UUID, value: String) {
        guard let index = agentChatTabs.firstIndex(where: { $0.id == id }) else { return }
        agentChatTabs[index].draft = value
        agentChatTabs[index].updatedAt = Date()
        scheduleAgentChatSave()
    }

    func setAgentChatTarget(id: UUID, target: GagTarget) {
        guard let index = agentChatTabs.firstIndex(where: { $0.id == id }),
              !agentChatTabs[index].isRunning else { return }
        agentChatTabs[index].target = target
        agentChatTabs[index].updatedAt = Date()
        scheduleAgentChatSave(immediate: true)
    }

    func setAgentChatPerformance(id: UUID, performance: GagPerformance) {
        guard let index = agentChatTabs.firstIndex(where: { $0.id == id }),
              !agentChatTabs[index].isRunning else { return }
        agentChatTabs[index].performance = performance
        agentChatTabs[index].updatedAt = Date()
        scheduleAgentChatSave(immediate: true)
    }

    func sendAgentChat(id: UUID) {
        guard let index = agentChatTabs.firstIndex(where: { $0.id == id }),
              !agentChatTabs[index].isRunning else { return }
        let prompt = agentChatTabs[index].draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let target = agentChatTabs[index].target
        let performance = agentChatTabs[index].selectedPerformance
        let conversationURL = agentChatTabs[index].activeJob?.target == target
            ? agentChatTabs[index].metrics?.conversationURL
            : nil
        let title = agentChatTabs[index].title == "Agent Chat" || agentChatTabs[index].title.hasPrefix("Agent Chat ")
            ? Self.agentChatTitle(from: prompt)
            : agentChatTabs[index].title
        agentChatTabs[index].title = title
        agentChatTabs[index].draft = ""
        agentChatTabs[index].lastError = nil
        agentChatTabs[index].messages.append(
            AgentChatMessage(
                role: .user,
                text: prompt,
                requestedPerformance: performance
            )
        )
        agentChatTabs[index].updatedAt = Date()
        scheduleAgentChatSave(immediate: true)
        launchAgentChat(
            tabID: id,
            prompt: prompt,
            target: target,
            performance: performance,
            title: title,
            conversationURL: conversationURL
        )
    }

    func cancelAgentChat(id: UUID) {
        guard let tab = agentChatTabs.first(where: { $0.id == id }),
              let reference = tab.metrics?.reference else { return }
        agentChatTasks[id]?.cancel()
        agentChatTasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let cancelled = try await agentTransport.cancel(reference: reference)
                applyAgentChatJob(cancelled, to: id)
                finalizeAgentChatJob(cancelled, in: id)
            } catch {
                setAgentChatError(error.localizedDescription, tabID: id)
            }
        }
    }

    func openAgentChatConversation(id: UUID) {
        guard let url = agentChatTabs.first(where: { $0.id == id })?.metrics?.conversationURL else {
            return
        }
        ChatConversationOpener.open(url)
    }

    private func launchAgentChat(
        tabID: UUID,
        prompt: String,
        target: GagTarget,
        performance: GagPerformance,
        title: String,
        conversationURL: URL?
    ) {
        agentChatTasks[tabID]?.cancel()
        agentChatTasks[tabID] = Task { [weak self] in
            guard let self else { return }
            do {
                let started = try await agentTransport.start(
                    prompt: prompt,
                    target: target,
                    performance: performance,
                    title: title,
                    conversationURL: conversationURL
                )
                await monitorAgentChat(tabID: tabID, initial: started)
            } catch is CancellationError {
                return
            } catch {
                setAgentChatError(error.localizedDescription, tabID: tabID)
            }
        }
    }

    private func monitorAgentChat(
        tabID: UUID,
        initial: GagTargetedJob
    ) async {
        let reference = GagJobReference(
            target: initial.target,
            jobID: initial.job.id
        ).serialized
        var receivedTerminalUpdate = false

        do {
            for try await update in agentTransport.updates(
                reference: reference,
                initial: initial
            ) {
                guard !Task.isCancelled else { return }
                applyAgentChatJob(update, to: tabID)
                if update.job.status.isTerminal
                    || update.job.status == .waitingApproval
                    || update.job.status == .interrupted {
                    receivedTerminalUpdate = true
                    finalizeAgentChatJob(update, in: tabID)
                    return
                }
            }

            if !Task.isCancelled && !receivedTerminalUpdate {
                setAgentChatError(
                    "Agent update stream ended before the job completed",
                    tabID: tabID
                )
            }
        } catch is CancellationError {
            return
        } catch {
            setAgentChatError(error.localizedDescription, tabID: tabID)
        }
    }

    private func applyAgentChatJob(_ targetedJob: GagTargetedJob, to tabID: UUID) {
        guard let index = agentChatTabs.firstIndex(where: { $0.id == tabID }) else { return }
        agentChatTabs[index].activeJob = targetedJob
        agentChatTabs[index].metrics = GagRuntimeMetrics.calculate(
            target: targetedJob.target,
            job: targetedJob.job
        )
        deliverAgentChatCallbackIfNeeded(tabID: tabID)
        agentChatTabs[index].lastError = targetedJob.job.error
        agentChatTabs[index].updatedAt = Date()
        recordAgentEventIfChanged(targetedJob, tabID: tabID)
        scheduleAgentChatSave()
    }

    private func recordAgentEventIfChanged(
        _ targetedJob: GagTargetedJob,
        tabID: UUID
    ) {
        guard let eventStore else { return }
        let job = targetedJob.job
        let fingerprint = [
            job.status.rawValue,
            String(job.progress),
            job.currentStep,
            job.error ?? "",
            String(job.state?.responseText?.count ?? 0)
        ].joined(separator: "|")
        guard agentEventFingerprints[tabID] != fingerprint else { return }
        agentEventFingerprints[tabID] = fingerprint

        let reference = GagJobReference(
            target: targetedJob.target,
            jobID: job.id
        ).serialized
        Task.detached(priority: .utility) {
            try? eventStore.appendJSON(
                kind: .agent,
                subjectID: reference,
                occurredAt: Date(),
                payload: targetedJob
            )
            try? eventStore.prune(kind: .agent, keeping: 5_000)
        }
    }

    private func finalizeAgentChatJob(_ targetedJob: GagTargetedJob, in tabID: UUID) {
        guard let index = agentChatTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let reference = GagJobReference(target: targetedJob.target, jobID: targetedJob.job.id).serialized
        if targetedJob.job.status == .succeeded,
           let response = targetedJob.job.state?.responseText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !response.isEmpty,
           !agentChatTabs[index].messages.contains(where: { $0.jobReference == reference && $0.role == .assistant }) {
            agentChatTabs[index].messages.append(
                AgentChatMessage(
                    role: .assistant,
                    text: response,
                    jobReference: reference,
                    requestedPerformance: targetedJob.job.state?.requestedPerformance
                        ?? targetedJob.job.input?.performance
                        ?? .high,
                    selectedModel: targetedJob.job.state?.selectedModel,
                    selectedModelLabel: targetedJob.job.state?.selectedModelLabel,
                    apiCostEstimate: targetedJob.job.state?.apiCostEstimate
                )
            )
        } else if let error = targetedJob.job.error, !error.isEmpty {
            agentChatTabs[index].lastError = error
        }
        agentChatTabs[index].updatedAt = Date()
        scheduleAgentChatSave(immediate: true)
    }

    private func deliverAgentChatCallbackIfNeeded(tabID: UUID) {
        guard !deliveredAgentChatCallbacks.contains(tabID),
              let callbackURL = agentChatCallbacks[tabID],
              let conversationURL = agentChatTabs.first(where: { $0.id == tabID })?.metrics?.conversationURL,
              var components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else { return }
        var items = components.queryItems ?? []
        items.removeAll { ["chatUrl", "agentStatus"].contains($0.name) }
        items.append(URLQueryItem(name: "chatUrl", value: conversationURL.absoluteString))
        items.append(URLQueryItem(name: "agentStatus", value: "running"))
        components.queryItems = items
        guard let resolved = components.url else { return }
        deliveredAgentChatCallbacks.insert(tabID)
        NSWorkspace.shared.open(resolved)
    }

    private func setAgentChatError(_ message: String, tabID: UUID) {
        guard let index = agentChatTabs.firstIndex(where: { $0.id == tabID }) else { return }
        agentChatTabs[index].lastError = message
        agentChatTabs[index].updatedAt = Date()
        scheduleAgentChatSave(immediate: true)
    }

    private func resumeAgentChatMonitoring() {
        for tab in agentChatTabs {
            guard let job = tab.activeJob,
                  !job.job.status.isTerminal,
                  job.job.status != .waitingApproval,
                  job.job.status != .interrupted else { continue }
            agentChatTasks[tab.id] = Task { [weak self] in
                await self?.monitorAgentChat(tabID: tab.id, initial: job)
            }
        }
    }

    private func scheduleAgentChatSave(immediate: Bool = false) {
        agentChatSaveTask?.cancel()
        let snapshot = agentChatTabs
        let fileURL = agentChatStoreURL
        agentChatSaveTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled else { return }
            _ = await Task.detached(priority: .utility) {
                try? AgentChatStore.save(snapshot, to: fileURL)
            }.value
        }
    }

    private static func agentChatTitle(from prompt: String) -> String {
        let normalized = prompt.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(32))
    }

    func createWorkspace() {
        let session = Self.makeLocalSession()
        let workspace = Workspace(
            name: "Workspace \(workspaces.count + 1)",
            rootDirectory: session.workingDirectory,
            layout: .column(TerminalColumn(sessionID: session.id))
        )
        sessions.append(session)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        selectedSessionID = session.id
        commitState()
    }

    func handleExternalURL(_ url: URL) {
        guard url.scheme?.lowercased() == "apexterm" else {
            persistenceMessage = "Unsupported ApexTerm URL"
            return
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            persistenceMessage = "Invalid ApexTerm URL"
            return
        }

        if url.host?.lowercased() == "agent-chat" {
            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let prompt = values["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !prompt.isEmpty else {
                persistenceMessage = "Agent Chat URL requires a prompt"
                return
            }
            let target: GagTarget = values["target"] == "gae" ? .gae : .local
            let callbackURL = values["callback"].flatMap(URL.init(string:))
            createAgentChatFromExternalURL(
                prompt: prompt,
                title: values["title"],
                target: target,
                callbackURL: callbackURL
            )
            return
        }

        guard url.host?.lowercased() == "open",
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else {
            persistenceMessage = "ApexTerm URL requires a folder path"
            return
        }

        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            persistenceMessage = "Folder is unavailable: \(directory.path)"
            return
        }
        createWorkspace(at: directory)
    }

    func createWorkspace(at directory: URL) {
        _ = openProjects(from: [directory])
    }

    @discardableResult
    func openProjects(from urls: [URL]) -> Bool {
        var seen = Set<String>()
        let directories = urls.compactMap { url -> URL? in
            guard url.isFileURL else { return nil }
            let normalized = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  seen.insert(normalized.path).inserted else {
                return nil
            }
            return normalized
        }
        guard !directories.isEmpty else {
            persistenceMessage = "Drop one or more folders to open them as Projects"
            return false
        }

        var lastWorkspaceID: UUID?
        var lastSessionID: UUID?
        var created = false

        for directory in directories {
            if let workspace = workspaces.first(where: { $0.rootDirectory == directory.path }),
               let sessionID = SplitTreeOperations.sessionIDs(in: workspace.layout).first {
                lastWorkspaceID = workspace.id
                lastSessionID = sessionID
                continue
            }

            let title = directory.lastPathComponent.isEmpty ? directory.path : directory.lastPathComponent
            let session = TerminalSession(
                title: title,
                kind: .local,
                state: .created,
                workingDirectory: directory.path
            )
            let workspace = Workspace(
                name: title,
                rootDirectory: directory.path,
                layout: .column(TerminalColumn(sessionID: session.id))
            )
            sessions.append(session)
            workspaces.append(workspace)
            lastWorkspaceID = workspace.id
            lastSessionID = session.id
            created = true
        }

        selectedWorkspaceID = lastWorkspaceID
        selectedSessionID = lastSessionID
        persistenceMessage = nil
        if created {
            commitState()
        } else {
            refreshAutomationStatus()
        }
        return true
    }

    func createNamedLocalTmuxWorkspace(name: String) {
        let normalized = LocalSessionLaunchPlanBuilder(
            tmuxExecutable: "tmux",
            shellExecutable: "/bin/zsh"
        ).normalizedSessionName(name)
        guard let normalized else {
            persistenceMessage = "tmux session name is required"
            return
        }
        guard LocalToolDiscovery.firstExecutable(named: "tmux") != nil else {
            persistenceMessage = "tmux is not installed on this Mac"
            return
        }
        let kind = SessionKind.localTmux(session: normalized)
        if let existingSession = sessions.first(where: { $0.kind == kind }),
           let existingWorkspace = workspaces.first(where: {
               SplitTreeOperations.sessionIDs(in: $0.layout).contains(existingSession.id)
           }) {
            selectedAgentChatID = nil
            selectedWorkspaceID = existingWorkspace.id
            selectedSessionID = existingSession.id
            refreshAutomationStatus()
            return
        }
        let session = TerminalSession(
            title: normalized,
            kind: kind,
            state: .created,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        let workspace = Workspace(
            name: normalized,
            rootDirectory: session.workingDirectory,
            layout: .column(TerminalColumn(sessionID: session.id))
        )
        sessions.append(session)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        selectedSessionID = session.id
        commitState()
    }

    func workspaceContainsTmux(_ workspace: Workspace) -> Bool {
        SplitTreeOperations.sessionIDs(in: workspace.layout)
            .compactMap(session(id:))
            .contains { terminal in
                switch terminal.kind {
                case .localTmux, .tmux:
                    true
                case .local, .ssh:
                    false
                }
            }
    }

    func closeWorkspaceAndKillTmux(id: UUID) {
        guard !isTmuxActionRunning else {
            tmuxActionMessage = "別のtmux終了処理が実行中です"
            return
        }
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        let targets = SplitTreeOperations.sessionIDs(in: workspace.layout)
            .compactMap(session(id:))
            .compactMap(tmuxDescriptor(for:))
        guard !targets.isEmpty else {
            closeWorkspace(id: id)
            return
        }
        startTmuxKill(targets, refreshAfter: false) { [weak self] outcomes in
            guard let self else { return }
            if outcomes.allSatisfy(\.succeeded) {
                closeWorkspace(id: id)
            } else {
                tmuxActionMessage = (tmuxActionMessage ?? "tmux終了に失敗しました")
                    + "。タブは閉じずに維持しました"
                persistenceMessage = tmuxActionMessage
            }
        }
    }

    func refreshTmuxSessions(clearMessage: Bool = true) {
        tmuxRefreshTask?.cancel()
        let profiles = ProcessInfo.processInfo.environment["APEXTERM_TMUX_MANAGER_LOCAL_ONLY"] == "1"
            ? []
            : remoteHostEntries.map(\.profile)
        let serverName = localTmuxServerName
        let tmuxExecutable = LocalToolDiscovery.firstExecutable(named: "tmux")
        let sshExecutable = resolvedSSHExecutable
        isTmuxRefreshing = true
        if clearMessage {
            tmuxActionMessage = nil
        }
        tmuxRefreshTask = Task { [weak self] in
            let states = await TmuxSessionRuntime.refresh(
                localServerName: serverName,
                localExecutable: tmuxExecutable,
                remoteProfiles: profiles,
                sshExecutable: sshExecutable
            )
            guard !Task.isCancelled, let self else { return }
            tmuxEndpointStates = states
            isTmuxRefreshing = false
            tmuxRefreshTask = nil
        }
    }

    func openTmuxSession(_ descriptor: TmuxSessionDescriptor) {
        switch descriptor.endpoint {
        case .localApexTerm:
            createNamedLocalTmuxWorkspace(name: descriptor.name)
        case let .remote(alias):
            guard let profile = remoteProfile(alias: alias) else {
                tmuxActionMessage = "リモート接続設定が見つかりません: \(alias)"
                return
            }
            createRemoteWorkspace(profile: profile, tmuxSession: descriptor.name)
        }
    }

    func killTmuxSessions(_ descriptors: [TmuxSessionDescriptor]) {
        startTmuxKill(descriptors, refreshAfter: true)
    }

    func tmuxEndpointTitle(_ endpoint: TmuxEndpoint) -> String {
        switch endpoint {
        case .localApexTerm:
            "このMac · ApexTerm"
        case let .remote(alias):
            remoteProfile(alias: alias)?.displayTitle ?? alias
        }
    }

    private func startTmuxKill(
        _ descriptors: [TmuxSessionDescriptor],
        refreshAfter: Bool,
        completion: (([TmuxKillOutcome]) -> Void)? = nil
    ) {
        var uniqueByID: [String: TmuxSessionDescriptor] = [:]
        for descriptor in descriptors {
            uniqueByID[descriptor.id] = descriptor
        }
        let unique = Array(uniqueByID.values)
        guard !unique.isEmpty else { return }
        tmuxActionTask?.cancel()
        let tmuxExecutable = LocalToolDiscovery.firstExecutable(named: "tmux")
        let profiles = remoteProfilesByAlias
        let sshExecutable = resolvedSSHExecutable
        isTmuxActionRunning = true
        tmuxActionMessage = nil
        tmuxActionTask = Task { [weak self] in
            let outcomes = await TmuxSessionRuntime.kill(
                unique,
                localExecutable: tmuxExecutable,
                remoteProfiles: profiles,
                sshExecutable: sshExecutable
            )
            guard !Task.isCancelled, let self else { return }
            let succeededIDs = Set(outcomes.filter(\.succeeded).map(\.session.id))
            tmuxEndpointStates = tmuxEndpointStates.map { state in
                TmuxEndpointState(
                    endpoint: state.endpoint,
                    sessions: state.sessions.filter { !succeededIDs.contains($0.id) },
                    message: state.message
                )
            }
            let failures = outcomes.filter { !$0.succeeded }
            if failures.isEmpty {
                tmuxActionMessage = "tmuxセッションを\(outcomes.count)件終了しました"
            } else {
                tmuxActionMessage = "\(outcomes.count - failures.count)件終了、\(failures.count)件失敗: \(failures.first?.message ?? "不明なエラー")"
            }
            persistenceMessage = tmuxActionMessage
            isTmuxActionRunning = false
            tmuxActionTask = nil
            completion?(outcomes)
            if refreshAfter {
                refreshTmuxSessions(clearMessage: false)
            }
        }
    }

    private func tmuxDescriptor(for terminal: TerminalSession) -> TmuxSessionDescriptor? {
        switch terminal.kind {
        case let .localTmux(name):
            TmuxSessionDescriptor(
                endpoint: .localApexTerm(serverName: localTmuxServerName),
                name: name,
                windowCount: 0,
                attachedClientCount: 0,
                createdAt: nil
            )
        case let .tmux(host, name):
            TmuxSessionDescriptor(
                endpoint: .remote(alias: host),
                name: name,
                windowCount: 0,
                attachedClientCount: 0,
                createdAt: nil
            )
        case .local, .ssh:
            nil
        }
    }

    private var localTmuxServerName: String {
        ApexTermPaths.tmuxServerName(environment: ProcessInfo.processInfo.environment)
    }

    private var resolvedSSHExecutable: String {
        let value = ProcessInfo.processInfo.environment["APEXTERM_SSH_EXECUTABLE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin/ssh"
    }

    private var remoteProfilesByAlias: [String: SSHHostProfile] {
        var result: [String: SSHHostProfile] = [:]
        for entry in remoteHostEntries {
            result[entry.profile.alias] = entry.profile
        }
        for profile in sshProfiles {
            result[profile.alias] = profile
        }
        return result
    }

    func renameMainWindow(to value: String) {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mainWindowName = String(name.prefix(80))
    }

    func renameWorkspace(id: UUID, to value: String) {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = String(name.prefix(80))
        workspaces[index].updatedAt = Date()
        commitState()
    }

    func renameSession(id: UUID, to value: String) {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = String(name.prefix(80))
        commitState()
    }

    func closeWorkspace(id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces.remove(at: index)
        let referencedSessionIDs = Set(workspaces.flatMap {
            SplitTreeOperations.sessionIDs(in: $0.layout)
        })
        sessions.removeAll { !referencedSessionIDs.contains($0.id) }

        if workspaces.isEmpty {
            let document = Self.makeInitialDocument()
            workspaces = document.workspaces
            sessions = document.sessions
        }
        let fallbackIndex = min(index, workspaces.count - 1)
        selectedWorkspaceID = workspaces[fallbackIndex].id
        selectedSessionID = SplitTreeOperations.sessionIDs(
            in: workspaces[fallbackIndex].layout
        ).first
        commitState()
    }

    func moveWorkspace(id: UUID, offset: Int) {
        guard offset != 0,
              let sourceIndex = workspaces.firstIndex(where: { $0.id == id }) else {
            return
        }
        moveMainTab(.workspace(id), offset: offset)
        let destination = min(max(0, sourceIndex + offset), workspaces.count - 1)
        guard destination != sourceIndex else { return }
        let workspace = workspaces.remove(at: sourceIndex)
        workspaces.insert(workspace, at: destination)
        selectedWorkspaceID = id
        selectedSessionID = SplitTreeOperations.sessionIDs(in: workspace.layout).first
        commitState()
    }

    func closeOtherWorkspaces(keeping id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        workspaces = [workspace]
        let referenced = Set(SplitTreeOperations.sessionIDs(in: workspace.layout))
        sessions.removeAll { !referenced.contains($0.id) }
        selectedWorkspaceID = workspace.id
        selectedSessionID = referenced.first
        commitState()
    }

    func closeWorkspacesToRight(of id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }),
              index + 1 < workspaces.count else {
            return
        }
        workspaces.removeSubrange((index + 1)..<workspaces.count)
        let referenced = Set(workspaces.flatMap {
            SplitTreeOperations.sessionIDs(in: $0.layout)
        })
        sessions.removeAll { !referenced.contains($0.id) }
        if !workspaces.contains(where: { $0.id == selectedWorkspaceID }) {
            selectedWorkspaceID = id
            selectedSessionID = SplitTreeOperations.sessionIDs(in: workspaces[index].layout).first
        }
        commitState()
    }

    func reorderWorkspace(draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID,
              let sourceIndex = workspaces.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = workspaces.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        let workspace = workspaces.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        workspaces.insert(workspace, at: adjustedTarget)
        mainTabOrder = MainTabOrder.moving(
            .workspace(draggedID),
            relativeTo: .workspace(targetID),
            after: false,
            in: mainTabOrder
        )
        commitState()
    }

    func reorderWorkspace(draggedID: UUID, after targetID: UUID) {
        guard draggedID != targetID,
              let sourceIndex = workspaces.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = workspaces.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        let workspace = workspaces.remove(at: sourceIndex)
        var insertion = targetIndex + 1
        if sourceIndex < insertion { insertion -= 1 }
        insertion = min(max(0, insertion), workspaces.count)
        workspaces.insert(workspace, at: insertion)
        mainTabOrder = MainTabOrder.moving(
            .workspace(draggedID),
            relativeTo: .workspace(targetID),
            after: true,
            in: mainTabOrder
        )
        selectedWorkspaceID = draggedID
        selectedSessionID = SplitTreeOperations.sessionIDs(in: workspace.layout).first
        commitState()
    }

    func dropMainTab(
        _ source: MainTabReference,
        ontoWorkspace targetWorkspaceID: UUID,
        targetSessionID: UUID,
        region: TerminalDropRegion
    ) {
        guard source != .workspace(targetWorkspaceID) else { return }
        switch source.kind {
        case .agentChat:
            persistenceMessage = "Agent Chatのペイン分割は未対応です"
        case .workspace:
            switch region {
            case .center:
                reorderMainTab(
                    dragged: source,
                    relativeTo: .workspace(targetWorkspaceID),
                    after: true
                )
            case .left:
                moveWorkspaceIntoSplit(
                    draggedID: source.uuid,
                    targetID: targetWorkspaceID,
                    targetSessionID: targetSessionID,
                    axis: .vertical,
                    newPaneFirst: true
                )
            case .right:
                moveWorkspaceIntoSplit(
                    draggedID: source.uuid,
                    targetID: targetWorkspaceID,
                    targetSessionID: targetSessionID,
                    axis: .vertical,
                    newPaneFirst: false
                )
            case .top:
                moveWorkspaceIntoSplit(
                    draggedID: source.uuid,
                    targetID: targetWorkspaceID,
                    targetSessionID: targetSessionID,
                    axis: .horizontal,
                    newPaneFirst: true
                )
            case .bottom:
                moveWorkspaceIntoSplit(
                    draggedID: source.uuid,
                    targetID: targetWorkspaceID,
                    targetSessionID: targetSessionID,
                    axis: .horizontal,
                    newPaneFirst: false
                )
            }
        }
    }

    func dropWorkspacePane(
        sourceSessionID: UUID,
        ontoWorkspace targetWorkspaceID: UUID,
        targetSessionID: UUID,
        region: TerminalDropRegion
    ) {
        guard let sourceWorkspaceID = workspaces.first(where: {
                  SplitTreeOperations.contains(sessionID: sourceSessionID, in: $0.layout)
              })?.id,
              let targetWorkspace = workspaces.first(where: { workspace in
                  workspace.id == targetWorkspaceID
                      && SplitTreeOperations.contains(sessionID: targetSessionID, in: workspace.layout)
              }) else {
            return
        }

        if sourceSessionID == targetSessionID && region == .center {
            return
        }

        let targetLayout: SplitNode
        if region == .center {
            if sourceWorkspaceID == targetWorkspaceID {
                targetLayout = SplitTreeOperations.movingSessionToColumnEnd(
                    sourceSessionID,
                    targetSessionID: targetSessionID,
                    in: targetWorkspace.layout
                )
            } else {
                targetLayout = SplitTreeOperations.addingSession(
                    sourceSessionID,
                    toColumnContaining: targetSessionID,
                    select: true,
                    in: targetWorkspace.layout
                )
            }
        } else {
            let axis: SplitNode.SplitAxis
            let newColumnFirst: Bool
            switch region {
            case .left:
                axis = .vertical
                newColumnFirst = true
            case .right:
                axis = .vertical
                newColumnFirst = false
            case .top:
                axis = .horizontal
                newColumnFirst = true
            case .bottom:
                axis = .horizontal
                newColumnFirst = false
            case .center:
                return
            }

            guard let splitTargetSessionID = SplitTreeOperations.splitAnchorSessionID(
                sourceSessionID: sourceSessionID,
                targetSessionID: targetSessionID,
                in: targetWorkspace.layout
            ) else {
                return
            }

            let baseLayout: SplitNode
            if sourceWorkspaceID == targetWorkspaceID {
                guard let reduced = SplitTreeOperations.removing(
                    sessionID: sourceSessionID,
                    from: targetWorkspace.layout
                ), SplitTreeOperations.contains(sessionID: splitTargetSessionID, in: reduced) else {
                    return
                }
                baseLayout = reduced
            } else {
                baseLayout = targetWorkspace.layout
            }

            let previousColumnCount = SplitTreeOperations.columnCount(in: baseLayout)
            targetLayout = SplitTreeOperations.inserting(
                subtree: .column(TerminalColumn(sessionID: sourceSessionID)),
                at: splitTargetSessionID,
                axis: axis,
                newPaneFirst: newColumnFirst,
                in: baseLayout
            )
            guard SplitTreeOperations.columnCount(in: targetLayout) == previousColumnCount + 1 else {
                persistenceMessage = "Workspace column limit reached"
                return
            }
        }

        guard SplitTreeOperations.contains(sessionID: sourceSessionID, in: targetLayout) else {
            return
        }

        if sourceWorkspaceID != targetWorkspaceID {
            guard let sourceWorkspace = workspaces.first(where: { $0.id == sourceWorkspaceID }) else {
                return
            }
            let reducedSourceLayout = SplitTreeOperations.removing(
                sessionID: sourceSessionID,
                from: sourceWorkspace.layout
            )

            if let targetIndex = workspaces.firstIndex(where: { $0.id == targetWorkspaceID }) {
                workspaces[targetIndex].layout = targetLayout
                workspaces[targetIndex].updatedAt = Date()
            }
            if let sourceIndex = workspaces.firstIndex(where: { $0.id == sourceWorkspaceID }) {
                if let reducedSourceLayout {
                    workspaces[sourceIndex].layout = reducedSourceLayout
                    workspaces[sourceIndex].updatedAt = Date()
                } else {
                    workspaces.remove(at: sourceIndex)
                }
            }
        } else if let targetIndex = workspaces.firstIndex(where: { $0.id == targetWorkspaceID }) {
            workspaces[targetIndex].layout = targetLayout
            workspaces[targetIndex].updatedAt = Date()
        }

        selectedWorkspaceID = targetWorkspaceID
        selectedSessionID = sourceSessionID
        persistenceMessage = region == .center ? "Tab moved to column" : "Tab moved to new column"
        commitState()
    }

    func reorderTerminalTab(
        sourceSessionID: UUID,
        relativeTo targetSessionID: UUID,
        after: Bool
    ) {
        guard sourceSessionID != targetSessionID,
              let workspaceIndex = workspaces.firstIndex(where: {
                  SplitTreeOperations.contains(sessionID: sourceSessionID, in: $0.layout)
                      && SplitTreeOperations.contains(sessionID: targetSessionID, in: $0.layout)
              }) else {
            return
        }
        let updated = SplitTreeOperations.movingSession(
            sourceSessionID,
            relativeTo: targetSessionID,
            after: after,
            in: workspaces[workspaceIndex].layout
        )
        guard updated != workspaces[workspaceIndex].layout else { return }
        workspaces[workspaceIndex].layout = updated
        workspaces[workspaceIndex].updatedAt = Date()
        selectedWorkspaceID = workspaces[workspaceIndex].id
        selectedSessionID = sourceSessionID
        commitState()
    }

    func addTerminalTab(toColumnContaining anchorSessionID: UUID? = nil) {
        guard let anchorSessionID = anchorSessionID ?? selectedSessionID,
              let workspaceIndex = workspaces.firstIndex(where: {
                  SplitTreeOperations.contains(sessionID: anchorSessionID, in: $0.layout)
              }) else {
            return
        }

        let source = session(id: anchorSessionID)
        let kind = source?.kind ?? .local
        let title: String
        if kind == .local {
            _ = normalizeLocalShellTitles(inWorkspaceAt: workspaceIndex)
            title = nextLocalShellTitle(inWorkspaceAt: workspaceIndex)
        } else {
            title = source?.title ?? "Terminal"
        }
        let newSession = TerminalSession(
            title: title,
            kind: kind,
            workingDirectory: source?.workingDirectory
        )
        let updated = SplitTreeOperations.addingSession(
            newSession.id,
            toColumnContaining: anchorSessionID,
            select: true,
            in: workspaces[workspaceIndex].layout
        )
        guard SplitTreeOperations.contains(sessionID: newSession.id, in: updated) else {
            return
        }
        workspaces[workspaceIndex].layout = updated
        workspaces[workspaceIndex].updatedAt = Date()
        sessions.append(newSession)
        selectedWorkspaceID = workspaces[workspaceIndex].id
        selectedSessionID = newSession.id
        commitState()
    }

    func mergeWorkspaceTabs(
        draggedID: UUID,
        targetID: UUID,
        axis: SplitNode.SplitAxis = .vertical,
        newPaneFirst: Bool = false
    ) {
        guard draggedID != targetID,
              let sourceIndex = workspaces.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = workspaces.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let sourceLayout = workspaces[sourceIndex].layout
        let targetLayout = workspaces[targetIndex].layout
        let combinedPaneCount = SplitTreeOperations.paneCount(in: sourceLayout)
            + SplitTreeOperations.paneCount(in: targetLayout)
        guard combinedPaneCount <= SplitTreeOperations.maximumPaneCount else {
            persistenceMessage = "Workspace pane limit reached"
            return
        }

        let mergedLayout = SplitNode.split(
            axis: axis,
            ratio: 0.5,
            first: newPaneFirst ? sourceLayout : targetLayout,
            second: newPaneFirst ? targetLayout : sourceLayout
        )
        let movedSessionID = SplitTreeOperations.firstSelectedSessionID(in: sourceLayout)
        workspaces[targetIndex].layout = mergedLayout
        workspaces[targetIndex].updatedAt = Date()
        workspaces.remove(at: sourceIndex)
        selectedWorkspaceID = targetID
        selectedSessionID = movedSessionID
            ?? SplitTreeOperations.sessionIDs(in: mergedLayout).first
        persistenceMessage = "Tabs merged into \(combinedPaneCount) panes"
        commitState()
    }

    func moveWorkspaceIntoSplit(
        draggedID: UUID,
        targetID: UUID,
        targetSessionID explicitTargetSessionID: UUID? = nil,
        axis: SplitNode.SplitAxis,
        newPaneFirst: Bool
    ) {
        guard draggedID != targetID,
              let sourceIndex = workspaces.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = workspaces.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        let sourceLayout = workspaces[sourceIndex].layout
        guard let movedSessionID = SplitTreeOperations.firstSelectedSessionID(in: sourceLayout) else {
            return
        }
        let targetSessionID: UUID
        if let explicitTargetSessionID,
           SplitTreeOperations.contains(
               sessionID: explicitTargetSessionID,
               in: workspaces[targetIndex].layout
           ) {
            targetSessionID = explicitTargetSessionID
        } else if let selectedSessionID,
                  SplitTreeOperations.contains(
                      sessionID: selectedSessionID,
                      in: workspaces[targetIndex].layout
                  ) {
            targetSessionID = selectedSessionID
        } else if let first = SplitTreeOperations.sessionIDs(in: workspaces[targetIndex].layout).first {
            targetSessionID = first
        } else {
            return
        }

        let previousCount = SplitTreeOperations.paneCount(in: workspaces[targetIndex].layout)
        let newLayout = SplitTreeOperations.inserting(
            subtree: sourceLayout,
            at: targetSessionID,
            axis: axis,
            newPaneFirst: newPaneFirst,
            in: workspaces[targetIndex].layout
        )
        guard SplitTreeOperations.paneCount(in: newLayout) > previousCount else {
            persistenceMessage = "Workspace pane limit reached"
            return
        }
        workspaces[targetIndex].layout = newLayout
        workspaces[targetIndex].updatedAt = Date()
        workspaces.remove(at: sourceIndex)
        selectedWorkspaceID = targetID
        selectedSessionID = movedSessionID
        commitState()
    }

    func createRemoteWorkspace(profile: SSHHostProfile, tmuxSession: String? = nil) {
        guard profile.isInteractiveShellCandidate else {
            persistenceMessage = "This SSH profile is for Git transport, not an interactive shell"
            return
        }

        let kind: SessionKind = tmuxSession.map {
            .tmux(host: profile.alias, session: $0)
        } ?? .ssh(host: profile.alias)

        if let existingSession = sessions.first(where: { $0.kind == kind }),
           let existingWorkspace = workspaces.first(where: {
               SplitTreeOperations.sessionIDs(in: $0.layout).contains(existingSession.id)
           }) {
            selectedWorkspaceID = existingWorkspace.id
            selectedSessionID = existingSession.id
            refreshAutomationStatus()
            return
        }

        let session = TerminalSession(
            title: tmuxSession.map { "\(profile.displayTitle):\($0)" } ?? profile.displayTitle,
            kind: kind,
            state: .created
        )
        let workspace = Workspace(
            name: profile.displayTitle,
            layout: .column(TerminalColumn(sessionID: session.id))
        )
        sessions.append(session)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        selectedSessionID = session.id
        commitState()
    }

    func saveRemoteHost(
        _ profile: SSHHostProfile,
        replacingAlias originalAlias: String? = nil
    ) {
        let alias = profile.alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else {
            persistenceMessage = "Remote host alias is required"
            return
        }

        if let originalAlias, originalAlias != alias {
            remoteHostConfiguration.customProfiles.removeAll { $0.alias == originalAlias }
            if baseSSHProfiles.contains(where: { $0.alias == originalAlias }) {
                remoteHostConfiguration.hiddenAliases.insert(originalAlias)
            }
            removeRemoteWorkspaces(alias: originalAlias)
        }

        var normalized = profile
        normalized.alias = alias
        let displayName = normalized.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.displayName = displayName?.isEmpty == false ? displayName : nil
        remoteHostConfiguration.customProfiles.removeAll { $0.alias == alias }
        remoteHostConfiguration.customProfiles.append(normalized)
        remoteHostConfiguration.hiddenAliases.remove(alias)
        remoteHostConfiguration.deletedAliases.remove(alias)
        updateRemoteWorkspaceTitles(profile: normalized)
        refreshRemoteProfiles()
        persistRemoteHostConfiguration()
    }

    func hideRemoteHost(alias: String) {
        remoteHostConfiguration.deletedAliases.remove(alias)
        remoteHostConfiguration.hiddenAliases.insert(alias)
        removeRemoteWorkspaces(alias: alias)
        refreshRemoteProfiles()
        remoteHostActionMessage = "\(alias)を非表示にしました"
        persistRemoteHostConfiguration()
    }

    func restoreRemoteHost(alias: String) {
        remoteHostConfiguration.deletedAliases.remove(alias)
        remoteHostConfiguration.hiddenAliases.remove(alias)
        refreshRemoteProfiles()
        remoteHostActionMessage = "\(alias)を表示しました"
        persistRemoteHostConfiguration()
    }

    func restoreDeletedRemoteHost(alias: String) {
        remoteHostConfiguration.deletedAliases.remove(alias)
        remoteHostConfiguration.hiddenAliases.remove(alias)
        refreshRemoteProfiles()
        remoteHostActionMessage = "\(alias)を復元しました"
        persistRemoteHostConfiguration()
    }

    func deleteRemoteHost(alias: String) {
        remoteHostConfiguration.customProfiles.removeAll { $0.alias == alias }
        remoteHostConfiguration.hiddenAliases.remove(alias)
        if baseSSHProfiles.contains(where: { $0.alias == alias }) {
            remoteHostConfiguration.deletedAliases.insert(alias)
        } else {
            remoteHostConfiguration.deletedAliases.remove(alias)
        }
        removeRemoteWorkspaces(alias: alias)
        refreshRemoteProfiles()
        remoteHostActionMessage = "\(alias)をApexTermから削除しました"
        persistRemoteHostConfiguration()
    }

    func selectWorkspace(_ workspace: Workspace) {
        let sessionID: UUID?
        if let selectedSessionID,
           SplitTreeOperations.contains(sessionID: selectedSessionID, in: workspace.layout) {
            sessionID = selectedSessionID
        } else {
            sessionID = SplitTreeOperations.firstSelectedSessionID(in: workspace.layout)
        }
        if selectedAgentChatID != nil {
            selectedAgentChatID = nil
        }
        if selectedWorkspaceID != workspace.id {
            selectedWorkspaceID = workspace.id
        }
        if selectedSessionID != sessionID {
            selectedSessionID = sessionID
        }
        refreshAutomationSelection()
    }

    func selectSession(_ sessionID: UUID) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        selectedSessionID = sessionID
        if let workspaceIndex = workspaces.firstIndex(where: {
            SplitTreeOperations.contains(sessionID: sessionID, in: $0.layout)
        }) {
            selectedWorkspaceID = workspaces[workspaceIndex].id
            let updated = SplitTreeOperations.selectingSession(
                sessionID,
                in: workspaces[workspaceIndex].layout
            )
            if updated != workspaces[workspaceIndex].layout {
                workspaces[workspaceIndex].layout = updated
                workspaces[workspaceIndex].updatedAt = Date()
                scheduleMetadataPersist()
            }
        }
        refreshAutomationSelection()
        TerminalPaneRuntimeStore.shared.requestFocus(sessionID: sessionID)
    }

    func splitSession(id: UUID, axis: SplitNode.SplitAxis) {
        guard let workspace = workspaces.first(where: {
            SplitTreeOperations.contains(sessionID: id, in: $0.layout)
        }) else {
            return
        }
        selectedWorkspaceID = workspace.id
        selectedSessionID = id
        splitSelected(axis: axis)
    }

    func closeSession(id: UUID) {
        guard let workspace = workspaces.first(where: {
            SplitTreeOperations.contains(sessionID: id, in: $0.layout)
        }) else {
            return
        }
        selectedWorkspaceID = workspace.id
        selectedSessionID = id
        closeSelectedSession()
    }

    func closeSessionAndKillTmux(id: UUID) {
        guard let terminal = session(id: id),
              let descriptor = tmuxDescriptor(for: terminal),
              let workspace = workspaces.first(where: {
                  SplitTreeOperations.contains(sessionID: id, in: $0.layout)
              }) else {
            return
        }
        let sessionIDs = SplitTreeOperations.sessionIDs(in: workspace.layout)
        if sessionIDs.count == 1 {
            closeWorkspaceAndKillTmux(id: workspace.id)
            return
        }
        selectedWorkspaceID = workspace.id
        selectedSessionID = id
        closeSelectedSession()
        startTmuxKill([descriptor], refreshAfter: false)
    }

    func splitSelected(axis: SplitNode.SplitAxis) {
        guard let selectedSessionID else { return }
        splitTerminalColumn(
            containing: selectedSessionID,
            axis: axis,
            newColumnFirst: false
        )
    }

    func splitTerminalColumn(
        containing anchorSessionID: UUID,
        axis: SplitNode.SplitAxis,
        newColumnFirst: Bool
    ) {
        guard let workspaceIndex = workspaces.firstIndex(where: {
            SplitTreeOperations.contains(sessionID: anchorSessionID, in: $0.layout)
        }) else {
            return
        }

        let source = session(id: anchorSessionID)
        let newKind = source?.kind ?? .local
        let newTitle: String
        if newKind == .local {
            _ = normalizeLocalShellTitles(inWorkspaceAt: workspaceIndex)
            newTitle = nextLocalShellTitle(inWorkspaceAt: workspaceIndex)
        } else {
            newTitle = source?.title ?? "Terminal"
        }
        let newSession = TerminalSession(
            title: newTitle,
            kind: newKind,
            workingDirectory: source?.workingDirectory
        )
        let previousCount = SplitTreeOperations.paneCount(
            in: workspaces[workspaceIndex].layout
        )
        let newLayout = SplitTreeOperations.split(
            sessionID: anchorSessionID,
            newSessionID: newSession.id,
            axis: axis,
            newPaneFirst: newColumnFirst,
            in: workspaces[workspaceIndex].layout
        )
        guard SplitTreeOperations.paneCount(in: newLayout) > previousCount else {
            persistenceMessage = "Workspace pane limit reached"
            return
        }

        workspaces[workspaceIndex].layout = newLayout
        workspaces[workspaceIndex].updatedAt = Date()
        sessions.append(newSession)
        selectedWorkspaceID = workspaces[workspaceIndex].id
        selectedSessionID = newSession.id
        commitState()
    }

    func closeSelectedSession() {
        guard let selectedSessionID,
              let workspaceIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else {
            return
        }
        let existingIDs = SplitTreeOperations.sessionIDs(in: workspaces[workspaceIndex].layout)
        let sourceColumnID = SplitTreeOperations.column(
            containing: selectedSessionID,
            in: workspaces[workspaceIndex].layout
        )?.id
        guard existingIDs.count > 1,
              let newLayout = SplitTreeOperations.removing(
                sessionID: selectedSessionID,
                from: workspaces[workspaceIndex].layout
              ) else {
            return
        }

        workspaces[workspaceIndex].layout = newLayout
        workspaces[workspaceIndex].updatedAt = Date()
        sessions.removeAll { $0.id == selectedSessionID }
        if let sourceColumnID,
           let survivingColumn = SplitTreeOperations.column(id: sourceColumnID, in: newLayout) {
            self.selectedSessionID = survivingColumn.selectedSessionID
        } else {
            self.selectedSessionID = SplitTreeOperations.sessionIDs(in: newLayout).first
        }
        commitState()
    }

    func updateTerminalTitle(_ title: String, sessionID: UUID? = nil) {
        let resolvedTitle = title.isEmpty ? LocalShellNaming.title(number: 1) : title
        guard let targetID = sessionID ?? selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        if targetID == selectedSessionID {
            terminalTitle = resolvedTitle
        }
        guard sessions[index].title != resolvedTitle else { return }
        sessions[index].title = resolvedTitle
        refreshAutomationStatus()
        scheduleMetadataPersist()
    }

    func updateCurrentDirectory(_ directory: String?, sessionID: UUID? = nil) {
        guard let targetID = sessionID ?? selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        if targetID == selectedSessionID {
            currentDirectory = directory
        }
        guard sessions[index].workingDirectory != directory else { return }
        sessions[index].workingDirectory = directory
        scheduleMetadataPersist()
    }

    func updateSessionState(_ state: SessionState, sessionID: UUID? = nil) {
        guard let targetID = sessionID ?? selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == targetID }),
              sessions[index].state != state else {
            return
        }
        sessions[index].state = state
        refreshAutomationStatus()
    }

    func recordSemanticEvents(_ events: [ShellSemanticEvent], sessionID: UUID) {
        guard !events.isEmpty else { return }
        commandStatusBySession[sessionID] = statusLabel(for: events.last!)

        var readySessions = shellPromptReadySessionIDs
        var remoteSessions = remoteInteractiveSessionIDs
        var activeCommands = activeCommandBySession
        var pendingConversationSends = conversationSendPendingSessionIDs

        for event in events {
            switch event {
            case .promptStarted, .commandInputStarted:
                readySessions.insert(sessionID)
                pendingConversationSends.remove(sessionID)
            case let .commandCaptured(command):
                readySessions.remove(sessionID)
                pendingConversationSends.remove(sessionID)
                activeCommands[sessionID] = command
                if TerminalConversationPolicy.commandStartsRemoteInteractiveSession(command) {
                    remoteSessions.insert(sessionID)
                }
            case .commandExecuted:
                readySessions.remove(sessionID)
            case .commandFinished:
                readySessions.remove(sessionID)
                pendingConversationSends.remove(sessionID)
                remoteSessions.remove(sessionID)
                activeCommands.removeValue(forKey: sessionID)
            }
        }

        if readySessions != shellPromptReadySessionIDs {
            shellPromptReadySessionIDs = readySessions
        }
        if remoteSessions != remoteInteractiveSessionIDs {
            remoteInteractiveSessionIDs = remoteSessions
        }
        if activeCommands != activeCommandBySession {
            activeCommandBySession = activeCommands
        }
        if pendingConversationSends != conversationSendPendingSessionIDs {
            conversationSendPendingSessionIDs = pendingConversationSends
        }

        Task { [commandBoundaryIndex] in
            await commandBoundaryIndex.append(events, sessionID: sessionID)
        }
    }

    func commandStatus(sessionID: UUID) -> String? {
        commandStatusBySession[sessionID]
    }

    func commandTranscriptMode(for sessionID: UUID) -> CommandTranscriptMode {
        let kind = session(id: sessionID)?.kind ?? .local
        return TerminalConversationPolicy.resolvesTranscriptMode(
            baseMode: commandTranscriptMode,
            sessionKind: kind,
            remoteInteractiveCommandActive: remoteInteractiveSessionIDs.contains(sessionID),
            userOverride: commandTranscriptModeOverrides[sessionID]
        )
    }

    func setCommandTranscriptMode(
        _ mode: CommandTranscriptMode,
        for sessionID: UUID
    ) {
        commandTranscriptModeOverrides[sessionID] = mode
        if mode == .ex {
            collapsedCommandIDs.formUnion(
                commandHistory.lazy
                    .filter { $0.sessionID == sessionID }
                    .map(\.id)
            )
        }
    }

    func cycleCommandTranscriptMode(for sessionID: UUID) {
        setCommandTranscriptMode(
            commandTranscriptMode(for: sessionID).next,
            for: sessionID
        )
    }

    func clearCommandTranscriptModeOverride(for sessionID: UUID) {
        commandTranscriptModeOverrides.removeValue(forKey: sessionID)
    }

    func isShellPromptReady(sessionID: UUID) -> Bool {
        if shellPromptReadySessionIDs.contains(sessionID)
            || TerminalPaneRuntimeStore.shared.isPromptReady(sessionID: sessionID) {
            return true
        }

        // OSC 133 is the authoritative local-shell boundary. The rendered-buffer
        // heuristic is deliberately secondary: a themed prompt, a command-not-found
        // message, or the first frame after leaving ssh can fail the heuristic even
        // though zsh has already reported that it is idle. Never let that late false
        // frame permanently relock C mode.
        guard let session = session(id: sessionID),
              !session.kind.isRemote,
              !remoteInteractiveSessionIDs.contains(sessionID),
              activeCommandBySession[sessionID] == nil,
              !conversationSendPendingSessionIDs.contains(sessionID),
              let status = commandStatusBySession[sessionID] else {
            return false
        }
        // `.commandInputStarted` means the shell has entered its editable input
        // region. The UI label is "Typing", but for C-mode send gating this is
        // already a real prompt boundary, even before any key is typed.
        return status == "Ready"
            || status == "Typing"
            || status == "Done"
            || status.hasPrefix("Exit ")
    }

    func supportsConversationComposer(sessionID: UUID) -> Bool {
        guard let session = session(id: sessionID),
              session.state == .attached,
              TerminalPaneRuntimeStore.shared.isProcessRunning(sessionID: sessionID),
              activeCommandBySession[sessionID] == nil else {
            return false
        }
        return isShellPromptReady(sessionID: sessionID)
    }

    func conversationComposerStatus(sessionID: UUID) -> String {
        guard TerminalPaneRuntimeStore.shared.isProcessRunning(sessionID: sessionID) else {
            return "端末未接続"
        }
        if activeCommandBySession[sessionID] != nil
            || (conversationSendPendingSessionIDs.contains(sessionID)
                && !isShellPromptReady(sessionID: sessionID)) {
            return "実行中"
        }
        return supportsConversationComposer(sessionID: sessionID)
            ? "送信可能"
            : "プロンプト同期中"
    }

    func updatePromptReadiness(_ ready: Bool, sessionID: UUID) {
        guard session(id: sessionID) != nil else { return }
        var readySessions = shellPromptReadySessionIDs
        if ready {
            readySessions.insert(sessionID)
            conversationSendPendingSessionIDs.remove(sessionID)
            if commandStatusBySession[sessionID] == "強制停止中" {
                commandStatusBySession[sessionID] = "Ready"
            }
        } else {
            readySessions.remove(sessionID)
        }
        if readySessions != shellPromptReadySessionIDs {
            shellPromptReadySessionIDs = readySessions
        }
    }

    @discardableResult
    func sendConversationCommand(sessionID: UUID) -> Bool {
        let draft = terminalConversationDrafts[sessionID] ?? ""
        let command = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return false }
        guard supportsConversationComposer(sessionID: sessionID) else {
            showTransientNotice("プロンプトへ戻るまで送信できません")
            return false
        }
        conversationSendPendingSessionIDs.insert(sessionID)
        let accepted = TerminalPaneRuntimeStore.shared.sendProgrammaticInput(
            sessionID: sessionID,
            text: command,
            execute: true
        )
        guard accepted else {
            conversationSendPendingSessionIDs.remove(sessionID)
            showTransientNotice("端末入力を送信できませんでした")
            return false
        }
        shellPromptReadySessionIDs.remove(sessionID)
        terminalConversationDrafts[sessionID] = ""
        return true
    }

    @discardableResult
    func scheduleConversationCommand(
        sessionID: UUID,
        command: String,
        at requestedDate: Date
    ) -> Bool {
        guard session(id: sessionID) != nil else { return false }
        let scheduled = ScheduledTerminalCommand(
            sessionID: sessionID,
            command: command,
            scheduledAt: ScheduledTerminalCommandPolicy.normalizedFireDate(
                requested: requestedDate
            )
        )
        guard scheduled.isValid else { return false }
        scheduledTerminalCommands.append(scheduled)
        scheduledTerminalCommands.sort { $0.scheduledAt < $1.scheduledAt }
        persistScheduledTerminalCommands()
        ensureScheduledCommandLoop()
        showTransientNotice("時間指定送信を予約しました")
        return true
    }

    func cancelScheduledTerminalCommand(id: UUID) {
        scheduledTerminalCommands.removeAll { $0.id == id }
        persistScheduledTerminalCommands()
    }

    func scheduledCommands(sessionID: UUID) -> [ScheduledTerminalCommand] {
        scheduledTerminalCommands
            .filter { $0.sessionID == sessionID }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private func ensureScheduledCommandLoop() {
        guard scheduledCommandLoopTask == nil,
              !scheduledTerminalCommands.isEmpty else {
            return
        }

        scheduledCommandLoopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.scheduledCommandLoopTask = nil }

            while !Task.isCancelled {
                let now = Date()
                let dueCommands = self.scheduledTerminalCommands.filter {
                    $0.scheduledAt <= now
                }
                var completedIDs: Set<UUID> = []

                for scheduled in dueCommands {
                    guard let session = self.session(id: scheduled.sessionID) else {
                        completedIDs.insert(scheduled.id)
                        continue
                    }

                    let shouldSend = ScheduledTerminalCommandPolicy.shouldSend(
                        sessionKind: session.kind,
                        processRunning: TerminalPaneRuntimeStore.shared.isProcessRunning(
                            sessionID: scheduled.sessionID
                        ),
                        shellPromptReady: self.isShellPromptReady(
                            sessionID: scheduled.sessionID
                        ),
                        remoteInteractiveCommandActive: self.remoteInteractiveSessionIDs.contains(
                            scheduled.sessionID
                        )
                    )
                    guard shouldSend else { continue }

                    let accepted = TerminalPaneRuntimeStore.shared.sendProgrammaticInput(
                        sessionID: scheduled.sessionID,
                        text: scheduled.command,
                        execute: true
                    )
                    if accepted {
                        self.shellPromptReadySessionIDs.remove(scheduled.sessionID)
                        completedIDs.insert(scheduled.id)
                        self.showTransientNotice("予約コマンドを送信しました")
                    }
                }

                if !completedIDs.isEmpty {
                    self.scheduledTerminalCommands.removeAll {
                        completedIDs.contains($0.id)
                    }
                    self.persistScheduledTerminalCommands()
                }

                if self.scheduledTerminalCommands.isEmpty {
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func resumeScheduledTerminalCommands() {
        scheduledTerminalCommands = scheduledTerminalCommands.filter {
            session(id: $0.sessionID) != nil && $0.isValid
        }
        persistScheduledTerminalCommands()
        ensureScheduledCommandLoop()
    }

    private static func loadScheduledTerminalCommands() -> [ScheduledTerminalCommand] {
        guard let data = UserDefaults.standard.data(forKey: scheduledCommandsDefaultsKey),
              let decoded = try? JSONDecoder().decode(
                  [ScheduledTerminalCommand].self,
                  from: data
              ) else {
            return []
        }
        return decoded.filter(\.isValid).sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private func persistScheduledTerminalCommands() {
        guard let data = try? JSONEncoder().encode(scheduledTerminalCommands) else { return }
        UserDefaults.standard.set(data, forKey: Self.scheduledCommandsDefaultsKey)
    }

    func recentCommands(sessionID: UUID? = nil, limit: Int = 3) -> [CommandExecutionRecord] {
        let boundedLimit = max(0, limit)
        guard boundedLimit > 0 else { return [] }
        var result: [CommandExecutionRecord] = []
        result.reserveCapacity(min(boundedLimit, commandHistory.count))
        for record in commandHistory {
            if let sessionID, record.sessionID != sessionID { continue }
            result.append(record)
            if result.count == boundedLimit { break }
        }
        return result
    }

    func copyLatestOutputFromActiveTab() {
        let output: String? = if let selectedAgentChat {
            selectedAgentChat.messages.reversed().first(where: {
                $0.role == .assistant
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })?.text
        } else if let selectedSessionID {
            commandHistory.first(where: {
                $0.sessionID == selectedSessionID
                    && !$0.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })?.output
        } else {
            nil
        }

        guard let output else {
            showTransientNotice("コピーできる最新出力がありません")
            return
        }
        ClipboardWriter.copy(output)
        showTransientNotice("コピーしました")
    }

    func cycleCommandTranscriptMode() {
        commandTranscriptMode = commandTranscriptMode.next
    }

    func toggleAutoCopyCommandOutput() {
        autoCopyCommandOutputEnabled.toggle()
        showTransientNotice(
            autoCopyCommandOutputEnabled
                ? "出力の自動コピーをONにしました"
                : "出力の自動コピーをOFFにしました"
        )
    }

    func forceInterruptAndRecover(sessionID: UUID) {
        shellPromptReadySessionIDs.remove(sessionID)
        commandStatusBySession[sessionID] = "強制停止中"
        let result = TerminalPaneRuntimeStore.shared.forceInterruptOrRestart(
            sessionID: sessionID
        )
        switch result {
        case .unavailable:
            showTransientNotice("端末プロセスを復旧できませんでした")
        case .sentControlC:
            showTransientNotice("Ctrl+Cを強制送信しました")
        case .signalledForegroundProcessGroup:
            showTransientNotice("前面プロセスを強制停止しています")
        case .restartedSession:
            showTransientNotice("端末セッションを再起動しました")
        }
    }

    private func showTransientNotice(_ message: String) {
        transientNoticeGeneration &+= 1
        let generation = transientNoticeGeneration
        transientNotice = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self,
                  self.transientNoticeGeneration == generation else { return }
            self.transientNotice = nil
        }
    }

    func recordCommandExecution(_ record: CommandExecutionRecord) {
        conversationSendPendingSessionIDs.remove(record.sessionID)
        activeCommandBySession.removeValue(forKey: record.sessionID)
        remoteInteractiveSessionIDs.remove(record.sessionID)
        commandStatusBySession[record.sessionID] = record.exitCode == 0
            ? "Done"
            : "Exit \(record.exitCode)"
        completeDirectAutomationIfNeeded(with: record)
        let isDuplicate = commandHistory.prefix(5).contains { existing in
            existing.sessionID == record.sessionID
                && existing.command == record.command
                && existing.output == record.output
                && existing.exitCode == record.exitCode
                && abs(existing.finishedAt.timeIntervalSince(record.finishedAt)) < 2
        }
        guard !isDuplicate else { return }
        commandHistory = commandHistoryRecorder.appendDeferred(record)
        if autoCopyCommandOutputEnabled, !record.output.isEmpty {
            ClipboardWriter.copy(record.output)
            AutoCopyToastPresenter.shared.showOutputCopied()
        }
        if commandTranscriptMode(for: record.sessionID) == .ex || commandBlocksStartCollapsed {
            collapsedCommandIDs.insert(record.id)
        } else if autoCollapseLargeOutputsEnabled {
            let lineCount = record.output.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count
            if lineCount >= autoCollapseLargeOutputLineThreshold {
                collapsedCommandIDs.insert(record.id)
            }
        }
    }

    func clearCommandHistory() {
        commandHistory = commandHistoryRecorder.clear()
        collapsedCommandIDs.removeAll()
    }

    func isCommandCollapsed(_ id: UUID) -> Bool {
        collapsedCommandIDs.contains(id)
    }

    func toggleCommandCollapsed(_ id: UUID) {
        var updated = collapsedCommandIDs
        if updated.contains(id) {
            updated.remove(id)
        } else {
            updated.insert(id)
        }
        collapsedCommandIDs = updated
    }

    func copySelectedContextPack() {
        guard let context = selectedCommandContext(preferFailure: false) else {
            persistenceMessage = "Run a command in the selected pane first"
            return
        }
        ClipboardWriter.copy(
            TerminalContextPackBuilder.markdown(
                record: context.record,
                sessionTitle: context.session.title,
                workingDirectory: context.session.workingDirectory
            )
        )
        persistenceMessage = "Context Pack copied with secrets redacted"
    }

    func prepareLastFailureInAgentChat() {
        guard let context = selectedCommandContext(preferFailure: true) else {
            persistenceMessage = "No failed command exists in the selected pane"
            return
        }
        let prompt = TerminalContextPackBuilder.agentPrompt(
            record: context.record,
            sessionTitle: context.session.title,
            workingDirectory: context.session.workingDirectory
        )
        createAgentChatTab(target: .local)
        guard let tabID = selectedAgentChatID,
              let index = agentChatTabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }
        let normalizedCommand = context.record.command
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        agentChatTabs[index].title = "Fix: " + String(normalizedCommand.prefix(44))
        agentChatTabs[index].draft = prompt
        agentChatTabs[index].updatedAt = Date()
        scheduleAgentChatSave(immediate: true)
        persistenceMessage = "Failure draft opened in Agent Chat; nothing was executed"
    }

    private func selectedCommandContext(
        preferFailure: Bool
    ) -> (record: CommandExecutionRecord, session: TerminalSession)? {
        guard let selectedSessionID,
              let session = session(id: selectedSessionID) else {
            return nil
        }
        let record = commandHistory.first { candidate in
            candidate.sessionID == selectedSessionID
                && (!preferFailure || candidate.exitCode != 0)
        }
        guard let record else { return nil }
        return (record, session)
    }

    func automationStatus() -> String {
        automationSocketURL == nil ? "Automation offline" : "Automation local"
    }

    func requestFind() {
        guard let selectedSessionID else { return }
        NotificationCenter.default.post(
            name: .apexTermFindRequested,
            object: selectedSessionID
        )
    }

    private func beginDirectAutomation(_ request: DirectTerminalAutomationRequest) {
        guard directAutomationRequests[request.sessionID] == nil else {
            request.finish(.failure("another command is already running in this terminal"))
            return
        }
        guard TerminalPaneRuntimeStore.shared.isProcessRunning(
            sessionID: request.sessionID
        ) else {
            request.finish(.failure("sessionUnavailable"))
            return
        }
        directAutomationRequests[request.sessionID] = request
        requestTerminalInput(
            request.command,
            execute: true,
            sessionID: request.sessionID
        )
    }

    private func cancelDirectAutomation(_ request: DirectTerminalAutomationRequest) {
        guard directAutomationRequests[request.sessionID]?.id == request.id else { return }
        directAutomationRequests.removeValue(forKey: request.sessionID)
    }

    private func completeDirectAutomationIfNeeded(
        with record: CommandExecutionRecord
    ) {
        guard let request = directAutomationRequests[record.sessionID] else { return }
        let expected = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = record.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expected == actual else { return }
        directAutomationRequests.removeValue(forKey: record.sessionID)
        request.finish(.record(record))
    }

    func requestTerminalInput(
        _ text: String,
        execute: Bool = false,
        sessionID: UUID? = nil
    ) {
        guard !text.isEmpty,
              let targetSessionID = sessionID ?? selectedSessionID else { return }
        NotificationCenter.default.post(
            name: .apexTermInputRequested,
            object: TerminalInputRequest(
                sessionID: targetSessionID,
                text: text,
                execute: execute
            )
        )
    }

    func saveCommandPreset(
        id: UUID? = nil,
        name: String,
        command: String
    ) {
        let preset = TerminalCommandPreset(
            id: id ?? UUID(),
            name: name,
            command: command
        )
        guard preset.isValid else { return }

        if let index = commandPresets.firstIndex(where: { $0.id == preset.id }) {
            commandPresets[index] = preset
        } else {
            commandPresets.append(preset)
        }
        synchronizeSettingsDocument()
    }

    func deleteCommandPreset(id: UUID) {
        commandPresets.removeAll { $0.id == id }
        synchronizeSettingsDocument()
    }

    func moveCommandPreset(id: UUID, offset: Int) {
        guard offset != 0,
              let source = commandPresets.firstIndex(where: { $0.id == id }) else {
            return
        }
        let destination = min(max(source + offset, 0), commandPresets.count - 1)
        guard destination != source else { return }
        let preset = commandPresets.remove(at: source)
        commandPresets.insert(preset, at: destination)
        synchronizeSettingsDocument()
    }

    func executeCommandPreset(
        _ preset: TerminalCommandPreset,
        sessionID: UUID? = nil
    ) {
        requestTerminalInput(
            preset.command,
            execute: true,
            sessionID: sessionID
        )
    }

    func toggleMaximizeSelectedPane() {
        guard let selectedSessionID else { return }
        maximizedSessionID = maximizedSessionID == selectedSessionID
            ? nil
            : selectedSessionID
    }

    func selectAdjacentTerminalTab(offset: Int) {
        guard offset != 0,
              let workspace = selectedWorkspace else { return }
        let ids = SplitTreeOperations.visualSessionIDs(in: workspace.layout)
        guard !ids.isEmpty else { return }
        let fallbackIndex = offset > 0 ? -1 : 0
        let currentIndex = selectedSessionID.flatMap { ids.firstIndex(of: $0) } ?? fallbackIndex
        let nextIndex = (currentIndex + offset % ids.count + ids.count) % ids.count
        selectSession(ids[nextIndex])
    }

    func selectAdjacentPane(offset: Int) {
        guard offset != 0,
              let workspace = selectedWorkspace else { return }
        let ids = SplitTreeOperations.sessionIDs(in: workspace.layout)
        guard !ids.isEmpty else { return }
        let currentIndex = selectedSessionID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let nextIndex = (currentIndex + offset % ids.count + ids.count) % ids.count
        selectPane(sessionID: ids[nextIndex])
    }

    func selectPane(number: Int) {
        guard number > 0,
              let workspace = selectedWorkspace else { return }
        let ids = SplitTreeOperations.sessionIDs(in: workspace.layout)
        guard ids.indices.contains(number - 1) else {
            persistenceMessage = "Pane \(number) is not available in this tab"
            return
        }
        selectPane(sessionID: ids[number - 1])
    }

    private func selectPane(sessionID: UUID) {
        guard selectedSessionID != sessionID else { return }
        selectedSessionID = sessionID
        maximizedSessionID = nil
        persistenceMessage = nil
        refreshAutomationStatus()
    }

    func universalSearchSnapshot() async -> UniversalSearchSnapshot {
        let workspaces = self.workspaces
        let sessions = self.sessions
        let commands = self.commandHistory
        let agentChats = self.agentChatTabs
        guard let eventStore else {
            return UniversalSearchSnapshot(
                workspaces: workspaces,
                sessions: sessions,
                commands: commands,
                agentChats: agentChats
            )
        }

        let agentEvents = await Task.detached(priority: .utility) {
            let storedEvents = (try? eventStore.events(
                kind: .agent,
                limit: 1_000
            )) ?? []
            let decoder = JSONDecoder()
            var seenReferences: Set<String> = []
            return storedEvents.compactMap { event -> UniversalAgentEvent? in
                guard let reference = event.subjectID,
                      seenReferences.insert(reference).inserted,
                      let targetedJob = try? decoder.decode(
                          GagTargetedJob.self,
                          from: event.payload
                      ) else {
                    return nil
                }
                let job = targetedJob.job
                let response = (job.state?.responseText ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let summary: String
                if let error = job.error?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ), !error.isEmpty {
                    summary = error
                } else if !response.isEmpty {
                    summary = response
                } else {
                    summary = job.currentStep
                }
                let metrics = GagRuntimeMetrics.calculate(
                    target: targetedJob.target,
                    job: job
                )
                return UniversalAgentEvent(
                    id: event.id,
                    reference: reference,
                    title: job.title,
                    status: job.status.rawValue,
                    summary: summary,
                    updatedAt: event.occurredAt,
                    conversationURL: metrics.conversationURL
                )
            }
        }.value

        return UniversalSearchSnapshot(
            workspaces: workspaces,
            sessions: sessions,
            commands: commands,
            agentChats: agentChats,
            agentEvents: agentEvents
        )
    }

    func commandTimelineSnapshot() async -> CommandTimelineSnapshot {
        let snapshot = await universalSearchSnapshot()
        return CommandTimelineSnapshot(
            commands: snapshot.commands,
            agentEvents: snapshot.agentEvents,
            sessionTitles: Dictionary(
                uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0.title) }
            )
        )
    }

    func activateCommandTimelineEntry(_ entry: CommandTimelineEntry) {
        switch entry.target {
        case let .command(recordID, sessionID):
            selectSessionFromUniversalSearch(sessionID)
            commandHistorySearchInitialQuery = commandHistory.first(where: {
                $0.id == recordID
            })?.command ?? entry.title
            commandHistorySearchSessionID = sessionID
            isCommandTimelinePresented = false
            isCommandHistorySearchPresented = true
        case let .agentJob(reference, conversationURL):
            isCommandTimelinePresented = false
            if let tab = agentChatTabs.first(where: { tab in
                if tab.metrics?.reference == reference { return true }
                guard let activeJob = tab.activeJob else { return false }
                return GagJobReference(
                    target: activeJob.target,
                    jobID: activeJob.job.id
                ).serialized == reference
            }) {
                selectAgentChat(id: tab.id)
            } else if let conversationURL {
                ChatConversationOpener.open(conversationURL)
            }
        }
    }

    func activateUniversalSearchItem(_ item: UniversalSearchItem) {
        switch item.target {
        case let .workspace(workspaceID):
            guard let workspace = workspaces.first(where: {
                $0.id == workspaceID
            }) else { return }
            selectWorkspace(workspace)
        case let .session(sessionID):
            selectSessionFromUniversalSearch(sessionID)
        case let .command(recordID, sessionID):
            selectSessionFromUniversalSearch(sessionID)
            commandHistorySearchInitialQuery = commandHistory.first(where: {
                $0.id == recordID
            })?.command ?? item.title
            commandHistorySearchSessionID = sessionID
            isCommandHistorySearchPresented = true
        case let .agentChat(tabID):
            selectAgentChat(id: tabID)
        case let .agentJob(reference, conversationURL):
            if let tab = agentChatTabs.first(where: { tab in
                if tab.metrics?.reference == reference { return true }
                guard let activeJob = tab.activeJob else { return false }
                return GagJobReference(
                    target: activeJob.target,
                    jobID: activeJob.job.id
                ).serialized == reference
            }) {
                selectAgentChat(id: tab.id)
            } else if let conversationURL {
                ChatConversationOpener.open(conversationURL)
            }
        }
    }

    func clearCommandHistorySearchContext() {
        commandHistorySearchInitialQuery = ""
        commandHistorySearchSessionID = nil
    }

    private func selectSessionFromUniversalSearch(_ sessionID: UUID) {
        guard let workspace = workspaces.first(where: {
            SplitTreeOperations.contains(sessionID: sessionID, in: $0.layout)
        }) else { return }
        selectWorkspace(workspace)
        selectSession(sessionID)
    }

    func filteredCommandHistory(
        query: String,
        failuresOnly: Bool = false,
        sessionID: UUID? = nil
    ) -> [CommandExecutionRecord] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return commandHistory.filter { record in
            if failuresOnly && record.exitCode == 0 { return false }
            if let sessionID, record.sessionID != sessionID { return false }
            guard !normalized.isEmpty else { return true }
            return record.command.localizedCaseInsensitiveContains(normalized)
                || record.output.localizedCaseInsensitiveContains(normalized)
        }
    }

    func sessionTitle(for id: UUID) -> String {
        session(id: id)?.title ?? LocalShellNaming.title(number: 1)
    }

    func performAction(id: String) {
        switch id {
        case "search.universal":
            isCommandPalettePresented = false
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                self?.isUniversalSearchPresented = true
            }
            return
        case "command.palette":
            isCommandPalettePresented = true
        case "workspace.new":
            createWorkspace()
        case "pane.split.vertical":
            splitSelected(axis: .vertical)
        case "pane.split.horizontal":
            splitSelected(axis: .horizontal)
        case "terminal.find":
            requestFind()
        case "terminal.compact.toggle":
            isCompactMode.toggle()
        case "terminal.secureInput.toggle":
            secureKeyboardEntryEnabled.toggle()
        case "terminal.quick":
            NotificationCenter.default.post(
                name: .apexTermQuickTerminalRequested,
                object: nil
            )
        case "tab.next":
            selectAdjacentMainTab(offset: 1)
        case "tab.previous":
            selectAdjacentMainTab(offset: -1)
        case "terminal.tab.next":
            selectAdjacentTerminalTab(offset: 1)
        case "terminal.tab.previous":
            selectAdjacentTerminalTab(offset: -1)
        case "tab.moveLeft":
            moveSelectedMainTab(offset: -1)
        case "tab.moveRight":
            moveSelectedMainTab(offset: 1)
        case let actionID where actionID.hasPrefix("tab.select."):
            if let number = Int(actionID.dropFirst("tab.select.".count)) {
                selectMainTab(number: number)
            }
        case "terminal.latestOutput.copy":
            copyLatestOutputFromActiveTab()
        case "terminal.conversation.send":
            if let selectedSessionID {
                _ = sendConversationCommand(sessionID: selectedSessionID)
            }
        case "terminal.transcript.cycle":
            cycleCommandTranscriptMode()
        case "agent.new.local":
            createAgentChatTab(target: .local)
        case "agent.toggleRail":
            isAgentRailVisible.toggle()
        case "sidebar.toggleLeft":
            isWorkspaceSidebarCollapsed.toggle()
        case "sidebar.toggleRight":
            isRightSidebarCollapsed.toggle()
        case "history.toggle":
            isCommandHistoryVisible.toggle()
        case "history.timeline":
            isCommandTimelinePresented = true
        case "history.search":
            clearCommandHistorySearchContext()
            isCommandHistorySearchPresented = true
        case "terminal.context.copy":
            copySelectedContextPack()
        case "terminal.failure.launchpad":
            prepareLastFailureInAgentChat()
        case "pane.maximize":
            toggleMaximizeSelectedPane()
        case "pane.next":
            selectAdjacentPane(offset: 1)
        case "pane.previous":
            selectAdjacentPane(offset: -1)
        case let actionID where actionID.hasPrefix("pane.select."):
            if let number = Int(actionID.dropFirst("pane.select.".count)) {
                selectPane(number: number)
            }
        case "pane.close":
            closeSelectedSession()
        default:
            break
        }
        isCommandPalettePresented = false
    }

    private func startAutomationServer(in supportDirectory: URL) {
        let socketURL = ApexTermPaths.automationSocketURL()
        let authorizer = AutomationRequestAuthorizer(
            grants: [
                AutomationGrant(
                    clientID: "gag",
                    capabilities: [
                        .readStatus,
                        .focusSession,
                        .openWorkspace,
                        .createSplit,
                        .runCommand,
                        .attachRemote,
                        .manageRemoteHosts,
                        .reportAgentRun
                    ]
                )
            ]
        )
        let statusStore = automationStatusStore
        let historyRecorder = commandHistoryRecorder
        let server = UnixAutomationServer(socketURL: socketURL) { [weak self] request in
            let authorization = authorizer.authorize(request)
            guard authorization.status == .accepted else {
                return authorization
            }

            if case .readStatus = request.action,
               let snapshot = statusStore.snapshot(),
               let data = try? JSONEncoder().encode(snapshot),
               let payload = String(data: data, encoding: .utf8) {
                return AutomationResponse(
                    requestID: request.id,
                    status: .accepted,
                    message: "Status",
                    payload: payload
                )
            }

            if case let .runCommand(sessionID, command) = request.action {
                guard !command.contains("\n"), !command.contains("\r") else {
                    return AutomationResponse(
                        requestID: request.id,
                        status: .failed,
                        message: "Command bridge failed: commandContainsNewline"
                    )
                }
                guard let session = statusStore.snapshot()?.sessions.first(where: {
                    $0.id == sessionID
                        && ($0.kind == "local" || $0.kind.hasPrefix("local-tmux:"))
                }) else {
                    return AutomationResponse(
                        requestID: request.id,
                        status: .failed,
                        message: "Only active local sessions support command capture"
                    )
                }

                if session.kind == "local" {
                    let directRequest = DirectTerminalAutomationRequest(
                        sessionID: session.id,
                        command: command
                    )
                    Task { @MainActor [weak self] in
                        guard let self else {
                            directRequest.finish(.failure("application unavailable"))
                            return
                        }
                        beginDirectAutomation(directRequest)
                    }
                    switch directRequest.wait(timeout: 15) {
                    case let .record(record):
                        let result = TmuxCommandResult(
                            output: record.output,
                            exitCode: record.exitCode
                        )
                        let data = try? JSONEncoder().encode(result)
                        return AutomationResponse(
                            requestID: request.id,
                            status: .accepted,
                            message: "Command completed",
                            payload: data.flatMap { String(data: $0, encoding: .utf8) }
                        )
                    case let .failure(reason):
                        return AutomationResponse(
                            requestID: request.id,
                            status: .failed,
                            message: "Direct command bridge failed: \(reason)"
                        )
                    case nil:
                        Task { @MainActor [weak self] in
                            self?.cancelDirectAutomation(directRequest)
                        }
                        return AutomationResponse(
                            requestID: request.id,
                            status: .failed,
                            message: "Direct command bridge failed: timeout"
                        )
                    }
                }

                do {
                    let startedAt = Date()
                    let explicitTmuxName = String(
                        session.kind.dropFirst("local-tmux:".count)
                    )
                    let result = try TmuxCommandBridge().runCommand(
                        sessionID: session.id,
                        command: command,
                        explicitSessionName: explicitTmuxName
                    )
                    let updatedHistory = historyRecorder.append(
                        CommandExecutionRecord(
                            sessionID: session.id,
                            command: command,
                            output: result.output,
                            exitCode: result.exitCode,
                            startedAt: startedAt,
                            finishedAt: Date()
                        )
                    )
                    Task { @MainActor [weak self] in
                        self?.commandHistory = updatedHistory
                    }
                    let data = try JSONEncoder().encode(result)
                    return AutomationResponse(
                        requestID: request.id,
                        status: .accepted,
                        message: "Command completed",
                        payload: String(data: data, encoding: .utf8)
                    )
                } catch {
                    return AutomationResponse(
                        requestID: request.id,
                        status: .failed,
                        message: "Command bridge failed: \(error)"
                    )
                }
            }

            Task { @MainActor [weak self] in
                self?.applyAutomationAction(request.action)
            }
            return authorization
        }

        do {
            try server.start()
            automationServer = server
            automationSocketURL = socketURL
        } catch {
            persistenceMessage = "Automation socket unavailable"
        }
    }

    private func applyAutomationAction(_ action: AutomationAction) {
        switch action {
        case .readStatus:
            break
        case let .focusSession(sessionID):
            guard sessions.contains(where: { $0.id == sessionID }) else { return }
            selectedWorkspaceID = workspaces.first {
                SplitTreeOperations.contains(sessionID: sessionID, in: $0.layout)
            }?.id
            selectSession(sessionID)
            refreshAutomationStatus()
        case let .openWorkspace(workspaceID):
            guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
                return
            }
            selectWorkspace(workspace)
        case let .createSplit(sessionID, axis):
            guard sessions.contains(where: { $0.id == sessionID }) else { return }
            selectedSessionID = sessionID
            selectedWorkspaceID = workspaces.first {
                SplitTreeOperations.contains(sessionID: sessionID, in: $0.layout)
            }?.id
            splitSelected(axis: axis)
        case let .attachRemote(hostAlias, tmuxSession):
            let profile = sshProfiles.first(where: { $0.alias == hostAlias })
                ?? SSHHostProfile(alias: hostAlias)
            createRemoteWorkspace(profile: profile, tmuxSession: tmuxSession)
        case let .hideRemoteHost(alias):
            hideRemoteHost(alias: alias)
        case let .restoreRemoteHost(alias):
            restoreRemoteHost(alias: alias)
        case let .deleteRemoteHost(alias):
            deleteRemoteHost(alias: alias)
        case let .reportAgentRun(report):
            let registry = agentRunRegistry
            Task { [weak self] in
                _ = await registry.apply(report: report)
                let updatedRuns = await registry.allRuns()
                await MainActor.run { [weak self] in
                    self?.agentRuns = updatedRuns
                    self?.refreshAutomationStatus()
                }
            }
        case .sendText, .runCommand:
            break
        }
    }

    private func refreshAutomationSelection() {
        guard !automationStatusStore.updateSelection(
            workspaceID: selectedWorkspaceID,
            sessionID: selectedSessionID
        ) else {
            return
        }
        refreshAutomationStatus()
    }

    private func refreshAutomationStatus() {
        let workspaceSummaries = workspaces.map { workspace in
            AutomationStatusSnapshot.WorkspaceSummary(
                id: workspace.id,
                name: workspace.name,
                paneCount: SplitTreeOperations.paneCount(in: workspace.layout)
            )
        }
        let sessionSummaries = sessions.map { session in
            AutomationStatusSnapshot.SessionSummary(
                id: session.id,
                title: session.title,
                state: session.state,
                kind: sessionKindLabel(session.kind)
            )
        }
        automationStatusStore.update(
            AutomationStatusSnapshot(
                workspaces: workspaceSummaries,
                sessions: sessionSummaries,
                selectedWorkspaceID: selectedWorkspaceID,
                selectedSessionID: selectedSessionID,
                activeAgentCount: agentRuns.filter {
                    ![AgentRunState.succeeded, .failed, .cancelled].contains($0.state)
                }.count,
                agents: agentRuns.map { run in
                    AutomationStatusSnapshot.AgentSummary(
                        id: run.id,
                        provider: run.provider,
                        label: run.label,
                        state: run.state,
                        progress: run.progress,
                        message: run.lastEvent,
                        estimatedCompletionAt: run.estimatedCompletionAt,
                        estimatedInputTokens: run.estimatedInputTokens,
                        estimatedOutputTokens: run.estimatedOutputTokens,
                        conversationURL: run.conversationURL,
                        jobReference: run.jobReference
                    )
                }
            )
        )
    }

    private func sessionKindLabel(_ kind: SessionKind) -> String {
        switch kind {
        case .local:
            "local"
        case let .localTmux(session):
            "local-tmux:\(session)"
        case let .ssh(host):
            "ssh:\(host)"
        case let .tmux(host, session):
            "tmux:\(host):\(session)"
        }
    }

    private func statusLabel(for event: ShellSemanticEvent) -> String {
        switch event {
        case .promptStarted:
            "Ready"
        case .commandInputStarted:
            "Typing"
        case .commandCaptured:
            "Running"
        case .commandExecuted:
            "Running"
        case let .commandFinished(exitCode):
            exitCode.map { $0 == 0 ? "Done" : "Exit \($0)" } ?? "Done"
        }
    }

    private static func makeInitialDocument() -> WorkspaceDocument {
        let session = makeLocalSession()
        let workspace = Workspace(
            name: "Main",
            rootDirectory: session.workingDirectory,
            layout: .column(TerminalColumn(sessionID: session.id))
        )
        return WorkspaceDocument(
            workspaces: [workspace],
            sessions: [session]
        )
    }

    private static func makeLocalSession() -> TerminalSession {
        TerminalSession(
            title: LocalShellNaming.title(number: 1),
            kind: .local,
            state: .created,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    @discardableResult
    private static func normalizeLocalShellTitles(
        in document: inout WorkspaceDocument
    ) -> Bool {
        var changed = false

        for workspace in document.workspaces {
            let sessionIndexes = SplitTreeOperations.sessionIDs(in: workspace.layout)
                .compactMap { sessionID in
                    document.sessions.firstIndex { session in
                        session.id == sessionID
                            && session.kind == .local
                            && LocalShellNaming.isAutomaticTitle(session.title)
                    }
                }
            let normalizedTitles = LocalShellNaming.normalizedAutomaticTitles(
                sessionIndexes.map { document.sessions[$0].title }
            )

            for (sessionIndex, title) in zip(sessionIndexes, normalizedTitles) {
                guard document.sessions[sessionIndex].title != title else { continue }
                document.sessions[sessionIndex].title = title
                changed = true
            }
        }

        return changed
    }

    @discardableResult
    private func normalizeLocalShellTitles(inWorkspaceAt workspaceIndex: Int) -> Bool {
        guard workspaces.indices.contains(workspaceIndex) else { return false }
        var document = WorkspaceDocument(
            workspaces: [workspaces[workspaceIndex]],
            sessions: workspaceDomain.sessions
        )
        let changed = Self.normalizeLocalShellTitles(in: &document)
        guard changed else { return false }
        sessions = document.sessions
        workspaces[workspaceIndex].updatedAt = Date()
        return true
    }

    private func nextLocalShellTitle(inWorkspaceAt workspaceIndex: Int) -> String {
        guard workspaces.indices.contains(workspaceIndex) else {
            return LocalShellNaming.title(number: 1)
        }
        let titles = SplitTreeOperations.sessionIDs(in: workspaces[workspaceIndex].layout)
            .compactMap { sessionID in
                sessions.first { $0.id == sessionID && $0.kind == .local }?.title
            }
        return LocalShellNaming.title(
            number: LocalShellNaming.nextAvailableNumber(in: titles)
        )
    }

    private func commitState() {
        metadataSaveTask?.cancel()
        metadataSaveTask = nil
        let liveSessionIDs = Set(sessions.map(\.id))
        shellPromptReadySessionIDs.formIntersection(liveSessionIDs)
        remoteInteractiveSessionIDs.formIntersection(liveSessionIDs)
        conversationSendPendingSessionIDs.formIntersection(liveSessionIDs)
        activeCommandBySession = activeCommandBySession.filter {
            liveSessionIDs.contains($0.key)
        }
        commandTranscriptModeOverrides = commandTranscriptModeOverrides.filter {
            liveSessionIDs.contains($0.key)
        }
        terminalConversationDrafts = terminalConversationDrafts.filter {
            liveSessionIDs.contains($0.key)
        }
        let staleScheduledIDs = scheduledTerminalCommands
            .filter { !liveSessionIDs.contains($0.sessionID) }
            .map(\.id)
        if !staleScheduledIDs.isEmpty {
            let staleSet = Set(staleScheduledIDs)
            scheduledTerminalCommands.removeAll { staleSet.contains($0.id) }
            persistScheduledTerminalCommands()
        }
        TerminalPaneRuntimeStore.shared.scheduleRetainOnly(
            sessionIDs: liveSessionIDs
        )
        normalizeMainTabOrder()
        refreshAutomationStatus()
        persist()
    }

    private static func loadMainTabOrder() -> [MainTabReference] {
        guard let data = UserDefaults.standard.data(forKey: mainTabOrderDefaultsKey),
              let value = try? JSONDecoder().decode([MainTabReference].self, from: data) else {
            return []
        }
        return value
    }

    private func normalizeMainTabOrder() {
        mainTabOrder = MainTabOrder.normalized(
            mainTabOrder,
            workspaceIDs: workspaces.map(\.id),
            agentChatIDs: agentChatTabs.map(\.id)
        )
        persistMainTabOrder()
    }

    private func persistMainTabOrder() {
        guard let data = try? JSONEncoder().encode(mainTabOrder) else { return }
        UserDefaults.standard.set(data, forKey: Self.mainTabOrderDefaultsKey)
    }

    private func scheduleMetadataPersist() {
        metadataSaveTask?.cancel()
        let document = workspaceDomain.snapshot()
        metadataSaveTask = Task { [weak self, store] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                try await store.save(document)
            } catch {
                await MainActor.run { [weak self] in
                    self?.persistenceMessage = "Workspace save failed"
                }
            }
            await MainActor.run { [weak self] in
                self?.metadataSaveTask = nil
            }
        }
    }

    private func persist() {
        let document = workspaceDomain.snapshot()
        Task { [store] in
            do {
                try await store.save(document)
            } catch {
                await MainActor.run { [weak self] in
                    self?.persistenceMessage = "Workspace save failed"
                }
            }
        }
    }

    private func loadSSHProfiles() {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config")
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let parsed = SSHConfigParser.parse(text)
        nonInteractiveSSHAliases = Set(
            parsed.filter { !$0.isInteractiveShellCandidate }.map(\.alias)
        )
        baseSSHProfiles = parsed.filter(\.isInteractiveShellCandidate)
        refreshRemoteProfiles()
    }

    private func refreshRemoteProfiles() {
        remoteHostEntries = remoteHostConfiguration.entries(
            baseProfiles: baseSSHProfiles
        )
        deletedRemoteHostAliases = remoteHostConfiguration.deletedAliases.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        sshProfiles = remoteHostConfiguration.visibleProfiles(
            baseProfiles: baseSSHProfiles
        )
    }

    private func persistRemoteHostConfiguration() {
        do {
            try RemoteHostConfigurationStore.save(
                remoteHostConfiguration,
                to: remoteHostConfigurationURL
            )
            persistenceMessage = nil
        } catch {
            persistenceMessage = "Remote host settings could not be saved"
        }
        commitState()
    }

    private func updateRemoteWorkspaceTitles(profile: SSHHostProfile) {
        for index in sessions.indices {
            switch sessions[index].kind {
            case let .ssh(host) where host == profile.alias:
                sessions[index].title = profile.displayTitle
            case let .tmux(host, sessionName) where host == profile.alias:
                sessions[index].title = "\(profile.displayTitle):\(sessionName)"
            default:
                break
            }
        }

        for index in workspaces.indices {
            let sessionIDs = SplitTreeOperations.sessionIDs(in: workspaces[index].layout)
            guard sessionIDs.count == 1,
                  let sessionID = sessionIDs.first,
                  let terminal = sessions.first(where: { $0.id == sessionID }),
                  remoteHost(for: terminal.kind) == profile.alias else {
                continue
            }
            workspaces[index].name = profile.displayTitle
            workspaces[index].updatedAt = Date()
        }
    }

    private func removeRemoteWorkspaces(alias: String) {
        let removedWorkspaceIDs = Set(workspaces.compactMap { workspace -> UUID? in
            let sessionIDs = SplitTreeOperations.sessionIDs(in: workspace.layout)
            guard sessionIDs.contains(where: { sessionID in
                sessions.first(where: { $0.id == sessionID })
                    .flatMap { remoteHost(for: $0.kind) } == alias
            }) else {
                return nil
            }
            return workspace.id
        })
        guard !removedWorkspaceIDs.isEmpty else { return }

        workspaces.removeAll { removedWorkspaceIDs.contains($0.id) }
        let referencedSessionIDs = Set(workspaces.flatMap {
            SplitTreeOperations.sessionIDs(in: $0.layout)
        })
        sessions.removeAll { !referencedSessionIDs.contains($0.id) }

        if workspaces.isEmpty {
            let document = Self.makeInitialDocument()
            workspaces = document.workspaces
            sessions = document.sessions
        }
        selectedWorkspaceID = workspaces.first?.id
        selectedSessionID = workspaces.first.flatMap {
            SplitTreeOperations.sessionIDs(in: $0.layout).first
        }
    }

    private func normalizeGeneratedRemoteWorkspaces() {
        var seenRemoteKeys: Set<String> = []
        var removedSessionIDs: Set<UUID> = []
        var normalized: [Workspace] = []

        for workspace in workspaces {
            let ids = SplitTreeOperations.sessionIDs(in: workspace.layout)
            guard ids.count == 1,
                  let sessionID = ids.first,
                  let session = sessions.first(where: { $0.id == sessionID }),
                  let key = remoteKey(for: session.kind) else {
                normalized.append(workspace)
                continue
            }

            let host = remoteHost(for: session.kind)
            if host.map(nonInteractiveSSHAliases.contains) == true
                || host.map(remoteHostConfiguration.hiddenAliases.contains) == true
                || host.map(remoteHostConfiguration.deletedAliases.contains) == true
                || !seenRemoteKeys.insert(key).inserted {
                removedSessionIDs.insert(sessionID)
                continue
            }
            normalized.append(workspace)
        }

        guard !removedSessionIDs.isEmpty else { return }
        workspaces = normalized
        let referenced = Set(workspaces.flatMap {
            SplitTreeOperations.sessionIDs(in: $0.layout)
        })
        sessions.removeAll { removedSessionIDs.contains($0.id) && !referenced.contains($0.id) }
        selectedWorkspaceID = workspaces.first?.id
        selectedSessionID = workspaces.first.flatMap {
            SplitTreeOperations.sessionIDs(in: $0.layout).first
        }
        persist()
    }

    private func remoteHost(for kind: SessionKind) -> String? {
        switch kind {
        case .local, .localTmux:
            nil
        case let .ssh(host), let .tmux(host, _):
            host
        }
    }

    private func remoteKey(for kind: SessionKind) -> String? {
        switch kind {
        case .local, .localTmux:
            nil
        case let .ssh(host):
            "ssh:\(host)"
        case let .tmux(host, session):
            "tmux:\(host):\(session)"
        }
    }
}
