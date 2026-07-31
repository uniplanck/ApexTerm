import ApexTermCore
import AppKit
import Darwin
import SwiftTerm
import SwiftUI

@MainActor
struct TerminalPaneView: NSViewRepresentable {
    let session: TerminalSessionSnapshot
    let onTitleChange: (String) -> Void
    let onDirectoryChange: (String?) -> Void
    let onStateChange: (SessionState) -> Void
    let onSemanticEvents: ([ShellSemanticEvent]) -> Void
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
        let container = ApexTerminalContainerView(terminal: terminal)
        terminal.processDelegate = context.coordinator
        terminal.configureFindObserver(sessionID: session.id)
        terminal.configureInputObserver(sessionID: session.id)
        terminal.onCaptureStateChanged = { [weak container] in
            container?.refreshActionButton()
        }
        terminal.onHostData = { [weak coordinator = context.coordinator] bytes in
            coordinator?.consumeHostData(bytes)
        }
        terminal.font = NSFont.monospacedSystemFont(
            ofSize: CGFloat(session.fontSize),
            weight: .regular
        )
        terminal.setAccessibilityLabel("Terminal: \(session.accessibilityLabel)")
        terminal.setAccessibilityHelp(
            "Interactive terminal session. Scroll moves through output; use Command-F to search."
        )

        do {
            try terminal.setUseMetal(true)
        } catch {
            // The CoreGraphics renderer remains available when Metal setup fails.
        }

        context.coordinator.configure(terminal: terminal, session: session)
        store.register(
            sessionID: session.id,
            coordinator: context.coordinator,
            container: container
        )
        configure(container: container, coordinator: context.coordinator)
        terminal.configureInputProbe()
        let sessionID = session.id
        let isUsingMetal = terminal.isUsingMetalRenderer
        Task { @MainActor [weak coordinator = context.coordinator, weak container] in
            guard let coordinator, let container else { return }
            coordinator.startProcess()
            store.noteProcessStarted(sessionID: sessionID, container: container)
            container.terminal.startInputProbeWhenReady()
            container.restoreVisiblePromptDecorationsWhenReady()
            writeSmokeReadyMarker(isUsingMetal: isUsingMetal)
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
        terminal.commandBlocksEnabled = session.commandBlocksEnabled
        terminal.smartPasteProtectionEnabled = session.smartPasteProtectionEnabled
        terminal.multilinePasteConfirmationEnabled = session.multilinePasteConfirmationEnabled
        terminal.onActivate = onActivate
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

    private func writeSmokeReadyMarker(isUsingMetal: Bool) {
        guard let path = ProcessInfo.processInfo.environment["APEXTERM_READY_FILE"],
              !path.isEmpty else {
            return
        }
        let payload = "ready=1\nmetal=\(isUsingMetal ? 1 : 0)\n"
        try? Data(payload.utf8).write(
            to: URL(fileURLWithPath: path),
            options: [.atomic]
        )
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        let onTitleChange: (String) -> Void
        let onDirectoryChange: (String?) -> Void
        let onStateChange: (SessionState) -> Void
        let onSemanticEvents: ([ShellSemanticEvent]) -> Void

        private let parserLock = NSLock()
        private var shellParser = ShellIntegrationParser()
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
                terminal.terminate()
            }

            onStateChange(reconnectAttempt == 0 ? .starting : .reconnecting)
            let launch = session.launchPlan
            terminal.startProcess(
                executable: launch.executable,
                args: launch.arguments,
                environment: session.environment,
                currentDirectory: session.workingDirectory
            )

            if terminal.process.running {
                onStateChange(.attached)
                scheduleStabilityReset()
                scheduleHealthMonitor()
            } else if session.supportsReconnect {
                scheduleReconnect()
            } else {
                onStateChange(.failed)
            }
        }

        func prepareForShutdown() {
            isShuttingDown = true
            reconnectTask?.cancel()
            stabilityTask?.cancel()
            healthTask?.cancel()
            reconnectTask = nil
            stabilityTask = nil
            healthTask = nil
        }

        func consumeHostData(_ bytes: ArraySlice<UInt8>) {
            parserLock.lock()
            let events = shellParser.feed(bytes)
            parserLock.unlock()
            guard !events.isEmpty else { return }
            onSemanticEvents(events)
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            onTitleChange(title)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            onDirectoryChange(directory)
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            stabilityTask?.cancel()
            stabilityTask = nil
            let childPID = (source as? ApexLocalProcessTerminalView)?.process.shellPid ?? 0
            scheduleChildReap(childPID)

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
                onStateChange(exitCode == nil ? .failed : .exited)
            }
        }

        private func scheduleReconnect() {
            guard !isShuttingDown, reconnectTask == nil else { return }
            reconnectAttempt += 1
            guard let delay = reconnectPolicy.delaySeconds(
                forAttempt: reconnectAttempt
            ) else {
                onStateChange(.failed)
                return
            }

            onStateChange(.reconnecting)
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
                onStateChange(.attached)
            }
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

    func isProcessRunning(sessionID: UUID) -> Bool {
        containers[sessionID]?.terminal.process.running == true
    }

    func noteProcessStarted(sessionID: UUID, container: ApexTerminalContainerView) {
        record(
            "process:\(sessionID.uuidString):pid=\(container.terminal.process.shellPid)"
        )
    }

    func noteReuse(sessionID: UUID, container: ApexTerminalContainerView) {
        let bufferPreserved: Int
        if let probeMarker, !probeMarker.isEmpty {
            let data = container.terminal.terminal.getBufferAsData(kind: .active)
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
        container?.terminal.onHostData = nil
        container?.terminal.onCommandCaptured = nil
        container?.terminal.onCaptureStateChanged = nil
        container?.terminal.processDelegate = nil
        container?.terminal.terminate()
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
    private var visibilityObservers: [NSObjectProtocol] = []
    private let promptProbePath = ProcessInfo.processInfo.environment[
        "APEXTERM_PROMPT_DECORATION_PROBE_FILE"
    ]
    private let promptRestoreProbePath = ProcessInfo.processInfo.environment[
        "APEXTERM_PROMPT_RESTORE_PROBE_FILE"
    ]
    private var promptProbeWritten = false

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

        terminal.onPromptStarted = { [weak self] row in
            self?.addPromptDecoration(row: row)
        }
        terminal.onTerminalRowsShifted = { [weak self] count in
            self?.shiftPromptDecorations(upBy: count)
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
            terminal.requestFocusWhenReady()
        }
    }

    func prepareForPresentation() {
        installScrollMonitor()
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

                let data = terminal.terminal.getBufferAsData(kind: .active)
                let text = String(decoding: data, as: UTF8.self)
                let lines = text.split(
                    separator: "\n",
                    omittingEmptySubsequences: false
                )
                let firstVisibleRow = max(0, terminal.terminal.buffer.yDisp)
                let visibleRows = max(1, terminal.terminal.rows)
                var matchedRows: [Int] = []

                for row in 0..<visibleRows {
                    let lineIndex = firstVisibleRow + row
                    guard lines.indices.contains(lineIndex) else { continue }
                    if looksLikeShellPrompt(String(lines[lineIndex])) {
                        matchedRows.append(row)
                    }
                }

                guard let latestPromptRow = matchedRows.last else { continue }
                addPromptDecoration(row: latestPromptRow)
                if let promptRestoreProbePath,
                   !promptRestoreProbePath.isEmpty {
                    let result = [
                        "restored_prompt_count=1",
                        "restored_current_prompt=\(latestPromptRow == terminal.terminal.buffer.y ? 1 : 0)"
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
        terminal.onPromptStarted = nil
        terminal.onTerminalRowsShifted = nil
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

    private func shiftPromptDecorations(upBy count: Int) {
        guard count > 0 else { return }
        for decoration in promptDecorations {
            decoration.row -= count
        }
        let removed = promptDecorations.filter { $0.row < 0 }
        for decoration in removed {
            decoration.button.removeFromSuperview()
        }
        promptDecorations.removeAll { $0.row < 0 }
        needsLayout = true
        layoutPromptDecorations()
    }

    private func removeAllPromptDecorations() {
        for decoration in promptDecorations {
            decoration.button.removeFromSuperview()
        }
        promptDecorations.removeAll()
        selectedDecoration = nil
    }

    private func layoutPromptDecorations() {
        let rows = max(1, terminal.terminal.rows)
        let cellHeight = terminal.bounds.height / CGFloat(rows)
        guard cellHeight.isFinite, cellHeight > 0 else { return }

        let isAtLiveBottom = !terminal.canScroll || terminal.scrollPosition >= 0.999
        for decoration in promptDecorations {
            let visible = decoration.row >= 0 && decoration.row < rows && isAtLiveBottom
            decoration.button.isHidden = !terminal.commandBlocksEnabled || !visible
            guard visible else { continue }
            let width: CGFloat = 18
            let height: CGFloat = 14
            let y = terminal.frame.maxY
                - CGFloat(decoration.row + 1) * cellHeight
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

final class ApexLocalProcessTerminalView: LocalProcessTerminalView {
    var onHostData: ((ArraySlice<UInt8>) -> Void)?
    var onCommandCaptured: ((CommandExecutionRecord) -> Void)?
    var onCaptureStateChanged: (() -> Void)?
    var onPromptStarted: ((Int) -> Void)?
    var onTerminalRowsShifted: ((Int) -> Void)?
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
    private var commandSessionID: UUID?
    private var streamParser = ShellIntegrationStreamParser()
    private var capturedCommand = ""
    private var capturedOutput: [UInt8] = []
    private var commandStartedAt: Date?
    private var isCapturingOutput = false
    private var outputWasTruncated = false
    private static let maximumCapturedOutputBytes = 2 * 1_024 * 1_024

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
                guard let self else { return }
                requestFocusWhenReady()
                var text = request.text
                if request.execute && !text.hasSuffix("\n") {
                    text += "\n"
                }
                insertText(
                    text,
                    replacementRange: NSRange(location: 0, length: 0)
                )
            }
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
        requestFocusWhenReady()
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        cancelPendingFocusRequest()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
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
        let bytes = TerminalPastePayload.bytes(
            for: text,
            bracketed: terminal.bracketedPasteMode
        )
        send(source: self, data: bytes[...])
    }

    /// SwiftTerm maps wheel events to Up/Down while an alternate buffer is active.
    /// tmux can keep that buffer active at a normal shell prompt, which accidentally
    /// walks shell history. Only mouse-aware TUIs retain wheel reporting; otherwise
    /// the wheel always moves the terminal viewport.
    func handleApexScrollWheel(_ event: NSEvent) {
        let verticalDelta = event.scrollingDeltaY != 0
            ? event.scrollingDeltaY
            : event.deltaY
        guard verticalDelta != 0 else { return }
        if terminal.isCurrentBufferAlternate, terminal.mouseMode != .off {
            super.scrollWheel(with: event)
            return
        }

        let delta = Int(abs(verticalDelta).rounded(.up))
        let lines: Int
        if delta > 9 {
            lines = max(terminal.rows, 20)
        } else if delta > 5 {
            lines = 10
        } else if delta > 1 {
            lines = 3
        } else {
            lines = 1
        }

        if verticalDelta > 0 {
            scrollUp(lines: lines)
        } else {
            scrollDown(lines: lines)
        }
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

    override func dataReceived(slice: ArraySlice<UInt8>) {
        onHostData?(slice)
        inspectInputProbe(slice)
        inspectProgrammaticInputProbe(slice)

        if streamParser.canBypass(slice) {
            processTerminalData(slice)
            return
        }

        let segments = streamParser.feed(slice)
        for segment in segments {
            switch segment {
            case let .data(bytes):
                processTerminalData(bytes[...])
            case let .marker(raw, event):
                super.dataReceived(slice: raw[...])
                if let event {
                    handleSemanticEvent(event)
                }
            }
        }
    }

    private func processTerminalData(_ bytes: ArraySlice<UInt8>) {
        appendCapturedOutput(bytes)
        let beforeRow = terminal.buffer.y
        var lineAdvances = 0
        for byte in bytes where byte == 0x0A {
            lineAdvances += 1
        }
        super.dataReceived(slice: bytes)
        let shiftedRows = max(0, beforeRow + lineAdvances - terminal.buffer.y)
        if shiftedRows > 0 {
            onTerminalRowsShifted?(shiftedRows)
        }
    }

    private func handleSemanticEvent(_ event: ShellSemanticEvent) {
        switch event {
        case .promptStarted:
            break
        case .commandInputStarted:
            onPromptStarted?(terminal.buffer.y)
        case let .commandCaptured(command):
            capturedCommand = command
            capturedOutput.removeAll(keepingCapacity: true)
            commandStartedAt = Date()
            outputWasTruncated = false
            notifyCaptureStateChanged()
        case .commandExecuted:
            isCapturingOutput = true
            notifyCaptureStateChanged()
        case let .commandFinished(exitCode):
            isCapturingOutput = false
            finalizeCapturedCommand(exitCode: exitCode ?? 0)
        }
    }

    private func appendCapturedOutput(_ bytes: ArraySlice<UInt8>) {
        guard isCapturingOutput, !bytes.isEmpty else { return }
        let remaining = Self.maximumCapturedOutputBytes - capturedOutput.count
        guard remaining > 0 else {
            outputWasTruncated = true
            return
        }
        capturedOutput.append(contentsOf: bytes.prefix(remaining))
        if bytes.count > remaining {
            outputWasTruncated = true
        }
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

            let mouseModeEnabled = terminal.mouseMode != .off
            let alternateBuffer = terminal.isCurrentBufferAlternate
            let scrollPositionBefore = terminal.buffer.yDisp
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
            let scrollPositionAfter = terminal.buffer.yDisp
            let payload = [
                "command_captured=1",
                "output_captured=\(record.output.contains(marker) ? 1 : 0)",
                "mouse_mode=\(mouseModeEnabled ? 1 : 0)",
                "alternate_buffer=\(alternateBuffer ? 1 : 0)",
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

    private func inspectProgrammaticInputProbe(_ slice: ArraySlice<UInt8>) {
        guard let marker = programmaticInputProbeMarker,
              let text = String(bytes: slice, encoding: .utf8),
              text.contains(marker),
              let path = programmaticInputProbeFile else { return }
        let payload = "programmatic_input=1\nprocess=\(process.running ? 1 : 0)\n"
        try? Data(payload.utf8).write(
            to: URL(fileURLWithPath: path),
            options: [.atomic]
        )
        programmaticInputProbeMarker = nil
    }

    private func inspectInputProbe(_ slice: ArraySlice<UInt8>) {
        if let marker = inputProbeMarker,
           let text = String(bytes: slice, encoding: .utf8),
           text.contains(marker),
           let inputProbeFile {
            let focus = window?.firstResponder === self ? 1 : 0
            let payload = "input=1\nfocus=\(focus)\nprocess=\(process.running ? 1 : 0)\n"
            try? Data(payload.utf8).write(
                to: URL(fileURLWithPath: inputProbeFile),
                options: [.atomic]
            )
            inputProbeMarker = nil
        }
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

    private var tmuxConfigurationPath: String {
        let wrapperDirectory = ApexTermPaths.shellIntegrationDirectory()
        guard (try? ShellIntegrationInstaller.prepare(at: wrapperDirectory)) != nil else {
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
