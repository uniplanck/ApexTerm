import ApexTermCore
import SwiftUI

struct RemoteHostSettingsView: View {
    @ObservedObject var model: AppModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RemoteHostDraft?
    @State private var pendingDeleteAlias: String?
    @State private var isTmuxManagerPresented = false
    @State private var hasRunDeleteProbe = false

    var body: some View {
        VStack(spacing: 0) {
            if embedded {
                embeddedHeader
            } else {
                header
            }
            Divider()

            if let message = model.remoteHostActionMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(message)
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Color.green.opacity(0.08))
                .accessibilityIdentifier("remote-host-action-message")
                Divider()
            }

            List {
                Section("Active and hidden") {
                    if model.remoteHostEntries.isEmpty {
                        Text("No active or hidden hosts")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(model.remoteHostEntries) { entry in
                        remoteHostRow(entry)
                    }
                }

                if !model.deletedRemoteHostAliases.isEmpty {
                    Section("Deleted from ApexTerm") {
                        ForEach(model.deletedRemoteHostAliases, id: \.self) { alias in
                            HStack(spacing: 12) {
                                Image(systemName: "trash.slash")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(alias)
                                    .lineLimit(1)
                                Spacer()
                                Button("Restore") {
                                    model.restoreDeletedRemoteHost(alias: alias)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityIdentifier("restore-remote-\(alias)")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: embedded ? 560 : 680, minHeight: embedded ? 390 : 480)
        .sheet(item: $draft) { value in
            RemoteHostEditorView(draft: value) { saved, originalAlias in
                model.saveRemoteHost(saved, replacingAlias: originalAlias)
                draft = nil
            }
        }
        .sheet(isPresented: $isTmuxManagerPresented) {
            TmuxSessionManagerView(model: model)
        }
        .alert(
            "ApexTermから削除しますか？",
            isPresented: Binding(
                get: { pendingDeleteAlias != nil },
                set: { if !$0 { pendingDeleteAlias = nil } }
            ),
            presenting: pendingDeleteAlias
        ) { alias in
            Button("削除", role: .destructive) {
                performDelete(alias)
            }
            Button("キャンセル", role: .cancel) {
                pendingDeleteAlias = nil
            }
        } message: { alias in
            Text("\(alias)と関連WorkspaceをApexTermから削除します。~/.ssh/configは変更しません。")
        }
        .task {
            await runDeleteProbeIfRequested()
        }
    }

    private func performDelete(_ alias: String) {
        model.deleteRemoteHost(alias: alias)
        pendingDeleteAlias = nil
    }

    @MainActor
    private func runDeleteProbeIfRequested() async {
        guard !hasRunDeleteProbe else { return }
        let environment = ProcessInfo.processInfo.environment
        guard let alias = environment["APEXTERM_UI_DELETE_PROBE_ALIAS"],
              let outputPath = environment["APEXTERM_UI_DELETE_PROBE_FILE"],
              !alias.isEmpty,
              !outputPath.isEmpty else {
            return
        }
        hasRunDeleteProbe = true
        let existedBefore = model.remoteHostEntries.contains { $0.profile.alias == alias }
        pendingDeleteAlias = alias
        try? await Task.sleep(for: .milliseconds(120))
        performDelete(alias)
        try? await Task.sleep(for: .milliseconds(120))
        let entryRemoved = !model.remoteHostEntries.contains { $0.profile.alias == alias }
        let markedDeleted = model.deletedRemoteHostAliases.contains(alias)
        let workspaceRemoved = !model.workspaces.contains { $0.name == alias }
        let result = [
            "sheet=1",
            "existed_before=\(existedBefore ? 1 : 0)",
            "entry_removed=\(entryRemoved ? 1 : 0)",
            "marked_deleted=\(markedDeleted ? 1 : 0)",
            "workspace_removed=\(workspaceRemoved ? 1 : 0)"
        ].joined(separator: "\n") + "\n"
        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: outputPath),
            options: [.atomic]
        )
    }

    private var embeddedHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Remote Hosts")
                    .font(.headline)
                Text("Paste an ssh command or enter the fields manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                draft = RemoteHostDraft()
            } label: {
                Label("Add Host", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Remote Hosts")
                    .font(.title2.weight(.semibold))
                Text("ApexTerm内だけの表示・接続設定です。~/.ssh/configは変更しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                draft = RemoteHostDraft()
            } label: {
                Label("Add Host", systemImage: "plus")
            }
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func remoteHostRow(_ entry: RemoteHostEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isHidden ? "eye.slash" : "network")
                .foregroundStyle(entry.isHidden ? .secondary : .primary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.profile.displayTitle)
                        .font(.body.weight(.medium))
                    if entry.isCustom {
                        badge("CUSTOM", color: .secondary)
                    }
                    if entry.isHidden {
                        badge("HIDDEN", color: .orange)
                    }
                }
                Text(remoteDescription(entry.profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                model.createRemoteWorkspace(profile: entry.profile)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Open SSH tab")
            .disabled(entry.isHidden)
            .accessibilityIdentifier("connect-remote-\(entry.profile.alias)")

            Button {
                isTmuxManagerPresented = true
            } label: {
                Image(systemName: "rectangle.stack")
            }
            .buttonStyle(.borderless)
            .help("tmuxセッション管理")
            .disabled(entry.isHidden)

            Button {
                draft = RemoteHostDraft(entry: entry)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")
            .accessibilityIdentifier("edit-remote-\(entry.profile.alias)")

            Button {
                if entry.isHidden {
                    model.restoreRemoteHost(alias: entry.profile.alias)
                } else {
                    model.hideRemoteHost(alias: entry.profile.alias)
                }
            } label: {
                Image(systemName: entry.isHidden ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)
            .help(entry.isHidden ? "Show in ApexTerm" : "Hide from ApexTerm")
            .accessibilityIdentifier("toggle-remote-\(entry.profile.alias)")

            Button(role: .destructive) {
                pendingDeleteAlias = entry.profile.alias
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete from ApexTerm")
            .accessibilityIdentifier("delete-remote-\(entry.profile.alias)")
        }
        .padding(.vertical, 5)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    private func remoteDescription(_ profile: SSHHostProfile) -> String {
        let user = profile.user.map { "\($0)@" } ?? ""
        let host = profile.hostName ?? profile.alias
        let port = profile.port.map { ":\($0)" } ?? ""
        let destination = user + host + port
        return profile.displayTitle == profile.alias
            ? destination
            : "\(profile.alias) · \(destination)"
    }
}

private struct RemoteHostDraft: Identifiable {
    let id = UUID()
    var originalAlias: String?
    var displayName = ""
    var alias = ""
    var hostName = ""
    var user = ""
    var port = ""
    var identityFile = ""
    var sshCommand = ""

    init() {}

    init(entry: RemoteHostEntry) {
        originalAlias = entry.profile.alias
        displayName = entry.profile.displayName ?? ""
        alias = entry.profile.alias
        hostName = entry.profile.hostName ?? ""
        user = entry.profile.user ?? ""
        port = entry.profile.port.map(String.init) ?? ""
        identityFile = entry.profile.identityFile ?? ""
    }
}

private struct RemoteHostEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: RemoteHostDraft
    @State private var commandImportError: String?
    let onSave: (SSHHostProfile, String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Import SSH command") {
                    TextField(
                        "ssh -i /path/to/key.pem user@host",
                        text: $draft.sshCommand
                    )
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { importSSHCommand() }

                    HStack {
                        Button("Apply command") {
                            importSSHCommand()
                        }
                        .disabled(
                            draft.sshCommand.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                        if let commandImportError {
                            Text(commandImportError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("The command is parsed locally and is not executed here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Name and connection") {
                    TextField("Display name", text: $draft.displayName)
                    TextField("Connection ID / SSH alias", text: $draft.alias)
                    TextField("Host name / IP", text: $draft.hostName)
                    TextField("User", text: $draft.user)
                    TextField("Port", text: $draft.port)
                    if !isPortValid {
                        Label("Port must be a number from 1 to 65535.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    TextField("Identity file", text: $draft.identityFile)
                    if let identityFileWarning {
                        Label(identityFileWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    let profile = SSHHostProfile(
                        alias: draft.alias,
                        displayName: nilIfBlank(draft.displayName),
                        hostName: nilIfBlank(draft.hostName),
                        user: nilIfBlank(draft.user),
                        port: parsedPort,
                        identityFile: nilIfBlank(draft.identityFile)
                    )
                    onSave(profile, draft.originalAlias)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    draft.alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !isPortValid
                )
            }
            .padding(16)
        }
        .frame(width: 560, height: 470)
    }

    private var parsedPort: Int? {
        let value = draft.port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let port = Int(value),
              (1...65_535).contains(port) else {
            return nil
        }
        return port
    }

    private var isPortValid: Bool {
        draft.port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || parsedPort != nil
    }

    private var identityFileWarning: String? {
        let value = draft.identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let expanded = NSString(string: value).expandingTildeInPath
        guard !FileManager.default.isReadableFile(atPath: expanded) else { return nil }
        return "Identity file is missing or unreadable on this Mac. SSH will show a warning until the path is fixed."
    }

    private func importSSHCommand() {
        do {
            let profile = try SSHCommandParser.parse(
                draft.sshCommand,
                alias: draft.alias
            )
            draft.alias = profile.alias
            draft.hostName = profile.hostName ?? ""
            draft.user = profile.user ?? ""
            draft.port = profile.port.map(String.init) ?? ""
            draft.identityFile = profile.identityFile ?? ""
            commandImportError = nil
        } catch {
            commandImportError = error.localizedDescription
        }
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
