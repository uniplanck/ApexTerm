import Foundation

/// Bounds Kitty graphics APC sequences before SwiftTerm accumulates and decodes
/// their payload. It shares the inline-image policy used for iTerm2 images:
/// bounded locally and disabled for remote sessions by default.
public struct TerminalKittyGraphicsSafetyFilter: Sendable {
    private struct Introducer: Sendable {
        let bytes: [UInt8]
        let envelope: TerminalStringEnvelope
    }

    private struct Start: Sendable {
        let index: Int
        let payloadStart: Int
        let envelope: TerminalStringEnvelope
    }

    private enum Detection: Sendable {
        case target(Start)
        case incomplete(index: Int)
        case none
    }

    private struct End {
        let nextIndex: Int
    }

    private static let escape: UInt8 = 0x1B
    private static let introducers: [Introducer] = [
        Introducer(
            bytes: [0x90] + Array("tmux;\u{001B}\u{001B}_G".utf8),
            envelope: .tmux
        ),
        Introducer(
            bytes: [0x90] + Array("tmux;".utf8) + [0x9F, 0x47],
            envelope: .tmux
        ),
        Introducer(
            bytes: Array("\u{001B}Ptmux;\u{001B}\u{001B}_G".utf8),
            envelope: .tmux
        ),
        Introducer(
            bytes: Array("\u{001B}Ptmux;".utf8) + [0x9F, 0x47],
            envelope: .tmux
        ),
        Introducer(bytes: [0x1B, 0x5F, 0x47], envelope: .raw),
        Introducer(bytes: [0x9F, 0x47], envelope: .raw)
    ]

    public var policy: TerminalInlineImageSafetyPolicy
    public private(set) var blockedKittyGraphicsCount = 0

    private var pending: [UInt8] = []
    private var discarding: TerminalStringEnvelope?
    private var discardingSearchIndex = 0
    private var terminatorSearchIndex = 0

    public init(policy: TerminalInlineImageSafetyPolicy) {
        self.policy = policy
    }

    public mutating func updatePolicy(_ policy: TerminalInlineImageSafetyPolicy) {
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

            switch detectStart() {
            case .none:
                terminatorSearchIndex = 0
                emitOrdinaryBytesPreservingUTF8Boundary(into: &output)
                return output

            case let .incomplete(index):
                terminatorSearchIndex = 0
                if index > 0 {
                    output.append(contentsOf: pending.prefix(index))
                    pending.removeFirst(index)
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
                    if pending.count > maximumAllowedBytes {
                        blockedKittyGraphicsCount += 1
                        discarding = start.envelope
                        discardingSearchIndex = terminatorSearchIndex
                        terminatorSearchIndex = 0
                    } else {
                        return output
                    }
                    continue
                }

                terminatorSearchIndex = 0
                if allows(sequenceBytes: end.nextIndex) {
                    output.append(contentsOf: pending.prefix(end.nextIndex))
                } else {
                    blockedKittyGraphicsCount += 1
                }
                pending.removeFirst(end.nextIndex)
            }
        }
        return output
    }

    private var maximumAllowedBytes: Int {
        switch policy.access {
        case .disabled:
            return 1_024
        case let .bounded(maximumSequenceBytes):
            return max(1_024, maximumSequenceBytes)
        }
    }

    private func allows(sequenceBytes: Int) -> Bool {
        switch policy.access {
        case .disabled:
            return false
        case let .bounded(maximumSequenceBytes):
            return sequenceBytes <= max(1_024, maximumSequenceBytes)
        }
    }

    private func detectStart() -> Detection {
        var earliestIncomplete: Int?

        for index in pending.indices {
            for introducer in Self.introducers {
                if introducer.bytes.first.map({ $0 >= 0x80 }) == true,
                   TerminalByteEncoding.isPartOfValidUTF8Sequence(
                        at: index,
                        in: pending
                   ) {
                    continue
                }
                let available = pending.count - index
                let compared = min(available, introducer.bytes.count)
                guard pending[index..<(index + compared)]
                    .elementsEqual(introducer.bytes.prefix(compared)) else {
                    continue
                }
                guard available >= introducer.bytes.count else {
                    earliestIncomplete = min(earliestIncomplete ?? index, index)
                    continue
                }
                return .target(
                    Start(
                        index: index,
                        payloadStart: index + introducer.bytes.count,
                        envelope: introducer.envelope
                    )
                )
            }
        }

        if let earliestIncomplete {
            return .incomplete(index: earliestIncomplete)
        }
        return .none
    }

    private func terminator(
        from start: Int,
        envelope: TerminalStringEnvelope
    ) -> End? {
        switch envelope {
        case .raw:
            var index = start
            while index < pending.count {
                if pending[index] == 0x9C {
                    return End(nextIndex: index + 1)
                }
                if pending[index] == Self.escape {
                    guard index + 1 < pending.count else { return nil }
                    if pending[index + 1] == 0x5C {
                        return End(nextIndex: index + 2)
                    }
                    return End(nextIndex: index)
                }
                index += 1
            }

        case .tmux:
            var index = start
            while index + 1 < pending.count {
                if pending[index] == Self.escape,
                   pending[index + 1] == 0x5C,
                   (index == start || pending[index - 1] != Self.escape) {
                    return End(nextIndex: index + 2)
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
