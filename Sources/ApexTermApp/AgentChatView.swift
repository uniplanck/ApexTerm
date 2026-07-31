import ApexTermCore
import AppKit
import SwiftUI

struct AgentChatView: View {
    @ObservedObject var model: AppModel
    let tabID: UUID

    private var tab: AgentChatTab? {
        model.agentChatTabs.first { $0.id == tabID }
    }

    var body: some View {
        GeometryReader { proxy in
            if let tab {
                ZStack {
                    AgentChatBackdrop()
                    VStack(spacing: 0) {
                        header(tab: tab, compact: proxy.size.width < 720)
                        Divider().opacity(0.45)
                        conversation(tab: tab, compact: proxy.size.width < 720)
                        composer(tab: tab, compact: proxy.size.width < 720)
                    }
                }
            } else {
                ContentUnavailableView("Agent Chat", systemImage: "sparkles")
            }
        }
    }

    private func header(tab: AgentChatTab, compact: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.pink.opacity(0.9), .purple.opacity(0.88), .cyan.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .shadow(color: .purple.opacity(0.25), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(tab.isRunning ? "Agent is working…" : "Conversational Agent UI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !compact {
                targetPicker(tab: tab)
            }

            if let job = tab.activeJob?.job {
                statusCapsule(job: job)
            }
        }
        .padding(.horizontal, compact ? 12 : 18)
        .frame(height: 62)
        .background(.ultraThinMaterial)
    }

    private func targetPicker(tab: AgentChatTab) -> some View {
        HStack(spacing: 4) {
            ForEach(GagTarget.allCases, id: \.self) { target in
                Button {
                    model.setAgentChatTarget(id: tab.id, target: target)
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(target == .local ? Color.pink : Color.cyan)
                            .frame(width: 6, height: 6)
                        Text(target.displayName)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        target == tab.target
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(tab.isRunning)
            }
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: Capsule())
    }

    private func statusCapsule(job: GagJobRecord) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(job.status))
                .frame(width: 7, height: 7)
            Text(job.status.isTerminal ? job.status.rawValue : "\(job.progress)%")
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(statusColor(job.status).opacity(0.12), in: Capsule())
    }

    private func conversation(tab: AgentChatTab, compact: Bool) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: compact ? 12 : 18) {
                    if tab.messages.isEmpty {
                        emptyState(tab: tab)
                            .padding(.top, compact ? 28 : 64)
                    } else {
                        ForEach(tab.messages) { message in
                            messageRow(message, compact: compact)
                                .id(message.id)
                        }
                    }

                    if let job = tab.activeJob?.job {
                        runtimeHUD(tab: tab, job: job, compact: compact)
                            .id("runtime-\(job.id)")
                    }

                    if let error = tab.lastError, !error.isEmpty {
                        errorCard(error)
                    }

                    Color.clear.frame(height: 4).id("bottom")
                }
                .frame(maxWidth: 860)
                .padding(.horizontal, compact ? 12 : 26)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: tab.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    reader.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: tab.activeJob?.job.progress) { _, _ in
                withAnimation(.easeOut(duration: 0.16)) {
                    reader.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func emptyState(tab: AgentChatTab) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.pink.opacity(0.75), .purple.opacity(0.75), .cyan.opacity(0.75), .pink.opacity(0.75)],
                            center: .center
                        )
                    )
                    .frame(width: 82, height: 82)
                    .blur(radius: 1)
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 68, height: 68)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [.pink, .purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            .shadow(color: .purple.opacity(0.2), radius: 18, y: 8)

            VStack(spacing: 7) {
                Text("What should the agent do?")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text("普通のShellではなく、設定済みの外部Agent Providerへ自然文で指示できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                suggestion("このProjectを分析", icon: "magnifyingglass", tab: tab)
                suggestion("不具合を修正", icon: "wrench.and.screwdriver", tab: tab)
                suggestion("進捗を確認", icon: "chart.bar", tab: tab)
            }
        }
        .frame(maxWidth: 640)
    }

    private func suggestion(_ text: String, icon: String, tab: AgentChatTab) -> some View {
        Button {
            model.updateAgentChatDraft(id: tab.id, value: text)
        } label: {
            Label(text, systemImage: icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    private func messageRow(_ message: AgentChatMessage, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: compact ? 24 : 90) }

            if message.role != .user {
                avatar(role: message.role)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 7) {
                Text(message.role == .user ? "YOU" : message.role == .assistant ? "AGENT" : "SYSTEM")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                MarkdownMessageText(text: message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(messageBackground(message.role))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(messageBorder(message.role), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        }
                    }

                if message.requestedPerformance != nil
                    || message.selectedModel != nil
                    || message.selectedModelLabel != nil
                    || message.apiCostEstimate != nil {
                    messageMetadata(message)
                }
            }
            .frame(maxWidth: compact ? .infinity : 680, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                avatar(role: .user)
            } else {
                Spacer(minLength: compact ? 24 : 90)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func avatar(role: AgentChatRole) -> some View {
        ZStack {
            Circle()
                .fill(role == .user ? Color.pink.opacity(0.16) : Color.purple.opacity(0.16))
            Image(systemName: role == .user ? "person.fill" : "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(role == .user ? .pink : .purple)
        }
        .frame(width: 30, height: 30)
    }

    private func runtimeHUD(tab: AgentChatTab, job: GagJobRecord, compact: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let metrics = GagRuntimeMetrics.calculate(target: tab.target, job: job, now: context.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: metrics.progress)
                            .stroke(
                                LinearGradient(colors: [.pink, .purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(metrics.progress * 100))%")
                            .font(.caption2.monospacedDigit().weight(.bold))
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.currentStep)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(metrics.reference)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 4)

                    if tab.isRunning {
                        Button(role: .destructive) {
                            model.cancelAgentChat(id: tab.id)
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Cancel")
                    }
                }

                ProgressView(value: metrics.progress)
                    .tint(.purple)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: compact ? 96 : 124), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    metricTile("Elapsed", value: formatDuration(metrics.elapsedSeconds), icon: "clock")
                    metricTile(
                        "ETA",
                        value: metrics.estimatedRemainingSeconds.map { "約\(formatDuration($0))" } ?? "Waiting",
                        icon: "hourglass"
                    )
                    metricTile(
                        "Complete",
                        value: metrics.estimatedCompletionAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—",
                        icon: "calendar.badge.clock"
                    )
                    metricTile("Input", value: "~\(formatTokens(metrics.tokens.input)) tok", icon: "arrow.up.circle")
                    metricTile("Output", value: metrics.tokens.output > 0 ? "~\(formatTokens(metrics.tokens.output)) tok" : "calculating", icon: "arrow.down.circle")
                    metricTile("Total", value: "~\(formatTokens(metrics.tokens.total)) tok", icon: "number.circle")
                    metricTile("Requested", value: metrics.requestedPerformance.displayName, icon: "speedometer")
                    metricTile(
                        "Actual model",
                        value: metrics.selectedModelLabel ?? metrics.selectedModel ?? "選択中",
                        icon: "brain.head.profile"
                    )
                    metricTile(
                        "This job",
                        value: formatCost(metrics.apiCostEstimate),
                        icon: "yensign.circle"
                    )
                    metricTile(
                        "Chat total",
                        value: formatCostRange(tab.cumulativeAPICostJPY),
                        icon: "sum"
                    )
                }

                if metrics.conversationURL != nil {
                    Button {
                        model.openAgentChatConversation(id: tab.id)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.forward.app")
                            Text("Open running Chat")
                            Spacer()
                            Text("既存タブへ移動 / なければ開く")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.pink.opacity(0.35), .purple.opacity(0.35), .cyan.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .purple.opacity(0.1), radius: 14, y: 5)
        }
    }

    private func metricTile(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func errorCard(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func composer(tab: AgentChatTab, compact: Bool) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                if compact {
                    targetPicker(tab: tab)
                }
                performancePicker(tab: tab, compact: compact)
                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom, spacing: 10) {
                AgentChatComposerTextView(
                    text: Binding(
                        get: { tab.draft },
                        set: { model.updateAgentChatDraft(id: tab.id, value: $0) }
                    ),
                    tabID: tab.id,
                    placeholder: "Agent Providerへ指示を入力…",
                    focusRequestGeneration: model.agentChatFocusRequestGeneration
                )
                .frame(minHeight: 42, maxHeight: 110)
                .id(tab.id)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                )

                Button {
                    model.sendAgentChat(id: tab.id)
                } label: {
                    Image(systemName: tab.isRunning ? "ellipsis" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            LinearGradient(
                                colors: tab.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? [.gray.opacity(0.7), .gray.opacity(0.55)]
                                    : [.pink, .purple, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .shadow(color: .purple.opacity(0.22), radius: 7, y: 3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(tab.isRunning || tab.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send")
            }

            HStack {
                Text("⌘↩ Send")
                Spacer()
                Text("料金はAPI換算推定・実請求ではありません")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private func performancePicker(tab: AgentChatTab, compact: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(GagPerformance.allCases, id: \.self) { performance in
                    Button {
                        model.setAgentChatPerformance(id: tab.id, performance: performance)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: performanceIcon(performance))
                                .font(.system(size: 10, weight: .bold))
                            Text(compact ? performance.compactName : performance.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, compact ? 8 : 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(tab.selectedPerformance == performance ? .white : .primary)
                        .background(
                            tab.selectedPerformance == performance
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [.pink, .purple, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(Color.clear),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(tab.isRunning)
                    .help(performance.displayName)
                }
            }
            .padding(3)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: Capsule())

            Menu {
                ForEach(GagPerformance.allCases, id: \.self) { performance in
                    Button {
                        model.setAgentChatPerformance(id: tab.id, performance: performance)
                    } label: {
                        Label(performance.displayName, systemImage: performanceIcon(performance))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: performanceIcon(tab.selectedPerformance))
                    Text(tab.selectedPerformance.displayName)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [.pink.opacity(0.18), .purple.opacity(0.18), .cyan.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.purple.opacity(0.2)))
            }
            .menuStyle(.borderlessButton)
            .disabled(tab.isRunning)
        }
    }

    private func messageMetadata(_ message: AgentChatMessage) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                metadataBadge(
                    icon: "speedometer",
                    text: "要求 \(message.requestedPerformance?.displayName ?? "高い")"
                )
                metadataBadge(
                    icon: "brain.head.profile",
                    text: "実モデル \(message.selectedModelLabel ?? message.selectedModel ?? "未確認")"
                )
                metadataBadge(icon: "yensign.circle", text: formatCost(message.apiCostEstimate))
            }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
                metadataBadge(
                    icon: "speedometer",
                    text: "要求 \(message.requestedPerformance?.displayName ?? "高い")"
                )
                if message.selectedModel != nil || message.selectedModelLabel != nil {
                    metadataBadge(
                        icon: "brain.head.profile",
                        text: "実モデル \(message.selectedModelLabel ?? message.selectedModel ?? "未確認")"
                    )
                }
                if message.apiCostEstimate != nil {
                    metadataBadge(icon: "yensign.circle", text: formatCost(message.apiCostEstimate))
                }
            }
        }
    }

    private func metadataBadge(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.045), in: Capsule())
            .lineLimit(1)
    }

    private func performanceIcon(_ performance: GagPerformance) -> String {
        performance == .fastest ? "bolt.fill" : "sparkles"
    }

    private func formatCost(_ estimate: GagAPICostEstimate?) -> String {
        guard let estimate else { return "計算中" }
        guard estimate.isRegistered else { return "単価未登録" }
        return formatCostRange((estimate.jpy ?? 0)...(estimate.maxJpy ?? estimate.jpy ?? 0))
    }

    private func formatCostRange(_ range: ClosedRange<Double>?) -> String {
        guard let range else { return "—" }
        if abs(range.upperBound - range.lowerBound) < 0.005 {
            return String(format: "¥%.2f", range.lowerBound)
        }
        return String(format: "¥%.2f–%.2f", range.lowerBound, range.upperBound)
    }

    private func messageBackground(_ role: AgentChatRole) -> AnyShapeStyle {
        if role == .user {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.pink.opacity(0.16), .purple.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private func messageBorder(_ role: AgentChatRole) -> Color {
        role == .user ? .pink.opacity(0.22) : .white.opacity(0.1)
    }

    private func statusColor(_ status: GagJobStatus) -> Color {
        switch status {
        case .queued: .orange
        case .running: .purple
        case .succeeded: .green
        case .failed: .red
        case .cancelling, .cancelled: .secondary
        case .waitingApproval: .yellow
        case .interrupted: .orange
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value < 60 { return "\(value)s" }
        if value < 3600 { return "\(value / 60)m \(value % 60)s" }
        return "\(value / 3600)h \((value % 3600) / 60)m"
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return String(value)
    }
}

private struct MarkdownMessageText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AgentChatBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [.purple.opacity(0.09), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 440
            )
            RadialGradient(
                colors: [.cyan.opacity(0.07), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}
