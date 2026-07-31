import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResolve: onResolve)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(onResolve: onResolve)
        context.coordinator.scheduleResolve(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(onResolve: onResolve)
        context.coordinator.scheduleResolve(for: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.cancelPendingResolve()
    }

    @MainActor
    final class Coordinator {
        private var onResolve: (NSWindow?) -> Void
        private var pendingResolve: Task<Void, Never>?

        init(onResolve: @escaping (NSWindow?) -> Void) {
            self.onResolve = onResolve
        }

        func update(onResolve: @escaping (NSWindow?) -> Void) {
            self.onResolve = onResolve
        }

        func scheduleResolve(for view: NSView) {
            pendingResolve?.cancel()
            pendingResolve = Task { @MainActor [weak self, weak view] in
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.pendingResolve = nil
                self.onResolve(view?.window)
            }
        }

        func cancelPendingResolve() {
            pendingResolve?.cancel()
            pendingResolve = nil
        }
    }
}

enum ApexTermWindowRole {
    static let main = NSUserInterfaceItemIdentifier("ApexTerm.MainWindow")
    static let quickTerminal = NSUserInterfaceItemIdentifier("ApexTerm.QuickTerminal")
}

enum WindowPinController {
    @MainActor
    static func apply(pinned: Bool, to window: NSWindow?) {
        guard let window else { return }
        window.level = pinned ? .floating : .normal
        if pinned {
            window.collectionBehavior.insert(.canJoinAllSpaces)
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
        }
    }
}
