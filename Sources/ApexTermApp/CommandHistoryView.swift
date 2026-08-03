import ApexTermCore
import AppKit
import SwiftUI

struct CommandHistoryPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("COMMAND HISTORY")
                    .font(.system(size: max(9, model.sidebarFontSize - 2), weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.commandHistory.isEmpty {
                    Button("Clear") {
                        model.clearCommandHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)

            Divider()

            if model.commandHistory.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No captured commands")
                        .font(.callout.weight(.medium))
                    Text("ApexTermで実行したコマンドがここに表示されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.recentCommands(limit: 3)) { record in
                            CommandHistoryCard(
                                record: record,
                                fontSize: model.sidebarFontSize
                            )
                        }
                    }
                    .padding(10)
                }
            }
        }
    }
}

private struct TerminalCommandTranscriptContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TerminalCommandTranscript: View {
    let records: [CommandExecutionRecord]
    let appearance: TerminalAppearance
    let fontSize: Double
    let collapsedCommandIDs: Set<UUID>
    let onToggleCollapsed: (UUID) -> Void
    let onInsertCommand: (String) -> Void
    let onContentHeightChange: (CGFloat) -> Void

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(Array(records.reversed())) { record in
                        TerminalCommandBlockCard(
                            record: record,
                            appearance: appearance,
                            fontSize: fontSize,
                            isExpanded: !collapsedCommandIDs.contains(record.id),
                            onToggle: { onToggleCollapsed(record.id) },
                            onInsertCommand: onInsertCommand
                        )
                        .id(record.id)
                    }
                }
                .padding(.leading, 5)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TerminalCommandTranscriptContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
            }
            .background(terminalBackground)
            .onPreferenceChange(TerminalCommandTranscriptContentHeightKey.self) { height in
                guard height > 0 else { return }
                onContentHeightChange(height)
            }
            .onAppear {
                if let latestID = records.first?.id {
                    reader.scrollTo(latestID, anchor: .top)
                }
            }
            .onChange(of: records.first?.id) { _, latestID in
                guard let latestID else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    reader.scrollTo(latestID, anchor: .top)
                }
            }
        }
    }

    private var terminalBackground: Color {
        Color(
            nsColor: NSColor(
                calibratedRed: 0.035,
                green: 0.043,
                blue: 0.055,
                alpha: 1
            )
        )
    }
}

struct CommandActionMenu: NSViewRepresentable {
    let record: CommandExecutionRecord
    let isExpanded: Bool?
    let onToggle: (() -> Void)?

    init(
        record: CommandExecutionRecord,
        isExpanded: Bool? = nil,
        onToggle: (() -> Void)? = nil
    ) {
        self.record = record
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(record: record, isExpanded: isExpanded, onToggle: onToggle)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .inline
        button.isBordered = false
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.imagePosition = .imageOnly
        button.controlSize = .small
        button.toolTip = "コマンド操作"
        button.contentTintColor = .controlAccentColor
        button.setAccessibilityLabel("Command actions")
        configure(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        configure(button, coordinator: context.coordinator)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSPopUpButton,
        context: Context
    ) -> CGSize? {
        CGSize(width: 22, height: 22)
    }

    private func configure(_ button: NSPopUpButton, coordinator: Coordinator) {
        coordinator.record = record
        coordinator.isExpanded = isExpanded
        coordinator.onToggle = onToggle
        let identifier = "command-action-\(record.id.uuidString)"
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.setAccessibilityIdentifier(identifier)
        button.isEnabled = !record.command.isEmpty || !record.output.isEmpty

        let menu = NSMenu()
        menu.autoenablesItems = false

        let iconItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        iconItem.image = NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: "Command actions"
        )
        menu.addItem(iconItem)
        menu.addItem(coordinator.item(
            title: "入力をコピー",
            action: #selector(Coordinator.copyInput),
            enabled: !record.command.isEmpty
        ))
        menu.addItem(coordinator.item(
            title: "出力をコピー",
            action: #selector(Coordinator.copyOutput),
            enabled: !record.output.isEmpty
        ))
        menu.addItem(coordinator.item(
            title: "入力と出力をコピー",
            action: #selector(Coordinator.copyInputAndOutput),
            enabled: !record.command.isEmpty || !record.output.isEmpty
        ))
        if isExpanded != nil, onToggle != nil, !record.output.isEmpty {
            menu.addItem(.separator())
            menu.addItem(coordinator.item(
                title: isExpanded == true ? "出力を閉じる" : "出力を開く",
                action: #selector(Coordinator.toggleOutput),
                enabled: true
            ))
        }
        button.menu = menu
        button.selectItem(at: 0)
    }

    @MainActor
    final class Coordinator: NSObject {
        var record: CommandExecutionRecord
        var isExpanded: Bool?
        var onToggle: (() -> Void)?

        init(
            record: CommandExecutionRecord,
            isExpanded: Bool?,
            onToggle: (() -> Void)?
        ) {
            self.record = record
            self.isExpanded = isExpanded
            self.onToggle = onToggle
        }

        func item(title: String, action: Selector, enabled: Bool) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            return item
        }

        @objc func copyInput() {
            ClipboardWriter.copy(record.command)
        }

        @objc func copyOutput() {
            ClipboardWriter.copy(record.output)
        }

        @objc func copyInputAndOutput() {
            ClipboardWriter.copy(record.commandAndOutput)
        }

        @objc func toggleOutput() {
            onToggle?()
        }
    }
}

private struct TerminalCommandBlockCard: View {
    let record: CommandExecutionRecord
    let appearance: TerminalAppearance
    let fontSize: Double
    let isExpanded: Bool
    let onToggle: () -> Void
    let onInsertCommand: (String) -> Void
    @State private var showsFullOutput = false

    var body: some View {
        RightClickableHostingContainer(
            accessibilityIdentifier: "terminal-command-block-\(record.id.uuidString)",
            onLeftClick: toggleOutput,
            onRightClick: copyOutput
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 7) {
                    CommandActionMenu(
                        record: record,
                        isExpanded: isExpanded,
                        onToggle: onToggle
                    )
                    .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(singleLineCommand)
                            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                            .foregroundStyle(appearance.inputColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, minHeight: 17, maxHeight: 17, alignment: .leading)
                            .contentShape(Rectangle())
                            .help(record.command.isEmpty ? "(入力なし)" : record.command)

                        HStack(spacing: 8) {
                            Text(timestamp)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text("exit \(record.exitCode)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(record.exitCode == 0 ? Color.secondary : Color.red)
                            Spacer()
                            if !record.output.isEmpty {
                                Text("\(outputLineCount) lines")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 18)
                                    .help(isExpanded ? "クリックして出力を閉じる" : "クリックして出力を開く")
                            }
                        }
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 5)
                .background(appearance.inputColor.opacity(0.055))

                if !record.output.isEmpty {
                    if isExpanded {
                        Divider()
                            .opacity(0.22)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(displayedOutput.text)
                                .font(.system(size: max(9, fontSize - 0.5), design: .monospaced))
                                .foregroundStyle(appearance.outputColor)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if outputPreview.isTruncated {
                                Button(showsFullOutput ? "軽量表示へ戻す" : "全出力を表示") {
                                    showsFullOutput.toggle()
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }

                            if !quickFixes.isEmpty {
                                actionRow(
                                    title: "Quick Fix",
                                    systemImage: "wrench.and.screwdriver"
                                ) {
                                    ForEach(quickFixes) { suggestion in
                                        Button {
                                            onInsertCommand(suggestion.command)
                                        } label: {
                                            Label(suggestion.title, systemImage: "arrow.down.to.line.compact")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .help(suggestion.detail)
                                    }
                                }
                            }

                            if !detectedItems.isEmpty {
                                actionRow(
                                    title: "検出",
                                    systemImage: "scope"
                                ) {
                                    ForEach(detectedItems) { item in
                                        Button {
                                            performDetectedItem(item)
                                        } label: {
                                            Label(
                                                detectedItemTitle(item),
                                                systemImage: detectedItemIcon(item)
                                            )
                                            .lineLimit(1)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .help(item.displayValue)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 35)
                        .padding(.trailing, 8)
                        .padding(.vertical, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        HStack(spacing: 7) {
                            Image(systemName: "text.line.last.and.arrowtriangle.forward")
                            Text("出力 \(outputLineCount) 行を折りたたみ中")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 31)
                        .padding(.vertical, 4)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.022))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(0.075), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(record.output.isEmpty ? [] : .isButton)
            .accessibilityIdentifier("terminal-command-block-content-\(record.id.uuidString)")
        }
    }

    private var singleLineCommand: String {
        let command = record.command.isEmpty ? "(入力なし)" : record.command
        return command
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private var outputLineCount: Int {
        max(1, record.output.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    private var insights: TerminalCommandInsights {
        TerminalInsightCache.shared.insights(for: record)
    }

    private var outputPreview: TerminalOutputPresentation {
        insights.outputPreview
    }

    private var displayedOutput: TerminalOutputPresentation {
        showsFullOutput
            ? TerminalOutputPresentation(text: record.output, omittedCharacterCount: 0)
            : outputPreview
    }

    private var quickFixes: [TerminalQuickFixSuggestion] {
        insights.quickFixes
    }

    private var detectedItems: [TerminalDetectedItem] {
        insights.detectedItems
    }

    private func actionRow<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    content()
                }
            }
        }
    }

    private func performDetectedItem(_ item: TerminalDetectedItem) {
        switch item.kind {
        case .url:
            if let url = URL(string: item.value) {
                NSWorkspace.shared.open(url)
            }
        case .fileLine, .gitHash:
            onInsertCommand(item.value)
        }
    }

    private func detectedItemTitle(_ item: TerminalDetectedItem) -> String {
        switch item.kind {
        case .url:
            return URL(string: item.value)?.host ?? item.displayValue
        case .fileLine:
            return item.displayValue
        case .gitHash:
            return String(item.value.prefix(10))
        }
    }

    private func detectedItemIcon(_ item: TerminalDetectedItem) -> String {
        switch item.kind {
        case .url: "link"
        case .fileLine: "doc.text.magnifyingglass"
        case .gitHash: "number"
        }
    }

    private var timestamp: String {
        record.finishedAt.formatted(
            .dateTime
                .hour().minute().second()
                .locale(Locale(identifier: "ja_JP"))
        )
    }

    private func toggleOutput() {
        guard !record.output.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.14)) {
            onToggle()
        }
    }

    private func copyOutput() {
        guard !record.output.isEmpty else { return }
        ClipboardWriter.copy(record.output)
    }
}

private struct CommandHistoryCard: View {
    let record: CommandExecutionRecord
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(timestamp)
                        .font(.system(size: max(8, fontSize - 2), design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(record.command)
                        .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 4)
                CommandActionMenu(record: record)
            }

            if !record.output.isEmpty {
                Text(record.output)
                    .font(.system(size: max(9, fontSize - 1), design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            HStack(spacing: 6) {
                quickCopyButton(
                    title: "All",
                    systemImage: "doc.on.doc",
                    value: record.commandAndOutput,
                    identifier: "copy-all"
                )
                quickCopyButton(
                    title: "Output",
                    systemImage: "text.quote",
                    value: record.output,
                    identifier: "copy-output"
                )
                quickCopyButton(
                    title: "Command",
                    systemImage: "terminal",
                    value: record.command,
                    identifier: "copy-command"
                )
                Spacer()
                Text("exit \(record.exitCode)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(record.exitCode == 0 ? Color.secondary : Color.red)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityIdentifier("command-history-\(record.id.uuidString)")
    }

    private var timestamp: String {
        record.finishedAt.formatted(
            .dateTime
                .year().month().day()
                .hour().minute().second()
                .locale(Locale(identifier: "ja_JP"))
        )
    }

    private func quickCopyButton(
        title: String,
        systemImage: String,
        value: String,
        identifier: String
    ) -> some View {
        Button {
            ClipboardWriter.copy(value)
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(title)
        .disabled(value.isEmpty)
        .accessibilityIdentifier("\(identifier)-\(record.id.uuidString)")
    }
}

private struct RightClickableHostingContainer<Content: View>: NSViewRepresentable {
    let accessibilityIdentifier: String
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> RightClickableHostingView<Content> {
        let view = RightClickableHostingView(
            rootView: content(),
            onLeftClick: onLeftClick,
            onRightClick: onRightClick
        )
        configureAccessibility(view)
        return view
    }

    func updateNSView(_ nsView: RightClickableHostingView<Content>, context: Context) {
        nsView.rootView = content()
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
        configureAccessibility(nsView)
    }

    private func configureAccessibility(_ view: NSView) {
        view.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        view.setAccessibilityIdentifier(accessibilityIdentifier)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Command block")
    }
}

private final class RightClickableHostingView<Content: View>: NSHostingView<Content> {
    var onLeftClick: () -> Void
    var onRightClick: () -> Void
    private var mouseDownPoint: NSPoint?
    private var mouseDownStartedInControl = false
    private var mouseDraggedSinceDown = false

    init(
        rootView: Content,
        onLeftClick: @escaping () -> Void,
        onRightClick: @escaping () -> Void
    ) {
        self.onLeftClick = onLeftClick
        self.onRightClick = onRightClick
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = point
        mouseDownStartedInControl = hasControlAncestor(hitTest(point))
        mouseDraggedSinceDown = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseDraggedSinceDown = true
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let start = mouseDownPoint
        let shouldToggle = !mouseDownStartedInControl
            && !mouseDraggedSinceDown
            && start.map { hypot(point.x - $0.x, point.y - $0.y) <= 4 } == true
        super.mouseUp(with: event)
        mouseDownPoint = nil
        if shouldToggle {
            onLeftClick()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick()
    }

    override func accessibilityPerformPress() -> Bool {
        onLeftClick()
        return true
    }

    private func hasControlAncestor(_ hitView: NSView?) -> Bool {
        var current = hitView
        while let view = current, view !== self {
            if view is NSControl { return true }
            current = view.superview
        }
        return false
    }
}

enum ClipboardWriter {
    static func copy(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
