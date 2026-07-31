import AppKit
import SwiftUI

struct NewTabButton: NSViewRepresentable {
    let onCreateLocalShell: () -> Void
    let onOpenNamedTmux: () -> Void
    let onCreateLocalAgentChat: () -> Void
    let onCreateRemoteAgentChat: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCreateLocalShell: onCreateLocalShell,
            onOpenNamedTmux: onOpenNamedTmux,
            onCreateLocalAgentChat: onCreateLocalAgentChat,
            onCreateRemoteAgentChat: onCreateRemoteAgentChat
        )
    }

    func makeNSView(context: Context) -> NewTabNSButton {
        let button = NewTabNSButton(frame: .zero)
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "New Local Shell"
        )
        button.toolTip = "New Local Shell"
        button.target = context.coordinator
        button.action = #selector(Coordinator.createLocalShell)
        button.identifier = NSUserInterfaceItemIdentifier("new-local-shell-button")
        button.setAccessibilityIdentifier("new-local-shell-button")
        button.setAccessibilityLabel("New Local Shell")
        button.contextMenuProvider = { [weak coordinator = context.coordinator] in
            coordinator?.makeContextMenu()
        }
        return button
    }

    func updateNSView(_ button: NewTabNSButton, context: Context) {
        context.coordinator.onCreateLocalShell = onCreateLocalShell
        context.coordinator.onOpenNamedTmux = onOpenNamedTmux
        context.coordinator.onCreateLocalAgentChat = onCreateLocalAgentChat
        context.coordinator.onCreateRemoteAgentChat = onCreateRemoteAgentChat
        button.target = context.coordinator
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NewTabNSButton,
        context: Context
    ) -> CGSize? {
        CGSize(width: 32, height: 32)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onCreateLocalShell: () -> Void
        var onOpenNamedTmux: () -> Void
        var onCreateLocalAgentChat: () -> Void
        var onCreateRemoteAgentChat: () -> Void

        init(
            onCreateLocalShell: @escaping () -> Void,
            onOpenNamedTmux: @escaping () -> Void,
            onCreateLocalAgentChat: @escaping () -> Void,
            onCreateRemoteAgentChat: @escaping () -> Void
        ) {
            self.onCreateLocalShell = onCreateLocalShell
            self.onOpenNamedTmux = onOpenNamedTmux
            self.onCreateLocalAgentChat = onCreateLocalAgentChat
            self.onCreateRemoteAgentChat = onCreateRemoteAgentChat
        }

        @objc func createLocalShell() {
            onCreateLocalShell()
        }

        @objc private func openNamedTmux() {
            onOpenNamedTmux()
        }

        @objc private func createLocalAgentChat() {
            onCreateLocalAgentChat()
        }

        @objc private func createRemoteAgentChat() {
            onCreateRemoteAgentChat()
        }

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(menuItem(
                title: "New Local Shell",
                action: #selector(createLocalShell)
            ))
            menu.addItem(menuItem(
                title: "Open Named tmux Session…",
                action: #selector(openNamedTmux)
            ))
            menu.addItem(.separator())
            menu.addItem(menuItem(
                title: "New Agent Chat — Local",
                action: #selector(createLocalAgentChat)
            ))
            menu.addItem(menuItem(
                title: "New Agent Chat — Remote",
                action: #selector(createRemoteAgentChat)
            ))

            return menu
        }

        private func menuItem(title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = true
            return item
        }
    }
}

final class NewTabNSButton: NSButton {
    var contextMenuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?()
    }
}
