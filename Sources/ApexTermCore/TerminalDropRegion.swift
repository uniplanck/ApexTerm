import CoreGraphics

public enum TerminalDropRegion: String, Codable, Equatable, CaseIterable, Sendable {
    case center
    case left
    case right
    case top
    case bottom

    public static func resolve(
        location: CGPoint,
        size: CGSize,
        edgeFraction: CGFloat = 0.23
    ) -> TerminalDropRegion {
        guard size.width > 0, size.height > 0 else { return .center }
        let horizontalEdge = max(44, min(size.width * edgeFraction, size.width * 0.4))
        let verticalEdge = max(38, min(size.height * edgeFraction, size.height * 0.4))

        let distances: [(TerminalDropRegion, CGFloat)] = [
            (.left, location.x / horizontalEdge),
            (.right, (size.width - location.x) / horizontalEdge),
            (.top, location.y / verticalEdge),
            (.bottom, (size.height - location.y) / verticalEdge)
        ]
        guard let closest = distances.min(by: { $0.1 < $1.1 }), closest.1 <= 1 else {
            return .center
        }
        return closest.0
    }

    /// The final pane footprint shown while dragging. Coordinates use the
    /// SwiftUI/DropInfo convention where y=0 is the top edge of the target.
    public func previewFrame(
        in size: CGSize,
        inset: CGFloat = 10,
        splitFraction: CGFloat = 0.5
    ) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }

        let safeInset = max(0, min(inset, min(size.width, size.height) * 0.2))
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: safeInset, dy: safeInset)
        let fraction = max(0.25, min(splitFraction, 0.75))

        switch self {
        case .center:
            return bounds
        case .left:
            return CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width * fraction,
                height: bounds.height
            )
        case .right:
            let width = bounds.width * fraction
            return CGRect(
                x: bounds.maxX - width,
                y: bounds.minY,
                width: width,
                height: bounds.height
            )
        case .top:
            return CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: bounds.height * fraction
            )
        case .bottom:
            let height = bounds.height * fraction
            return CGRect(
                x: bounds.minX,
                y: bounds.maxY - height,
                width: bounds.width,
                height: height
            )
        }
    }
}
