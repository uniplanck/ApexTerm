import Foundation

public struct RemoteHostEntry: Identifiable, Equatable, Sendable {
    public var id: String { profile.alias }
    public var profile: SSHHostProfile
    public var isHidden: Bool
    public var isCustom: Bool

    public init(
        profile: SSHHostProfile,
        isHidden: Bool,
        isCustom: Bool
    ) {
        self.profile = profile
        self.isHidden = isHidden
        self.isCustom = isCustom
    }
}

public struct RemoteHostConfiguration: Codable, Equatable, Sendable {
    public var hiddenAliases: Set<String>
    public var deletedAliases: Set<String>
    public var customProfiles: [SSHHostProfile]

    public init(
        hiddenAliases: Set<String> = [],
        deletedAliases: Set<String> = [],
        customProfiles: [SSHHostProfile] = []
    ) {
        self.hiddenAliases = hiddenAliases
        self.deletedAliases = deletedAliases
        self.customProfiles = customProfiles
    }

    private enum CodingKeys: String, CodingKey {
        case hiddenAliases
        case deletedAliases
        case customProfiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenAliases = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenAliases) ?? []
        deletedAliases = try container.decodeIfPresent(Set<String>.self, forKey: .deletedAliases) ?? []
        customProfiles = try container.decodeIfPresent([SSHHostProfile].self, forKey: .customProfiles) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hiddenAliases, forKey: .hiddenAliases)
        try container.encode(deletedAliases, forKey: .deletedAliases)
        try container.encode(customProfiles, forKey: .customProfiles)
    }

    public func entries(baseProfiles: [SSHHostProfile]) -> [RemoteHostEntry] {
        let customByAlias = Dictionary(
            uniqueKeysWithValues: customProfiles.map { ($0.alias, $0) }
        )
        let baseAliases = Set(baseProfiles.map(\.alias))
        var result = baseProfiles.compactMap { base -> RemoteHostEntry? in
            guard !deletedAliases.contains(base.alias) else { return nil }
            return RemoteHostEntry(
                profile: customByAlias[base.alias] ?? base,
                isHidden: hiddenAliases.contains(base.alias),
                isCustom: customByAlias[base.alias] != nil
            )
        }

        for profile in customProfiles
        where !baseAliases.contains(profile.alias) && !deletedAliases.contains(profile.alias) {
            result.append(
                RemoteHostEntry(
                    profile: profile,
                    isHidden: hiddenAliases.contains(profile.alias),
                    isCustom: true
                )
            )
        }

        return result.sorted {
            $0.profile.alias.localizedCaseInsensitiveCompare($1.profile.alias) == .orderedAscending
        }
    }

    public func visibleProfiles(baseProfiles: [SSHHostProfile]) -> [SSHHostProfile] {
        entries(baseProfiles: baseProfiles)
            .filter { !$0.isHidden }
            .map(\.profile)
    }
}

public enum RemoteHostConfigurationStore {
    public static func load(from fileURL: URL) throws -> RemoteHostConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return RemoteHostConfiguration()
        }
        return try JSONDecoder().decode(
            RemoteHostConfiguration.self,
            from: Data(contentsOf: fileURL)
        )
    }

    public static func save(
        _ configuration: RemoteHostConfiguration,
        to fileURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: fileURL, options: [.atomic])
    }
}
