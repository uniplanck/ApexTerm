import ApexTermCore
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct TerminalDragPayload: Codable, Equatable, Hashable, Transferable {
    enum Kind: String, Codable, Hashable {
        case workspace
        case workspacePane
        case agentChat
        case quickTerminalTab
    }

    let kind: Kind
    let id: UUID

    var mainTabReference: MainTabReference? {
        switch kind {
        case .workspace:
            .workspace(id)
        case .agentChat:
            .agentChat(id)
        case .workspacePane, .quickTerminalTab:
            nil
        }
    }

    var workspacePaneSessionID: UUID? {
        kind == .workspacePane ? id : nil
    }

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.apexTermTerminalTab.identifier,
            visibility: .all
        ) { completion in
            do {
                completion(try JSONEncoder().encode(self), nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        return provider
    }

    static func load(
        from provider: NSItemProvider,
        completion: @escaping @Sendable (TerminalDragPayload?) -> Void
    ) {
        provider.loadDataRepresentation(
            forTypeIdentifier: UTType.apexTermTerminalTab.identifier
        ) { data, _ in
            let payload = data.flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
            completion(payload)
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .apexTermTerminalTab)
    }
}

extension UTType {
    static let apexTermTerminalTab = UTType(
        exportedAs: "com.uniplanck.apexterm.terminal-tab"
    )
}
