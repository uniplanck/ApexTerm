import AppKit
import SwiftUI

struct AgentChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let tabID: UUID
    let placeholder: String
    let focusRequestGeneration: UInt64

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            focusRequestGeneration: focusRequestGeneration
        )
    }

    func makeNSView(context: Context) -> AgentChatComposerContainerView {
        let view = AgentChatComposerContainerView(
            tabID: tabID,
            placeholder: placeholder
        )
        view.textView.delegate = context.coordinator
        view.setText(text)
        view.requestFocusWhenReady()
        return view
    }

    func updateNSView(_ nsView: AgentChatComposerContainerView, context: Context) {
        context.coordinator.text = $text
        nsView.setPlaceholder(placeholder)
        nsView.setText(text)
        if context.coordinator.focusRequestGeneration != focusRequestGeneration {
            context.coordinator.focusRequestGeneration = focusRequestGeneration
            nsView.requestFocusWhenReady()
        }
    }

    static func dismantleNSView(
        _ nsView: AgentChatComposerContainerView,
        coordinator: Coordinator
    ) {
        nsView.cancelPendingFocusRequest()
        nsView.textView.delegate = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var focusRequestGeneration: UInt64

        init(
            text: Binding<String>,
            focusRequestGeneration: UInt64
        ) {
            self.text = text
            self.focusRequestGeneration = focusRequestGeneration
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
        }
    }
}

final class AgentChatComposerContainerView: NSView {
    static let contentInset = NSSize(width: 10, height: 10)
    static let editorFont = NSFont.systemFont(ofSize: 14)

    let tabID: UUID
    let textView = NSTextView(frame: .zero)

    private let scrollView = NSScrollView(frame: .zero)
    private let placeholderView = AgentChatPlaceholderTextView(frame: .zero)
    private var focusTask: Task<Void, Never>?

    init(tabID: UUID, placeholder: String) {
        self.tabID = tabID
        super.init(frame: .zero)
        configureTextView(textView, textColor: .labelColor)
        configureTextView(placeholderView, textColor: .placeholderTextColor)

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.insertionPointColor = .controlAccentColor
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        placeholderView.isEditable = false
        placeholderView.isSelectable = false
        placeholderView.string = placeholder

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        addSubview(placeholderView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        identifier = NSUserInterfaceItemIdentifier(
            "agent-chat-composer-\(tabID.uuidString)"
        )
        setAccessibilityIdentifier(identifier?.rawValue ?? "agent-chat-composer")
        textView.setAccessibilityIdentifier("agent-chat-composer")
        updatePlaceholderVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setText(_ value: String) {
        guard textView.string != value else {
            updatePlaceholderVisibility()
            return
        }
        let selectedRanges = textView.selectedRanges
        textView.string = value
        if selectedRanges.allSatisfy({ NSMaxRange($0.rangeValue) <= value.utf16.count }) {
            textView.selectedRanges = selectedRanges
        }
        updatePlaceholderVisibility()
    }

    func setPlaceholder(_ value: String) {
        if placeholderView.string != value {
            placeholderView.string = value
        }
        updatePlaceholderVisibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelPendingFocusRequest()
        } else {
            requestFocusWhenReady()
        }
    }

    func requestFocusWhenReady() {
        cancelPendingFocusRequest()
        focusTask = Task { @MainActor [weak self] in
            for _ in 0..<20 {
                guard !Task.isCancelled, let self else { return }
                if let window,
                   superview != nil,
                   !isHidden,
                   window.makeFirstResponder(textView),
                   window.firstResponder === textView {
                    focusTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            self?.focusTask = nil
        }
    }

    func cancelPendingFocusRequest() {
        focusTask?.cancel()
        focusTask = nil
    }

    func alignmentMetrics() -> AgentChatComposerAlignmentMetrics {
        layoutSubtreeIfNeeded()
        textView.layoutSubtreeIfNeeded()
        placeholderView.layoutSubtreeIfNeeded()
        let editorOrigin = textView.convert(textView.textContainerOrigin, to: self)
        let placeholderOrigin = placeholderView.convert(placeholderView.textContainerOrigin, to: self)
        return AgentChatComposerAlignmentMetrics(
            editorOrigin: editorOrigin,
            placeholderOrigin: placeholderOrigin
        )
    }

    private func configureTextView(_ view: NSTextView, textColor: NSColor) {
        view.font = Self.editorFont
        view.textColor = textColor
        view.drawsBackground = false
        view.backgroundColor = .clear
        view.textContainerInset = Self.contentInset
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
    }

    private func updatePlaceholderVisibility() {
        placeholderView.isHidden = !textView.string.isEmpty
    }
}

struct AgentChatComposerAlignmentMetrics {
    let editorOrigin: NSPoint
    let placeholderOrigin: NSPoint

    var deltaX: CGFloat { abs(editorOrigin.x - placeholderOrigin.x) }
    var deltaY: CGFloat { abs(editorOrigin.y - placeholderOrigin.y) }
    var isAligned: Bool { deltaX <= 0.5 && deltaY <= 0.5 }
}

private final class AgentChatPlaceholderTextView: NSTextView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
