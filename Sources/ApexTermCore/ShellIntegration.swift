import Foundation

public enum ShellSemanticEvent: Equatable, Sendable {
    case promptStarted
    case commandInputStarted
    case commandCaptured(command: String)
    case commandExecuted
    case commandFinished(exitCode: Int?)
}

public enum ShellStreamSegment: Equatable, Sendable {
    case data([UInt8])
    case marker(raw: [UInt8], event: ShellSemanticEvent?)
}

/// Splits a PTY byte stream into ordinary terminal data and OSC 133 shell-integration markers.
/// Marker bytes are retained so callers can still feed the exact stream into a terminal emulator.
public struct ShellIntegrationStreamParser: Sendable {
    private static let escape: UInt8 = 0x1B
    private static let bell: UInt8 = 0x07
    private static let rawSignature: [UInt8] = [escape, 0x5D, 0x31, 0x33, 0x33, 0x3B]
    private static let tmuxSignature: [UInt8] = [
        escape, 0x50, 0x74, 0x6D, 0x75, 0x78, 0x3B,
        escape, escape, 0x5D, 0x31, 0x33, 0x33, 0x3B
    ]
    private static let maximumPendingMarkerBytes = 65_536

    private enum MarkerEnvelope: Equatable {
        case raw
        case tmux
    }

    private struct MarkerStart {
        let index: Int
        let payloadStart: Int
        let envelope: MarkerEnvelope
    }

    private var pending: [UInt8] = []

    public init() {}

    /// Returns true when the incoming bytes cannot contain a complete or fragmented
    /// OSC 133 marker and may be sent directly to the terminal engine without
    /// allocating stream segments.
    public func canBypass(_ bytes: ArraySlice<UInt8>) -> Bool {
        guard pending.isEmpty else { return false }
        guard !bytes.isEmpty else { return true }

        var searchStart = bytes.startIndex
        while searchStart < bytes.endIndex,
              let escapeIndex = bytes[searchStart...].firstIndex(of: Self.escape) {
            if matchesOrPrefixes(Self.rawSignature, in: bytes, at: escapeIndex)
                || matchesOrPrefixes(Self.tmuxSignature, in: bytes, at: escapeIndex) {
                return false
            }
            searchStart = bytes.index(after: escapeIndex)
        }
        return true
    }

    public mutating func feed(_ bytes: ArraySlice<UInt8>) -> [ShellStreamSegment] {
        pending.append(contentsOf: bytes)
        var segments: [ShellStreamSegment] = []
        var cursor = 0

        while cursor < pending.count {
            guard let marker = findMarkerStart(from: cursor) else {
                let retained = possibleSignaturePrefixLength(in: pending[cursor...])
                let emitEnd = pending.count - retained
                if cursor < emitEnd {
                    segments.append(.data(Array(pending[cursor..<emitEnd])))
                }
                pending = retained > 0 ? Array(pending.suffix(retained)) : []
                return segments
            }

            if cursor < marker.index {
                segments.append(.data(Array(pending[cursor..<marker.index])))
            }

            guard let terminator = findTerminator(
                from: marker.payloadStart,
                envelope: marker.envelope
            ) else {
                pending = Array(pending[marker.index...])
                if pending.count > Self.maximumPendingMarkerBytes {
                    segments.append(.data(pending))
                    pending.removeAll(keepingCapacity: true)
                }
                return segments
            }

            let payload = String(
                bytes: pending[marker.payloadStart..<terminator.payloadEnd],
                encoding: .utf8
            ) ?? ""
            let raw = Array(pending[marker.index..<terminator.nextIndex])
            segments.append(.marker(raw: raw, event: Self.parsePayload(payload)))
            cursor = terminator.nextIndex
        }

        pending.removeAll(keepingCapacity: true)
        return segments
    }

    private func matchesOrPrefixes(
        _ signature: [UInt8],
        in bytes: ArraySlice<UInt8>,
        at index: Int
    ) -> Bool {
        let available = bytes.distance(from: index, to: bytes.endIndex)
        let comparisonCount = min(available, signature.count)
        guard comparisonCount > 0 else { return false }
        let comparisonEnd = bytes.index(index, offsetBy: comparisonCount)
        return bytes[index..<comparisonEnd].elementsEqual(signature.prefix(comparisonCount))
    }

    private func findMarkerStart(from index: Int) -> MarkerStart? {
        let rawIndex = firstIndex(of: Self.rawSignature, from: index)
        let tmuxIndex = firstIndex(of: Self.tmuxSignature, from: index)

        switch (rawIndex, tmuxIndex) {
        case let (raw?, tmux?) where tmux <= raw:
            return MarkerStart(
                index: tmux,
                payloadStart: tmux + Self.tmuxSignature.count,
                envelope: .tmux
            )
        case let (raw?, _):
            return MarkerStart(
                index: raw,
                payloadStart: raw + Self.rawSignature.count,
                envelope: .raw
            )
        case let (_, tmux?):
            return MarkerStart(
                index: tmux,
                payloadStart: tmux + Self.tmuxSignature.count,
                envelope: .tmux
            )
        case (nil, nil):
            return nil
        }
    }

    private func firstIndex(of signature: [UInt8], from index: Int) -> Int? {
        guard pending.count >= signature.count,
              index <= pending.count - signature.count else {
            return nil
        }
        for candidate in index...(pending.count - signature.count) {
            if pending[candidate..<(candidate + signature.count)]
                .elementsEqual(signature) {
                return candidate
            }
        }
        return nil
    }

    private func findTerminator(
        from index: Int,
        envelope: MarkerEnvelope
    ) -> (payloadEnd: Int, nextIndex: Int)? {
        guard index < pending.count else { return nil }
        var cursor = index
        while cursor < pending.count {
            if pending[cursor] == Self.bell {
                if envelope == .tmux {
                    guard cursor + 2 < pending.count else { return nil }
                    guard pending[cursor + 1] == Self.escape,
                          pending[cursor + 2] == 0x5C else {
                        return nil
                    }
                    return (cursor, cursor + 3)
                }
                return (cursor, cursor + 1)
            }
            if envelope == .raw,
               pending[cursor] == Self.escape,
               cursor + 1 < pending.count,
               pending[cursor + 1] == 0x5C {
                return (cursor, cursor + 2)
            }
            cursor += 1
        }
        return nil
    }

    private func possibleSignaturePrefixLength(in bytes: ArraySlice<UInt8>) -> Int {
        [Self.rawSignature, Self.tmuxSignature].reduce(0) { longest, signature in
            let maximum = min(bytes.count, signature.count - 1)
            guard maximum > 0 else { return longest }
            for length in stride(from: maximum, through: 1, by: -1) {
                if bytes.suffix(length).elementsEqual(signature.prefix(length)) {
                    return max(longest, length)
                }
            }
            return longest
        }
    }

    private static func parsePayload(_ payload: String) -> ShellSemanticEvent? {
        if payload == "A" {
            return .promptStarted
        }
        if payload == "B" {
            return .commandInputStarted
        }
        if payload == "C" {
            return .commandExecuted
        }
        if payload == "E" {
            return .commandCaptured(command: "")
        }
        if payload.hasPrefix("E;") {
            return .commandCaptured(command: String(payload.dropFirst(2)))
        }
        if payload == "D" {
            return .commandFinished(exitCode: nil)
        }
        if payload.hasPrefix("D;") {
            return .commandFinished(exitCode: Int(payload.dropFirst(2)))
        }
        return nil
    }
}

public struct ShellIntegrationParser: Sendable {
    private var streamParser = ShellIntegrationStreamParser()

    public init() {}

    public mutating func feed(_ bytes: ArraySlice<UInt8>) -> [ShellSemanticEvent] {
        streamParser.feed(bytes).compactMap { segment in
            guard case let .marker(_, event) = segment else { return nil }
            return event
        }
    }
}

public enum TerminalTextSanitizer {
    public static func plainText(from bytes: [UInt8]) -> String {
        var cleaned: [UInt8] = []
        cleaned.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x1B {
                index = skipEscapeSequence(in: bytes, from: index)
                continue
            }
            if byte == 0x08 {
                if let last = cleaned.last, last != 0x0A {
                    cleaned.removeLast()
                }
                index += 1
                continue
            }
            if byte == 0x0D {
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    index += 1
                }
                cleaned.append(0x0A)
                index += 1
                continue
            }
            if byte == 0x0A || byte == 0x09 || byte >= 0x20 {
                cleaned.append(byte)
            }
            index += 1
        }

        let text = String(decoding: cleaned, as: UTF8.self)
        return String(text.reversed().drop(while: \.isWhitespace).reversed())
    }

    private static func skipEscapeSequence(in bytes: [UInt8], from start: Int) -> Int {
        guard start + 1 < bytes.count else { return start + 1 }
        let introducer = bytes[start + 1]

        if introducer == 0x5B {
            var index = start + 2
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if (0x40...0x7E).contains(byte) {
                    break
                }
            }
            return index
        }

        if introducer == 0x5D {
            var index = start + 2
            while index < bytes.count {
                if bytes[index] == 0x07 {
                    return index + 1
                }
                if bytes[index] == 0x1B,
                   index + 1 < bytes.count,
                   bytes[index + 1] == 0x5C {
                    return index + 2
                }
                index += 1
            }
            return index
        }

        if [UInt8(0x50), 0x58, 0x5E, 0x5F].contains(introducer) {
            var index = start + 2
            while index < bytes.count {
                if bytes[index] == 0x1B,
                   index + 1 < bytes.count,
                   bytes[index + 1] == 0x5C {
                    return index + 2
                }
                index += 1
            }
            return index
        }

        if (0x20...0x2F).contains(introducer) {
            var index = start + 2
            while index < bytes.count, (0x20...0x2F).contains(bytes[index]) {
                index += 1
            }
            if index < bytes.count, (0x30...0x7E).contains(bytes[index]) {
                return index + 1
            }
            return index
        }

        return min(start + 2, bytes.count)
    }
}

public enum CommandBoundaryKind: String, Codable, Equatable, Sendable {
    case promptStarted
    case inputStarted
    case commandCaptured
    case executed
    case finished
}

public struct CommandBoundary: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var kind: CommandBoundaryKind
    public var timestamp: Date
    public var exitCode: Int?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        kind: CommandBoundaryKind,
        timestamp: Date = Date(),
        exitCode: Int? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.timestamp = timestamp
        self.exitCode = exitCode
    }
}

public actor CommandBoundaryIndex {
    private var boundaries: [UUID: [CommandBoundary]] = [:]
    private let maximumEventsPerSession: Int

    public init(maximumEventsPerSession: Int = 10_000) {
        self.maximumEventsPerSession = max(100, maximumEventsPerSession)
    }

    public func append(
        _ events: [ShellSemanticEvent],
        sessionID: UUID,
        timestamp: Date = Date()
    ) {
        guard !events.isEmpty else { return }
        var sessionEvents = boundaries[sessionID, default: []]
        sessionEvents.append(contentsOf: events.map { event in
            switch event {
            case .promptStarted:
                CommandBoundary(sessionID: sessionID, kind: .promptStarted, timestamp: timestamp)
            case .commandInputStarted:
                CommandBoundary(sessionID: sessionID, kind: .inputStarted, timestamp: timestamp)
            case .commandCaptured:
                CommandBoundary(sessionID: sessionID, kind: .commandCaptured, timestamp: timestamp)
            case .commandExecuted:
                CommandBoundary(sessionID: sessionID, kind: .executed, timestamp: timestamp)
            case let .commandFinished(exitCode):
                CommandBoundary(
                    sessionID: sessionID,
                    kind: .finished,
                    timestamp: timestamp,
                    exitCode: exitCode
                )
            }
        })
        if sessionEvents.count > maximumEventsPerSession {
            sessionEvents.removeFirst(sessionEvents.count - maximumEventsPerSession)
        }
        boundaries[sessionID] = sessionEvents
    }

    public func events(sessionID: UUID) -> [CommandBoundary] {
        boundaries[sessionID, default: []]
    }

    public func clear(sessionID: UUID) {
        boundaries[sessionID] = nil
    }
}
