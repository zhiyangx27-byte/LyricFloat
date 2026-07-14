import Foundation
import ScriptingBridge

@MainActor
final class AppleMusicSource: MediaSource {
    let sourceID = "com.apple.Music"

    private var application: SBApplication? {
        SBApplication(bundleIdentifier: sourceID)
    }

    func snapshot() throws -> PlaybackSnapshot? {
        guard let application, application.isRunning else {
            return nil
        }

        let state = playbackState(from: resolvedValue(application, key: "playerState"))
        guard state != .stopped else {
            return nil
        }

        guard let track = resolvedValue(application, key: "currentTrack") as? NSObject else {
            throw MediaSourceError.missingTrackMetadata
        }

        let title = stringValue(resolvedValue(track, key: "name"))
        guard !title.isEmpty else {
            throw MediaSourceError.missingTrackMetadata
        }

        let artist = stringValue(resolvedValue(track, key: "artist"))
        let album = stringValue(resolvedValue(track, key: "album"))
        let duration = numberValue(resolvedValue(track, key: "duration"))
        let position = numberValue(resolvedValue(application, key: "playerPosition"))
        let persistentID = stringValue(resolvedValue(track, key: "persistentID"))
        let databaseID = stringValue(resolvedValue(track, key: "databaseID"))
        let embeddedLyrics = optionalString(resolvedValue(track, key: "lyrics"))
        let trackID = persistentID.isEmpty
            ? (databaseID.isEmpty ? "\(title)|\(artist)|\(album)|\(Int(duration))" : databaseID)
            : persistentID

        return PlaybackSnapshot(
            sourceID: sourceID,
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position,
            state: state,
            embeddedLyrics: embeddedLyrics
        )
    }

    func playPause() {
        perform("playpause")
    }

    func nextTrack() {
        perform("nextTrack")
    }

    func previousTrack() {
        perform("previousTrack")
    }

    private func perform(_ selectorName: String) {
        guard let application else { return }
        _ = application.perform(NSSelectorFromString(selectorName))
    }

    private func playbackState(from value: Any?) -> PlaybackState {
        if let number = value as? NSNumber {
            switch fourCharacterCode(number.uint32Value) {
            case "kPSP": return .playing
            case "kPSp": return .paused
            default: return .stopped
            }
        }

        let state = stringValue(value).lowercased()
        if state.contains("playing") {
            return .playing
        }
        if state.contains("paused") {
            return .paused
        }

        return .stopped
    }

    private func resolvedValue(_ object: NSObject, key: String) -> Any? {
        let value = object.value(forKey: key)
        if let scriptingObject = value as? SBObject {
            return scriptingObject.get()
        }
        return value
    }

    private func stringValue(_ value: Any?) -> String {
        switch value {
        case let value as String:
            value
        case let value as NSString:
            value as String
        case let value as NSNumber:
            String(value.uint32Value, radix: 16)
        case .none:
            ""
        default:
            String(describing: value!)
        }
    }

    private func optionalString(_ value: Any?) -> String? {
        let value = stringValue(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func numberValue(_ value: Any?) -> TimeInterval {
        switch value {
        case let value as NSNumber:
            value.doubleValue
        case let value as Double:
            value
        case let value as Int:
            TimeInterval(value)
        case let value as String:
            TimeInterval(value) ?? 0
        default:
            0
        }
    }

    private func fourCharacterCode(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? ""
    }
}
