import Foundation

enum LRCParser {
    private static let timestampPattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#

    static func parse(_ contents: String) -> [TimedLyricsLine] {
        guard let regex = try? NSRegularExpression(pattern: timestampPattern) else {
            return []
        }

        var parsed: [TimedLyricsLine] = []

        for rawLine in contents.components(separatedBy: .newlines) {
            let range = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
            let matches = regex.matches(in: rawLine, range: range)
            guard !matches.isEmpty else { continue }

            let lyricStart = matches.compactMap {
                Range($0.range, in: rawLine)?.upperBound
            }.max() ?? rawLine.startIndex
            let text = rawLine[lyricStart...].trimmingCharacters(in: .whitespacesAndNewlines)

            for match in matches {
                guard
                    let minutes = integer(match, group: 1, in: rawLine),
                    let seconds = integer(match, group: 2, in: rawLine)
                else {
                    continue
                }

                let fraction = fractionalSeconds(match, group: 3, in: rawLine)
                parsed.append(
                    TimedLyricsLine(
                        timestamp: TimeInterval(minutes * 60 + seconds) + fraction,
                        text: text
                    )
                )
            }
        }

        return parsed.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.text < $1.text
            }
            return $0.timestamp < $1.timestamp
        }
    }

    private static func integer(
        _ match: NSTextCheckingResult,
        group: Int,
        in string: String
    ) -> Int? {
        guard match.range(at: group).location != NSNotFound,
              let range = Range(match.range(at: group), in: string)
        else {
            return nil
        }
        return Int(string[range])
    }

    private static func fractionalSeconds(
        _ match: NSTextCheckingResult,
        group: Int,
        in string: String
    ) -> TimeInterval {
        guard match.range(at: group).location != NSNotFound,
              let range = Range(match.range(at: group), in: string)
        else {
            return 0
        }

        let digits = String(string[range])
        guard let value = Double(digits) else { return 0 }
        return value / pow(10, Double(digits.count))
    }
}
