import Foundation

/// Removes Sixel DCS images before SwiftTerm's unbounded decoder receives them.
/// Other DCS sequences are preserved byte-for-byte across arbitrary chunking,
/// including 7-bit, 8-bit C1, and tmux passthrough framing.
public struct TerminalSixelSafetyFilter: Sendable {
    private enum Mode: Sendable {
        case scanning
        case passingDCS(envelope: TerminalStringEnvelope)
        case discardingSixel(envelope: TerminalStringEnvelope)
    }

    private struct Introducer: Sendable {
        let bytes: [UInt8]
        let envelope: TerminalStringEnvelope
    }

    private struct DCSStart: Sendable {
        let index: Int
        let headerStart: Int
        let envelope: TerminalStringEnvelope
    }

    private struct DCSFinal: Sendable {
        let byte: UInt8
        let nextIndex: Int
    }

    private enum Detection: Sendable {
        case start(DCSStart)
        case incomplete(index: Int)
        case none
    }

    private static let escape: UInt8 = 0x1B
    private static let introducers: [Introducer] = [
        Introducer(
            bytes: [0x90] + Array("tmux;\u{001B}\u{001B}P".utf8),
            envelope: .tmux
        ),
        Introducer(
            bytes: [0x90] + Array("tmux;".utf8) + [0x90],
            envelope: .tmux
        ),
        Introducer(
            bytes: Array("\u{001B}Ptmux;\u{001B}\u{001B}P".utf8),
            envelope: .tmux
        ),
        Introducer(
            bytes: Array("\u{001B}Ptmux;".utf8) + [0x90],
            envelope: .tmux
        ),
        Introducer(bytes: [0x1B, 0x50], envelope: .raw),
        Introducer(bytes: [0x90], envelope: .raw)
    ]
    private static let maximumHeaderBytes = 64

    public private(set) var blockedSixelCount = 0

    private var pending: [UInt8] = []
    private var mode: Mode = .scanning

    public init() {}

    public mutating func resetStreamState() {
        pending.removeAll(keepingCapacity: true)
        mode = .scanning
    }

    public mutating func feed(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        pending.append(contentsOf: bytes)
        var output: [UInt8] = []

        while !pending.isEmpty {
            switch mode {
            case let .passingDCS(envelope):
                guard let end = stringTerminator(from: 0, envelope: envelope) else {
                    emitSafeDCSBody(into: &output, envelope: envelope)
                    return output
                }
                output.append(contentsOf: pending.prefix(end))
                pending.removeFirst(end)
                mode = .scanning

            case let .discardingSixel(envelope):
                guard let end = stringTerminator(from: 0, envelope: envelope) else {
                    retainTerminatorPrefix(for: envelope)
                    return output
                }
                pending.removeFirst(end)
                mode = .scanning

            case .scanning:
                switch detectDCSStart() {
                case .none:
                    emitOrdinaryBytesPreservingUTF8Boundary(into: &output)
                    return output

                case let .incomplete(index):
                    if index > 0 {
                        output.append(contentsOf: pending.prefix(index))
                        pending.removeFirst(index)
                    }
                    return output

                case let .start(start):
                    if start.index > 0 {
                        output.append(contentsOf: pending.prefix(start.index))
                        pending.removeFirst(start.index)
                        continue
                    }

                    switch dcsFinalByte(from: start.headerStart) {
                    case .none:
                        if pending.count > Self.maximumHeaderBytes {
                            output.append(contentsOf: pending.prefix(start.headerStart))
                            pending.removeFirst(start.headerStart)
                        } else {
                            return output
                        }
                    case let .some(final) where final.byte == 0x71:
                        blockedSixelCount += 1
                        pending.removeFirst(final.nextIndex)
                        mode = .discardingSixel(envelope: start.envelope)
                    case let .some(final):
                        output.append(contentsOf: pending.prefix(final.nextIndex))
                        pending.removeFirst(final.nextIndex)
                        mode = .passingDCS(envelope: start.envelope)
                    }
                }
            }
        }

        return output
    }

    private func detectDCSStart() -> Detection {
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
                    return .incomplete(index: index)
                }
                return .start(
                    DCSStart(
                        index: index,
                        headerStart: index + introducer.bytes.count,
                        envelope: introducer.envelope
                    )
                )
            }
        }

        return .none
    }

    private func dcsFinalByte(from start: Int) -> DCSFinal? {
        guard start < pending.count else { return nil }
        let end = min(pending.count, start + Self.maximumHeaderBytes)
        for index in start..<end {
            let byte = pending[index]
            if byte >= 0x40, byte <= 0x7E {
                return DCSFinal(byte: byte, nextIndex: index + 1)
            }
            guard byte >= 0x20, byte <= 0x3F else {
                return DCSFinal(byte: byte, nextIndex: index + 1)
            }
        }
        return nil
    }

    private func stringTerminator(
        from start: Int,
        envelope: TerminalStringEnvelope
    ) -> Int? {
        switch envelope {
        case .raw:
            var index = start
            while index < pending.count {
                if pending[index] == 0x9C {
                    return index + 1
                }
                if pending[index] == Self.escape {
                    guard index + 1 < pending.count else { return nil }
                    if pending[index + 1] == 0x5C {
                        return index + 2
                    }
                    return index
                }
                index += 1
            }

        case .tmux:
            var index = start
            while index + 1 < pending.count {
                if pending[index] == Self.escape,
                   pending[index + 1] == 0x5C,
                   (index == start || pending[index - 1] != Self.escape) {
                    return index + 2
                }
                index += 1
            }
        }
        return nil
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

    private mutating func emitSafeDCSBody(
        into output: inout [UInt8],
        envelope: TerminalStringEnvelope
    ) {
        let retained = trailingEscapeCount(for: envelope)
        let count = pending.count - retained
        output.append(contentsOf: pending.prefix(count))
        pending.removeFirst(count)
    }

    private mutating func retainTerminatorPrefix(
        for envelope: TerminalStringEnvelope
    ) {
        pending = Array(
            repeating: Self.escape,
            count: trailingEscapeCount(for: envelope)
        )
    }

    private func trailingEscapeCount(
        for envelope: TerminalStringEnvelope
    ) -> Int {
        let maximumEscapes = envelope == .tmux ? 2 : 1
        return pending.reversed()
            .prefix(while: { $0 == Self.escape })
            .prefix(maximumEscapes)
            .count
    }
}
