import Foundation

enum LyricsOrigin: String, Codable, Sendable {
    case localOverride
    case manualLRCLIB
    case cache
    case lrclib
    case appleMusic

    var localizedName: String {
        switch self {
        case .localOverride: L10n.text("本地 LRC")
        case .manualLRCLIB: L10n.text("手动选择")
        case .cache: L10n.text("本地缓存")
        case .lrclib: "LRCLIB"
        case .appleMusic: "Apple Music"
        }
    }
}

struct TimedLyricsLine: Codable, Equatable, Identifiable, Sendable {
    let timestamp: TimeInterval
    let text: String

    var id: String {
        "\(timestamp)-\(text)"
    }
}

struct LyricsDocument: Codable, Equatable, Sendable {
    var trackID: String
    var origin: LyricsOrigin
    var lines: [TimedLyricsLine]
    var plainLyrics: String?
    var instrumental: Bool

    var isSynced: Bool {
        !lines.isEmpty
    }

    func activeLineIndex(at position: TimeInterval, offset: TimeInterval = 0) -> Int? {
        guard !lines.isEmpty else { return nil }

        let adjustedPosition = position + offset
        let index = lines.partitioningIndex { $0.timestamp > adjustedPosition } - 1
        return index >= 0 ? index : nil
    }

    func visibleLineIndices(around activeIndex: Int?, mode: LyricsDisplayMode) -> [Int] {
        guard !lines.isEmpty else { return [] }
        let currentIndex = min(max(activeIndex ?? 0, 0), lines.count - 1)

        switch mode {
        case .currentLine:
            return [currentIndex]
        case .surroundingLines:
            return Array(max(0, currentIndex - 1)...min(lines.count - 1, currentIndex + 1))
        }
    }
}

private extension Array {
    func partitioningIndex(where belongsInSecondPartition: (Element) -> Bool) -> Int {
        var low = 0
        var high = count

        while low < high {
            let mid = low + (high - low) / 2
            if belongsInSecondPartition(self[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }

        return low
    }
}
