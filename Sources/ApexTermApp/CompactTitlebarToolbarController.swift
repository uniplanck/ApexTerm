import AppKit
import SwiftUI

struct CompactTitlebarPerformanceSnapshot {
    let hostingRootCreations: Int
    let layoutResizes: Int
    let contentUpdates: Int
    let contentRevision: String?
    let hostFillsContainer: Bool
    let containerFillsToolbarHostVertically: Bool
    let geometryAvailable: Bool
    let contentBottomGap: CGFloat
    let contentTopGap: CGFloat
    let contentCenterDeltaFromTrafficLights: CGFloat
}

@MainActor
final class CompactTitlebarToolbarController: NSObject, NSToolbarDelegate {
    static let shared = CompactTitlebarToolbarController()

    static let toolbarIdentifier = NSToolbar.Identifier("ApexTerm.CompactTitlebarToolbar")
    static let hostedViewIdentifier = NSUserInterfaceItemIdentifier("ApexTerm.CompactTitlebarHostedView")

    private weak var installedWindow: NSWindow?
    private var compactToolbar: NSToolbar?
    private var hostingView: NSHostingView<CompactTitlebarContentView>?
    private var hostingContainer: CompactTitlebarHostingContainerView?
    private var titlebarConstraints: [NSLayoutConstraint] = []
    private var windowObservers: [NSObjectProtocol] = []
    private var hostingRootCreationCount = 0
    private var layoutResizeCount = 0
    private var contentUpdateCount = 0
    private var lastContentRevision: String?

    private let contentStore = CompactTitlebarContentStore()

    private var previousToolbar: NSToolbar?
    private var previousToolbarStyle: NSWindow.ToolbarStyle?
    private var previousTitleVisibility: NSWindow.TitleVisibility?
    private var previousTitlebarAppearsTransparent: Bool?

    private override init() {
        super.init()
    }

    func update(
        window: NSWindow?,
        enabled: Bool,
        contentRevision: String,
        content: AnyView
    ) {
        guard let window else { return }

        if !enabled {
            uninstall(from: window)
            return
        }

        contentStore.update(content: content)
        contentUpdateCount += 1
        lastContentRevision = contentRevision

        if installedWindow !== window || compactToolbar == nil || hostingContainer == nil {
            uninstallFromCurrentWindow()
            install(on: window)
        } else {
            ensureOverlayAttached(to: window)
        }
    }

    func isInstalled(on window: NSWindow) -> Bool {
        installedWindow === window
            && window.toolbar?.identifier == Self.toolbarIdentifier
            && compactToolbar != nil
            && hostingView != nil
            && hostingContainer?.superview != nil
    }

    func hostedViewContains(identifier: NSUserInterfaceItemIdentifier) -> Bool {
        guard let hostingContainer else { return false }
        return findView(identifier: identifier, in: hostingContainer) != nil
    }

    func hostedViewAllowsWindowDrag(
        identifier: NSUserInterfaceItemIdentifier
    ) -> Bool {
        guard let hostingContainer,
              let view = findView(identifier: identifier, in: hostingContainer) else {
            return false
        }
        return view.mouseDownCanMoveWindow
    }

    private func install(on window: NSWindow) {
        installedWindow = window
        previousToolbar = window.toolbar
        previousToolbarStyle = window.toolbarStyle
        previousTitleVisibility = window.titleVisibility
        previousTitlebarAppearsTransparent = window.titlebarAppearsTransparent

        let hostingView = NSHostingView(
            rootView: CompactTitlebarContentView(store: contentStore)
        )
        hostingView.identifier = Self.hostedViewIdentifier
        hostingView.setAccessibilityIdentifier(Self.hostedViewIdentifier.rawValue)
        hostingView.autoresizingMask = [.width, .height]
        self.hostingView = hostingView
        hostingRootCreationCount += 1

        let hostingContainer = CompactTitlebarHostingContainerView(
            hostingView: hostingView
        ) { [weak self] in
            self?.layoutResizeCount += 1
        }
        self.hostingContainer = hostingContainer

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.showsBaselineSeparator = false

        compactToolbar = toolbar
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        observeWindowHierarchyChanges(on: window)
        ensureOverlayAttached(to: window)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.ensureOverlayAttached(to: window)
        }
    }

    private func observeWindowHierarchyChanges(on window: NSWindow) {
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ]
        windowObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor in
                    guard let self, let window else { return }
                    self.ensureOverlayAttached(to: window)
                }
            }
        }
    }

    private func ensureOverlayAttached(to window: NSWindow) {
        guard let hostingContainer,
              let closeButton = window.standardWindowButton(.closeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let titlebarContainer = closeButton.superview,
              zoomButton.superview === titlebarContainer else {
            return
        }

        guard hostingContainer.superview !== titlebarContainer else {
            titlebarContainer.layoutSubtreeIfNeeded()
            return
        }

        NSLayoutConstraint.deactivate(titlebarConstraints)
        titlebarConstraints.removeAll()
        hostingContainer.removeFromSuperview()
        hostingContainer.translatesAutoresizingMaskIntoConstraints = false
        titlebarContainer.addSubview(
            hostingContainer,
            positioned: .above,
            relativeTo: nil
        )

        titlebarConstraints = [
            hostingContainer.leadingAnchor.constraint(
                equalTo: zoomButton.trailingAnchor,
                constant: 10
            ),
            hostingContainer.trailingAnchor.constraint(
                equalTo: titlebarContainer.trailingAnchor,
                constant: -8
            ),
            hostingContainer.topAnchor.constraint(
                equalTo: titlebarContainer.topAnchor
            ),
            hostingContainer.bottomAnchor.constraint(
                equalTo: titlebarContainer.bottomAnchor
            )
        ]
        NSLayoutConstraint.activate(titlebarConstraints)
        titlebarContainer.layoutSubtreeIfNeeded()
    }

    private func uninstall(from window: NSWindow) {
        guard installedWindow === window else { return }
        uninstallFromCurrentWindow()
    }

    private func uninstallFromCurrentWindow() {
        guard let window = installedWindow else {
            clearInstallationState()
            return
        }

        NSLayoutConstraint.deactivate(titlebarConstraints)
        titlebarConstraints.removeAll()
        hostingContainer?.removeFromSuperview()

        if window.toolbar?.identifier == Self.toolbarIdentifier {
            window.toolbar = previousToolbar
            if let previousToolbarStyle {
                window.toolbarStyle = previousToolbarStyle
            }
            if let previousTitleVisibility {
                window.titleVisibility = previousTitleVisibility
            }
            if let previousTitlebarAppearsTransparent {
                window.titlebarAppearsTransparent = previousTitlebarAppearsTransparent
            }
        }

        clearInstallationState()
    }

    private func clearInstallationState() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
        compactToolbar?.delegate = nil
        installedWindow = nil
        compactToolbar = nil
        hostingView = nil
        hostingContainer = nil
        titlebarConstraints.removeAll()
        previousToolbar = nil
        previousToolbarStyle = nil
        previousTitleVisibility = nil
        previousTitlebarAppearsTransparent = nil
        lastContentRevision = nil
    }

    func performanceSnapshot() -> CompactTitlebarPerformanceSnapshot {
        let fillsContainer: Bool
        let fillsTitlebarVertically: Bool
        var geometryAvailable = false
        var contentBottomGap: CGFloat = 0
        var contentTopGap: CGFloat = 0
        var contentCenterDeltaFromTrafficLights: CGFloat = 0

        if let hostingView, let hostingContainer {
            fillsContainer = approximatelyEqual(
                hostingView.frame.size,
                hostingContainer.bounds.size
            )

            if let window = installedWindow,
               let closeButton = window.standardWindowButton(.closeButton),
               let titlebarContainer = closeButton.superview,
               hostingContainer.superview === titlebarContainer {
                let contentFrame = hostingContainer.convert(
                    hostingContainer.bounds,
                    to: nil
                )
                let titlebarFrame = titlebarContainer.convert(
                    titlebarContainer.bounds,
                    to: nil
                )
                let trafficLightFrame = closeButton.convert(
                    closeButton.bounds,
                    to: nil
                )
                geometryAvailable = true
                contentBottomGap = contentFrame.minY - titlebarFrame.minY
                contentTopGap = titlebarFrame.maxY - contentFrame.maxY
                contentCenterDeltaFromTrafficLights = contentFrame.midY
                    - trafficLightFrame.midY
                fillsTitlebarVertically = abs(contentBottomGap) < 0.5
                    && abs(contentTopGap) < 0.5
            } else {
                fillsTitlebarVertically = false
            }
        } else {
            fillsContainer = false
            fillsTitlebarVertically = false
        }

        return CompactTitlebarPerformanceSnapshot(
            hostingRootCreations: hostingRootCreationCount,
            layoutResizes: layoutResizeCount,
            contentUpdates: contentUpdateCount,
            contentRevision: lastContentRevision,
            hostFillsContainer: fillsContainer,
            containerFillsToolbarHostVertically: fillsTitlebarVertically,
            geometryAvailable: geometryAvailable,
            contentBottomGap: contentBottomGap,
            contentTopGap: contentTopGap,
            contentCenterDeltaFromTrafficLights: contentCenterDeltaFromTrafficLights
        )
    }

    private func approximatelyEqual(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }

    private func findView(
        identifier: NSUserInterfaceItemIdentifier,
        in view: NSView
    ) -> NSView? {
        if view.identifier == identifier {
            return view
        }
        for subview in view.subviews {
            if let match = findView(identifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}

@MainActor
private final class CompactTitlebarHostingContainerView: NSView {
    let hostingView: NSHostingView<CompactTitlebarContentView>
    private let onSizeChange: () -> Void
    private var lastLayoutSize = NSSize.zero

    init(
        hostingView: NSHostingView<CompactTitlebarContentView>,
        onSizeChange: @escaping () -> Void
    ) {
        self.hostingView = hostingView
        self.onSizeChange = onSizeChange
        super.init(frame: .zero)
        addSubview(hostingView)
        hostingView.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: NSView.noIntrinsicMetric
        )
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
        guard !approximatelyEqual(bounds.size, lastLayoutSize) else { return }
        lastLayoutSize = bounds.size
        onSizeChange()
    }

    private func approximatelyEqual(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }
}
