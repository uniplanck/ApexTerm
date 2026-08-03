import Foundation

public enum TerminalInlineImageAccess: Equatable, Sendable {
    case disabled
    case bounded(maximumSequenceBytes: Int)
}

public struct TerminalInlineImageSafetyPolicy: Equatable, Sendable {
    public var access: TerminalInlineImageAccess

    public init(access: TerminalInlineImageAccess) {
        self.access = access
    }

    public static let localDefault = Self(
        access: .bounded(maximumSequenceBytes: 8 * 1_024 * 1_024)
    )
    public static let remoteDefault = Self(access: .disabled)
}

/// Bounds iTerm2 OSC 1337 inline-image sequences before SwiftTerm decodes Base64.
public struct TerminalInlineImageSafetyFilter: Sendable {
    private enum Envelope: Sendable { case raw, tmux }

    private struct Start {
        let index: Int
        let envelope: Envelope
        let payloadStart: Int
    }

    private struct End {
        let nextIndex: Int
    }

    private static let escape: UInt8 = 0x1B
    private static let rawSignature = Array("\u{001B}]1337;File=".utf8)
    private static let tmuxSignature = Array("\u{001B}Ptmux;\u{001B}\u{001B}]1337;File=".utf8)

    public var policy: TerminalInlineImageSafetyPolicy
    public private(set) var blockedInlineImageCount = 0

    private var pending: [UInt8] = []
    private var discarding: Envelope?

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
    }

    public mutating func feed(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        pending.append(contentsOf: bytes)
        var output: [UInt8] = []

        while !pending.isEmpty {
            if let envelope = discarding {
                guard let end = terminator(from: 0, envelope: envelope) else {
                    pending = pending.last == Self.escape ? [Self.escape] : []
                    return output
                }
                pending.removeFirst(end.nextIndex)
                discarding = nil
                continue
            }

            guard let start = sequenceStart() else {
                let retained = signaturePrefixLength()
                let count = pending.count - retained
                output.append(contentsOf: pending.prefix(count))
                pending.removeFirst(count)
                return output
            }

            if start.index > 0 {
                output.append(contentsOf: pending.prefix(start.index))
                pending.removeFirst(start.index)
                continue
            }

            guard let end = terminator(
                from: start.payloadStart,
                envelope: start.envelope
            ) else {
                if pending.count > maximumAllowedBytes {
                    blockedInlineImageCount += 1
                    discarding = start.envelope
                } else {
                    return output
                }
                continue
            }

            if allows(sequenceBytes: end.nextIndex) {
                output.append(contentsOf: pending.prefix(end.nextIndex))
            } else {
                blockedInlineImageCount += 1
            }
            pending.removeFirst(end.nextIndex)
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

    private func sequenceStart() -> Start? {
        let raw = firstIndex(of: Self.rawSignature)
        let tmux = firstIndex(of: Self.tmuxSignature)
        if let tmux, tmux <= (raw ?? Int.max) {
            return Start(
                index: tmux,
                envelope: .tmux,
                payloadStart: tmux + Self.tmuxSignature.count
            )
        }
        if let raw {
            return Start(
                index: raw,
                envelope: .raw,
                payloadStart: raw + Self.rawSignature.count
            )
        }
        return nil
    }

    private func firstIndex(of signature: [UInt8]) -> Int? {
        guard pending.count >= signature.count else { return nil }
        for index in 0...(pending.count - signature.count) {
            if pending[index..<(index + signature.count)].elementsEqual(signature) {
                return index
            }
        }
        return nil
    }

    private func signaturePrefixLength() -> Int {
        let upper = min(
            pending.count,
            max(Self.rawSignature.count, Self.tmuxSignature.count) - 1
        )
        guard upper > 0 else { return 0 }
        for length in stride(from: upper, through: 1, by: -1) {
            let suffix = pending.suffix(length)
            if length < Self.rawSignature.count,
               suffix.elementsEqual(Self.rawSignature.prefix(length)) {
                return length
            }
            if length < Self.tmuxSignature.count,
               suffix.elementsEqual(Self.tmuxSignature.prefix(length)) {
                return length
            }
        }
        return 0
    }

    private func terminator(from start: Int, envelope: Envelope) -> End? {
        switch envelope {
        case .raw:
            var index = start
            while index < pending.count {
                if pending[index] == 0x07 {
                    return End(nextIndex: index + 1)
                }
                if pending[index] == Self.escape,
                   index + 1 < pending.count,
                   pending[index + 1] == 0x5C {
                    return End(nextIndex: index + 2)
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
}
