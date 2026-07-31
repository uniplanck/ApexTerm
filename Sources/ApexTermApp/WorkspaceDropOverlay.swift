import ApexTermCore
import SwiftUI

struct WorkspaceDropPreview: View {
    let activeRegion: TerminalDropRegion

    var body: some View {
        GeometryReader { proxy in
            let footprint = activeRegion.previewFrame(in: proxy.size, inset: 9)

            ZStack {
                Color.black.opacity(0.28)
                destinationFootprint(frame: footprint)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workspace-pane-drop-preview")
            .accessibilityLabel("Pane drop destination: \(title(for: activeRegion))")
        }
        .transition(.opacity)
    }

    private func destinationFootprint(frame: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(Color.accentColor.opacity(0.23))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.accentColor, lineWidth: 2.5)
            }
            .overlay(alignment: .topLeading) {
                Label(title(for: activeRegion), systemImage: symbol(for: activeRegion))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(Color.accentColor.opacity(0.9), in: Capsule())
                    .padding(9)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .animation(.snappy(duration: 0.16), value: activeRegion)
            .allowsHitTesting(false)
    }

    private func title(for region: TerminalDropRegion) -> String {
        switch region {
        case .center:
            "WHOLE"
        case .left:
            "LEFT"
        case .right:
            "RIGHT"
        case .top:
            "TOP"
        case .bottom:
            "BOTTOM"
        }
    }

    private func symbol(for region: TerminalDropRegion) -> String {
        switch region {
        case .center:
            "rectangle.fill"
        case .left:
            "rectangle.lefthalf.filled"
        case .right:
            "rectangle.righthalf.filled"
        case .top:
            "rectangle.tophalf.filled"
        case .bottom:
            "rectangle.bottomhalf.filled"
        }
    }
}
