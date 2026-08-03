import Foundation

enum TerminalStringEnvelope: Equatable, Sendable {
    case raw
    case tmux
}

struct TerminalStringSequenceStart: Sendable {
    let index: Int
    let payloadStart: Int
    let envelope: TerminalStringEnvelope
}

struct TerminalStringSequenceCandidate: Sendable {
    let index: Int
    let envelope: TerminalStringEnvelope
}

enum TerminalStringSequenceDetection: Sendable {
    case target(TerminalStringSequenceStart)
    case incomplete(TerminalStringSequenceCandidate)
    case none
}

/// Locates one OSC command across arbitrary PTY chunking. SwiftTerm accepts both
/// 7-bit and context-sensitive C1 introducers, and its numeric parser returns the
/// decimal prefix before any non-digit. Security filters must recognize the same
/// command language, including leading zeroes and junk before the first semicolon.
struct TerminalOSCSequenceMatcher: Sendable {
    private struct Introducer: Sendable {
        let bytes: [UInt8]
        let envelope: TerminalStringEnvelope
    }

    private enum SeparatorDetection: Sendable {
        case separator(Int)
        case terminated
        case incomplete
    }

    private static let introducers: [Introducer] = [
        Introducer(
            bytes: [0x90] + Array("tmux;\u{001B}\u{001B}]".utf8),
            envelope: .tmux
        ),
        Introducer(
            bytes: [0x90] + Array("tmux;".utf8) + [0x9D],
            envelope: .tmux
        ),
        Introducer(
            bytes: Array("\u{001B}Ptmux;\u{001B}\u{001B}]".utf8),
            envelope: .tmux
        ),
        Introducer(
            bytes: Array("\u{001B}Ptmux;".utf8) + [0x9D],
            envelope: .tmux
        ),
        Introducer(bytes: [0x1B, 0x5D], envelope: .raw),
        Introducer(bytes: [0x9D], envelope: .raw)
    ]

    private let targetCode: [UInt8]
    private let requiredPayloadPrefix: [UInt8]

    init(targetCode: Int, requiredPayloadPrefix: [UInt8] = []) {
        self.targetCode = Array(String(targetCode).utf8)
        self.requiredPayloadPrefix = requiredPayloadPrefix
    }

    func detect(in bytes: [UInt8]) -> TerminalStringSequenceDetection {
        guard !bytes.isEmpty else { return .none }
        var earliestIncomplete: TerminalStringSequenceCandidate?

        for index in bytes.indices {
            for introducer in Self.introducers {
                if introducer.bytes.first.map({ $0 >= 0x80 }) == true,
                   TerminalByteEncoding.isPartOfValidUTF8Sequence(
                        at: index,
                        in: bytes
                   ) {
                    continue
                }

                let available = bytes.count - index
                let compared = min(available, introducer.bytes.count)
                guard bytes[index..<(index + compared)]
                    .elementsEqual(introducer.bytes.prefix(compared)) else {
                    continue
                }

                let candidate = TerminalStringSequenceCandidate(
                    index: index,
                    envelope: introducer.envelope
                )
                guard available >= introducer.bytes.count else {
                    return .incomplete(candidate)
                }

                let codeStart = index + introducer.bytes.count
                switch parseTarget(
                    in: bytes,
                    codeStart: codeStart,
                    candidate: candidate
                ) {
                case let .target(start):
                    return .target(start)
                case let .incomplete(incomplete):
                    if earliestIncomplete == nil
                            || incomplete.index < earliestIncomplete!.index {
                        earliestIncomplete = incomplete
                    }
                case .none:
                    continue
                }
            }
        }

        if let earliestIncomplete {
            return .incomplete(earliestIncomplete)
        }
        return .none
    }

    private func parseTarget(
        in bytes: [UInt8],
        codeStart: Int,
        candidate: TerminalStringSequenceCandidate
    ) -> TerminalStringSequenceDetection {
        var numericEnd = codeStart
        while numericEnd < bytes.count,
              bytes[numericEnd] >= 0x30,
              bytes[numericEnd] <= 0x39 {
            numericEnd += 1
        }
        guard numericEnd > codeStart else {
            return numericEnd == bytes.count ? .incomplete(candidate) : .none
        }
        guard numericEnd < bytes.count else { return .incomplete(candidate) }
        guard matchesTargetCode(bytes[codeStart..<numericEnd]) else { return .none }

        let separator: Int
        switch payloadSeparator(
            in: bytes,
            from: numericEnd,
            envelope: candidate.envelope
        ) {
        case let .separator(index):
            separator = index
        case .terminated:
            return .none
        case .incomplete:
            return .incomplete(candidate)
        }
        var payloadStart = separator + 1

        if !requiredPayloadPrefix.isEmpty {
            let available = bytes.count - payloadStart
            let compared = min(available, requiredPayloadPrefix.count)
            guard bytes[payloadStart..<(payloadStart + compared)]
                .elementsEqual(requiredPayloadPrefix.prefix(compared)) else {
                return .none
            }
            guard available >= requiredPayloadPrefix.count else {
                return .incomplete(candidate)
            }
            payloadStart += requiredPayloadPrefix.count
        }

        return .target(
            TerminalStringSequenceStart(
                index: candidate.index,
                payloadStart: payloadStart,
                envelope: candidate.envelope
            )
        )
    }

    private func payloadSeparator(
        in bytes: [UInt8],
        from start: Int,
        envelope: TerminalStringEnvelope
    ) -> SeparatorDetection {
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x3B {
                return .separator(index)
            }
            if byte == 0x07 || byte == 0x9C {
                return .terminated
            }
            if byte == 0x1B {
                if envelope == .raw {
                    return .terminated
                }
                guard index + 1 < bytes.count else { return .incomplete }
                if bytes[index + 1] == 0x5C {
                    return .terminated
                }
                if bytes[index + 1] == 0x1B,
                   index + 2 < bytes.count,
                   bytes[index + 2] == 0x5C {
                    return .terminated
                }
            }
            index += 1
        }
        return .incomplete
    }

    private func matchesTargetCode(_ digits: ArraySlice<UInt8>) -> Bool {
        let firstNonZero = digits.firstIndex(where: { $0 != 0x30 })
        let normalized: ArraySlice<UInt8>
        if let firstNonZero {
            normalized = digits[firstNonZero...]
        } else {
            normalized = digits.suffix(1)
        }
        return normalized.elementsEqual(targetCode)
    }
}
