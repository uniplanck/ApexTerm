import ApexTermCore
import Darwin
import Foundation
import SwiftUI

struct TmuxEndpointState: Identifiable, Equatable, Sendable {
    var id: String { endpoint.id }
    let endpoint: TmuxEndpoint
    let sessions: [TmuxSessionDescriptor]
    let message: String?
}

struct TmuxKillOutcome: Equatable, Sendable {
    let session: TmuxSessionDescriptor
    let succeeded: Bool
    let message: String?
}

private struct TmuxProcessResult: Sendable {
    let exitCode: Int32
    let output: String
    let errorOutput: String
    let didTimeOut: Bool
}

private final class TmuxPipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func attach(to handle: FileHandle) {
        handle.readabilityHandler = { [weak self] readable in
            let chunk = readable.availableData
            guard !chunk.isEmpty else {
                readable.readabilityHandler = nil
                return
            }
            self?.append(chunk)
        }
    }

    func finish(from handle: FileHandle) -> Data {
        handle.readabilityHandler = nil
        let remainder = handle.readDataToEndOfFile()
        append(remainder)
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    private func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }
}

enum TmuxSessionRuntime {
    static func refresh(
        localServerName: String,
        localExecutable: String?,
        remoteProfiles: [SSHHostProfile],
        sshExecutable: String = "/usr/bin/ssh"
    ) async -> [TmuxEndpointState] {
        var requests: [(TmuxEndpoint, ProcessLaunchPlan?)] = [
            (
                .localApexTerm(serverName: localServerName),
                localExecutable.map {
                    TmuxLaunchPlanBuilder.listLocalApexTerm(
                        executable: $0,
                        serverName: localServerName
                    )
                }
            )
        ]
        requests += remoteProfiles.map { profile in
            (
                .remote(alias: profile.alias),
                TmuxLaunchPlanBuilder.listRemote(
                    profile: profile,
                    executable: sshExecutable
                )
            )
        }

        return await withTaskGroup(of: TmuxEndpointState.self) { group in
            for (endpoint, plan) in requests {
                group.addTask {
                    guard let plan else {
                        return TmuxEndpointState(
                            endpoint: endpoint,
                            sessions: [],
                            message: "tmuxがインストールされていません"
                        )
                    }
                    let result = await execute(plan)
                    if result.exitCode == 0 {
                        return TmuxEndpointState(
                            endpoint: endpoint,
                            sessions: TmuxSessionListParser.parse(
                                result.output,
                                endpoint: endpoint
                            ),
                            message: nil
                        )
                    }
                    if indicatesNoSessions(result) {
                        return TmuxEndpointState(
                            endpoint: endpoint,
                            sessions: [],
                            message: "実行中のtmuxセッションはありません"
                        )
                    }
                    return TmuxEndpointState(
                        endpoint: endpoint,
                        sessions: [],
                        message: conciseError(result)
                    )
                }
            }

            var states: [TmuxEndpointState] = []
            for await state in group {
                states.append(state)
            }
            return states.sorted { lhs, rhs in
                switch (lhs.endpoint, rhs.endpoint) {
                case (.localApexTerm, .remote): true
                case (.remote, .localApexTerm): false
                default: lhs.endpoint.id < rhs.endpoint.id
                }
            }
        }
    }

    static func kill(
        _ sessions: [TmuxSessionDescriptor],
        localExecutable: String?,
        remoteProfiles: [String: SSHHostProfile],
        sshExecutable: String = "/usr/bin/ssh"
    ) async -> [TmuxKillOutcome] {
        await withTaskGroup(of: TmuxKillOutcome.self) { group in
            for session in sessions {
                group.addTask {
                    let plan: ProcessLaunchPlan?
                    switch session.endpoint {
                    case let .localApexTerm(serverName):
                        plan = localExecutable.map {
                            TmuxLaunchPlanBuilder.killLocalApexTerm(
                                executable: $0,
                                serverName: serverName,
                                sessionName: session.name
                            )
                        }
                    case let .remote(alias):
                        plan = remoteProfiles[alias].map {
                            TmuxLaunchPlanBuilder.killRemote(
                                profile: $0,
                                sessionName: session.name,
                                executable: sshExecutable
                            )
                        }
                    }
                    guard let plan else {
                        return TmuxKillOutcome(
                            session: session,
                            succeeded: false,
                            message: "接続設定またはtmux実行ファイルが見つかりません"
                        )
                    }
                    let result = await execute(plan)
                    let succeeded = result.exitCode == 0 || indicatesNoSessions(result)
                    return TmuxKillOutcome(
                        session: session,
                        succeeded: succeeded,
                        message: succeeded ? nil : conciseError(result)
                    )
                }
            }

            var outcomes: [TmuxKillOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }
    }

    private static func execute(_ plan: ProcessLaunchPlan) async -> TmuxProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = TmuxPipeCollector()
        let errorCollector = TmuxPipeCollector()
        process.executableURL = URL(fileURLWithPath: plan.executable)
        process.arguments = plan.arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return TmuxProcessResult(
                exitCode: -1,
                output: "",
                errorOutput: error.localizedDescription,
                didTimeOut: false
            )
        }

        outputCollector.attach(to: outputPipe.fileHandleForReading)
        errorCollector.attach(to: errorPipe.fileHandleForReading)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(15))
        var didTimeOut = false
        while process.isRunning {
            if Task.isCancelled || clock.now >= deadline {
                didTimeOut = true
                process.terminate()
                for _ in 0..<20 where process.isRunning {
                    usleep(25_000)
                }
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if process.isRunning {
            process.waitUntilExit()
        }

        let outputData = outputCollector.finish(from: outputPipe.fileHandleForReading)
        let errorData = errorCollector.finish(from: errorPipe.fileHandleForReading)
        return TmuxProcessResult(
            exitCode: process.terminationStatus,
            output: String(data: outputData, encoding: .utf8) ?? "",
            errorOutput: String(data: errorData, encoding: .utf8) ?? "",
            didTimeOut: didTimeOut
        )
    }

    private static func indicatesNoSessions(_ result: TmuxProcessResult) -> Bool {
        let text = (result.output + "\n" + result.errorOutput).lowercased()
        return text.contains("no server running")
            || text.contains("no sessions")
            || text.contains("failed to connect to server")
    }

    private static func conciseError(_ result: TmuxProcessResult) -> String {
        if result.didTimeOut {
            return "tmux接続が15秒でタイムアウトしました"
        }
        let text = result.errorOutput.isEmpty ? result.output : result.errorOutput
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            ?? "tmux操作に失敗しました（exit \(result.exitCode)）"
    }
}

struct TmuxSessionManagerView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []
    @State private var pendingKill: PendingKill?

    private enum PendingKill: Identifiable {
        case selected([TmuxSessionDescriptor])
        case all([TmuxSessionDescriptor])

        var id: String {
            switch self {
            case .selected: "selected"
            case .all: "all"
            }
        }

        var sessions: [TmuxSessionDescriptor] {
            switch self {
            case let .selected(value), let .all(value): value
            }
        }
    }

    private var allSessions: [TmuxSessionDescriptor] {
        model.tmuxEndpointStates.flatMap(\.sessions)
    }

    private var selectedSessions: [TmuxSessionDescriptor] {
        allSessions.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("tmux Session Manager")
                        .font(.title2.weight(.semibold))
                    Text("このMacと登録済みリモート先のtmuxを確認・選択・終了します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isTmuxRefreshing || model.isTmuxActionRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    model.refreshTmuxSessions()
                } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isTmuxRefreshing || model.isTmuxActionRunning)
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            if let message = model.tmuxActionMessage {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Color.secondary.opacity(0.06))
                Divider()
            }

            if model.tmuxEndpointStates.isEmpty && model.isTmuxRefreshing {
                ProgressView("tmuxセッションを確認しています…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.tmuxEndpointStates) { state in
                        Section {
                            if state.sessions.isEmpty {
                                Text(state.message ?? "実行中のtmuxセッションはありません")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(state.sessions) { session in
                                    sessionRow(session)
                                }
                            }
                        } header: {
                            HStack {
                                Text(model.tmuxEndpointTitle(state.endpoint))
                                Spacer()
                                Text("\(state.sessions.count)")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack(spacing: 10) {
                Text("選択 \(selectedSessions.count) / \(allSessions.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("すべて選択") {
                    selectedIDs = Set(allSessions.map(\.id))
                }
                .disabled(allSessions.isEmpty)
                Button("選択解除") {
                    selectedIDs.removeAll()
                }
                .disabled(selectedIDs.isEmpty)
                Spacer()
                Button {
                    guard let session = selectedSessions.first else { return }
                    model.openTmuxSession(session)
                } label: {
                    Label("選択したセッションを開く", systemImage: "play.fill")
                }
                .disabled(selectedSessions.count != 1 || model.isTmuxActionRunning)
                Button(role: .destructive) {
                    pendingKill = .selected(selectedSessions)
                } label: {
                    Label("選択を終了", systemImage: "xmark.circle")
                }
                .disabled(selectedSessions.isEmpty || model.isTmuxActionRunning)
                Button(role: .destructive) {
                    pendingKill = .all(allSessions)
                } label: {
                    Label("すべて終了", systemImage: "trash")
                }
                .disabled(allSessions.isEmpty || model.isTmuxActionRunning)
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 540)
        .task {
            if model.tmuxEndpointStates.isEmpty {
                model.refreshTmuxSessions()
            }
        }
        .onChange(of: allSessions.map(\.id)) { _, validIDs in
            selectedIDs.formIntersection(validIDs)
        }
        .alert(item: $pendingKill) { pending in
            Alert(
                title: Text("tmuxセッションを終了しますか？"),
                message: Text("対象: \(pending.sessions.count)件。セッション内の実行中プロセスも終了します。"),
                primaryButton: .destructive(Text("終了")) {
                    model.killTmuxSessions(pending.sessions)
                    selectedIDs.subtract(pending.sessions.map(\.id))
                },
                secondaryButton: .cancel(Text("キャンセル"))
            )
        }
    }

    private func sessionRow(_ session: TmuxSessionDescriptor) -> some View {
        HStack(spacing: 10) {
            Button {
                if selectedIDs.contains(session.id) {
                    selectedIDs.remove(session.id)
                } else {
                    selectedIDs.insert(session.id)
                }
            } label: {
                Image(systemName: selectedIDs.contains(session.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selectedIDs.contains(session.id) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selectedIDs.contains(session.id) ? "選択解除" : "選択")

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                HStack(spacing: 10) {
                    Label("\(session.windowCount) windows", systemImage: "macwindow.on.rectangle")
                    Label("\(session.attachedClientCount) attached", systemImage: "person.crop.circle")
                    if let createdAt = session.createdAt {
                        Label(createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("開く") {
                model.openTmuxSession(session)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(role: .destructive) {
                pendingKill = .selected([session])
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("このtmuxセッションを終了")
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }
}
