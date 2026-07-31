import Foundation

public enum LocalShellNaming {
    public static let baseTitle = "Local Shell"

    public static func title(number: Int) -> String {
        "\(baseTitle) (\(String(format: "%02d", max(1, number))))"
    }

    public static func automaticNumber(in title: String) -> Int? {
        let prefix = "\(baseTitle) ("
        guard title.hasPrefix(prefix), title.hasSuffix(")") else { return nil }

        let start = title.index(title.startIndex, offsetBy: prefix.count)
        let end = title.index(before: title.endIndex)
        guard start < end,
              let number = Int(title[start..<end]),
              number > 0 else {
            return nil
        }
        return number
    }

    public static func isAutomaticTitle(_ title: String) -> Bool {
        title == baseTitle || automaticNumber(in: title) != nil
    }

    public static func nextAvailableNumber(in titles: [String]) -> Int {
        let used = Set(titles.compactMap(automaticNumber(in:)))
        var candidate = 1
        while used.contains(candidate) {
            candidate += 1
        }
        return candidate
    }

    public static func normalizedAutomaticTitles(_ titles: [String]) -> [String] {
        var result = titles
        var used = Set<Int>()
        var needsAssignment: [Int] = []

        for index in titles.indices {
            let value = titles[index]
            if value == baseTitle {
                needsAssignment.append(index)
            } else if let number = automaticNumber(in: value) {
                if used.insert(number).inserted {
                    result[index] = title(number: number)
                } else {
                    needsAssignment.append(index)
                }
            }
        }

        for index in needsAssignment {
            var candidate = 1
            while used.contains(candidate) {
                candidate += 1
            }
            used.insert(candidate)
            result[index] = title(number: candidate)
        }

        return result
    }
}
