import ApexTermCore
import Darwin
import Foundation

struct ApexTerminalCompletedCommand: Sendable {
    let command: String
    let output: [UInt8]
    let exitCode: Int
    let startedAt: Date
    let outputWasTruncated: Bool
}

struct ApexTerminalOutputSignals: Sendable {
    var controlCEcho = false
    var inputProbe = false
    var programmaticInputProbe = false
    var semanticEvents: [ShellSemanticEvent] = []
    var completedCommands: [ApexTerminalCompletedCommand] = []
}

/// Owns the raw PTY trust and shell-integration boundary before bytes enter
/// SwiftTerm's parser.
///
/// `LocalProcess` direct delivery invokes this object on its IO parse thread.
/// Keeping all state behind one lock preserves ApexTerm's OSC 52 / iTerm2 /
/// Kitty / Sixel policy, while the lightweight OSC 133 parser identifies shell
/// lifecycle boundaries without running a second terminal parser. Filtered bytes
/// still flow directly into next-generation SwiftTerm's render-owner parser.
final class ApexTerminalOutputPipeline: @unchecked Sendable {
    private static let maximumCapturedOutputBytes = 2 * 1_024 * 1_024

    private struct State {
        var trustFilter = TerminalEscapeSequenceTrustFilter(policy: .localDefault)
        var inlineImageFilter = TerminalInlineImageSafetyFilter(policy: .localDefault)
        var kittyGraphicsFilter = TerminalKittyGraphicsSafetyFilter(policy: .localDefault)
        var sixelFilter = TerminalSixelSafetyFilter()
        var shellParser = ShellIntegrationStreamParser()
        var windowSize = winsize(
            ws_row: 25,
            ws_col: 80,
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        var inputProbeMarker: [UInt8]?
        var programmaticInputProbeMarker: [UInt8]?
        var observesControlCEcho = false
        var promptInspectionScheduled = false

        var capturedCommand = ""
        var capturedOutput: [UInt8] = []
        var commandStartedAt: Date?
        var isCapturingOutput = false
        var outputWasTruncated = false
    }

    private let lock = NSLock()
    private var state = State()

    func updateTrustPolicy(_ policy: TerminalEscapeSequenceTrustPolicy) {
        lock.lock()
        state.trustFilter.updatePolicy(policy)
        lock.unlock()
    }

    func updateInlineImagePolicy(_ policy: TerminalInlineImageSafetyPolicy) {
        lock.lock()
        state.inlineImageFilter.updatePolicy(policy)
        state.kittyGraphicsFilter.updatePolicy(policy)
        lock.unlock()
    }

    func resetStreamState() {
        lock.lock()
        state.trustFilter.resetStreamState()
        state.inlineImageFilter.resetStreamState()
        state.kittyGraphicsFilter.resetStreamState()
        state.sixelFilter.resetStreamState()
        state.shellParser = ShellIntegrationStreamParser()
        resetCommandCapture(&state)
        lock.unlock()
    }

    func updateWindowSize(_ size: winsize) {
        lock.lock()
        state.windowSize = size
        lock.unlock()
    }

    func windowSize() -> winsize {
        lock.lock()
        defer { lock.unlock() }
        return state.windowSize
    }

    func configureProbeMarkers(input: String?, programmaticInput: String?) {
        lock.lock()
        state.inputProbeMarker = input.map { Array($0.utf8) }
        state.programmaticInputProbeMarker = programmaticInput.map { Array($0.utf8) }
        lock.unlock()
    }

    func setObservesControlCEcho(_ enabled: Bool) {
        lock.lock()
        state.observesControlCEcho = enabled
        lock.unlock()
    }

    func claimPromptInspection() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !state.promptInspectionScheduled else { return false }
        state.promptInspectionScheduled = true
        return true
    }

    func completePromptInspection() {
        lock.lock()
        state.promptInspectionScheduled = false
        lock.unlock()
    }

    func process(_ bytes: ArraySlice<UInt8>) -> (bytes: [UInt8], signals: ApexTerminalOutputSignals) {
        lock.lock()
        defer { lock.unlock() }

        let clipboardFiltered = state.trustFilter.feed(bytes)
        guard !clipboardFiltered.isEmpty else { return ([], ApexTerminalOutputSignals()) }

        let imageFiltered = state.inlineImageFilter.feed(clipboardFiltered[...])
        guard !imageFiltered.isEmpty else { return ([], ApexTerminalOutputSignals()) }

        let kittyFiltered = state.kittyGraphicsFilter.feed(imageFiltered[...])
        guard !kittyFiltered.isEmpty else { return ([], ApexTerminalOutputSignals()) }

        let filtered = state.sixelFilter.feed(kittyFiltered[...])
        guard !filtered.isEmpty else { return ([], ApexTerminalOutputSignals()) }

        var signals = ApexTerminalOutputSignals()
        inspectShellIntegration(filtered, state: &state, signals: &signals)

        if state.observesControlCEcho,
           Self.contains(filtered, needle: [0x5E, 0x43]) {
            signals.controlCEcho = true
        }
        if let marker = state.inputProbeMarker,
           Self.contains(filtered, needle: marker) {
            signals.inputProbe = true
            state.inputProbeMarker = nil
        }
        if let marker = state.programmaticInputProbeMarker,
           Self.contains(filtered, needle: marker) {
            signals.programmaticInputProbe = true
            state.programmaticInputProbeMarker = nil
        }
        return (filtered, signals)
    }

    private func inspectShellIntegration(
        _ bytes: [UInt8],
        state: inout State,
        signals: inout ApexTerminalOutputSignals
    ) {
        if state.shellParser.canBypass(bytes[...]) {
            appendCapturedOutput(bytes[...], state: &state)
            return
        }

        let segments = state.shellParser.feed(bytes[...])
        for segment in segments {
            switch segment {
            case let .data(data):
                appendCapturedOutput(data[...], state: &state)
            case let .marker(_, event):
                guard let event else { continue }
                signals.semanticEvents.append(event)
                apply(event, state: &state, signals: &signals)
            }
        }
    }

    private func apply(
        _ event: ShellSemanticEvent,
        state: inout State,
        signals: inout ApexTerminalOutputSignals
    ) {
        switch event {
        case .promptStarted, .commandInputStarted:
            break
        case let .commandCaptured(command):
            state.capturedCommand = command
            state.capturedOutput.removeAll(keepingCapacity: true)
            state.commandStartedAt = Date()
            state.isCapturingOutput = false
            state.outputWasTruncated = false
        case .commandExecuted:
            state.isCapturingOutput = true
        case let .commandFinished(exitCode):
            state.isCapturingOutput = false
            let command = state.capturedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !command.isEmpty || !state.capturedOutput.isEmpty {
                signals.completedCommands.append(
                    ApexTerminalCompletedCommand(
                        command: command,
                        output: state.capturedOutput,
                        exitCode: exitCode ?? 0,
                        startedAt: state.commandStartedAt ?? Date(),
                        outputWasTruncated: state.outputWasTruncated
                    )
                )
            }
            resetCommandCapture(&state)
        }
    }

    private func appendCapturedOutput(_ bytes: ArraySlice<UInt8>, state: inout State) {
        guard state.isCapturingOutput, !bytes.isEmpty else { return }
        let remaining = Self.maximumCapturedOutputBytes - state.capturedOutput.count
        guard remaining > 0 else {
            state.outputWasTruncated = true
            return
        }
        state.capturedOutput.append(contentsOf: bytes.prefix(remaining))
        if bytes.count > remaining {
            state.outputWasTruncated = true
        }
    }

    private func resetCommandCapture(_ state: inout State) {
        state.capturedCommand = ""
        state.capturedOutput.removeAll(keepingCapacity: true)
        state.commandStartedAt = nil
        state.isCapturingOutput = false
        state.outputWasTruncated = false
    }

    private static func contains(_ bytes: [UInt8], needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, needle.count <= bytes.count else { return false }
        let lastStart = bytes.count - needle.count
        for start in 0...lastStart {
            if bytes[start..<(start + needle.count)].elementsEqual(needle) {
                return true
            }
        }
        return false
    }
}
