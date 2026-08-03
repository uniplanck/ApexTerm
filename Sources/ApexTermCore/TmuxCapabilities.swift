import Foundation

public struct TmuxVersion: Comparable, Equatable, Sendable {
    public var major: Int
    public var minor: Int
    public var suffix: String

    public init(major: Int, minor: Int, suffix: String = "") {
        self.major = major
        self.minor = minor
        self.suffix = suffix
    }

    public init?(versionOutput: String) {
        guard let token = versionOutput
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first(where: { $0.first?.isNumber == true }) else {
            return nil
        }
        let parts = token.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let major = Int(parts[0]) else {
            return nil
        }
        let minorDigits = parts[1].prefix(while: \.isNumber)
        guard !minorDigits.isEmpty,
              let minor = Int(minorDigits) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.suffix = String(parts[1].dropFirst(minorDigits.count))
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.suffix.localizedStandardCompare(rhs.suffix) == .orderedAscending
    }
}

public struct TmuxCapabilities: Equatable, Sendable {
    public var supportsTerminalFeatures: Bool
    public var supportsExtendedKeys: Bool
    public var supportsAllowPassthrough: Bool
    public var supportsExtendedKeysFormat: Bool

    public init(version: TmuxVersion) {
        supportsTerminalFeatures = version >= TmuxVersion(major: 3, minor: 2)
        supportsExtendedKeys = version >= TmuxVersion(major: 3, minor: 2)
        supportsAllowPassthrough = version >= TmuxVersion(major: 3, minor: 3)
        supportsExtendedKeysFormat = version >= TmuxVersion(major: 3, minor: 5)
    }

    public init(
        supportsTerminalFeatures: Bool,
        supportsExtendedKeys: Bool,
        supportsAllowPassthrough: Bool,
        supportsExtendedKeysFormat: Bool
    ) {
        self.supportsTerminalFeatures = supportsTerminalFeatures
        self.supportsExtendedKeys = supportsExtendedKeys
        self.supportsAllowPassthrough = supportsAllowPassthrough
        self.supportsExtendedKeysFormat = supportsExtendedKeysFormat
    }

    public static let modernFallback = Self(
        supportsTerminalFeatures: true,
        supportsExtendedKeys: true,
        supportsAllowPassthrough: true,
        supportsExtendedKeysFormat: false
    )
}

public enum TmuxRuntimeProbe {
    public static func capabilities(executable: String) -> TmuxCapabilities? {
        guard let output = versionOutput(executable: executable),
              let version = TmuxVersion(versionOutput: output) else {
            return nil
        }
        return TmuxCapabilities(version: version)
    }

    public static func versionOutput(executable: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-V"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )
    }
}
