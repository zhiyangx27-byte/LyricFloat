import Foundation

enum LyricsRepositoryError: LocalizedError {
    case invalidLRC

    var errorDescription: String? {
        switch self {
        case .invalidLRC:
            "文件中没有识别到 LRC 时间戳，未替换当前歌词。"
        }
    }
}

actor LyricsRepository {
    struct PersistedLyrics: Codable, Sendable {
        var cache: [String: LyricsDocument] = [:]
        var overrides: [String: LyricsDocument] = [:]
        var manualSelections: [String: LyricsDocument] = [:]
        var offsets: [String: TimeInterval] = [:]

        private enum CodingKeys: String, CodingKey {
            case cache
            case overrides
            case manualSelections
            case offsets
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cache = try container.decodeIfPresent([String: LyricsDocument].self, forKey: .cache) ?? [:]
            overrides = try container.decodeIfPresent([String: LyricsDocument].self, forKey: .overrides) ?? [:]
            manualSelections = try container.decodeIfPresent(
                [String: LyricsDocument].self,
                forKey: .manualSelections
            ) ?? [:]
            offsets = try container.decodeIfPresent([String: TimeInterval].self, forKey: .offsets) ?? [:]
        }
    }

    private let remoteClient: any LyricsRemoteClient
    private let store: JSONFileStore<PersistedLyrics>
    private var persisted: PersistedLyrics?

    init(
        remoteClient: any LyricsRemoteClient = LRCLIBClient(),
        store: JSONFileStore<PersistedLyrics> = JSONFileStore(fileName: "lyrics.json")
    ) {
        self.remoteClient = remoteClient
        self.store = store
    }

    func lyrics(for snapshot: PlaybackSnapshot) async -> LyricsDocument? {
        await loadIfNeeded()
        guard let persisted else { return fallbackLyrics(for: snapshot) }

        if let local = persisted.overrides[snapshot.trackID] {
            return local
        }

        if let manual = persisted.manualSelections[snapshot.trackID] {
            return manual
        }

        if let cached = persisted.cache[snapshot.trackID] {
            return cached
        }

        do {
            if let remote = try await remoteClient.fetchLyrics(for: snapshot) {
                self.persisted?.cache[snapshot.trackID] = remote
                try? await save()
                return remote
            }
        } catch {
            AppLog.lyrics.error("LRCLIB request failed: \(error.localizedDescription, privacy: .public)")
        }

        return fallbackLyrics(for: snapshot)
    }

    func importLRC(_ contents: String, for snapshot: PlaybackSnapshot) async throws -> LyricsDocument {
        await loadIfNeeded()
        let lines = LRCParser.parse(contents)
        guard lines.contains(where: { !$0.text.isEmpty }) else {
            throw LyricsRepositoryError.invalidLRC
        }
        let document = LyricsDocument(
            trackID: snapshot.trackID,
            origin: .localOverride,
            lines: lines,
            plainLyrics: nil,
            instrumental: false
        )
        persisted?.overrides[snapshot.trackID] = document
        try await save()
        return document
    }

    func clearLocalOverride(for trackID: String) async throws {
        await loadIfNeeded()
        persisted?.overrides.removeValue(forKey: trackID)
        try await save()
    }

    func hasLocalOverride(for trackID: String) async -> Bool {
        await loadIfNeeded()
        return persisted?.overrides[trackID] != nil
    }

    func candidates(for snapshot: PlaybackSnapshot) async throws -> [LyricsCandidate] {
        try await remoteClient.fetchCandidates(for: snapshot)
    }

    func selectCandidate(_ candidate: LyricsCandidate, for snapshot: PlaybackSnapshot) async throws {
        await loadIfNeeded()
        var document = candidate.document
        document.trackID = snapshot.trackID
        document.origin = .manualLRCLIB
        persisted?.manualSelections[snapshot.trackID] = document
        try await save()
    }

    func clearManualSelection(for trackID: String) async throws {
        await loadIfNeeded()
        persisted?.manualSelections.removeValue(forKey: trackID)
        try await save()
    }

    func hasManualSelection(for trackID: String) async -> Bool {
        await loadIfNeeded()
        return persisted?.manualSelections[trackID] != nil
    }

    func offset(for trackID: String) async -> TimeInterval {
        await loadIfNeeded()
        return persisted?.offsets[trackID] ?? 0
    }

    func setOffset(_ offset: TimeInterval, for trackID: String) async {
        await loadIfNeeded()
        persisted?.offsets[trackID] = offset
        try? await save()
    }

    func clearOffset(for trackID: String) async {
        await setOffset(0, for: trackID)
    }

    func clearCache() async {
        await loadIfNeeded()
        persisted?.cache.removeAll()
        try? await save()
    }

    private func fallbackLyrics(for snapshot: PlaybackSnapshot) -> LyricsDocument? {
        guard let embeddedLyrics = snapshot.embeddedLyrics, !embeddedLyrics.isEmpty else {
            return nil
        }

        return LyricsDocument(
            trackID: snapshot.trackID,
            origin: .appleMusic,
            lines: [],
            plainLyrics: embeddedLyrics,
            instrumental: false
        )
    }

    private func loadIfNeeded() async {
        guard persisted == nil else { return }
        persisted = await store.load(default: PersistedLyrics())
    }

    private func save() async throws {
        guard let persisted else { return }
        try await store.save(persisted)
    }
}
