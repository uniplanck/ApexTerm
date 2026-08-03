import Foundation

/// Removes Sixel DCS images before SwiftTerm's unbounded decoder receives them.
/// Other DCS sequences are preserved byte-for-byte across arbitrary chunking.
public struct TerminalSixelSafetyFilter: Sendable {
    private enum Mode: Sendable {
        case scanning
        case passingDCS
        case discardingSixel(tmuxEnvelope: Bool)
    }

    private static let escape: UInt8 = 0x1B
    private static let dcsStart: [UInt8] = [0x1B, 0x50]
    private static let tmuxInnerDCSStart: [UInt8] = [
        0x1B, 0x50, 0x74, 0x6D, 0x75, 0x78, 0x3B,
        0x1B, 0x1B, 0x50
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
            case .passingDCS:
                guard let end = rawStringTerminator(from: 0) else {
                    emitSafeDCSBody(into: &output)
                    return output
                }
                output.append(contentsOf: pending.prefix(end))
                pending.removeFirst(end)
                mode = .scanning

            case let .discardingSixel(tmuxEnvelope):
                let end = tmuxEnvelope
                    ? tmuxStringTerminator(from: 0)
                    : rawStringTerminator(from: 0)
                guard let end else {
                    let maximumRetainedEscapes = tmuxEnvelope ? 2 : 1
                    let trailingEscapes = pending.reversed()
                        .prefix(while: { $0 == Self.escape })
                        .prefix(maximumRetainedEscapes)
                        .count
                    pending = Array(repeating: Self.escape, count: trailingEscapes)
                    return output
                }
                pending.removeFirst(end)
                mode = .scanning

            case .scanning:
                guard let start = firstDCSStart() else {
                    let retained = pending.last == Self.escape ? 1 : 0
                    let count = pending.count - retained
                    output.append(contentsOf: pending.prefix(count))
                    pending.removeFirst(count)
                    return output
                }

                if start > 0 {
                    output.append(contentsOf: pending.prefix(start))
                    pending.removeFirst(start)
                    continue
                }

                if isPrefixOfTmuxInnerDCSStart() {
                    guard pending.count >= Self.tmuxInnerDCSStart.count else {
                        return output
                    }
                    if pending.prefix(Self.tmuxInnerDCSStart.count)
                        .elementsEqual(Self.tmuxInnerDCSStart) {
                        switch dcsFinalByte(from: Self.tmuxInnerDCSStart.count) {
                        case .none:
                            return output
                        case .some(0x71):
                            blockedSixelCount += 1
                            mode = .discardingSixel(tmuxEnvelope: true)
                            continue
                        case .some:
                            mode = .passingDCS
                            continue
                        }
                    }
                }

                switch dcsFinalByte(from: Self.dcsStart.count) {
                case .none:
                    if pending.count > Self.maximumHeaderBytes {
                        output.append(contentsOf: pending.prefix(Self.dcsStart.count))
                        pending.removeFirst(Self.dcsStart.count)
                    } else {
                        return output
                    }
                case .some(0x71):
                    blockedSixelCount += 1
                    mode = .discardingSixel(tmuxEnvelope: false)
                case .some:
                    mode = .passingDCS
                }
            }
        }

        return output
    }

    private func firstDCSStart() -> Int? {
        guard pending.count >= 2 else { return nil }
        for index in 0..<(pending.count - 1) {
            if pending[index] == Self.escape, pending[index + 1] == 0x50 {
                return index
            }
        }
        return nil
    }

    private func isPrefixOfTmuxInnerDCSStart() -> Bool {
        let count = min(pending.count, Self.tmuxInnerDCSStart.count)
        return pending.prefix(count).elementsEqual(Self.tmuxInnerDCSStart.prefix(count))
    }

    private func dcsFinalByte(from start: Int) -> UInt8? {
        guard start < pending.count else { return nil }
        let end = min(pending.count, start + Self.maximumHeaderBytes)
        for byte in pending[start..<end] {
            if byte >= 0x40, byte <= 0x7E {
                return byte
            }
            guard (byte >= 0x20 && byte <= 0x3F) else {
                return byte
            }
        }
        return nil
    }

    private func rawStringTerminator(from start: Int) -> Int? {
        var index = start
        while index + 1 < pending.count {
            if pending[index] == Self.escape, pending[index + 1] == 0x5C {
                return index + 2
            }
            index += 1
        }
        return nil
    }

    private func tmuxStringTerminator(from start: Int) -> Int? {
        var index = start
        while index + 1 < pending.count {
            if pending[index] == Self.escape,
               pending[index + 1] == 0x5C,
               (index == start || pending[index - 1] != Self.escape) {
                return index + 2
            }
            index += 1
        }
        return nil
    }

    private mutating func emitSafeDCSBody(into output: inout [UInt8]) {
        let retained = pending.last == Self.escape ? 1 : 0
        let count = pending.count - retained
        output.append(contentsOf: pending.prefix(count))
        pending.removeFirst(count)
    }
}
