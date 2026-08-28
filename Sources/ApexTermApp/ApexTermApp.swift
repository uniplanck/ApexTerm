import ApexTermCore
import AppKit
import SwiftUI

@main
struct ApexTermApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var appLifecycle
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("ApexTerm") {
            RootView(model: model)
                .preferredColorScheme(model.interfaceAppearance.colorScheme)
                .tint(Color(nsColor: model.interfaceAccentNSColor))
                .frame(
                    minWidth: ApexTermWindowSizing.mainMinimumContentSize.width,
                    minHeight: ApexTermWindowSizing.mainMinimumContentSize.height
                )
                .onOpenURL { url in
                    if url.isFileURL {
                        _ = model.openProjects(from: [url])
                    } else {
                        model.handleExternalURL(url)
                    }
                }
        }
        .defaultSize(
            width: ApexTermWindowSizing.mainDefaultContentSize.width,
            height: ApexTermWindowSizing.mainDefaultContentSize.height
        )
        .windowResizability(.automatic)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Workspace") {
                    model.performAction(id: "workspace.new")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "workspace.new"))

                Button("New Agent Chat") {
                    model.performAction(id: "agent.new.local")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "agent.new.local"))

                Divider()

                Button("Universal Search") {
                    model.performAction(id: "search.universal")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "search.universal"))

                Button("Command Palette") {
                    model.performAction(id: "command.palette")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "command.palette"))

                Button("Quick Terminal") {
                    model.performAction(id: "terminal.quick")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "terminal.quick"))

                Button("Command Timeline") {
                    model.performAction(id: "history.timeline")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "history.timeline"))

                Button("Search Command History") {
                    model.performAction(id: "history.search")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "history.search"))

                Button("Toggle Command History") {
                    model.performAction(id: "history.toggle")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "history.toggle"))
            }

            CommandMenu("Tabs") {
                Button("Next Tab") {
                    model.performAction(id: "tab.next")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "tab.next"))

                Button("Previous Tab") {
                    model.performAction(id: "tab.previous")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "tab.previous"))

                Divider()

                Button("Next Terminal Tab") {
                    model.performAction(id: "terminal.tab.next")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "terminal.tab.next"))

                Button("Previous Terminal Tab") {
                    model.performAction(id: "terminal.tab.previous")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "terminal.tab.previous"))

                Divider()

                Button("Move Current Tab Left") {
                    model.performAction(id: "tab.moveLeft")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "tab.moveLeft"))

                Button("Move Current Tab Right") {
                    model.performAction(id: "tab.moveRight")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "tab.moveRight"))

                Divider()

                ForEach(1...9, id: \.self) { number in
                    Button("Select Tab \(number)") {
                        model.performAction(id: "tab.select.\(number)")
                    }
                    .apexKeyboardShortcut(
                        model.keybindingChord(for: "tab.select.\(number)")
                    )
                }
            }

            CommandMenu("Pane") {
                Button("Split Left / Right") {
                    model.performAction(id: "pane.split.vertical")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "pane.split.vertical"))

                Button("Split Top / Bottom") {
                    model.performAction(id: "pane.split.horizontal")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "pane.split.horizontal"))

                Button("Close Selected Pane") {
                    model.performAction(id: "pane.close")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "pane.close"))

                Divider()

                Button(model.maximizedSessionID == nil ? "Maximize Selected Pane" : "Restore Pane Layout") {
                    model.performAction(id: "pane.maximize")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "pane.maximize"))

                Button("Focus Next Pane") {
                    model.performAction(id: "pane.next")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "pane.next"))

                Button("Focus Previous Pane") {
                    model.performAction(id: "pane.previous")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "pane.previous"))

                Divider()

                ForEach(1...4, id: \.self) { number in
                    Button("Focus Pane \(number)") {
                        model.performAction(id: "pane.select.\(number)")
                    }
                    .apexKeyboardShortcut(
                        model.keybindingChord(for: "pane.select.\(number)")
                    )
                }
            }

            CommandGroup(after: .textEditing) {
                Button("Find in Terminal") {
                    model.performAction(id: "terminal.find")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "terminal.find"))

                Button("Copy Latest Output") {
                    model.performAction(id: "terminal.latestOutput.copy")
                }
                .apexKeyboardShortcut(
                    model.keybindingChord(for: "terminal.latestOutput.copy")
                )

                Button("Send in C Mode") {
                    model.performAction(id: "terminal.conversation.send")
                }
                .apexKeyboardShortcut(
                    model.keybindingChord(
                        for: "terminal.conversation.send",
                        scope: .terminal
                    )
                )

                Button("Cycle Transcript Mode") {
                    model.performAction(id: "terminal.transcript.cycle")
                }
                .apexKeyboardShortcut(
                    model.keybindingChord(for: "terminal.transcript.cycle")
                )

                Divider()

                Button(model.secureKeyboardEntryEnabled ? "Disable Secure Keyboard Entry" : "Enable Secure Keyboard Entry") {
                    model.performAction(id: "terminal.secureInput.toggle")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "terminal.secureInput.toggle"))
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Left Sidebar") {
                    model.performAction(id: "sidebar.toggleLeft")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "sidebar.toggleLeft"))

                Button("Toggle Right Sidebar") {
                    model.performAction(id: "sidebar.toggleRight")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "sidebar.toggleRight"))

                Divider()

                Button("Toggle Agent Rail") {
                    model.performAction(id: "agent.toggleRail")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "agent.toggleRail"))

                Button(model.isCompactMode ? "Exit Compact Terminal Mode" : "Compact Terminal Mode") {
                    model.performAction(id: "terminal.compact.toggle")
                }
                .apexKeyboardShortcut(model.keybindingChord(for: "terminal.compact.toggle"))
            }
        }

        Window("Quick Terminal", id: "quick-terminal") {
            QuickTerminalView()
                .preferredColorScheme(model.interfaceAppearance.colorScheme)
                .tint(Color(nsColor: model.interfaceAccentNSColor))
        }
        .defaultSize(width: 680, height: 340)
        .windowResizability(.automatic)
    }
}

private extension ApexInterfaceAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
