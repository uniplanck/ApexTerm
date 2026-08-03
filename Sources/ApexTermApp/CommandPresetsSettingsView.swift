import ApexTermCore
import SwiftUI

struct CommandPresetsSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var editor: CommandPresetEditor?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("定型コマンド")
                        .font(.headline)
                    Text("各Paneの稲妻ボタンから、選択中のTerminalへ即時送信します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editor = CommandPresetEditor(
                        id: UUID(),
                        name: "",
                        command: "",
                        isNew: true
                    )
                } label: {
                    Label("追加", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            .padding(16)

            Divider()

            if model.commandPresets.isEmpty {
                ContentUnavailableView(
                    "定型コマンドはありません",
                    systemImage: "bolt.horizontal.circle",
                    description: Text("よく使うコマンドを追加すると、Paneヘッダーからすぐ送信できます。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(model.commandPresets.enumerated()), id: \.element.id) { index, preset in
                        commandRow(preset, index: index)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $editor) { editor in
            CommandPresetEditorView(editor: editor) { saved in
                model.saveCommandPreset(
                    id: saved.id,
                    name: saved.name,
                    command: saved.command
                )
            }
        }
    }

    private func commandRow(
        _ preset: TerminalCommandPreset,
        index: Int
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(preset.command)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            HStack(spacing: 5) {
                Button {
                    model.moveCommandPreset(id: preset.id, offset: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help("上へ移動")

                Button {
                    model.moveCommandPreset(id: preset.id, offset: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == model.commandPresets.count - 1)
                .help("下へ移動")

                Button {
                    editor = CommandPresetEditor(
                        id: preset.id,
                        name: preset.name,
                        command: preset.command,
                        isNew: false
                    )
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("編集")

                Button(role: .destructive) {
                    model.deleteCommandPreset(id: preset.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("削除")
            }
        }
        .padding(.vertical, 7)
        .contextMenu {
            Button("編集…") {
                editor = CommandPresetEditor(
                    id: preset.id,
                    name: preset.name,
                    command: preset.command,
                    isNew: false
                )
            }
            Divider()
            Button("削除", role: .destructive) {
                model.deleteCommandPreset(id: preset.id)
            }
        }
    }
}

private struct CommandPresetEditor: Identifiable {
    let id: UUID
    var name: String
    var command: String
    var isNew: Bool
}

private struct CommandPresetEditorView: View {
    let editor: CommandPresetEditor
    let onSave: (CommandPresetEditor) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var command: String

    init(
        editor: CommandPresetEditor,
        onSave: @escaping (CommandPresetEditor) -> Void
    ) {
        self.editor = editor
        self.onSave = onSave
        _name = State(initialValue: editor.name)
        _command = State(initialValue: editor.command)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editor.isNew ? "定型コマンドを追加" : "定型コマンドを編集")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 5) {
                Text("表示名")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("例: AWSボリューム状態", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("送信するコマンド")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $command)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 160)
                    .padding(5)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                    }
                Text("選択すると改行付きで送信され、そのまま実行されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("キャンセル", role: .cancel) {
                    dismiss()
                }
                Button("保存") {
                    onSave(CommandPresetEditor(
                        id: editor.id,
                        name: name,
                        command: command,
                        isNew: editor.isNew
                    ))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 540)
    }
}
