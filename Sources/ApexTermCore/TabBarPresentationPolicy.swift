import Foundation

public struct TabBarPresentationPolicy: Equatable, Sendable {
    public static let iconOnlyWidthThreshold: Double = 430

    public let availableWidth: Double
    public let separatorsEnabled: Bool

    public init(
        availableWidth: Double,
        separatorsEnabled: Bool
    ) {
        self.availableWidth = max(0, availableWidth)
        self.separatorsEnabled = separatorsEnabled
    }

    public var usesIconOnlyTabs: Bool {
        availableWidth < Self.iconOnlyWidthThreshold
    }

    public var showsSeparators: Bool {
        usesIconOnlyTabs || separatorsEnabled
    }
}
