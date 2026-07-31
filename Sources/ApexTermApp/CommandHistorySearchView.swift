import ApexTermCore
import AppKit
import SwiftUI

struct CommandHistorySearchView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var failuresOnly = false
    @State private var selectedSessionOnly: Bool
    @FocusState private var searchFocused: Bool

    init(model: AppModel) {
        self.model = model
        _query = State(initialValue: model.commandHistorySearchInitialQuery)
        _selectedSessionOnly = State(
            initialValue: model.commandHistorySearchSessionID != nil
        )
    }

    private var records: [CommandExecutionRecord] {
        model.filteredCommandHistory(
            query: query,
            failuresOnly: failuresOnly,
            sessionID: selectedSessionOnly
                ? (model.commandHistorySearchSessionID ?? model.selectedSessionID)
                : nil
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("コマンド・出力を検索", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                Text("\(records.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("閉じる") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            Divider()

            HStack(spacing: 14) {
                Toggle("失敗のみ", isOn: $failuresOnly)
                Toggle("選択ペインのみ", isOn: $selectedSessionOnly)
                    .disabled(model.selectedSessionID == nil)
                Spacer()
                Text("実行は内容確認後に端末へ送信")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 16)
            .frame(height: 38)

            Divider()

            if records.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(records) { record in
                            historyRow(record)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(CommandHistorySearchProbeView())
        .accessibilityIdentifier("command-history-search-view")
        .onAppear { searchFocused = true }
        .onDisappear {
            model.clearCommandHistorySearchContext()
        }
    }

    private func historyRow(_ record: CommandExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: record.exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(record.exitCode == 0 ? Color.green : Color.red)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.command.isEmpty ? "(入力なし)" : record.command)
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        Text(model.sessionTitle(for: record.sessionID))
                        Text("exit \(record.exitCode)")
                        Text(duration(record))
                        Text(record.finishedAt.formatted(date: .abbreviated, time: .standard))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    insert(record.command, execute: false)
                } label: {
                    Label("挿入", systemImage: "arrow.down.to.line.compact")
                }
                .disabled(record.command.isEmpty)

                Button {
                    insert(record.command, execute: true)
                } label: {
                    Label("実行", systemImage: "play.fill")
                }
                .disabled(record.command.isEmpty)

                Button {
                    ClipboardWriter.copy(record.commandAndOutput)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("入力と出力をコピー")
            }

            if !record.output.isEmpty {
                Text(TerminalOutputPresentation.preview(
                    record.output,
                    maximumCharacters: 1_500
                ).text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(8)
                .textSelection(.enabled)
                .padding(.leading, 28)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .contextMenu {
            Button("入力欄へ挿入") { insert(record.command, execute: false) }
            Button("実行") { insert(record.command, execute: true) }
            Divider()
            Button("入力をコピー") { ClipboardWriter.copy(record.command) }
            Button("出力をコピー") { ClipboardWriter.copy(record.output) }
            Button("入力と出力をコピー") { ClipboardWriter.copy(record.commandAndOutput) }
        }
    }

    private func insert(_ command: String, execute: Bool) {
        guard !command.isEmpty else { return }
        if execute {
            let assessment = SmartPastePolicy().assess(command + "\n")
            let alert = NSAlert()
            alert.alertStyle = assessment.riskDecision.level == .requireApproval
                ? .critical
                : .warning
            alert.messageText = assessment.riskDecision.level == .requireApproval
                ? "危険な可能性があるコマンド"
                : "このコマンドを実行しますか？"
            alert.informativeText = command
            alert.addButton(withTitle: "実行")
            alert.addButton(withTitle: "キャンセル")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        model.requestTerminalInput(command, execute: execute)
        dismiss()
    }

    private func duration(_ record: CommandExecutionRecord) -> String {
        let seconds = max(0, record.finishedAt.timeIntervalSince(record.startedAt))
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1_000)
        }
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.1fmin", seconds / 60)
    }
}

private struct CommandHistorySearchProbeView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let identifier = "command-history-search-view"
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityElement(true)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
