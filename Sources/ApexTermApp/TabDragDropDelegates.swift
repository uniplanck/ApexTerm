import AppKit
import ApexTermCore
import SwiftUI
import UniformTypeIdentifiers

enum MainTabDropIntent: Equatable {
    case before
    case merge
    case after

    static func resolve(
        locationX: CGFloat,
        width: CGFloat,
        allowsMerge: Bool
    ) -> MainTabDropIntent {
        let normalizedWidth = max(1, width)
        let fraction = min(max(0, locationX / normalizedWidth), 1)
        if fraction < 0.24 { return .before }
        if fraction > 0.76 { return .after }
        return allowsMerge ? .merge : (fraction < 0.5 ? .before : .after)
    }
}

struct MainTabDropIndicator: Equatable {
    let target: MainTabReference
    let intent: MainTabDropIntent
}

struct MainTabDropDelegate: DropDelegate {
    let target: MainTabReference
    let width: CGFloat
    let allowsMerge: Bool
    @Binding var indicator: MainTabDropIndicator?
    let onHover: (MainTabReference) -> Void
    let onExit: () -> Void
    let onPayload: @MainActor @Sendable (TerminalDragPayload, MainTabReference, MainTabDropIntent) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.apexTermTerminalTab])
    }

    func dropEntered(info: DropInfo) {
        updateIndicator(location: info.location)
        onHover(target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateIndicator(location: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if indicator?.target == target {
            indicator = nil
        }
        onExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        let intent = resolvedIntent(location: info.location)
        indicator = nil
        onExit()
        guard let provider = info.itemProviders(for: [.apexTermTerminalTab]).first else {
            return false
        }
        TerminalDragPayload.load(from: provider) { payload in
            guard let payload else { return }
            Task { @MainActor in
                onPayload(payload, target, intent)
            }
        }
        return true
    }

    private func updateIndicator(location: CGPoint) {
        indicator = MainTabDropIndicator(
            target: target,
            intent: resolvedIntent(location: location)
        )
    }

    private func resolvedIntent(location: CGPoint) -> MainTabDropIntent {
        MainTabDropIntent.resolve(
            locationX: location.x,
            width: width,
            allowsMerge: allowsMerge
        )
    }
}

struct TerminalTabDropIndicator: Equatable {
    let targetSessionID: UUID
    let after: Bool
}

struct TerminalTabDropDelegate: DropDelegate {
    let targetSessionID: UUID
    let width: CGFloat
    @Binding var indicator: TerminalTabDropIndicator?
    let onPayload: @MainActor @Sendable (TerminalDragPayload, UUID, Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.apexTermTerminalTab])
    }

    func dropEntered(info: DropInfo) {
        updateIndicator(location: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateIndicator(location: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if indicator?.targetSessionID == targetSessionID {
            indicator = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let after = info.location.x >= max(1, width) / 2
        indicator = nil
        guard let provider = info.itemProviders(for: [.apexTermTerminalTab]).first else {
            return false
        }
        TerminalDragPayload.load(from: provider) { payload in
            guard let payload else { return }
            Task { @MainActor in
                onPayload(payload, targetSessionID, after)
            }
        }
        return true
    }

    private func updateIndicator(location: CGPoint) {
        indicator = TerminalTabDropIndicator(
            targetSessionID: targetSessionID,
            after: location.x >= max(1, width) / 2
        )
    }
}

struct WorkspacePaneDropDelegate: DropDelegate {
    let size: CGSize
    @Binding var region: TerminalDropRegion?
    let onPayload: @MainActor @Sendable (TerminalDragPayload, TerminalDropRegion) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.apexTermTerminalTab])
    }

    func dropEntered(info: DropInfo) {
        updateRegion(location: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateRegion(location: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        region = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let resolved = TerminalDropRegion.resolve(location: info.location, size: size)
        region = nil
        guard let provider = info.itemProviders(for: [.apexTermTerminalTab]).first else {
            return false
        }
        TerminalDragPayload.load(from: provider) { payload in
            guard let payload else { return }
            Task { @MainActor in
                onPayload(payload, resolved)
            }
        }
        return true
    }

    private func updateRegion(location: CGPoint) {
        region = TerminalDropRegion.resolve(location: location, size: size)
    }
}
