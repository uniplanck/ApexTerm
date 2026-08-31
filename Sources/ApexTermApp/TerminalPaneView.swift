import ApexTermCore
import AppKit
import Darwin
import SwiftTerm
import SwiftUI

@MainActor
struct TerminalPaneView: NSViewRepresentable {
    let session: TerminalSessionSnapshot
    let isActive: Bool
    let onTitleChange: (String) -> Void
    let onDirectoryChange: (String?) -> Void
    let onStateChange: (SessionState) -> Void
    let onSemanticEvents: ([ShellSemanticEvent]) -> Void
    let onPromptReadinessChange: (Bool) -> Void
    let onCommandCaptured: (CommandExecutionRecord) -> Void
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator {
        TerminalPaneRuntimeStore.shared.coordinator(for: session.id) {
            Coordinator(
                onTitleChange: onTitleChange,
                onDirectoryChange: onDirectoryChange,
                onStateChange: onStateChange,
                onSemanticEvents: onSemanticEvents
            )
        }
    }

    func makeNSView(context: Context) -> ApexTerminalHostView {
        let host = ApexTerminalHostView()
        let container = resolveContainer(context: context)
        configure(container: container, coordinator: context.coordinator)
        host.noteConfigured(session)
        _ = host.attach(container)
        container.prepareForPresentation()
        return host
    }

    func updateNSView(_ host: ApexTerminalHostView, context: Context) {
        let container = resolveContainer(context: context)
        if host.needsConfiguration(for: session) {
            context.coordinator.configure(terminal: container.terminal, session: session)
            configure(container: container, coordinator: context.coordinator)
            host.noteConfigured(session)
        }
        let didAttach = host.attach(container)
        if didAttach {
            container.prepareForPresentation()
        }
    }

    private func resolveContainer(context: Context) -> ApexTerminalContainerView {
        let store = TerminalPaneRuntimeStore.shared
        if let existing = store.container(for: session.id) {
            context.coordinator.configure(terminal: existing.terminal, session: session)
            store.noteReuse(sessionID: session.id, container: existing)
            return existing
        }

        let terminal = ApexLocalProcessTerminalView(frame: .zero)
        terminal.metalBufferingMode = .perRowPersistent
        terminal.suspendsRenderingWhenNotVisible = true
        let container = ApexTerminalContainerView(terminal: terminal)
        terminal.processDelegate = context.coordinator
        terminal.configureFindObserver(sessionID: session.id)
        terminal.configureInputObserver(sessionID: session.id)
        terminal.onCaptureStateChanged = { [weak container] in
            container?.refreshActionButton()
        }
        terminal.onSemanticEvent = { [weak coordinator = context.coordinator] event in
            coordinator?.consumeSemanticEvent(event)
        }
        terminal.font = NSFont.monospacedSystemFont(
            ofSize: CGFloat(session.fontSize),
            weight: .regular
        )
        terminal.setAccessibilityLabel("Terminal: \(session.accessibilityLabel)")
        terminal.setAccessibilityHelp(
            "Interactive terminal session. Scroll moves through output; use Command-F to search."
        )

        context.coordinator.configure(terminal: terminal, session: session)
        store.register(
            sessionID: session.id,
            coordinator: context.coordinator,
            container: container
        )
        configure(container: container, coordinator: context.coordinator)
        terminal.configureInputProbe()
        let sessionID = session.id
        Task { @MainActor [weak coordinator = context.coordinator, weak container] in
            guard let coordinator, let container else { return }
            coordinator.startProcess()
            store.noteProcessStarted(sessionID: sessionID, container: container)
            container.terminal.startInputProbeWhenReady()
            container.restoreVisiblePromptDecorationsWhenReady()
            await writeSmokeReadyMarker(terminal: container.terminal)
        }
        return container
    }

    static func dismantleNSView(
        _ host: ApexTerminalHostView,
        coordinator: Coordinator
    ) {
        host.detach()
        if let sessionID = coordinator.sessionID {
            TerminalPaneRuntimeStore.shared.noteDetached(sessionID: sessionID)
        }
    }

    private func configure(
        container: ApexTerminalContainerView,
        coordinator: Coordinator
    ) {
        let terminal = container.terminal
        terminal.processDelegate = coordinator
        if case .local = session.kind {
            terminal.setLocalControlCRecoveryEnabled(true)
        } else {
            terminal.setLocalControlCRecoveryEnabled(false)
        }
        terminal.commandBlocksEnabled = session.commandBlocksEnabled
        terminal.smartPasteProtectionEnabled = session.smartPasteProtectionEnabled
        terminal.multilinePasteConfirmationEnabled = session.multilinePasteConfirmationEnabled
        terminal.configureTrustPolicy(session.escapeSequenceTrustPolicy)
        terminal.configureInlineImageSafetyPolicy(session.inlineImageSafetyPolicy)
        terminal.configureResourceBudget()
        terminal.onActivate = onActivate
        terminal.onPromptReadinessChanged = onPromptReadinessChange
        container.setInteractionActive(isActive)
        if abs(terminal.font.pointSize - CGFloat(session.fontSize)) > 0.1 {
            terminal.font = NSFont.monospacedSystemFont(
                ofSize: CGFloat(session.fontSize),
                weight: .regular
            )
        }
        terminal.configureCommandCapture(
            sessionID: session.id,
            commandBlocksEnabled: session.commandBlocksEnabled,
            onCommandCaptured: onCommandCaptured
        )
        terminal.applyAppearance(session.appearance)
        terminal.setAccessibilityLabel("Terminal: \(session.accessibilityLabel)")
        container.refreshActionButton()
    }

    private func writeSmokeReadyMarker(terminal: ApexLocalProcessTerminalView) async {
        guard let path = ProcessInfo.processInfo.environment["APEXTERM_READY_FILE"],
              !path.isEmpty else {
            return
        }
        for _ in 0..<40 where terminal.window == nil {
            try? await Task.sleep(for: .milliseconds(25))
        }
        terminal.enableMetalRendererWhenAttached()
        let payload = "ready=1\nmetal=\(terminal.isUsingMetalRenderer ? 1 : 0)\n"
        try? Data(payload.utf8).write(
            to: URL(fileURLWithPath: path),
            options: [.atomic]
        )
    }

    @MainActor
    final class Coordinator: NSObject, ApexLocalProcessTerminalViewDelegate {
        let onTitleChange: (String) -> Void
        let onDirectoryChange: (String?) -> Void
        let onStateChange: (SessionState) -> Void
        let onSemanticEvents: ([ShellSemanticEvent]) -> Void

        private weak var terminal: ApexLocalProcessTerminalView?
        private var session: TerminalSessionSnapshot?
        private var isShuttingDown = false
        private var reconnectAttempt = 0
        private var reconnectTask: Task<Void, Never>?
        private var stabilityTask: Task<Void, Never>?
        private var healthTask: Task<Void, Never>?
        private let reconnectPolicy = ReconnectPolicy()

        var sessionID: UUID? {
            session?.id
        }

        var terminationScope: TerminalProcessTerminationScope {
            session?.terminationScope ?? .processOnly
        }

        init(
            onTitleChange: @escaping (String) -> Void,
            onDirectoryChange: @escaping (String?) -> Void,
            onStateChange: @escaping (SessionState) -> Void,
            onSemanticEvents: @escaping ([ShellSemanticEvent]) -> Void
        ) {
            self.onTitleChange = onTitleChange
            self.onDirectoryChange = onDirectoryChange
            self.onStateChange = onStateChange
            self.onSemanticEvents = onSemanticEvents
        }

        func configure(
            terminal: ApexLocalProcessTerminalView,
            session: TerminalSessionSnapshot
        ) {
            self.terminal = terminal
            self.session = session
        }

        func startProcess() {
            guard !isShuttingDown,
                  let terminal,
                  let session else {
                return
            }

            reconnectTask?.cancel()
            reconnectTask = nil
            if reconnectAttempt > 0, !terminal.process.running {
                terminal.terminateSession(scope: session.terminationScope)
            }

            terminal.prepareForProcessStart(trustPolicy: session.escapeSequenceTrustPolicy)
            transition(to: reconnectAttempt == 0 ? .starting : .reconnecting)
            let launch = session.launchPlan
            terminal.startProcess(
                executable: launch.executable,
                args: launch.arguments,
                environment: session.environment,
                currentDirectory: session.workingDirectory
            )

            if terminal.process.running {
                transition(to: .attached)
                scheduleStabilityReset()
                scheduleHealthMonitor()
            } else if session.supportsReconnect {
                scheduleReconnect()
            } else {
                transition(to: .failed)
            }
        }

        @discardableResult
        func restartProcessIfNeeded() -> Bool {
            guard !isShuttingDown,
                  let terminal,
                  !terminal.process.running else {
                return false
            }
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
            startProcess()
            return terminal.process.running
        }

        func prepareForShutdown() {
            isShuttingDown = true
            reconnectTask?.cancel()
            stabilityTask?.cancel()
            healthTask?.cancel()
            reconnectTask = nil
            stabilityTask = nil
            healthTask = nil
            terminal?.setProgrammaticInputEnabled(false)
        }

        func consumeSemanticEvent(_ event: ShellSemanticEvent) {
            onSemanticEvents([event])
        }

        func sizeChanged(source: ApexLocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: ApexLocalProcessTerminalView, title: String) {
            onTitleChange(title)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            onDirectoryChange(directory)
        }

        func processTerminated(source: ApexLocalProcessTerminalView, exitCode: Int32?) {
            stabilityTask?.cancel()
            stabilityTask = nil
            terminal?.setProgrammaticInputEnabled(false)
            terminal?.recoverTerminalModesAfterProcessExit()
            scheduleChildReap(source.process.shellPid)

            guard !isShuttingDown else { return }
            handleProcessStopped(exitCode: exitCode)
        }

        private func handleProcessStopped(exitCode: Int32?) {
            healthTask?.cancel()
            healthTask = nil
            guard reconnectTask == nil else { return }
            if session?.supportsReconnect == true {
                scheduleReconnect()
            } else {
                transition(to: exitCode == nil ? .failed : .exited)
            }
        }

        private func scheduleReconnect() {
            guard !isShuttingDown, reconnectTask == nil else { return }
            reconnectAttempt += 1
            guard let delay = reconnectPolicy.delaySeconds(
                forAttempt: reconnectAttempt
            ) else {
                transition(to: .failed)
                return
            }

            transition(to: .reconnecting)
            reconnectTask?.cancel()
            reconnectTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                reconnectTask = nil
                startProcess()
            }
        }

        private func scheduleHealthMonitor() {
            healthTask?.cancel()
            healthTask = nil
            guard session?.supportsReconnect == true else { return }
            healthTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self else { return }
                    guard !isShuttingDown else { return }
                    if terminal?.process.running != true {
                        handleProcessStopped(exitCode: nil)
                        return
                    }
                }
            }
        }

        private func scheduleChildReap(_ pid: pid_t) {
            guard pid > 0 else { return }
            Task.detached(priority: .utility) {
                var status: Int32 = 0
                for _ in 0..<40 {
                    let result = Darwin.waitpid(pid, &status, WNOHANG)
                    if result == pid || (result == -1 && errno == ECHILD) {
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(25))
                }
            }
        }

        private func scheduleStabilityReset() {
            stabilityTask?.cancel()
            stabilityTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled,
                      let self,
                      terminal?.process.running == true else {
                    return
                }
                reconnectAttempt = 0
                transition(to: .attached)
            }
        }

        private func transition(to state: SessionState) {
            terminal?.setProgrammaticInputEnabled(state == .attached)
            onStateChange(state)
        }
    }
}

@MainActor
final class ApexTerminalHostView: NSView {
    private weak var attachedContainer: ApexTerminalContainerView?
    private var configuredSession: TerminalSessionSnapshot?
    private let livePaneFrameProbeURL = ProcessInfo.processInfo.environment[
        "APEXTERM_LIVE_PANE_FRAME_PROBE_FILE"
    ].flatMap { value in
        value.isEmpty ? nil : URL(fileURLWithPath: value)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func needsConfiguration(for session: TerminalSessionSnapshot) -> Bool {
        configuredSession != session
    }

    func noteConfigured(_ session: TerminalSessionSnapshot) {
        configuredSession = session
        recordLivePaneFrameProbe()
    }

    @discardableResult
    func attach(_ container: ApexTerminalContainerView) -> Bool {
        guard attachedContainer !== container || container.superview !== self else {
            container.frame = bounds
            return false
        }
        if container.superview !== self {
            container.removeFromSuperview()
            container.translatesAutoresizingMaskIntoConstraints = true
            container.autoresizingMask = [.width, .height]
            container.frame = bounds
            addSubview(container)
        }
        attachedContainer = container
        needsLayout = true
        layoutSubtreeIfNeeded()
        return true
    }

    func detach() {
        guard let container = attachedContainer else { return }
        if container.superview === self {
            container.removeFromSuperview()
        }
        attachedContainer = nil
    }

    override func layout() {
        super.layout()
        attachedContainer?.frame = bounds
        recordLivePaneFrameProbe()
    }

    private func recordLivePaneFrameProbe() {
        guard let livePaneFrameProbeURL,
              let sessionID = configuredSession?.id,
              window != nil else {
            return
        }
        let payload: [String: Any] = [
            "sessionID": sessionID.uuidString,
            "hostHeight": bounds.height,
            "hostWidth": bounds.width,
            "containerHeight": attachedContainer?.bounds.height ?? 0,
            "terminalHeight": attachedContainer?.terminal.bounds.height ?? 0
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: livePaneFrameProbeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: livePaneFrameProbeURL, options: .atomic)
    }
}

@MainActor
final class TerminalPaneRuntimeStore {
    static let shared = TerminalPaneRuntimeStore()

    private var coordinators: [UUID: TerminalPaneView.Coordinator] = [:]
    private var containers: [UUID: ApexTerminalContainerView] = [:]
    private var pendingRetentionTask: Task<Void, Never>?
    private var pendingSessionIDs: Set<UUID> = []
    private let probePath = ProcessInfo.processInfo.environment[
        "APEXTERM_TERMINAL_PERSISTENCE_PROBE_FILE"
    ]
    private let probeMarker = ProcessInfo.processInfo.environment[
        "APEXTERM_TERMINAL_PERSISTENCE_MARKER"
    ]

    private init() {}

    func coordinator(
        for sessionID: UUID,
        create: () -> TerminalPaneView.Coordinator
    ) -> TerminalPaneView.Coordinator {
        if let existing = coordinators[sessionID] {
            return existing
        }
        let coordinator = create()
        coordinators[sessionID] = coordinator
        return coordinator
    }

    func register(
        sessionID: UUID,
        coordinator: TerminalPaneView.Coordinator,
        container: ApexTerminalContainerView
    ) {
        coordinators[sessionID] = coordinator
        containers[sessionID] = container
        record("create:\(sessionID.uuidString)")
    }

    func container(for sessionID: UUID) -> ApexTerminalContainerView? {
        containers[sessionID]
    }

    func requestFocus(sessionID: UUID) {
        containers[sessionID]?.terminal.requestFocusWhenReady()
    }

    func isProcessRunning(sessionID: UUID) -> Bool {
        containers[sessionID]?.terminal.process.running == true
    }

    func isPromptReady(sessionID: UUID) -> Bool {
        containers[sessionID]?.terminal.promptReadySnapshot == true
    }

    @discardableResult
    func sendProgrammaticInput(
        sessionID: UUID,
        text: String,
        execute: Bool
    ) -> Bool {
        guard !text.isEmpty,
              let terminal = containers[sessionID]?.terminal else {
            return false
        }
        return terminal.handleProgrammaticInput(
            TerminalInputRequest(
                sessionID: sessionID,
                text: text,
                execute: execute
            )
        )
    }

    func forceInterruptOrRestart(
        sessionID: UUID
    ) -> TerminalForceInterruptResult {
        if let terminal = containers[sessionID]?.terminal,
           terminal.process.running {
            return terminal.forceInterruptAndRecover()
        }
        if coordinators[sessionID]?.restartProcessIfNeeded() == true {
            return .restartedSession
        }
        return .unavailable
    }

    func noteProcessStarted(sessionID: UUID, container: ApexTerminalContainerView) {
        record(
            "process:\(sessionID.uuidString):pid=\(container.terminal.process.shellPid)"
        )
    }

    func noteReuse(sessionID: UUID, container: ApexTerminalContainerView) {
        let bufferPreserved: Int
        if let probeMarker, !probeMarker.isEmpty {
            let data = container.terminal.getBufferAsData(kind: .active)
            let text = String(decoding: data, as: UTF8.self)
            bufferPreserved = text.contains(probeMarker) ? 1 : 0
        } else {
            bufferPreserved = -1
        }
        let pid = container.terminal.process.shellPid
        record(
            "reuse:\(sessionID.uuidString):buffer=\(bufferPreserved):pid=\(pid)"
        )
    }

    func noteDetached(sessionID: UUID) {
        record("detach:\(sessionID.uuidString)")
    }

    func scheduleRetainOnly(sessionIDs: Set<UUID>) {
        pendingSessionIDs = sessionIDs
        pendingRetentionTask?.cancel()
        pendingRetentionTask = Task { @MainActor [weak self] in
            // Never remove AppKit terminal views in the same MainActor turn in which
            // SwiftUI is reconciling a tab/pane removal. Doing so can invalidate the
            // representable hierarchy and its first responder mid-update.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            pendingRetentionTask = nil
            retainOnlyNow(sessionIDs: pendingSessionIDs)
        }
    }

    func retainOnly(sessionIDs: Set<UUID>) {
        pendingSessionIDs = sessionIDs
        pendingRetentionTask?.cancel()
        pendingRetentionTask = nil
        retainOnlyNow(sessionIDs: sessionIDs)
    }

    func shutdownAll() {
        pendingRetentionTask?.cancel()
        pendingRetentionTask = nil
        pendingSessionIDs.removeAll()
        let knownIDs = Set(coordinators.keys).union(containers.keys)
        for sessionID in knownIDs {
            shutdown(sessionID: sessionID)
        }
    }

    private func retainOnlyNow(sessionIDs: Set<UUID>) {
        let knownIDs = Set(coordinators.keys).union(containers.keys)
        for sessionID in knownIDs where !sessionIDs.contains(sessionID) {
            shutdown(sessionID: sessionID)
        }
    }

    private func shutdown(sessionID: UUID) {
        let coordinator = coordinators.removeValue(forKey: sessionID)
        let container = containers.removeValue(forKey: sessionID)
        coordinator?.prepareForShutdown()
        container?.prepareForDetachment()
        container?.invalidate()
        container?.terminal.removeFindObserver()
        container?.terminal.removeInputObserver()
        container?.terminal.onSemanticEvent = nil
        container?.terminal.onCommandCaptured = nil
        container?.terminal.onCaptureStateChanged = nil
        container?.terminal.onPromptReadinessChanged = nil
        container?.terminal.processDelegate = nil
        container?.terminal.terminateSession(
            scope: coordinator?.terminationScope ?? .processOnly
        )
        container?.removeFromSuperview()
        record("shutdown:\(sessionID.uuidString)")
    }

    private func record(_ event: String) {
        guard let probePath, !probePath.isEmpty else { return }
        let url = URL(fileURLWithPath: probePath)
        let data = Data((event + "\n").utf8)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: [.atomic])
            }
        } catch {
            // Test-only observability must never affect terminal operation.
        }
    }
}

final class ApexTerminalContainerView: NSView {
    private final class PromptDecoration {
        let id = UUID()
        let button: NSButton
        var row: Int

        init(button: NSButton, row: Int) {
            self.button = button
            self.row = row
        }
    }

    let terminal: ApexLocalProcessTerminalView
    private var promptDecorations: [PromptDecoration] = []
    private var selectedDecoration: PromptDecoration?
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var visibilityObservers: [NSObjectProtocol] = []
    private let promptProbePath = ProcessInfo.processInfo.environment[
        "APEXTERM_PROMPT_DECORATION_PROBE_FILE"
    ]
    private let promptRestoreProbePath = ProcessInfo.processInfo.environment[
        "APEXTERM_PROMPT_RESTORE_PROBE_FILE"
    ]
    private var promptProbeWritten = false
    private var isInteractionActive = false

    init(terminal: ApexLocalProcessTerminalView) {
        self.terminal = terminal
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor

        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        terminal.onPromptStarted = { [weak self] bufferRow in
            self?.addPromptDecoration(row: bufferRow)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            prepareForDetachment()
        } else {
            prepareForPresentation()
            terminal.setInteractionActive(isInteractionActive)
        }
    }

    func setInteractionActive(_ active: Bool) {
        guard isInteractionActive != active else {
            terminal.setInteractionActive(active)
            return
        }
        isInteractionActive = active
        terminal.setInteractionActive(active)
    }

    func prepareForPresentation() {
        installScrollMonitor()
        installKeyMonitor()
        installVisibilityObservers()
        needsLayout = true
        layoutSubtreeIfNeeded()
        needsDisplay = true
        terminal.needsDisplay = true
        terminal.layer?.setNeedsDisplay()
        DispatchQueue.main.async { [weak self] in
            guard let self, window != nil else { return }
            needsLayout = true
            layoutSubtreeIfNeeded()
            needsDisplay = true
            terminal.needsDisplay = true
            displayIfNeeded()
            terminal.displayIfNeeded()
        }
    }

    func prepareForDetachment() {
        terminal.cancelPendingFocusRequest()
        removeScrollMonitor()
        removeKeyMonitor()
        removeVisibilityObservers()
    }

    override func layout() {
        super.layout()
        layoutPromptDecorations()
    }

    func restoreVisiblePromptDecorationsWhenReady() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                guard terminal.process.running else { continue }
                guard promptDecorations.isEmpty else { return }

                let state = terminal.terminalStateSnapshot()
                let matchedRows = state.visibleRows.compactMap { row in
                    looksLikeShellPrompt(row.text) ? row.row : nil
                }

                guard let latestPromptRow = matchedRows.last else { continue }
                addPromptDecoration(row: state.viewportRow + latestPromptRow)
                if let promptRestoreProbePath,
                   !promptRestoreProbePath.isEmpty {
                    let result = [
                        "restored_prompt_count=1",
                        "restored_current_prompt=\(latestPromptRow == state.cursor.row ? 1 : 0)"
                    ].joined(separator: "\n") + "\n"
                    try? Data(result.utf8).write(
                        to: URL(fileURLWithPath: promptRestoreProbePath),
                        options: [.atomic]
                    )
                }
                return
            }
        }
    }

    private func looksLikeShellPrompt(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty,
              normalized.count <= 300,
              let suffix = normalized.last,
              "%$#❯➜>".contains(suffix) else {
            return false
        }

        return normalized.hasPrefix("(")
            || normalized.contains("@")
            || normalized.contains("~")
            || normalized.contains("/")
            || normalized.count <= 3
    }

    private func installScrollMonitor() {
        removeScrollMonitor()
        guard window != nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  event.window === window,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else {
                return event
            }
            terminal.handleApexScrollWheel(event)
            layoutPromptDecorations()
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === window,
                  window?.firstResponder === terminal else {
                return event
            }
            terminal.handleApexKeyDown(event)
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func installVisibilityObservers() {
        removeVisibilityObservers()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification
        ]
        visibilityObservers = names.map { name in
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, window != nil else { return }
                    needsLayout = true
                    layoutSubtreeIfNeeded()
                    needsDisplay = true
                    terminal.needsDisplay = true
                    terminal.layer?.setNeedsDisplay()
                    displayIfNeeded()
                    terminal.displayIfNeeded()
                }
            }
        }
    }

    private func removeVisibilityObservers() {
        let center = NotificationCenter.default
        for observer in visibilityObservers {
            center.removeObserver(observer)
        }
        visibilityObservers.removeAll()
    }

    func invalidate() {
        terminal.cancelPendingFocusRequest()
        removeScrollMonitor()
        removeKeyMonitor()
        terminal.onPromptStarted = nil
        removeAllPromptDecorations()
    }

    func refreshActionButton() {
        let hidden = !terminal.commandBlocksEnabled
        for decoration in promptDecorations {
            decoration.button.isHidden = hidden
        }
        layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor
        needsLayout = true
    }

    private func addPromptDecoration(row: Int) {
        guard terminal.commandBlocksEnabled else { return }
        let resolvedRow = max(0, row)

        if let current = promptDecorations.last {
            current.row = resolvedRow
            if promptDecorations.count > 1 {
                for stale in promptDecorations.dropLast() {
                    stale.button.removeFromSuperview()
                }
                promptDecorations = [current]
            }
            current.button.identifier = NSUserInterfaceItemIdentifier("prompt-decoration-latest")
            current.button.setAccessibilityIdentifier("prompt-decoration-latest")
            selectedDecoration = nil
            needsLayout = true
            layoutPromptDecorations()
            writePromptProbeIfRequested(current)
            return
        }

        let button = NSButton(frame: .zero)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: "Prompt actions"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        )
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "このプロンプトの操作"
        button.target = self
        button.action = #selector(showPromptActions(_:))
        button.setAccessibilityLabel("Prompt actions")

        let decoration = PromptDecoration(button: button, row: resolvedRow)
        button.identifier = NSUserInterfaceItemIdentifier("prompt-decoration-latest")
        button.setAccessibilityIdentifier("prompt-decoration-latest")
        addSubview(button, positioned: .above, relativeTo: terminal)
        promptDecorations = [decoration]
        needsLayout = true
        layoutPromptDecorations()
        writePromptProbeIfRequested(decoration)
    }

    private func writePromptProbeIfRequested(_ decoration: PromptDecoration) {
        guard !promptProbeWritten,
              let promptProbePath,
              !promptProbePath.isEmpty else {
            return
        }

        Task { @MainActor [weak self, weak button = decoration.button] in
            guard let self, let button else { return }
            for _ in 0..<30 {
                layoutPromptDecorations()
                let center = NSPoint(
                    x: button.bounds.midX,
                    y: button.bounds.midY
                )
                let pointInSuperview = button.convert(center, to: button.superview)
                let hit = button.superview?.hitTest(pointInSuperview)
                let visible = button.frame.width > 0
                    && button.frame.height > 0
                    && !button.visibleRect.isEmpty
                    && !button.isHiddenOrHasHiddenAncestor
                let hittable = hit === button
                    || hit?.isDescendant(of: button) == true
                if visible && hittable && button.target != nil && button.action != nil {
                    promptProbeWritten = true
                    let result = [
                        "prompt_button_found=1",
                        "prompt_button_visible=1",
                        "prompt_button_hittable=1",
                        "prompt_button_action=1",
                        "prompt_button_count=\(promptDecorations.count)",
                        "prompt_button_frame=\(NSStringFromRect(button.frame))"
                    ].joined(separator: "\n") + "\n"
                    try? Data(result.utf8).write(
                        to: URL(fileURLWithPath: promptProbePath),
                        options: [.atomic]
                    )
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }

            promptProbeWritten = true
            let result = [
                "prompt_button_found=1",
                "prompt_button_visible=0",
                "prompt_button_hittable=0",
                "prompt_button_action=\((button.target != nil && button.action != nil) ? 1 : 0)",
                "prompt_button_count=\(promptDecorations.count)",
                "prompt_button_frame=\(NSStringFromRect(button.frame))"
            ].joined(separator: "\n") + "\n"
            try? Data(result.utf8).write(
                to: URL(fileURLWithPath: promptProbePath),
                options: [.atomic]
            )
        }
    }

    private func removeAllPromptDecorations() {
        for decoration in promptDecorations {
            decoration.button.removeFromSuperview()
        }
        promptDecorations.removeAll()
        selectedDecoration = nil
    }

    private func layoutPromptDecorations() {
        let state = terminal.terminalStateSnapshot()
        let rows = max(1, state.dimensions.rows)
        let cellHeight = terminal.bounds.height / CGFloat(rows)
        guard cellHeight.isFinite, cellHeight > 0 else { return }

        let isAtLiveBottom = !terminal.canScroll || terminal.scrollPosition >= 0.999
        for decoration in promptDecorations {
            let visibleRow = decoration.row - state.viewportRow
            let visible = visibleRow >= 0 && visibleRow < rows && isAtLiveBottom
            decoration.button.isHidden = !terminal.commandBlocksEnabled || !visible
            guard visible else { continue }
            let width: CGFloat = 18
            let height: CGFloat = 14
            let y = terminal.frame.maxY
                - CGFloat(visibleRow + 1) * cellHeight
                + max(0, (cellHeight - height) / 2)
            decoration.button.frame = NSRect(x: 4, y: y, width: width, height: height)
        }
    }

    @objc private func showPromptActions(_ sender: NSButton) {
        selectedDecoration = promptDecorations.first { $0.button === sender }
        let isLatest = selectedDecoration === promptDecorations.last
        let command = isLatest ? terminal.currentCommandText : ""
        let output = isLatest ? terminal.currentOutputText : ""

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(copyItem(
            title: "入力をコピー",
            enabled: !command.isEmpty,
            action: #selector(copyInput)
        ))
        menu.addItem(copyItem(
            title: "出力をコピー",
            enabled: !output.isEmpty,
            action: #selector(copyOutput)
        ))
        menu.addItem(copyItem(
            title: "入力と出力をコピー",
            enabled: !command.isEmpty || !output.isEmpty,
            action: #selector(copyInputAndOutput)
        ))
        if command.isEmpty && output.isEmpty {
            menu.addItem(.separator())
            let pending = NSMenuItem(
                title: isLatest ? "実行後にコピーできます" : "空のプロンプトです",
                action: nil,
                keyEquivalent: ""
            )
            pending.isEnabled = false
            menu.addItem(pending)
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: sender.frame.minX, y: sender.frame.minY - 2),
            in: self
        )
    }

    private func copyItem(title: String, enabled: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func copyInput() {
        ClipboardWriter.copy(terminal.currentCommandText)
    }

    @objc private func copyOutput() {
        ClipboardWriter.copy(terminal.currentOutputText)
    }

    @objc private func copyInputAndOutput() {
        ClipboardWriter.copy(terminal.currentCommandAndOutput)
    }
}

enum TerminalProcessTerminationScope {
    case processOnly
    case processGroup
}

enum TerminalForceInterruptResult: Equatable {
    case unavailable
    case sentControlC
    case signalledForegroundProcessGroup(pid_t)
    case restartedSession
}

#if DEBUG
private final class ApexTerminalDebugHostObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: ((ArraySlice<UInt8>) -> Void)?

    func set(_ callback: ((ArraySlice<UInt8>) -> Void)?) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func emit(_ bytes: [UInt8]) {
        lock.lock()
        let callback = self.callback
        lock.unlock()
        callback?(bytes[...])
    }
}
#endif

@MainActor
protocol ApexLocalProcessTerminalViewDelegate: AnyObject {
    func sizeChanged(source: ApexLocalProcessTerminalView, newCols: Int, newRows: Int)
    func setTerminalTitle(source: ApexLocalProcessTerminalView, title: String)
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?)
    func processTerminated(source: ApexLocalProcessTerminalView, exitCode: Int32?)
}

final class ApexLocalProcessTerminalView: TerminalView, TerminalViewDelegate, LocalProcessDelegate {
    weak var processDelegate: ApexLocalProcessTerminalViewDelegate?
    var onSemanticEvent: ((ShellSemanticEvent) -> Void)?
    var onCommandCaptured: ((CommandExecutionRecord) -> Void)?
    var onCaptureStateChanged: (() -> Void)?
    var onPromptStarted: ((Int) -> Void)?
    var onPromptReadinessChanged: ((Bool) -> Void)?
    var commandBlocksEnabled = true
    var smartPasteProtectionEnabled = true
    var multilinePasteConfirmationEnabled = false
    var onActivate: (() -> Void)?

    private var findObserver: NSObjectProtocol?
    private var inputObserver: NSObjectProtocol?
    private var inputProbeFile: String?
    private var inputProbeMarker: String?
    private var programmaticInputProbeFile: String?
    private var programmaticInputProbeMarker: String?
    private var scrollProbeFile: String?
    private var scrollProbeMarker: String?
    private var focusTask: Task<Void, Never>?
    private var resizeSyncTask: Task<Void, Never>?
    private var promptReadinessTask: Task<Void, Never>?
    private var lastReportedPromptReadiness = false
    private var controlCRecoveryTask: Task<Void, Never>?
    private var controlCRecoveryArmedUntil: Date?
    private var controlCRecoveryAllowsAlternateScreen = false
    private var lastControlCAt: Date?
    private var localControlCRecoveryEnabled = false
    private var commandSessionID: UUID?
    nonisolated private let outputPipeline = ApexTerminalOutputPipeline()
#if DEBUG
    nonisolated private let debugHostObserver = ApexTerminalDebugHostObserver()
    var onHostData: ((ArraySlice<UInt8>) -> Void)? {
        didSet { debugHostObserver.set(onHostData) }
    }
#endif
    private var trustPolicy = TerminalEscapeSequenceTrustPolicy.localDefault
    private var inlineImageSafetyPolicy = TerminalInlineImageSafetyPolicy.localDefault
    private var isAlternateBufferActive = false
    private var programmaticInputEnabled = false
    private var interactionActive = false
    private var capturedCommand = ""
    private var capturedOutput: [UInt8] = []
    private var commandStartedAt: Date?
    private var isCapturingOutput = false
    private var outputWasTruncated = false
    private static let maximumKittyImageCacheBytes = 64 * 1_024 * 1_024

    lazy var process = LocalProcess(
        delegate: self,
        dispatchQueue: .main,
        directDelivery: true
    )

    static func terminalOptions() -> TerminalOptions {
        var options = TerminalOptions.default
        options.enableSixelReported = false
        options.kittyGraphics.storageLimitBytesPerScreen = UInt32(
            clamping: Self.maximumKittyImageCacheBytes
        )
        return options
    }

    override init(frame: CGRect) {
        super.init(frame: frame, font: nil, options: Self.terminalOptions())
        terminalDelegate = self
        outputPipeline.updateWindowSize(computeWindowSize())
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        terminalDelegate = self
        outputPipeline.updateWindowSize(computeWindowSize())
    }

    var currentCommandText: String {
        capturedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentOutputText: String {
        var output = TerminalTextSanitizer.plainText(from: capturedOutput)
        if outputWasTruncated {
            output += output.isEmpty
                ? "出力は2MBで省略されました"
                : "\n… 出力は2MBで省略されました"
        }
        return output
    }

    var hasCurrentCommandPayload: Bool {
        !currentCommandText.isEmpty || !currentOutputText.isEmpty
    }

    var promptReadySnapshot: Bool {
        guard process.running, !isAlternateBufferActive else {
            return false
        }
        let data = getBufferAsData(kind: .active)
        return TerminalPromptHeuristic.isPromptReady(
            bufferText: String(decoding: data, as: UTF8.self)
        )
    }

    var currentCommandAndOutput: String {
        let command = currentCommandText
        let output = currentOutputText
        if command.isEmpty { return output }
        if output.isEmpty { return command }
        return "$ \(command)\n\(output)"
    }

    func configureFindObserver(sessionID: UUID) {
        removeFindObserver()
        findObserver = NotificationCenter.default.addObserver(
            forName: .apexTermFindRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let requestedID = notification.object as? UUID,
                  requestedID == sessionID else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let menuItem = NSMenuItem()
                menuItem.tag = NSTextFinder.Action.showFindInterface.rawValue
                self.performTextFinderAction(menuItem)
            }
        }
    }

    func configureInputObserver(sessionID: UUID) {
        removeInputObserver()
        inputObserver = NotificationCenter.default.addObserver(
            forName: .apexTermInputRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let request = notification.object as? TerminalInputRequest,
                  request.sessionID == sessionID else { return }
            Task { @MainActor [weak self] in
                _ = self?.handleProgrammaticInput(request)
            }
        }
    }

    @discardableResult
    func handleProgrammaticInput(_ request: TerminalInputRequest) -> Bool {
        guard programmaticInputEnabled, process.running else { return false }
        reportPromptReadiness(false)
        requestFocusWhenReady()
        var text = request.text
        if request.execute && !text.hasSuffix("\n") {
            text += "\n"
        }
        if request.execute {
            // Programmatic execution must not depend on AppKit first-responder or
            // IME state. Write the command bytes to the PTY directly, exactly as a
            // physical terminal would after the user presses Return.
            let bytes = Array(text.utf8)
            send(source: self, data: bytes[...])
        } else {
            insertText(
                text,
                replacementRange: NSRange(location: 0, length: 0)
            )
        }
        return true
    }

    func setProgrammaticInputEnabled(_ enabled: Bool) {
        programmaticInputEnabled = enabled
    }

    func configureTrustPolicy(_ policy: TerminalEscapeSequenceTrustPolicy) {
        guard trustPolicy != policy else { return }
        trustPolicy = policy
        outputPipeline.updateTrustPolicy(policy)
    }

    func configureInlineImageSafetyPolicy(_ policy: TerminalInlineImageSafetyPolicy) {
        guard inlineImageSafetyPolicy != policy else { return }
        inlineImageSafetyPolicy = policy
        outputPipeline.updateInlineImagePolicy(policy)
    }

    func configureResourceBudget() {
        // Resource limits are startup-only in next-generation SwiftTerm and are
        // applied by this view's initializer before the terminal core is created.
    }

    func startProcess(
        executable: String = "/bin/bash",
        args: [String] = [],
        environment: [String]? = nil,
        execName: String? = nil,
        currentDirectory: String? = nil
    ) {
        syncProcessWindowSize(updatePTY: false)
        process.startProcess(
            executable: executable,
            args: args,
            environment: environment,
            execName: execName,
            currentDirectory: currentDirectory
        )
    }

    func terminate() {
        process.terminate()
    }

    // MARK: - TerminalView / PTY bridge

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        syncProcessWindowSize()
        processDelegate?.sizeChanged(source: self, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        processDelegate?.setTerminalTitle(source: self, title: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        processDelegate?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        process.send(data: data)
    }

    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func clipboardCopy(source: TerminalView, content: Data) {
        guard trustPolicy.clipboardAccess != .disabled,
              let text = String(data: content, encoding: .utf8) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([text as NSString])
    }

    func clipboardRead(source: TerminalView) -> Data? {
        guard trustPolicy.clipboardAccess == .readWrite,
              let text = NSPasteboard.general.string(forType: .string) else {
            return nil
        }
        return text.data(using: .utf8)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    nonisolated func dataReceived(slice: ArraySlice<UInt8>) {
        let result = outputPipeline.process(slice)
        guard !result.bytes.isEmpty else { return }

#if DEBUG
        debugHostObserver.emit(result.bytes)
#endif
        feed(byteArray: result.bytes[...])
        let signals = result.signals
        let hasSignals = signals.controlCEcho
            || signals.inputProbe
            || signals.programmaticInputProbe
            || !signals.semanticEvents.isEmpty
            || !signals.completedCommands.isEmpty
        if hasSignals {
            Task { @MainActor [weak self] in
                self?.handleOutputSignals(signals)
            }
        }

        if result.bytes.contains(0x0A), outputPipeline.claimPromptInspection() {
            let pipeline = outputPipeline
            Task { @MainActor [weak self] in
                defer { pipeline.completePromptInspection() }
                try? await Task.sleep(for: .milliseconds(140))
                guard let self, process.running else { return }
                reportPromptReadiness(promptReadySnapshot)
            }
        }
    }

    nonisolated func getWindowSize() -> winsize {
        outputPipeline.windowSize()
    }

    nonisolated func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            processDelegate?.processTerminated(source: self, exitCode: exitCode)
        }
    }

    nonisolated override func bufferActivated(source: Terminal) {
        let alternate = source.isCurrentBufferAlternate
        super.bufferActivated(source: source)
        Task { @MainActor [weak self] in
            self?.isAlternateBufferActive = alternate
        }
    }

#if DEBUG
    var debugIsAlternateBufferActive: Bool { isAlternateBufferActive }
    var debugBufferText: String {
        String(decoding: getBufferAsData(kind: .active), as: UTF8.self)
    }
#endif

    private func computeWindowSize() -> winsize {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let dimensions = terminalDimensions
        let pxW = Int(max(0, bounds.width) * scale)
        let pxH = Int(max(0, bounds.height) * scale)
        return winsize(
            ws_row: UInt16(clamping: dimensions.rows),
            ws_col: UInt16(clamping: dimensions.cols),
            ws_xpixel: UInt16(clamping: pxW),
            ws_ypixel: UInt16(clamping: pxH)
        )
    }

    private func syncProcessWindowSize(updatePTY: Bool = true) {
        var size = computeWindowSize()
        outputPipeline.updateWindowSize(size)
        if updatePTY, process.running, process.childfd >= 0 {
            _ = PseudoTerminalHelpers.setWinSize(
                masterPtyDescriptor: process.childfd,
                windowSize: &size
            )
        }
    }

    func prepareForProcessStart(trustPolicy: TerminalEscapeSequenceTrustPolicy) {
        cancelControlCRecovery()
        self.trustPolicy = trustPolicy
        outputPipeline.updateTrustPolicy(trustPolicy)
        outputPipeline.updateInlineImagePolicy(inlineImageSafetyPolicy)
        outputPipeline.resetStreamState()
        promptReadinessTask?.cancel()
        promptReadinessTask = nil
        reportPromptReadiness(false)
        setProgrammaticInputEnabled(false)
        resetCapture()
    }

    func terminateSession(scope: TerminalProcessTerminationScope) {
        setProgrammaticInputEnabled(false)
        cancelPendingFocusRequest()
        resizeSyncTask?.cancel()
        resizeSyncTask = nil
        promptReadinessTask?.cancel()
        promptReadinessTask = nil
        reportPromptReadiness(false)
        cancelControlCRecovery()
        outputPipeline.resetStreamState()

        if scope == .processGroup {
            terminateLocalProcessSessionIfSafe()
        }
        terminate()
    }

    func recoverTerminalModesAfterProcessExit() {
        outputPipeline.resetStreamState()

        // A dead process cannot legitimately own terminal modes anymore. Clear the
        // active buffer's Kitty stack, leave the alternate screen, then clear the
        // normal buffer's stack as well. Other input-affecting private modes are
        // reset without using RIS, so scrollback remains available for diagnosis.
        feed(text: "\u{001B}[<17u")
        feed(text: "\u{001B}[?1000l\u{001B}[?1002l\u{001B}[?1003l\u{001B}[?1006l")
        feed(text: "\u{001B}[?1004l\u{001B}[?2004l\u{001B}[?2026l")
        feed(text: "\u{001B}[?1l\u{001B}>\u{001B}[?1049l\u{001B}[<17u\u{001B}[?25h")
    }

    @discardableResult
    func forceInterruptAndRecover() -> TerminalForceInterruptResult {
        guard process.running else { return .unavailable }
        cancelControlCRecovery()

        if let processSession = LocalTerminalProcessSession(rootPID: process.shellPid),
           let group = processSession.signalForegroundJob(SIGINT) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                if processSession.foregroundJobProcessGroup() == group {
                    _ = Darwin.kill(-group, SIGTERM)
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if processSession.foregroundJobProcessGroup() == group {
                    _ = Darwin.kill(-group, SIGKILL)
                    try? await Task.sleep(for: .milliseconds(100))
                }
                finishForcedInterruptRecovery(restoreTTYState: true)
            }
            return .signalledForegroundProcessGroup(group)
        }

        // Dedicated SSH sessions may expose the SSH client itself as the PTY root
        // process, so there is no child foreground group to signal safely. Send the
        // actual terminal interrupt bytes twice, then a newline, without fabricating
        // a prompt. The remote shell or reconnect state remains the source of truth.
        send(source: self, data: [0x03, 0x03, 0x0A][...])
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            self?.finishForcedInterruptRecovery(restoreTTYState: false)
        }
        return .sentControlC
    }

    private func finishForcedInterruptRecovery(restoreTTYState: Bool) {
        recoverTerminalModesAfterProcessExit()
        guard process.running else { return }
        if restoreTTYState {
            // A broken TUI may have left the PTY line discipline in raw/no-ISIG
            // mode. The explicit force-recovery action is allowed to normalize it,
            // but only after the foreground job has been released. Ctrl-U clears a
            // possible partial shell line; the real prompt remains shell-generated.
            let recovery = [UInt8(0x15)]
                + Array("stty sane >/dev/null 2>&1\n".utf8)
            send(source: self, data: recovery[...])
        } else {
            send(source: self, data: [0x0A][...])
        }
        requestFocusWhenReady()
    }

    private func terminateLocalProcessSessionIfSafe() {
        guard let processSession = LocalTerminalProcessSession(
            rootPID: process.shellPid
        ) else {
            return
        }

        processSession.signalAllProcessGroups(SIGHUP)
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(200))
            processSession.signalAllProcessGroups(SIGTERM)
            try? await Task.sleep(for: .milliseconds(800))
            processSession.signalAllProcessGroups(SIGKILL)
        }
    }

    func configureCommandCapture(
        sessionID: UUID,
        commandBlocksEnabled: Bool,
        onCommandCaptured: @escaping (CommandExecutionRecord) -> Void
    ) {
        commandSessionID = sessionID
        self.commandBlocksEnabled = commandBlocksEnabled
        self.onCommandCaptured = onCommandCaptured
    }

    func applyAppearance(_ appearance: TerminalAppearance) {
        nativeBackgroundColor = NSColor(
            calibratedRed: 0.035,
            green: 0.043,
            blue: 0.055,
            alpha: 1
        )
        nativeForegroundColor = appearance.outputNSColor
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enableMetalRendererWhenAttached()
        syncProcessWindowSize()
        setInteractionActive(interactionActive)
    }

    func enableMetalRendererWhenAttached() {
        guard window != nil, !isUsingMetalRenderer else { return }
        do {
            try setUseMetal(true)
        } catch {
            // CoreGraphics remains the fail-safe renderer if Metal is unavailable.
        }
    }

    func setInteractionActive(_ active: Bool) {
        interactionActive = active
        applyCursorStyle(forActiveState: active)
        needsDisplay = true
        layer?.setNeedsDisplay()

        if active {
            requestFocusWhenReady()
        } else {
            cancelPendingFocusRequest()
            if window?.firstResponder === self {
                window?.makeFirstResponder(nil)
            }
        }
    }

    private func applyCursorStyle(forActiveState active: Bool) {
        let current = terminalStateSnapshot().cursorStyle
        let parameter: Int
        switch current {
        case .blinkBlock, .steadyBlock:
            parameter = active ? 1 : 2
        case .blinkUnderline, .steadyUnderline:
            parameter = active ? 3 : 4
        case .blinkBar, .steadyBar:
            parameter = active ? 5 : 6
        }
        feed(text: "\u{001B}[\(parameter) q")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleFinalPTYResizeSync()
    }

    private func scheduleFinalPTYResizeSync() {
        resizeSyncTask?.cancel()
        resizeSyncTask = Task { @MainActor [weak self] in
            // SwiftTerm updates rows/cols synchronously in setFrameSize. A final
            // coalesced ioctl after AppKit/SwiftUI live-resize settles prevents the
            // PTY from being left at an intermediate winsize during rapid resizing.
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled, let self, process.running else { return }
            resizeSyncTask = nil
            syncProcessWindowSize()
            needsDisplay = true
            layer?.setNeedsDisplay()
        }
    }

    private func forceApexSelection(for event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        cancelPendingFocusRequest()
        window?.makeFirstResponder(self)

        let forceSelection = forceApexSelection(for: event)
        let previousMouseReporting = allowMouseReporting
        if forceSelection {
            // SwiftTerm normally lets Shift bypass TUI mouse reporting, but a TUI
            // can claim Shift via XTSHIFTESCAPE. ApexTerm reserves Shift-drag as a
            // reliable local selection escape hatch without changing TUI mouse mode.
            allowMouseReporting = false
        }
        defer {
            if forceSelection {
                allowMouseReporting = previousMouseReporting
            }
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let forceSelection = forceApexSelection(for: event)
        let previousMouseReporting = allowMouseReporting
        if forceSelection {
            allowMouseReporting = false
        }
        defer {
            if forceSelection {
                allowMouseReporting = previousMouseReporting
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let forceSelection = forceApexSelection(for: event)
        let previousMouseReporting = allowMouseReporting
        if forceSelection {
            allowMouseReporting = false
        }
        defer {
            if forceSelection {
                allowMouseReporting = previousMouseReporting
            }
        }
        super.mouseUp(with: event)
    }

    func handleApexKeyDown(_ event: NSEvent) {
        if localControlCRecoveryEnabled, isControlC(event) {
            armControlCRecovery()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let output = currentOutputText
        if !output.isEmpty {
            ClipboardWriter.copy(output)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func paste(_ sender: Any) {
        guard smartPasteProtectionEnabled,
              let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty else {
            super.paste(sender)
            return
        }

        let policy = SmartPastePolicy()
        let assessment = policy.assess(
            text,
            confirmMultiline: multilinePasteConfirmationEnabled
        )
        guard assessment.requiresConfirmation else {
            super.paste(sender)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = assessment.riskDecision.level == .requireApproval
            ? .critical
            : .warning
        alert.messageText = assessment.riskDecision.level == .requireApproval
            ? "危険な可能性がある貼り付け"
            : "貼り付け内容を確認"
        let reason = assessment.reason.map { $0 + "\n\n" } ?? ""
        alert.informativeText = reason + policy.preview(text)
        alert.addButton(withTitle: "確認して貼り付け")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        sendApprovedPaste(text)
    }

    private func sendApprovedPaste(_ text: String) {
        unmarkText()
        // SwiftTerm owns bracketed-paste framing behind its concurrency boundary.
        // Do not substitute clipboard contents that changed after user approval.
        guard NSPasteboard.general.string(forType: .string) == text else { return }
        super.paste(self)
    }

    /// Next-generation SwiftTerm owns mouse reporting, alternate-scroll mode,
    /// precise trackpad accumulation, and normal scrollback routing.
    func handleApexScrollWheel(_ event: NSEvent) {
        super.scrollWheel(with: event)
    }

    func requestFocusWhenReady() {
        cancelPendingFocusRequest()
        focusTask = Task { @MainActor [weak self] in
            for _ in 0..<10 {
                guard !Task.isCancelled, let self else { return }
                if let window, superview != nil, !isHidden {
                    window.makeFirstResponder(self)
                    focusTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            self?.focusTask = nil
        }
    }

    func cancelPendingFocusRequest() {
        focusTask?.cancel()
        focusTask = nil
    }

    func configureInputProbe() {
        let environment = ProcessInfo.processInfo.environment
        inputProbeFile = environment["APEXTERM_INPUT_PROBE_FILE"]
        inputProbeMarker = environment["APEXTERM_INPUT_PROBE_MARKER"]
        programmaticInputProbeFile = environment["APEXTERM_PROGRAMMATIC_INPUT_PROBE_FILE"]
        programmaticInputProbeMarker = environment["APEXTERM_PROGRAMMATIC_INPUT_PROBE_MARKER"]
        scrollProbeFile = environment["APEXTERM_SCROLL_PROBE_FILE"]
        scrollProbeMarker = environment["APEXTERM_SCROLL_PROBE_MARKER"]
            ?? "APT_SCROLL_PROBE_DONE"
        outputPipeline.configureProbeMarkers(
            input: inputProbeMarker,
            programmaticInput: programmaticInputProbeMarker
        )
    }

    func startInputProbeWhenReady() {
        if let marker = inputProbeMarker, !marker.isEmpty {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, process.running else { return }
                requestFocusWhenReady()
                let command = "printf '\(marker)\\n'\n"
                let bytes = Array(command.utf8)
                send(source: self, data: bytes[...])
            }
        }

        if let marker = programmaticInputProbeMarker,
           !marker.isEmpty,
           let sessionID = commandSessionID {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                NotificationCenter.default.post(
                    name: .apexTermInputRequested,
                    object: TerminalInputRequest(
                        sessionID: sessionID,
                        text: "printf '\(marker)\\n'",
                        execute: true
                    )
                )
            }
        }

        if scrollProbeFile != nil,
           let marker = scrollProbeMarker,
           !marker.isEmpty {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1_100))
                guard let self, process.running else { return }
                requestFocusWhenReady()
                let command = "for i in {1..160}; do printf 'APT_SCROLL_PROBE_%03d\\n' $i; done; printf '\(marker)\\n'\n"
                let bytes = Array(command.utf8)
                send(source: self, data: bytes[...])
            }
        }
    }

    func removeFindObserver() {
        if let findObserver {
            NotificationCenter.default.removeObserver(findObserver)
            self.findObserver = nil
        }
    }

    func removeInputObserver() {
        if let inputObserver {
            NotificationCenter.default.removeObserver(inputObserver)
            self.inputObserver = nil
        }
    }

    private func handleOutputSignals(_ signals: ApexTerminalOutputSignals) {
        if signals.controlCEcho {
            inspectControlCEcho()
        }
        if signals.inputProbe {
            inspectInputProbe()
        }
        if signals.programmaticInputProbe {
            inspectProgrammaticInputProbe()
        }
        for event in signals.semanticEvents {
            handleSemanticEvent(event)
        }
        for completed in signals.completedCommands {
            handleCompletedCommand(completed)
        }
    }

    private func enforceInactiveCursorStyle() {
        guard !interactionActive else { return }
        applyCursorStyle(forActiveState: false)
    }

    func handleSemanticEvent(_ event: ShellSemanticEvent) {
        onSemanticEvent?(event)
        switch event {
        case .promptStarted:
            cancelControlCRecovery()
            promptReadinessTask?.cancel()
            promptReadinessTask = nil
            clearResidualKittyKeyboardModeAtPrompt()
            reportPromptReadiness(true)
        case .commandInputStarted:
            promptReadinessTask?.cancel()
            promptReadinessTask = nil
            let state = terminalStateSnapshot()
            let absoluteRow = state.viewportRow + state.cursor.row
            onPromptStarted?(absoluteRow)
            reportPromptReadiness(true)
        case let .commandCaptured(command):
            reportPromptReadiness(false)
            capturedCommand = command
            capturedOutput.removeAll(keepingCapacity: true)
            commandStartedAt = Date()
            outputWasTruncated = false
            notifyCaptureStateChanged()
        case .commandExecuted:
            reportPromptReadiness(false)
            isCapturingOutput = true
            notifyCaptureStateChanged()
        case .commandFinished:
            reportPromptReadiness(false)
            isCapturingOutput = false
            notifyCaptureStateChanged()
        }
    }

    private func handleCompletedCommand(_ completed: ApexTerminalCompletedCommand) {
        capturedCommand = completed.command
        capturedOutput = completed.output
        commandStartedAt = completed.startedAt
        outputWasTruncated = completed.outputWasTruncated
        isCapturingOutput = false
        finalizeCapturedCommand(exitCode: completed.exitCode)
    }

    private func schedulePromptReadinessInspection() {
        promptReadinessTask?.cancel()
        promptReadinessTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, let self, process.running else { return }
            promptReadinessTask = nil
            reportPromptReadiness(promptReadySnapshot)
        }
    }

    private func reportPromptReadiness(_ ready: Bool) {
        guard ready != lastReportedPromptReadiness else { return }
        lastReportedPromptReadiness = ready
        DispatchQueue.main.async { [weak self] in
            self?.onPromptReadinessChanged?(ready)
        }
    }

    private func clearResidualKittyKeyboardModeAtPrompt() {
        // The mode stack is intentionally bounded to 16 entries. Popping 17 times
        // is idempotent at a real shell prompt and avoids reaching into mutable
        // SwiftTerm parser state merely to decide whether recovery is necessary.
        feed(text: "\u{001B}[<17u")
    }

    func setLocalControlCRecoveryEnabled(_ enabled: Bool) {
        localControlCRecoveryEnabled = enabled
        if !enabled {
            cancelControlCRecovery()
        }
    }

    private func isControlC(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.control),
              !modifiers.contains(.command),
              !modifiers.contains(.option) else {
            return false
        }
        return event.charactersIgnoringModifiers?.lowercased() == "c"
    }

    private func armControlCRecovery() {
        outputPipeline.setObservesControlCEcho(true)
        let now = Date()
        let repeated = lastControlCAt.map { now.timeIntervalSince($0) < 1.5 } ?? false
        lastControlCAt = now
        controlCRecoveryArmedUntil = now.addingTimeInterval(1.5)
        controlCRecoveryAllowsAlternateScreen = repeated
        controlCRecoveryTask?.cancel()
        controlCRecoveryTask = nil

        // The first Control-C always respects an alternate-screen TUI's ownership.
        // A repeated Control-C is an explicit recovery gesture: if the foreground
        // job is still alive, signal only that job's process group, never the shell.
        scheduleControlCRecovery(after: repeated ? .milliseconds(120) : .milliseconds(250))
    }

    private func inspectControlCEcho() {
        guard localControlCRecoveryEnabled,
              let armedUntil = controlCRecoveryArmedUntil,
              Date() <= armedUntil else {
            return
        }
        scheduleControlCRecovery(after: .milliseconds(250))
    }

    private func scheduleControlCRecovery(after delay: Duration) {
        controlCRecoveryTask?.cancel()
        controlCRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            defer { cancelControlCRecovery() }
            guard localControlCRecoveryEnabled,
                  process.running,
                  (!isAlternateBufferActive || controlCRecoveryAllowsAlternateScreen),
                  let processSession = LocalTerminalProcessSession(rootPID: process.shellPid) else {
                return
            }
            _ = processSession.signalForegroundJob(SIGINT)
        }
    }

    private func cancelControlCRecovery() {
        controlCRecoveryTask?.cancel()
        controlCRecoveryTask = nil
        controlCRecoveryArmedUntil = nil
        controlCRecoveryAllowsAlternateScreen = false
        outputPipeline.setObservesControlCEcho(false)
    }

    private func finalizeCapturedCommand(exitCode: Int) {
        guard let sessionID = commandSessionID else {
            resetCapture()
            return
        }
        let command = currentCommandText
        let output = currentOutputText
        guard !command.isEmpty || !output.isEmpty else {
            resetCapture()
            return
        }

        let record = CommandExecutionRecord(
            sessionID: sessionID,
            command: command,
            output: output,
            exitCode: exitCode,
            startedAt: commandStartedAt ?? Date(),
            finishedAt: Date()
        )
        let callback = onCommandCaptured
        DispatchQueue.main.async {
            callback?(record)
        }
        runScrollProbeIfNeeded(record)
        resetCapture()
    }

    private func runScrollProbeIfNeeded(_ record: CommandExecutionRecord) {
        guard let path = scrollProbeFile,
              let marker = scrollProbeMarker,
              record.command.contains(marker) else {
            return
        }
        scrollProbeFile = nil

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(4_000))
            guard let self else { return }

            let scrollPositionBefore = scrollPosition
            let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: 12,
                wheel2: 0,
                wheel3: 0
            ).flatMap(NSEvent.init(cgEvent:))
            if let event {
                handleApexScrollWheel(event)
            }

            try? await Task.sleep(for: .milliseconds(350))
            let scrollPositionAfter = scrollPosition
            let payload = [
                "command_captured=1",
                "output_captured=\(record.output.contains(marker) ? 1 : 0)",
                "scroll_event_sent=\(event == nil ? 0 : 1)",
                "scrollback_changed=\(scrollPositionBefore != scrollPositionAfter ? 1 : 0)",
                "scroll_position_before=\(scrollPositionBefore)",
                "scroll_position_after=\(scrollPositionAfter)"
            ].joined(separator: "\n") + "\n"
            try? Data(payload.utf8).write(
                to: URL(fileURLWithPath: path),
                options: [.atomic]
            )
        }
    }

    private func resetCapture() {
        capturedCommand = ""
        capturedOutput.removeAll(keepingCapacity: true)
        commandStartedAt = nil
        isCapturingOutput = false
        outputWasTruncated = false
        notifyCaptureStateChanged()
    }

    private func notifyCaptureStateChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.onCaptureStateChanged?()
        }
    }

    private func inspectProgrammaticInputProbe() {
        guard let path = programmaticInputProbeFile else { return }
        let payload = "programmatic_input=1\nprocess=\(process.running ? 1 : 0)\n"
        try? Data(payload.utf8).write(
            to: URL(fileURLWithPath: path),
            options: [.atomic]
        )
        programmaticInputProbeMarker = nil
    }

    private func inspectInputProbe() {
        guard let inputProbeFile else { return }
        let focus = window?.firstResponder === self ? 1 : 0
        let payload = "input=1\nfocus=\(focus)\nprocess=\(process.running ? 1 : 0)\n"
        try? Data(payload.utf8).write(
            to: URL(fileURLWithPath: inputProbeFile),
            options: [.atomic]
        )
        inputProbeMarker = nil
    }
}

struct TerminalSessionSnapshot: Equatable {
    let id: UUID
    let kind: SessionKind
    let workingDirectory: String?
    let appearance: TerminalAppearance
    let remoteProfile: SSHHostProfile?
    let fontSize: Double
    let commandBlocksEnabled: Bool
    let smartPasteProtectionEnabled: Bool
    let multilinePasteConfirmationEnabled: Bool

    var escapeSequenceTrustPolicy: TerminalEscapeSequenceTrustPolicy {
        switch kind {
        case .local, .localTmux:
            return .localDefault
        case .ssh, .tmux:
            return .remoteDefault
        }
    }

    var inlineImageSafetyPolicy: TerminalInlineImageSafetyPolicy {
        switch kind {
        case .local, .localTmux:
            return .localDefault
        case .ssh, .tmux:
            return .remoteDefault
        }
    }

    var terminationScope: TerminalProcessTerminationScope {
        switch kind {
        case .local:
            return .processGroup
        case .localTmux, .ssh, .tmux:
            return .processOnly
        }
    }

    var isRemote: Bool {
        switch kind {
        case .local, .localTmux:
            false
        case .ssh, .tmux:
            true
        }
    }

    var supportsReconnect: Bool {
        switch kind {
        case .local:
            return false
        case .localTmux:
            return LocalToolDiscovery.firstExecutable(named: "tmux") != nil
        case .ssh, .tmux:
            return true
        }
    }

    var accessibilityLabel: String {
        switch kind {
        case .local:
            "Local shell"
        case let .localTmux(session):
            "Local tmux session \(session)"
        case let .ssh(host):
            "SSH host \(host)"
        case let .tmux(host, session):
            "tmux session \(session) on \(host)"
        }
    }

    var environment: [String]? {
        switch kind {
        case .local, .localTmux:
            return serializedEnvironment(localEnvironmentDictionary)
        case .ssh, .tmux:
            return serializedEnvironment(inheritedTerminalEnvironmentDictionary())
        }
    }

    private var localEnvironmentDictionary: [String: String] {
        let wrapperDirectory = ApexTermPaths.shellIntegrationDirectory()
        var base = ProcessInfo.processInfo.environment
        base["APEXTERM_INPUT_ANSI"] = appearance.inputANSI
        base["APEXTERM_OUTPUT_ANSI"] = appearance.outputANSI
        do {
            try ShellIntegrationInstaller.prepare(at: wrapperDirectory)
            return ShellIntegrationInstaller.environmentDictionary(
                wrapperDirectory: wrapperDirectory,
                base: base
            )
        } catch {
            return inheritedTerminalEnvironmentDictionary(base: base)
        }
    }

    private var tmuxShellEnvironment: [String: String] {
        let environment = localEnvironmentDictionary
        let allowedKeys = [
            "APEXTERM_INPUT_ANSI",
            "APEXTERM_ORIGINAL_ZDOTDIR",
            "APEXTERM_OUTPUT_ANSI",
            "APEXTERM_SHELL_INTEGRATION",
            "COLORTERM",
            "LANG",
            "TERM",
            "TERM_PROGRAM",
            "TERM_PROGRAM_VERSION",
            "ZDOTDIR"
        ]
        return Dictionary(
            uniqueKeysWithValues: allowedKeys.compactMap { key in
                environment[key].map { (key, $0) }
            }
        )
    }

    private static let localTmuxCapabilities: TmuxCapabilities = {
        guard let executable = LocalToolDiscovery.firstExecutable(named: "tmux") else {
            return .modernFallback
        }
        return TmuxRuntimeProbe.capabilities(executable: executable) ?? .modernFallback
    }()

    private var tmuxConfigurationPath: String {
        let wrapperDirectory = ApexTermPaths.shellIntegrationDirectory()
        guard (try? ShellIntegrationInstaller.prepare(
            at: wrapperDirectory,
            tmuxCapabilities: Self.localTmuxCapabilities
        )) != nil else {
            return "/dev/null"
        }
        return ShellIntegrationInstaller.tmuxConfigurationURL(at: wrapperDirectory).path
    }

    private func inheritedTerminalEnvironmentDictionary(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "ApexTerm"
        environment["TERM_PROGRAM_VERSION"] = "0.1.0"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment
    }

    private func serializedEnvironment(_ environment: [String: String]) -> [String] {
        environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
    }

    var launchPlan: ProcessLaunchPlan {
        switch kind {
        case .local:
            let environment = ProcessInfo.processInfo.environment
            return LocalSessionLaunchPlanBuilder(
                tmuxExecutable: nil,
                shellExecutable: environment["SHELL"] ?? "/bin/zsh"
            ).build(
                sessionID: id,
                workingDirectory: workingDirectory
            )
        case let .localTmux(session):
            let environment = ProcessInfo.processInfo.environment
            return LocalSessionLaunchPlanBuilder(
                tmuxExecutable: LocalToolDiscovery.firstExecutable(named: "tmux"),
                shellExecutable: environment["SHELL"] ?? "/bin/zsh",
                tmuxServerName: ApexTermPaths.tmuxServerName(environment: environment),
                tmuxConfigurationPath: tmuxConfigurationPath
            ).build(
                sessionID: id,
                workingDirectory: workingDirectory,
                explicitSessionName: session,
                tmuxEnvironment: tmuxShellEnvironment
            )
        case let .ssh(host):
            return RemoteLaunchPlanBuilder.ssh(
                profile: remoteProfile ?? SSHHostProfile(alias: host),
                executable: sshExecutable
            )
        case let .tmux(host, session):
            return RemoteLaunchPlanBuilder.tmuxAttach(
                profile: remoteProfile ?? SSHHostProfile(alias: host),
                sessionName: session,
                executable: sshExecutable
            )
        }
    }

    private var sshExecutable: String {
        let override = ProcessInfo.processInfo.environment["APEXTERM_SSH_EXECUTABLE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return override.flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin/ssh"
    }
}
