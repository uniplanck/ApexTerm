import Foundation

public enum TerminalClipboardAccess: Equatable, Sendable {
    case disabled
    case writeOnly
    case readWrite
}

public struct TerminalEscapeSequenceTrustPolicy: Equatable, Sendable {
    public var clipboardAccess: TerminalClipboardAccess

    public init(clipboardAccess: TerminalClipboardAccess) {
        self.clipboardAccess = clipboardAccess
    }

    public static let localDefault = Self(clipboardAccess: .writeOnly)
    public static let remoteDefault = Self(clipboardAccess: .disabled)
}

/// Removes denied OSC 52 clipboard access before bytes reach SwiftTerm.
/// Allowed sequences are preserved byte-for-byte, including tmux passthrough,
/// 8-bit C1 framing, and numeric commands with leading zeroes.
public struct TerminalEscapeSequenceTrustFilter: Sendable {
    private enum ClipboardAction { case read, write, malformed }

    private struct End {
        let payloadEnd: Int
        let nextIndex: Int
    }

    private static let escape: UInt8 = 0x1B

    public var policy: TerminalEscapeSequenceTrustPolicy
    public let maximumOSC52Bytes: Int
    public private(set) var blockedOSC52Count = 0

    private let matcher = TerminalOSCSequenceMatcher(targetCode: 52)
    private var pending: [UInt8] = []
    private var discarding: TerminalStringEnvelope?
    private var discardingSearchIndex = 0
    private var terminatorSearchIndex = 0

    public init(
        policy: TerminalEscapeSequenceTrustPolicy,
        maximumOSC52Bytes: Int = 256 * 1_024
    ) {
        self.policy = policy
        self.maximumOSC52Bytes = max(1_024, maximumOSC52Bytes)
    }

    public mutating func updatePolicy(_ policy: TerminalEscapeSequenceTrustPolicy) {
        self.policy = policy
        resetStreamState()
    }

    public mutating func resetStreamState() {
        pending.removeAll(keepingCapacity: true)
        discarding = nil
        discardingSearchIndex = 0
        terminatorSearchIndex = 0
    }

    public mutating func feed(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        pending.append(contentsOf: bytes)
        var output: [UInt8] = []

        while !pending.isEmpty {
            if let envelope = discarding {
                guard let end = terminator(
                    from: discardingSearchIndex,
                    envelope: envelope
                ) else {
                    retainTerminatorPrefix(for: envelope)
                    discardingSearchIndex = 0
                    return output
                }
                if end.nextIndex > 0 {
                    pending.removeFirst(end.nextIndex)
                }
                discarding = nil
                discardingSearchIndex = 0
                continue
            }

            switch matcher.detect(in: pending) {
            case .none:
                terminatorSearchIndex = 0
                emitOrdinaryBytesPreservingUTF8Boundary(into: &output)
                return output

            case let .incomplete(candidate):
                terminatorSearchIndex = 0
                if candidate.index > 0 {
                    output.append(contentsOf: pending.prefix(candidate.index))
                    pending.removeFirst(candidate.index)
                }
                if pending.count > maximumPendingCandidateBytes {
                    blockedOSC52Count += 1
                    discarding = candidate.envelope
                    discardingSearchIndex = min(1, pending.count)
                    continue
                }
                return output

            case let .target(start):
                if start.index > 0 {
                    output.append(contentsOf: pending.prefix(start.index))
                    pending.removeFirst(start.index)
                    continue
                }

                let searchStart = max(start.payloadStart, terminatorSearchIndex)
                guard let end = terminator(
                    from: searchStart,
                    envelope: start.envelope
                ) else {
                    terminatorSearchIndex = nextTerminatorSearchIndex(
                        envelope: start.envelope,
                        minimum: start.payloadStart
                    )
                    if pending.count > maximumOSC52Bytes {
                        blockedOSC52Count += 1
                        discarding = start.envelope
                        discardingSearchIndex = terminatorSearchIndex
                        terminatorSearchIndex = 0
                    } else {
                        return output
                    }
                    continue
                }

                terminatorSearchIndex = 0
                let length = end.nextIndex
                let action = clipboardAction(
                    in: pending[start.payloadStart..<end.payloadEnd]
                )
                if length <= maximumOSC52Bytes, allows(action) {
                    output.append(contentsOf: pending.prefix(length))
                } else {
                    blockedOSC52Count += 1
                }
                pending.removeFirst(length)
            }
        }
        return output
    }

    private var maximumPendingCandidateBytes: Int {
        switch policy.clipboardAccess {
        case .disabled:
            return min(maximumOSC52Bytes, 1_024)
        case .writeOnly, .readWrite:
            return maximumOSC52Bytes
        }
    }

    private func terminator(
        from start: Int,
        envelope: TerminalStringEnvelope
    ) -> End? {
        switch envelope {
        case .raw:
            var index = start
            while index < pending.count {
                if pending[index] == 0x07 || pending[index] == 0x9C {
                    return End(payloadEnd: index, nextIndex: index + 1)
                }
                if pending[index] == Self.escape {
                    guard index + 1 < pending.count else { return nil }
                    if pending[index + 1] == 0x5C {
                        return End(payloadEnd: index, nextIndex: index + 2)
                    }
                    return End(payloadEnd: index, nextIndex: index)
                }
                index += 1
            }

        case .tmux:
            var index = start
            while index + 1 < pending.count {
                if pending[index] == Self.escape,
                   pending[index + 1] == 0x5C,
                   (index == start || pending[index - 1] != Self.escape) {
                    return End(payloadEnd: index, nextIndex: index + 2)
                }
                index += 1
            }
        }
        return nil
    }

    private func nextTerminatorSearchIndex(
        envelope: TerminalStringEnvelope,
        minimum: Int
    ) -> Int {
        switch envelope {
        case .raw:
            let retained = pending.last == Self.escape ? 1 : 0
            return max(minimum, pending.count - retained)
        case .tmux:
            return max(minimum, pending.count - min(2, pending.count))
        }
    }

    private func clipboardAction(in payload: ArraySlice<UInt8>) -> ClipboardAction {
        guard let separator = payload.firstIndex(of: 0x3B) else {
            return .malformed
        }
        let content = payload.index(after: separator)
        guard content < payload.endIndex else { return .write }
        return payload[content] == 0x3F ? .read : .write
    }

    private func allows(_ action: ClipboardAction) -> Bool {
        switch (policy.clipboardAccess, action) {
        case (.disabled, _), (_, .malformed), (.writeOnly, .read):
            return false
        case (.writeOnly, .write), (.readWrite, .read), (.readWrite, .write):
            return true
        }
    }

    private mutating func emitOrdinaryBytesPreservingUTF8Boundary(
        into output: inout [UInt8]
    ) {
        let retained = TerminalByteEncoding.trailingIncompleteSequenceLength(
            in: pending
        )
        let count = pending.count - retained
        output.append(contentsOf: pending.prefix(count))
        pending.removeFirst(count)
    }

    private mutating func retainTerminatorPrefix(
        for envelope: TerminalStringEnvelope
    ) {
        let maximumEscapes = envelope == .tmux ? 2 : 1
        let trailingEscapes = pending.reversed()
            .prefix(while: { $0 == Self.escape })
            .prefix(maximumEscapes)
            .count
        pending = Array(repeating: Self.escape, count: trailingEscapes)
    }
}
