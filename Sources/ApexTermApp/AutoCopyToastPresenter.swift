import AppKit
import QuartzCore
import SwiftUI

enum AutoCopyToastPreferences {
    static let scaleKey = "apexterm.terminal.autoCopyToastScale"
    static let durationKey = "apexterm.terminal.autoCopyToastDuration"
    static let transparencyKey = "apexterm.terminal.autoCopyToastTransparency"

    static let defaultScale = 1.45
    static let defaultDuration = 2.0
    static let defaultTransparency = 0.10

    static let scaleRange = 0.80...2.00
    static let durationRange = 0.50...5.00
    static let transparencyRange = 0.00...0.55

    static func current(defaults: UserDefaults = .standard) -> AutoCopyToastPresentation {
        AutoCopyToastPresentation(
            scale: clamped(
                storedDouble(defaults: defaults, key: scaleKey, fallback: defaultScale),
                to: scaleRange
            ),
            duration: clamped(
                storedDouble(defaults: defaults, key: durationKey, fallback: defaultDuration),
                to: durationRange
            ),
            transparency: clamped(
                storedDouble(
                    defaults: defaults,
                    key: transparencyKey,
                    fallback: defaultTransparency
                ),
                to: transparencyRange
            )
        )
    }

    private static func storedDouble(
        defaults: UserDefaults,
        key: String,
        fallback: Double
    ) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else {
            return fallback
        }
        return number.doubleValue
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct AutoCopyToastPresentation: Equatable {
    let scale: Double
    let duration: Double
    let transparency: Double

    var visibleAlpha: CGFloat {
        CGFloat(1 - transparency)
    }
}

@MainActor
final class AutoCopyToastPresenter {
    static let shared = AutoCopyToastPresenter()

    private var panel: NSPanel?
    private var generation: UInt64 = 0

    private init() {}

    func showOutputCopied() {
        show(message: "出力コピーしました")
    }

    private func show(message: String) {
        let presentation = AutoCopyToastPreferences.current()
        generation &+= 1
        let currentGeneration = generation
        let panel = makePanelIfNeeded()
        let hostingView = NSHostingView(
            rootView: AutoCopyToastView(
                message: message,
                scale: presentation.scale
            )
        )
        hostingView.setAccessibilityIdentifier("auto-copy-toast")

        let provisionalWidth = 300 * presentation.scale
        let provisionalHeight = 76 * presentation.scale
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: provisionalWidth,
            height: provisionalHeight
        )
        hostingView.layoutSubtreeIfNeeded()

        let fitting = hostingView.fittingSize
        let width = max(220 * presentation.scale, fitting.width)
        let height = max(54 * presentation.scale, fitting.height)
        panel.contentView = hostingView

        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            let frame = screen.visibleFrame
            panel.setFrame(
                NSRect(
                    x: frame.midX - width / 2,
                    y: frame.midY - height / 2,
                    width: width,
                    height: height
                ),
                display: true
            )
        } else {
            panel.setContentSize(NSSize(width: width, height: height))
            panel.center()
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = presentation.visibleAlpha
        }

        let fadeDuration = min(0.22, max(0.14, presentation.duration * 0.10))
        let holdMilliseconds = Int(
            max(100, (presentation.duration - fadeDuration) * 1_000).rounded()
        )

        Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(holdMilliseconds))
            guard let self,
                  let panel,
                  self.generation == currentGeneration else {
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak panel] in
                Task { @MainActor in
                    guard let self,
                          let panel,
                          self.generation == currentGeneration else {
                        return
                    }
                    panel.orderOut(nil)
                }
            })
        }
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("auto-copy-toast-window")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        self.panel = panel
        return panel
    }
}

private struct AutoCopyToastView: View {
    let message: String
    let scale: Double

    private var factor: CGFloat {
        CGFloat(scale)
    }

    var body: some View {
        HStack(spacing: 10 * factor) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18 * factor, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.green)

            Text(message)
                .font(.system(size: 15 * factor, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18 * factor)
        .padding(.vertical, 13 * factor)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 14 * factor,
                style: .continuous
            )
        )
        .background(
            Color.black.opacity(0.28),
            in: RoundedRectangle(
                cornerRadius: 14 * factor,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14 * factor,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.18), lineWidth: max(1, factor * 0.8))
        }
        .shadow(
            color: Color.black.opacity(0.34),
            radius: 20 * factor,
            y: 9 * factor
        )
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
