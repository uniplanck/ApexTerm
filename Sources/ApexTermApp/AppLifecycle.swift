import AppKit

enum ApexTermWindowSizing {
    static let mainMinimumContentSize = NSSize(width: 320, height: 250)
    static let mainDefaultContentSize = NSSize(width: 1_280, height: 780)
}

extension Notification.Name {
    static let apexTermExternalFoldersRequested = Notification.Name("ApexTermExternalFoldersRequested")
}

@MainActor
final class ApexTermExternalOpenCoordinator {
    static let shared = ApexTermExternalOpenCoordinator()
    private var pendingURLs: [URL] = []

    func enqueue(_ urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
        NotificationCenter.default.post(name: .apexTermExternalFoldersRequested, object: nil)
    }

    func drain() -> [URL] {
        let values = pendingURLs
        pendingURLs.removeAll()
        return values
    }
}

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        activateMainWindow()
    }


    func applicationWillTerminate(_ notification: Notification) {
        TerminalPaneRuntimeStore.shared.shutdownAll()
        SecureKeyboardEntryController.shared.disableIfOwned()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handleExternalOpen(urls, in: application)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        handleExternalOpen(filenames.map { URL(fileURLWithPath: $0) }, in: sender)
        sender.reply(toOpenOrPrint: .success)
    }

    private func handleExternalOpen(_ urls: [URL], in application: NSApplication) {
        ApexTermExternalOpenCoordinator.shared.enqueue(urls)
        mainWindow(in: application)?.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            mainWindow(in: sender)?.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    private func activateMainWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.mainWindow(in: NSApp)?.makeKeyAndOrderFront(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.runWindowProbeIfRequested()
            }
        }
    }

    private func mainWindow(in application: NSApplication) -> NSWindow? {
        application.windows.first { $0.identifier == ApexTermWindowRole.main }
            ?? application.windows.first { window in
                window.identifier != ApexTermWindowRole.quickTerminal && window.canBecomeKey
            }
    }

    private func runWindowProbeIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_WINDOW_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        guard let window = mainWindow(in: NSApp) else {
            try? Data("window=missing\n".utf8).write(
                to: URL(fileURLWithPath: outputPath),
                options: [.atomic]
            )
            return
        }

        let isResizable = window.styleMask.contains(.resizable)
        let requestedMinimum = ApexTermWindowSizing.mainMinimumContentSize
        let configuredMinimum = window.contentMinSize
        window.setContentSize(requestedMinimum)
        let minimumSize = window.contentView?.bounds.size ?? .zero
        window.setContentSize(NSSize(width: 640, height: 480))
        let compactSize = window.contentView?.bounds.size ?? .zero
        window.setContentSize(ApexTermWindowSizing.mainDefaultContentSize)
        let expandedSize = window.contentView?.bounds.size ?? .zero

        let result = [
            "resizable=\(isResizable ? 1 : 0)",
            "requested_minimum=\(Int(requestedMinimum.width))x\(Int(requestedMinimum.height))",
            "configured_minimum=\(Int(configuredMinimum.width))x\(Int(configuredMinimum.height))",
            "minimum=\(Int(minimumSize.width))x\(Int(minimumSize.height))",
            "compact=\(Int(compactSize.width))x\(Int(compactSize.height))",
            "expanded=\(Int(expandedSize.width))x\(Int(expandedSize.height))"
        ].joined(separator: "\n") + "\n"

        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: outputPath),
            options: [.atomic]
        )

        if environment["APEXTERM_WINDOW_PROBE_EXIT"] == "1" {
            NSApp.terminate(nil)
        }
    }
}
