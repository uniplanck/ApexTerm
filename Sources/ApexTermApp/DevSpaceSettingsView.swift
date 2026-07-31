import SwiftUI

struct DevSpaceSettingsView: View {
    private let repositoryURL = URL(
        string: "https://github.com/uniplanck/devspace"
    )!

    var body: some View {
        Form {
            Section("Optional DevSpace Companion") {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect ChatGPT to approved local projects")
                            .font(.headline)
                        Text("DevSpace is a separate self-hosted MCP server. ApexTerm works normally without it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .font(.title2)
                }

                Link(destination: repositoryURL) {
                    Label(
                        "Open uniplanck/devspace on GitHub",
                        systemImage: "arrow.up.right.square"
                    )
                }

                Text("Install DevSpace from the repository above, then follow its setup guide to connect ChatGPT. Only grant access to folders you intentionally expose.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What remains independent") {
                Text("Terminal tabs, split panes, command history, tmux, remote hosts, and keyboard shortcuts do not require DevSpace.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }
}
