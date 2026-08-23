import Foundation

public struct ResponsiveLayoutPolicy: Equatable, Sendable {
    public enum Mode: String, Equatable, Sendable {
        case compact
        case balanced
        case wide
    }

    public static let compactBreakpoint: CGFloat = 760
    public static let fullToolbarBreakpoint: CGFloat = 1_000
    public static let wideBreakpoint: CGFloat = 1_180

    public let mode: Mode
    public let showsWorkspaceSidebar: Bool
    public let showsAgentRail: Bool
    public let usesCompactToolbar: Bool
    public let mainToolbarControlCapacity: Int

    public init(width: CGFloat, agentRailPreferred: Bool) {
        let safeWidth = max(0, width)

        if safeWidth < Self.compactBreakpoint {
            mode = .compact
            showsWorkspaceSidebar = false
            showsAgentRail = false
            usesCompactToolbar = false
        } else if safeWidth < Self.wideBreakpoint {
            mode = .balanced
            showsWorkspaceSidebar = true
            showsAgentRail = false
            usesCompactToolbar = false
        } else {
            mode = .wide
            showsWorkspaceSidebar = true
            showsAgentRail = agentRailPreferred
            usesCompactToolbar = false
        }

        mainToolbarControlCapacity = Self.toolbarCapacity(for: safeWidth)
    }

    private static func toolbarCapacity(for width: CGFloat) -> Int {
        switch width {
        case ..<500: 2
        case ..<580: 3
        case ..<660: 4
        case ..<740: 5
        case ..<820: 7
        case ..<900: 9
        case ..<980: 11
        default: Int.max
        }
    }
}
