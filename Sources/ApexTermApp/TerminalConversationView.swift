import ApexTermCore
import SwiftUI

struct TerminalConversationView: View {
    let records: [CommandExecutionRecord]
    let appearance: TerminalAppearance
    let fontSize: Double
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

    var body: some View {
        VStack(spacing: 0) {
            conversation

            if !scheduledCommands.isEmpty {
                scheduledCommandStrip
                Divider()
            }

            composer
        }
        .background(conversationBackground)
        .background {
            TerminalConversationProbeView(identifier: "terminal-conversation-mode-probe")
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("terminal-conversation-mode")
    }

    private var conversation: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if records.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(records.reversed())) { record in
                            conversationTurn(record)
                                .id(record.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            .onAppear {
                scrollToLatest(reader)
            }
            .onChange(of: records.first?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.16)) {
                    scrollToLatest(reader)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("コマンドを送信すると、入力と出力が会話形式で表示されます")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    @ViewBuilder
    private func conversationTurn(_ record: CommandExecutionRecord) -> some View {
        VStack(spacing: 8) {
            if !record.command.isEmpty {
                HStack(alignment: .bottom) {
                    Spacer(minLength: 48)
                    compactBubble(
                        text: record.command,
                        foreground: appearance.inputColor,
                        isExpanded: expandedCommandIDs.contains(record.id),
                        alignment: .trailing,
                        accessibilityIdentifier: "terminal-conversation-command-\(record.id.uuidString)",
                        expansionIdentifier: "terminal-conversation-command-expand-\(record.id.uuidString)"
                    ) {
                        toggle(record.id, in: &expandedCommandIDs)
                    }
                    .background(
                        appearance.inputColor.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }

            if !record.output.isEmpty {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        compactBubble(
                            text: record.output,
                            foreground: appearance.outputColor,
                            isExpanded: expandedOutputIDs.contains(record.id),
                            alignment: .leading,
                            accessibilityIdentifier: "terminal-conversation-output-\(record.id.uuidString)",
                            expansionIdentifier: "terminal-conversation-output-expand-\(record.id.uuidString)"
                        ) {
                            toggle(record.id, in: &expandedOutputIDs)
                        }
                        .background(
                            Color.primary.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                        HStack(spacing: 4) {
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
                            Text("exit \(record.exitCode)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(record.exitCode == 0 ? Color.secondary : Color.red)
                            Text(record.finishedAt.formatted(.dateTime.hour().minute().second()))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.leading, 3)
                    }
                    Spacer(minLength: 48)
                }
            }
        }
    }

    private func compactBubble(
        text: String,
        foreground: Color,
        isExpanded: Bool,
        alignment: Alignment,
        accessibilityIdentifier: String,
        expansionIdentifier: String,
        onToggle: @escaping () -> Void
    ) -> some View {
        VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 5) {
            Text(text)
                .font(.system(size: max(9, fontSize), design: .monospaced))
                .foregroundStyle(foreground)
                .lineLimit(isExpanded ? nil : 3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: alignment)
                .accessibilityIdentifier(accessibilityIdentifier)
                .background {
                    TerminalConversationProbeView(identifier: accessibilityIdentifier + "-probe")
                        .allowsHitTesting(false)
                }

            if shouldOfferExpansion(text) {
                Button(action: onToggle) {
                    Label(
                        isExpanded ? "折りたたむ" : "すべて表示",
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption2)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 640, alignment: alignment)
    }

    private var scheduledCommandStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scheduledCommands) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption2)
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .accessibilityIdentifier("scheduled-terminal-command-\(item.id.uuidString)")
                    .background {
                        TerminalConversationProbeView(
                            identifier: "scheduled-terminal-command-\(item.id.uuidString)-probe"
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 38)
        .accessibilityIdentifier("scheduled-terminal-command-strip")
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $draft)
                .font(.system(size: max(10, fontSize), design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 36, idealHeight: 44, maxHeight: 88)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Color(nsColor: .textBackgroundColor).opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
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
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
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
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 23))
            }
            .buttonStyle(.borderless)
            .disabled(!canSend)
            .help(sendHelp)
            .accessibilityLabel("コマンドを送信")
            .accessibilityValue(isReady ? "Ready" : "プロンプト待ち")
            .accessibilityIdentifier("terminal-conversation-send")
            .background {
                TerminalConversationProbeView(identifier: "terminal-conversation-send-probe")
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .overlay(alignment: .topLeading) {
            Text(isReady ? "Ready" : "実行中 · プロンプトへ戻るまで送信できません")
                .font(.caption2)
                .foregroundStyle(isReady ? Color.secondary : Color.orange)
                .padding(.leading, 12)
                .offset(y: -16)
        }
        .background(.regularMaterial)
    }

    private var schedulePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("時間指定送信")
                .font(.headline)
            Text(normalizedDraft)
                .font(.caption.monospaced())
                .lineLimit(3)
                .frame(maxWidth: 320, alignment: .leading)
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
        .padding(14)
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
                .frame(width: 20, height: 18)
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

    private var canSend: Bool {
        isReady && !normalizedDraft.isEmpty
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sendHelp: String {
        if normalizedDraft.isEmpty {
            return "コマンドを入力してください"
        }
        return isReady
            ? "コマンドを送信"
            : "プロンプトへ戻るまで送信できません"
    }

    private var conversationBackground: Color {
        Color(
            nsColor: NSColor(
                calibratedRed: 0.035,
                green: 0.043,
                blue: 0.055,
                alpha: 1
            )
        )
    }

    private func shouldOfferExpansion(_ text: String) -> Bool {
        let explicitLines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        // A narrow terminal column wraps roughly 20–24 monospaced characters per
        // line. Offer expansion early enough that a visually clipped third line is
        // never left without a way to open it.
        return explicitLines > 3 || text.count > 64
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func scrollToLatest(_ reader: ScrollViewProxy) {
        guard let latest = records.first?.id else { return }
        reader.scrollTo(latest, anchor: .bottom)
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
