import Foundation

public enum ApexSettingsStoreError: Error, Equatable {
    case unsupportedSchema(found: Int, supported: Int)
    case corruptFile(quarantinedAt: URL)
}

public actor ApexSettingsStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load(defaults: ApexSettingsDocument) throws -> ApexSettingsDocument {
        try Self.loadSynchronously(from: fileURL, defaults: defaults)
    }

    public func save(_ document: ApexSettingsDocument) throws {
        try Self.saveSynchronously(document, to: fileURL)
    }

    public nonisolated static func loadSynchronously(
        from fileURL: URL,
        defaults: ApexSettingsDocument
    ) throws -> ApexSettingsDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return defaults
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder().decode(SchemaEnvelope.self, from: data)
            guard envelope.schemaVersion == ApexSettingsDocument.currentSchemaVersion else {
                throw ApexSettingsStoreError.unsupportedSchema(
                    found: envelope.schemaVersion,
                    supported: ApexSettingsDocument.currentSchemaVersion
                )
            }
            let decoded = try JSONDecoder().decode(ApexSettingsDocument.self, from: data)
            return ApexSettingsDocument(
                schemaVersion: decoded.schemaVersion,
                activeProfileID: decoded.activeProfileID,
                profiles: decoded.profiles,
                keybindings: decoded.keybindings,
                general: decoded.general,
                uiControls: decoded.uiControls
            )
        } catch let error as ApexSettingsStoreError {
            throw error
        } catch {
            let quarantineURL = try quarantineCorruptFile(at: fileURL)
            throw ApexSettingsStoreError.corruptFile(
                quarantinedAt: quarantineURL
            )
        }
    }

    public nonisolated static func saveSynchronously(
        _ document: ApexSettingsDocument,
        to fileURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private struct SchemaEnvelope: Decodable {
        var schemaVersion: Int
    }

    private nonisolated static func quarantineCorruptFile(
        at fileURL: URL
    ) throws -> URL {
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantineURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp).json")
        try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
        return quarantineURL
    }
}
