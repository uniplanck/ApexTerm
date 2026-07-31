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

    public init(width: CGFloat, agentRailPreferred: Bool) {
        let safeWidth = max(0, width)

        if safeWidth < Self.compactBreakpoint {
            mode = .compact
            showsWorkspaceSidebar = false
            showsAgentRail = false
            usesCompactToolbar = true
        } else if safeWidth < Self.wideBreakpoint {
            mode = .balanced
            showsWorkspaceSidebar = true
            showsAgentRail = false
            usesCompactToolbar = safeWidth < Self.fullToolbarBreakpoint
        } else {
            mode = .wide
            showsWorkspaceSidebar = true
            showsAgentRail = agentRailPreferred
            usesCompactToolbar = false
        }
    }
}
