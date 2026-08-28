import ApexTermCore
import AppKit
import SwiftUI

struct TerminalConversationView: View {
    let records: [CommandExecutionRecord]
    let appearance: TerminalAppearance
    let fontSize: Double
    let collapsedLineLimit: Int
    let sendShortcut: ApexKeyChord?
    let statusText: String
    @Binding var draft: String
    let isReady: Bool
    let scheduledCommands: [ScheduledTerminalCommand]
    let onSend: () -> Void
    let onSchedule: (String, Date) -> Void
    let onCancelScheduled: (UUID) -> Void

    @State private var expandedCommandIDs: Set<UUID> = []
    @State private var expandedOutputIDs: Set<UUID> = []
    @State private var scheduleDate = Date().addingTimeInterval(60)
    @State private var isSchedulePopoverPresented = false

    private static let bottomAnchorID = "terminal-conversation-bottom-anchor"

    var body: some View {
        VStack(spacing: 0) {
            conversation
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            Divider()
                .opacity(0.45)

            composer
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(conversationBackground)
        .background {
            TerminalConversationProbeView(identifier: "terminal-conversation-mode-probe")
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("terminal-conversation-mode")
    }

    private var conversation: some View {
        GeometryReader { geometry in
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 20) {
                        if records.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(records.reversed())) { record in
                                conversationTurn(
                                    record,
                                    bubbleMaxWidth: adaptiveBubbleMaxWidth(
                                        for: geometry.size.width
                                    )
                                )
                                .id(record.id)
                            }
                        }

                        Color.clear
                            .frame(height: 26)
                            .id(Self.bottomAnchorID)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    .background {
                        TerminalConversationProbeView(identifier: "terminal-conversation-scroll-probe")
                            .allowsHitTesting(false)
                    }
                }
                .scrollDisabled(false)
                .contentShape(Rectangle())
                .background(conversationBackground)
                .accessibilityIdentifier("terminal-conversation-scroll")
                .onAppear {
                    scrollToLatest(reader)
                }
                .onChange(of: records.first?.id) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        scrollToLatest(reader)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 48, height: 48)
                Image(systemName: "terminal.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 4) {
                Text("C Mode")
                    .font(.system(size: 14, weight: .semibold))
                Text("入力は右、出力は左。シェルの文字列を見せずにコマンドを扱います。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }

    @ViewBuilder
    private func conversationTurn(
        _ record: CommandExecutionRecord,
        bubbleMaxWidth: CGFloat
    ) -> some View {
        VStack(spacing: 14) {
            if !record.command.isEmpty {
                HStack(alignment: .bottom, spacing: 10) {
                    Spacer(minLength: 18)
                    VStack(alignment: .trailing, spacing: 5) {
                        messageBubble(
                            text: record.command,
                            foreground: appearance.inputColor,
                            fill: appearance.inputColor.opacity(0.10),
                            stroke: appearance.inputColor.opacity(0.18),
                            isExpanded: expandedCommandIDs.contains(record.id),
                            alignment: .trailing,
                            maxWidth: bubbleMaxWidth,
                            accessibilityIdentifier: "terminal-conversation-command-\(record.id.uuidString)",
                            expansionIdentifier: "terminal-conversation-command-expand-\(record.id.uuidString)"
                        ) {
                            toggle(record.id, in: &expandedCommandIDs)
                        }

                        commandFooter(record)
                    }
                    .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
                }
            }

            if !record.output.isEmpty {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        messageBubble(
                            text: record.output,
                            foreground: appearance.outputColor,
                            fill: Color.primary.opacity(0.038),
                            stroke: Color.primary.opacity(0.08),
                            isExpanded: expandedOutputIDs.contains(record.id),
                            alignment: .leading,
                            maxWidth: bubbleMaxWidth,
                            accessibilityIdentifier: "terminal-conversation-output-\(record.id.uuidString)",
                            expansionIdentifier: "terminal-conversation-output-expand-\(record.id.uuidString)"
                        ) {
                            toggle(record.id, in: &expandedOutputIDs)
                        }

                        outputFooter(record)
                    }
                    .frame(maxWidth: bubbleMaxWidth, alignment: .leading)

                    Spacer(minLength: 18)
                }
            }
        }
    }

    private func messageBubble(
        text: String,
        foreground: Color,
        fill: Color,
        stroke: Color,
        isExpanded: Bool,
        alignment: Alignment,
        maxWidth: CGFloat,
        accessibilityIdentifier: String,
        expansionIdentifier: String,
        onToggle: @escaping () -> Void
    ) -> some View {
        VStack(
            alignment: alignment == .trailing ? .trailing : .leading,
            spacing: 7
        ) {
            Text(text)
                .font(.system(size: max(9, fontSize), design: .monospaced))
                .foregroundStyle(foreground)
                .lineSpacing(2)
                .lineLimit(isExpanded ? nil : boundedCollapsedLineLimit)
                .textSelection(.enabled)
                .frame(
                    maxWidth: usesIntrinsicBubbleWidth(text) ? nil : maxWidth,
                    alignment: alignment
                )
                .fixedSize(horizontal: usesIntrinsicBubbleWidth(text), vertical: false)
                .accessibilityIdentifier(accessibilityIdentifier)
                .background {
                    TerminalConversationProbeView(identifier: accessibilityIdentifier + "-probe")
                        .allowsHitTesting(false)
                }

            if shouldOfferExpansion(text) {
                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                        Text(isExpanded ? "折りたたむ" : "すべて表示")
                            .font(.caption2.weight(.medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.045), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(expansionIdentifier)
                .background {
                    TerminalConversationProbeView(identifier: expansionIdentifier + "-probe")
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        }
        .frame(maxWidth: maxWidth, alignment: alignment)
    }

    private func commandFooter(_ record: CommandExecutionRecord) -> some View {
        HStack(spacing: 5) {
            Spacer(minLength: 0)
            copyButton(
                systemImage: "doc.on.clipboard",
                help: "入力をコピー",
                accessibilityIdentifier: "terminal-conversation-copy-input-\(record.id.uuidString)"
            ) {
                ClipboardWriter.copy(record.command)
            }
        }
        .padding(.trailing, 3)
    }

    private func outputFooter(_ record: CommandExecutionRecord) -> some View {
        HStack(spacing: 5) {
            copyButton(
                systemImage: "doc.on.doc",
                help: "入力と出力をコピー",
                accessibilityIdentifier: "terminal-conversation-copy-both-\(record.id.uuidString)"
            ) {
                ClipboardWriter.copy(record.commandAndOutput)
            }

            copyButton(
                systemImage: "doc.on.clipboard",
                help: "出力のみコピー",
                accessibilityIdentifier: "terminal-conversation-copy-output-\(record.id.uuidString)"
            ) {
                ClipboardWriter.copy(record.output)
            }

            Divider()
                .frame(height: 11)
                .padding(.horizontal, 2)

            HStack(spacing: 4) {
                Circle()
                    .fill(record.exitCode == 0 ? Color.green : Color.red)
                    .frame(width: 5, height: 5)
                Text("exit \(record.exitCode)")
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            Text(record.finishedAt.formatted(.dateTime.hour().minute().second()))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 3)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !scheduledCommands.isEmpty {
                scheduledCommandStrip
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isReady ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isReady ? Color.secondary : Color.orange)
                }
                .accessibilityIdentifier("terminal-conversation-status")
                .background {
                    TerminalConversationProbeView(identifier: "terminal-conversation-status-probe")
                        .allowsHitTesting(false)
                }

                Spacer(minLength: 0)

                Text("\(sendShortcutDisplay) 送信")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)

            HStack(alignment: .bottom, spacing: 9) {
                TerminalConversationComposerView(
                    text: $draft,
                    fontSize: max(10, fontSize),
                    sendShortcut: sendShortcut,
                    canSend: canSend,
                    onSend: onSend
                )
                .frame(minHeight: 42, idealHeight: 48, maxHeight: 96)
                .background(
                    Color(nsColor: .textBackgroundColor).opacity(0.76),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            isReady
                                ? Color.primary.opacity(0.10)
                                : Color.orange.opacity(0.18),
                            lineWidth: 1
                        )
                }
                .accessibilityLabel("Terminal command")
                .accessibilityIdentifier("terminal-conversation-composer")
                .background {
                    TerminalConversationProbeView(identifier: "terminal-conversation-composer-probe")
                        .allowsHitTesting(false)
                }

                Button {
                    scheduleDate = max(Date().addingTimeInterval(60), scheduleDate)
                    isSchedulePopoverPresented = true
                } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(normalizedDraft.isEmpty)
                .help("時間を指定して送信")
                .accessibilityLabel("時間指定送信")
                .accessibilityIdentifier("terminal-conversation-schedule")
                .background {
                    TerminalConversationProbeView(identifier: "terminal-conversation-schedule-probe")
                        .allowsHitTesting(false)
                }
                .popover(isPresented: $isSchedulePopoverPresented, arrowEdge: .bottom) {
                    schedulePopover
                }

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : Color.secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            canSend ? Color.accentColor : Color.primary.opacity(0.06),
                            in: Circle()
                        )
                        .shadow(
                            color: canSend ? Color.accentColor.opacity(0.22) : Color.clear,
                            radius: 6,
                            y: 2
                        )
                }
                .buttonStyle(.plain)
                .apexKeyboardShortcut(sendShortcut)
                .disabled(!canSend)
                .help(sendHelp)
                .accessibilityLabel("コマンドを送信")
                .accessibilityValue(isReady ? "Ready" : statusText)
                .accessibilityIdentifier("terminal-conversation-send")
                .background {
                    TerminalConversationProbeView(identifier: "terminal-conversation-send-probe")
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var scheduledCommandStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(scheduledCommands) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.accentColor)
                        Text(item.scheduledAt.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption2.monospacedDigit())
                        Text(item.command.replacingOccurrences(of: "\n", with: " "))
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                            .frame(maxWidth: 180)
                        Button {
                            onCancelScheduled(item.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help("予約を取り消す")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.055), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                    .accessibilityIdentifier("scheduled-terminal-command-\(item.id.uuidString)")
                    .background {
                        TerminalConversationProbeView(
                            identifier: "scheduled-terminal-command-\(item.id.uuidString)-probe"
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxHeight: 32)
        .accessibilityIdentifier("scheduled-terminal-command-strip")
    }

    private var schedulePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(Color.accentColor)
                Text("時間指定送信")
                    .font(.headline)
            }

            Text(normalizedDraft)
                .font(.caption.monospaced())
                .lineLimit(3)
                .frame(maxWidth: 320, alignment: .leading)
                .padding(9)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))

            DatePicker(
                "送信時刻",
                selection: $scheduleDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)

            HStack {
                Spacer()
                Button("キャンセル") {
                    isSchedulePopoverPresented = false
                }
                Button("予約") {
                    let command = normalizedDraft
                    guard !command.isEmpty else { return }
                    onSchedule(command, scheduleDate)
                    draft = ""
                    isSchedulePopoverPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func copyButton(
        systemImage: String,
        help: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 22, height: 20)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(accessibilityIdentifier)
        .background {
            TerminalConversationProbeView(identifier: accessibilityIdentifier + "-probe")
                .allowsHitTesting(false)
        }
    }

    private var boundedCollapsedLineLimit: Int {
        min(max(collapsedLineLimit, 1), 8)
    }

    private func adaptiveBubbleMaxWidth(for containerWidth: CGFloat) -> CGFloat {
        let usableWidth = max(260, containerWidth - 28)
        return min(1_080, max(280, usableWidth * 0.92))
    }

    private func usesIntrinsicBubbleWidth(_ text: String) -> Bool {
        !text.contains("\n") && text.count <= 72
    }

    private var canSend: Bool {
        isReady && !normalizedDraft.isEmpty
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sendShortcutDisplay: String {
        sendShortcut?.displayName ?? "Button"
    }

    private var sendHelp: String {
        if normalizedDraft.isEmpty {
            return "コマンドを入力してください"
        }
        return isReady
            ? "\(sendShortcutDisplay) でコマンドを送信"
            : "現在は送信できません: \(statusText)"
    }

    private var conversationBackground: Color {
        Color(
            nsColor: NSColor(
                calibratedRed: 0.030,
                green: 0.036,
                blue: 0.048,
                alpha: 1
            )
        )
    }

    private func shouldOfferExpansion(_ text: String) -> Bool {
        let explicitLines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let approximateWrappedCharacters = max(28, boundedCollapsedLineLimit * 34)
        return explicitLines > boundedCollapsedLineLimit
            || text.count > approximateWrappedCharacters
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func scrollToLatest(_ reader: ScrollViewProxy) {
        reader.scrollTo(Self.bottomAnchorID, anchor: .bottom)
    }
}

private struct TerminalConversationComposerView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let sendShortcut: ApexKeyChord?
    let canSend: Bool
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> TerminalConversationComposerContainer {
        let container = TerminalConversationComposerContainer()
        container.textView.delegate = context.coordinator
        configure(container)
        return container
    }

    func updateNSView(
        _ container: TerminalConversationComposerContainer,
        context: Context
    ) {
        context.coordinator.text = $text
        configure(container)
    }

    static func dismantleNSView(
        _ container: TerminalConversationComposerContainer,
        coordinator: Coordinator
    ) {
        container.textView.delegate = nil
        container.onSend = nil
    }

    private func configure(_ container: TerminalConversationComposerContainer) {
        container.sendShortcut = sendShortcut
        container.canSend = canSend
        container.onSend = onSend
        container.textView.font = NSFont.monospacedSystemFont(
            ofSize: CGFloat(fontSize),
            weight: .regular
        )
        container.setText(text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  text.wrappedValue != textView.string else {
                return
            }
            text.wrappedValue = textView.string
        }
    }
}

@MainActor
private final class TerminalConversationComposerContainer: NSScrollView {
    let textView = TerminalConversationTextView(frame: .zero)
    var sendShortcut: ApexKeyChord? {
        didSet { textView.sendShortcut = sendShortcut }
    }
    var canSend = false {
        didSet { textView.canSend = canSend }
    }
    var onSend: (() -> Void)? {
        didSet { textView.onSend = onSend }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .noBorder
        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = true
        autohidesScrollers = true

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 9)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.insertionPointColor = .controlAccentColor
        documentView = textView
        setAccessibilityIdentifier("terminal-conversation-composer-native")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setText(_ value: String) {
        guard textView.string != value else { return }
        let selectedRanges = textView.selectedRanges
        textView.string = value
        if selectedRanges.allSatisfy({ NSMaxRange($0.rangeValue) <= value.utf16.count }) {
            textView.selectedRanges = selectedRanges
        }
    }
}

@MainActor
private final class TerminalConversationTextView: NSTextView {
    var sendShortcut: ApexKeyChord?
    var canSend = false
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if canSend,
           let sendShortcut,
           Self.matches(event, chord: sendShortcut) {
            onSend?()
            return
        }
        super.keyDown(with: event)
    }

    private static func matches(_ event: NSEvent, chord: ApexKeyChord) -> Bool {
        guard keyName(for: event) == chord.key else { return false }
        return modifiers(for: event.modifierFlags) == chord.modifiers
    }

    private static func modifiers(
        for flags: NSEvent.ModifierFlags
    ) -> Set<ApexKeyModifier> {
        var result: Set<ApexKeyModifier> = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
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
        case 53: return "escape"
        default:
            guard let characters = event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .controlCharacters),
                !characters.isEmpty else {
                return nil
            }
            return ApexKeyChord.normalizedKey(characters)
        }
    }
}

private struct TerminalConversationProbeView: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.setAccessibilityIdentifier(identifier)
    }
}
