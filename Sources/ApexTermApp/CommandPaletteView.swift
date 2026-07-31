import ApexTermCore
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private let registry = ApexActionRegistry()

    private var results: [ApexActionDescriptor] {
        registry.search(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("Search actions", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit {
                        guard let first = results.first else { return }
                        model.performAction(id: first.id)
                    }
                Text("⌘⇧P")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)

            Divider()

            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { action in
                            Button {
                                model.performAction(id: action.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: action.systemImage)
                                        .frame(width: 24)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(action.title)
                                            .font(.system(size: 14, weight: .medium))
                                        Text(action.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(action.id)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 54)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(action.title)
                            .accessibilityHint(action.subtitle)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 640, height: 440)
        .onAppear {
            isSearchFocused = true
        }
    }
}
