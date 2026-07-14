import Foundation

@MainActor
protocol MediaSource: AnyObject {
    var sourceID: String { get }

    func snapshot() throws -> PlaybackSnapshot?
    func playPause()
    func nextTrack()
    func previousTrack()
}

enum MediaSourceError: LocalizedError {
    case unavailable
    case missingTrackMetadata

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Music 当前不可用。"
        case .missingTrackMetadata:
            "无法读取当前歌曲信息。"
        }
    }
}
