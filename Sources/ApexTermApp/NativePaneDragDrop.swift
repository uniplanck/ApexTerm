import AppKit
import ApexTermCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private enum NativePaneDragState {
    static var activeSessionID: UUID?
}

private struct NativePaneProbeRect: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

private struct NativePaneProbeDocument: Codable {
    var handles: [String: NativePaneProbeRect] = [:]
    var targets: [String: NativePaneProbeRect] = [:]
    var events: [String] = []
}

@MainActor
private enum NativePaneDragProbe {
    private static var document = NativePaneProbeDocument()
    private static let fileURL = ProcessInfo.processInfo.environment[
        "APEXTERM_NATIVE_PANE_DRAG_PROBE_FILE"
    ].flatMap { value in
        value.isEmpty ? nil : URL(fileURLWithPath: value)
    }

    static func recordHandle(_ view: NSView, sessionID: UUID) {
        guard let rect = screenRect(for: view) else { return }
        document.handles[sessionID.uuidString] = rect
        flush()
    }

    static func recordTarget(_ view: NSView, sessionID: UUID) {
        guard let rect = screenRect(for: view) else { return }
        document.targets[sessionID.uuidString] = rect
        flush()
    }

    static func recordEvent(_ event: String) {
        guard fileURL != nil else { return }
        if event.hasPrefix("region:"), document.events.last == event {
            return
        }
        document.events.append(event)
        if document.events.count > 40 {
            document.events.removeFirst(document.events.count - 40)
        }
        flush()
    }

    private static func screenRect(for view: NSView) -> NativePaneProbeRect? {
        guard fileURL != nil, let window = view.window else { return nil }
        let windowRect = view.convert(view.bounds, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(screenRect) })
            ?? NSScreen.main
        guard let screen else { return nil }
        return NativePaneProbeRect(
            x: screenRect.minX,
            y: screen.frame.maxY - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    private static func flush() {
        guard let fileURL,
              let data = try? JSONEncoder().encode(document) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct NativeTerminalTabProbe: NSViewRepresentable {
    let sessionID: UUID

    func makeNSView(context: Context) -> NativeTerminalTabProbeView {
        let view = NativeTerminalTabProbeView()
        view.sessionID = sessionID
        return view
    }

    func updateNSView(_ nsView: NativeTerminalTabProbeView, context: Context) {
        nsView.sessionID = sessionID
        nsView.recordFrame()
    }
}

@MainActor
final class NativeTerminalTabProbeView: NSView {
    var sessionID = UUID()
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        recordFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        recordFrame()
    }

    func recordFrame() {
        NativePaneDragProbe.recordHandle(self, sessionID: sessionID)
    }
}

struct NativePaneDragHandle: NSViewRepresentable {
    let sessionID: UUID
    let title: String
    let onSelect: @MainActor () -> Void
    let onRename: @MainActor () -> Void

    func makeNSView(context: Context) -> NativePaneDragHandleView {
        let view = NativePaneDragHandleView()
        view.configure(
            sessionID: sessionID,
            title: title,
            onSelect: onSelect,
            onRename: onRename
        )
        return view
    }

    func updateNSView(_ nsView: NativePaneDragHandleView, context: Context) {
        nsView.configure(
            sessionID: sessionID,
            title: title,
            onSelect: onSelect,
            onRename: onRename
        )
    }
}

@MainActor
final class NativePaneDragHandleView: NSView, NSDraggingSource {
    private var sessionID = UUID()
    private var paneTitle = "01"
    private var onSelect: @MainActor () -> Void = {}
    private var onRename: @MainActor () -> Void = {}
    private var mouseDownPoint: NSPoint?
    private var activeDraggingSession: NSDraggingSession?
    private var draggedSessionID: UUID?
    private var hasDraggedDuringCurrentMouseDown = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        sessionID: UUID,
        title: String,
        onSelect: @escaping @MainActor () -> Void,
        onRename: @escaping @MainActor () -> Void
    ) {
        self.sessionID = sessionID
        paneTitle = title
        self.onSelect = onSelect
        self.onRename = onRename
        setAccessibilityLabel("\(title) pane drag handle")
        setAccessibilityIdentifier("native-pane-drag-handle-\(sessionID.uuidString)")
        toolTip = "Drag this pane into another pane"
    }

    override func layout() {
        super.layout()
        NativePaneDragProbe.recordHandle(self, sessionID: sessionID)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NativePaneDragProbe.recordHandle(self, sessionID: sessionID)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        hasDraggedDuringCurrentMouseDown = false
        draggedSessionID = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard activeDraggingSession == nil,
              !hasDraggedDuringCurrentMouseDown,
              let mouseDownPoint else {
            return
        }

        let currentPoint = convert(event.locationInWindow, from: nil)
        guard hypot(currentPoint.x - mouseDownPoint.x, currentPoint.y - mouseDownPoint.y) >= 4 else {
            return
        }

        let sourceSessionID = sessionID
        hasDraggedDuringCurrentMouseDown = true
        draggedSessionID = sourceSessionID
        onSelect()
        NativePaneDragState.activeSessionID = sourceSessionID
        NativePaneDragProbe.recordEvent("drag-start:\(sourceSessionID.uuidString)")

        let payload = TerminalDragPayload(kind: .workspacePane, id: sourceSessionID)
        guard let data = try? JSONEncoder().encode(payload) else {
            NativePaneDragState.activeSessionID = nil
            return
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(
            data,
            forType: NSPasteboard.PasteboardType(UTType.apexTermTerminalTab.identifier)
        )

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = dragImage(title: paneTitle)
        draggingItem.setDraggingFrame(
            NSRect(
                x: currentPoint.x - 18,
                y: currentPoint.y - image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ),
            contents: image
        )

        activeDraggingSession = beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
    }

    override func mouseUp(with event: NSEvent) {
        if !hasDraggedDuringCurrentMouseDown {
            if event.clickCount >= 2 {
                onRename()
            } else {
                onSelect()
            }
        }
        activeDraggingSession = nil
        draggedSessionID = nil
        hasDraggedDuringCurrentMouseDown = false
        mouseDownPoint = nil
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        activeDraggingSession = nil
        mouseDownPoint = nil
        let sourceSessionID = draggedSessionID ?? NativePaneDragState.activeSessionID ?? sessionID
        NativePaneDragProbe.recordEvent(
            "drag-end:\(sourceSessionID.uuidString):\(operation.rawValue)"
        )
        if NativePaneDragState.activeSessionID == sourceSessionID {
            NativePaneDragState.activeSessionID = nil
        }
    }

    private func dragImage(title: String) -> NSImage {
        let size = NSSize(width: 246, height: 42)
        return NSImage(size: size, flipped: true) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()

            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
            border.lineWidth = 1.5
            border.stroke()

            let symbol = NSImage(systemSymbolName: "rectangle.on.rectangle.angled", accessibilityDescription: nil)
            symbol?.draw(
                in: NSRect(x: 12, y: 11, width: 20, height: 20),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            NSString(string: title).draw(
                in: NSRect(x: 42, y: 7, width: 190, height: 28),
                withAttributes: attributes
            )
            return true
        }
    }
}

struct NativePaneDropTarget: NSViewRepresentable {
    let targetSessionID: UUID
    let allowsSelfEdgeDrop: Bool
    let onRegionChange: @MainActor (TerminalDropRegion?) -> Void
    let onDrop: @MainActor (TerminalDragPayload, TerminalDropRegion) -> Void

    func makeNSView(context: Context) -> NativePaneDropTargetView {
        let view = NativePaneDropTargetView()
        view.configure(
            targetSessionID: targetSessionID,
            allowsSelfEdgeDrop: allowsSelfEdgeDrop,
            onRegionChange: onRegionChange,
            onDrop: onDrop
        )
        return view
    }

    func updateNSView(_ nsView: NativePaneDropTargetView, context: Context) {
        nsView.configure(
            targetSessionID: targetSessionID,
            allowsSelfEdgeDrop: allowsSelfEdgeDrop,
            onRegionChange: onRegionChange,
            onDrop: onDrop
        )
    }
}

@MainActor
final class NativePaneDropTargetView: NSView {
    private var targetSessionID = UUID()
    private var allowsSelfEdgeDrop = false
    private var onRegionChange: @MainActor (TerminalDropRegion?) -> Void = { _ in }
    private var onDrop: @MainActor (TerminalDragPayload, TerminalDropRegion) -> Void = { _, _ in }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(UTType.apexTermTerminalTab.identifier)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        targetSessionID: UUID,
        allowsSelfEdgeDrop: Bool,
        onRegionChange: @escaping @MainActor (TerminalDropRegion?) -> Void,
        onDrop: @escaping @MainActor (TerminalDragPayload, TerminalDropRegion) -> Void
    ) {
        self.targetSessionID = targetSessionID
        self.allowsSelfEdgeDrop = allowsSelfEdgeDrop
        self.onRegionChange = onRegionChange
        self.onDrop = onDrop
        NativePaneDragProbe.recordTarget(self, sessionID: targetSessionID)
        setAccessibilityLabel("Pane drop target")
        setAccessibilityIdentifier("native-pane-drop-target-\(targetSessionID.uuidString)")
    }

    override func layout() {
        super.layout()
        NativePaneDragProbe.recordTarget(self, sessionID: targetSessionID)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NativePaneDragProbe.recordTarget(self, sessionID: targetSessionID)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sourceSessionID = NativePaneDragState.activeSessionID,
              bounds.contains(point) else {
            return nil
        }
        if sourceSessionID == targetSessionID && !allowsSelfEdgeDrop {
            return nil
        }
        return self
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateRegion(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateRegion(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onRegionChange(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let sourceSessionID = decodedPayload(from: sender)?.workspacePaneSessionID else {
            return false
        }
        guard sourceSessionID == targetSessionID else { return true }
        return allowsSelfEdgeDrop && resolvedRegion(for: sender) != .center
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let payload = decodedPayload(from: sender),
              let sourceSessionID = payload.workspacePaneSessionID else {
            onRegionChange(nil)
            return false
        }

        let region = resolvedRegion(for: sender)
        if sourceSessionID == targetSessionID
            && (!allowsSelfEdgeDrop || region == .center) {
            onRegionChange(nil)
            return false
        }
        let sourceID = payload.workspacePaneSessionID?.uuidString ?? "unknown"
        NativePaneDragProbe.recordEvent(
            "drop:\(sourceID):\(targetSessionID.uuidString):\(region.rawValue)"
        )
        onDrop(payload, region)
        onRegionChange(nil)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onRegionChange(nil)
    }

    private func updateRegion(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let payload = decodedPayload(from: sender),
              let sourceSessionID = payload.workspacePaneSessionID else {
            onRegionChange(nil)
            return []
        }
        let region = resolvedRegion(for: sender)
        if sourceSessionID == targetSessionID {
            guard allowsSelfEdgeDrop else {
                onRegionChange(nil)
                return []
            }
            if region == .center {
                onRegionChange(nil)
                return .move
            }
        }
        NativePaneDragProbe.recordEvent(
            "region:\(targetSessionID.uuidString):\(region.rawValue)"
        )
        onRegionChange(region)
        return .move
    }

    private func resolvedRegion(for sender: NSDraggingInfo) -> TerminalDropRegion {
        let point = convert(sender.draggingLocation, from: nil)
        return TerminalDropRegion.resolve(
            location: CGPoint(x: point.x, y: point.y),
            size: bounds.size
        )
    }

    private func decodedPayload(from sender: NSDraggingInfo) -> TerminalDragPayload? {
        let type = NSPasteboard.PasteboardType(UTType.apexTermTerminalTab.identifier)
        guard let data = sender.draggingPasteboard.data(forType: type) else {
            return nil
        }
        return try? JSONDecoder().decode(TerminalDragPayload.self, from: data)
    }
}
