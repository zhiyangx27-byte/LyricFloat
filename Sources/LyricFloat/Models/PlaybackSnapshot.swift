import Foundation

enum PlaybackState: String, Codable, Sendable {
    case playing
    case paused
    case stopped
}

struct PlaybackSnapshot: Equatable, Sendable {
    let sourceID: String
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let state: PlaybackState
    let embeddedLyrics: String?

    var displayTitle: String {
        artist.isEmpty ? title : "\(title) — \(artist)"
    }
}

struct PlaybackPositionInterpolator: Equatable, Sendable {
    let anchorPosition: TimeInterval
    let duration: TimeInterval
    let state: PlaybackState
    let anchorUptime: TimeInterval

    init(snapshot: PlaybackSnapshot, uptime: TimeInterval) {
        anchorPosition = snapshot.position
        duration = snapshot.duration
        state = snapshot.state
        anchorUptime = uptime
    }

    func position(at uptime: TimeInterval) -> TimeInterval {
        guard state == .playing else {
            return clamped(anchorPosition)
        }

        return clamped(anchorPosition + max(0, uptime - anchorUptime))
    }

    private func clamped(_ value: TimeInterval) -> TimeInterval {
        min(max(0, value), max(0, duration))
    }
}
