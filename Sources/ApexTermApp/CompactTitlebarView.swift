import AppKit
import SwiftUI

@MainActor
final class CompactTitlebarContentStore: ObservableObject {
    @Published private(set) var content = AnyView(EmptyView())

    func update(content: AnyView) {
        self.content = content
    }
}

struct CompactTitlebarContentView: View {
    @ObservedObject var store: CompactTitlebarContentStore

    var body: some View {
        store.content
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
    }
}

struct CompactTitlebarDragRegion: NSViewRepresentable {
    static let identifier = NSUserInterfaceItemIdentifier(
        "ApexTerm.CompactTitlebarDragRegion"
    )

    func makeNSView(context: Context) -> CompactTitlebarDragView {
        CompactTitlebarDragView()
    }

    func updateNSView(_ nsView: CompactTitlebarDragView, context: Context) {}
}

@MainActor
final class CompactTitlebarDragView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = CompactTitlebarDragRegion.identifier
        setAccessibilityIdentifier(CompactTitlebarDragRegion.identifier.rawValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
