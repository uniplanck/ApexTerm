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
/// Allowed sequences are preserved byte-for-byte, including tmux passthrough.
public struct TerminalEscapeSequenceTrustFilter: Sendable {
    private enum Envelope: Sendable { case raw, tmux }
    private enum ClipboardAction { case read, write, malformed }

    private struct Start {
        let index: Int
        let payloadStart: Int
        let envelope: Envelope
    }

    private struct End {
        let payloadEnd: Int
        let nextIndex: Int
    }

    private static let escape: UInt8 = 0x1B
    private static let rawSignature: [UInt8] = [0x1B, 0x5D, 0x35, 0x32, 0x3B]
    private static let tmuxSignature: [UInt8] = [
        0x1B, 0x50, 0x74, 0x6D, 0x75, 0x78, 0x3B,
        0x1B, 0x1B, 0x5D, 0x35, 0x32, 0x3B
    ]

    public var policy: TerminalEscapeSequenceTrustPolicy
    public let maximumOSC52Bytes: Int
    public private(set) var blockedOSC52Count = 0

    private var pending: [UInt8] = []
    private var discarding: Envelope?

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
    }

    public mutating func feed(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        pending.append(contentsOf: bytes)
        var output: [UInt8] = []

        while !pending.isEmpty {
            if let envelope = discarding {
                guard let end = terminator(from: 0, envelope: envelope) else {
                    retainTerminatorPrefix()
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
                if pending.count > maximumOSC52Bytes {
                    blockedOSC52Count += 1
                    discarding = start.envelope
                } else {
                    return output
                }
                continue
            }

            let length = end.nextIndex
            let action = clipboardAction(in: pending[start.payloadStart..<end.payloadEnd])
            if length <= maximumOSC52Bytes, allows(action) {
                output.append(contentsOf: pending.prefix(length))
            } else {
                blockedOSC52Count += 1
            }
            pending.removeFirst(length)
        }
        return output
    }

    private func sequenceStart() -> Start? {
        let raw = firstIndex(of: Self.rawSignature)
        let tmux = firstIndex(of: Self.tmuxSignature)
        if let tmux, tmux <= (raw ?? Int.max) {
            return Start(
                index: tmux,
                payloadStart: tmux + Self.tmuxSignature.count,
                envelope: .tmux
            )
        }
        if let raw {
            return Start(
                index: raw,
                payloadStart: raw + Self.rawSignature.count,
                envelope: .raw
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
                    return End(payloadEnd: index, nextIndex: index + 1)
                }
                if pending[index] == Self.escape,
                   index + 1 < pending.count,
                   pending[index + 1] == 0x5C {
                    return End(payloadEnd: index, nextIndex: index + 2)
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

    private mutating func retainTerminatorPrefix() {
        pending = pending.last == Self.escape ? [Self.escape] : []
    }
}
