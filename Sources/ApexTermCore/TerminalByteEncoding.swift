import Foundation

enum TerminalByteEncoding {
    static func isPartOfValidUTF8Sequence(
        at index: Int,
        in bytes: [UInt8]
    ) -> Bool {
        guard bytes.indices.contains(index) else { return false }
        let byte = bytes[index]
        guard isContinuation(byte) else { return false }

        var start = index
        var continuationCount = 0
        while start > 0,
              continuationCount < 3,
              isContinuation(bytes[start]) {
            start -= 1
            continuationCount += 1
        }
        let lead = bytes[start]
        guard let length = sequenceLength(for: lead),
              start + length <= bytes.count,
              index < start + length else {
            return false
        }
        guard bytes[(start + 1)..<(start + length)].allSatisfy(isContinuation) else {
            return false
        }
        return isValidScalarPrefix(
            lead: lead,
            firstContinuation: bytes[start + 1],
            length: length
        )
    }

    static func trailingIncompleteSequenceLength(in bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }
        let lowerBound = max(0, bytes.count - 4)

        for start in stride(from: bytes.count - 1, through: lowerBound, by: -1) {
            guard let length = sequenceLength(for: bytes[start]) else { continue }
            let available = bytes.count - start
            guard available < length else { continue }
            guard available == 1
                    || bytes[(start + 1)...].allSatisfy(isContinuation) else {
                continue
            }
            if available >= 2,
               !isValidScalarPrefix(
                    lead: bytes[start],
                    firstContinuation: bytes[start + 1],
                    length: length
               ) {
                return 0
            }
            return available
        }
        return 0
    }

    private static func sequenceLength(for lead: UInt8) -> Int? {
        switch lead {
        case 0xC2...0xDF: return 2
        case 0xE0...0xEF: return 3
        case 0xF0...0xF4: return 4
        default: return nil
        }
    }

    private static func isContinuation(_ byte: UInt8) -> Bool {
        byte >= 0x80 && byte <= 0xBF
    }

    private static func isValidScalarPrefix(
        lead: UInt8,
        firstContinuation: UInt8,
        length: Int
    ) -> Bool {
        guard isContinuation(firstContinuation) else { return false }
        switch (lead, length) {
        case (0xE0, 3): return firstContinuation >= 0xA0
        case (0xED, 3): return firstContinuation <= 0x9F
        case (0xF0, 4): return firstContinuation >= 0x90
        case (0xF4, 4): return firstContinuation <= 0x8F
        default: return true
        }
    }
}
