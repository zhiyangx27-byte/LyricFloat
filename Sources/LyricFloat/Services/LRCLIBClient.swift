import Foundation

protocol LyricsRemoteClient: Sendable {
    func fetchLyrics(for snapshot: PlaybackSnapshot) async throws -> LyricsDocument?
    func fetchCandidates(for snapshot: PlaybackSnapshot) async throws -> [LyricsCandidate]
}

extension LyricsRemoteClient {
    func fetchCandidates(for snapshot: PlaybackSnapshot) async throws -> [LyricsCandidate] {
        []
    }
}

struct LyricsCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: TimeInterval?
    let hasSyncedLyrics: Bool
    let score: Double
    let document: LyricsDocument

    var confidenceLabel: String {
        switch score {
        case 90...: L10n.text("高")
        case 68...: L10n.text("较高")
        case 45...: L10n.text("较低")
        default: L10n.text("低")
        }
    }
}

struct LRCLIBClient: LyricsRemoteClient {
    struct Record: Decodable, Sendable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: TimeInterval?
        let instrumental: Bool
        let plainLyrics: String?
        let syncedLyrics: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case trackName
            case artistName
            case albumName
            case duration
            case instrumental
            case plainLyrics
            case syncedLyrics
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(Int.self, forKey: .id)
            trackName = try container.decodeIfPresent(String.self, forKey: .trackName)
                ?? container.decodeIfPresent(String.self, forKey: .name)
            artistName = try container.decodeIfPresent(String.self, forKey: .artistName)
            albumName = try container.decodeIfPresent(String.self, forKey: .albumName)
            duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
            instrumental = try container.decodeIfPresent(Bool.self, forKey: .instrumental) ?? false
            plainLyrics = try container.decodeIfPresent(String.self, forKey: .plainLyrics)
            syncedLyrics = try container.decodeIfPresent(String.self, forKey: .syncedLyrics)
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLyrics(for snapshot: PlaybackSnapshot) async throws -> LyricsDocument? {
        guard !snapshot.title.isEmpty, snapshot.duration > 0 else {
            return nil
        }

        var lastError: Error?
        do {
            if let exact = try await exactMatch(for: snapshot) {
                AppLog.lyrics.info("LRCLIB exact match resolved")
                return document(from: exact, trackID: snapshot.trackID)
            }
        } catch {
            lastError = error
        }

        let candidates = await searchCandidates(for: snapshot)
        if let best = LRCLIBMatcher.bestCandidate(for: snapshot, from: candidates) {
            AppLog.lyrics.info("LRCLIB ranked search resolved a reliable match")
            return document(from: best, trackID: snapshot.trackID)
        }

        if let lastError {
            throw lastError
        }
        return nil
    }

    func fetchCandidates(for snapshot: PlaybackSnapshot) async throws -> [LyricsCandidate] {
        guard !snapshot.title.isEmpty else { return [] }

        var records: [Record] = []
        var lastError: Error?
        for query in LRCLIBMatcher.searchQueries(for: snapshot) {
            do {
                records.append(contentsOf: try await search(query))
            } catch {
                lastError = error
            }
        }

        let candidates = uniqueRecords(records)
            .filter(hasLyrics)
            .map { record in
                LyricsCandidate(
                    id: candidateID(for: record),
                    trackName: record.trackName ?? L10n.text("未知歌名"),
                    artistName: record.artistName ?? L10n.text("未知歌手"),
                    albumName: record.albumName,
                    duration: record.duration,
                    hasSyncedLyrics: record.syncedLyrics?.isEmpty == false,
                    score: LRCLIBMatcher.score(snapshot, record),
                    document: document(from: record, trackID: snapshot.trackID, origin: .manualLRCLIB)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.hasSyncedLyrics && !rhs.hasSyncedLyrics
                }
                return lhs.score > rhs.score
            }

        if candidates.isEmpty, let lastError {
            throw lastError
        }
        return candidates
    }

    private func exactMatch(for snapshot: PlaybackSnapshot) async throws -> Record? {
        try await request(
            path: "/api/get",
            queryItems: [
                URLQueryItem(name: "track_name", value: snapshot.title),
                URLQueryItem(name: "artist_name", value: snapshot.artist),
                URLQueryItem(name: "album_name", value: snapshot.album),
                URLQueryItem(name: "duration", value: String(Int(snapshot.duration.rounded())))
            ],
            as: Record.self,
            allowsNotFound: true
        )
    }

    private func search(_ query: LRCLIBMatcher.SearchQuery) async throws -> [Record] {
        try await request(
            path: "/api/search",
            queryItems: query.queryItems,
            as: [Record].self
        ) ?? []
    }

    private func searchCandidates(for snapshot: PlaybackSnapshot) async -> [Record] {
        let queries = LRCLIBMatcher.searchQueries(for: snapshot)
        return await withTaskGroup(of: [Record].self, returning: [Record].self) { group in
            for query in queries {
                group.addTask {
                    (try? await search(query)) ?? []
                }
            }

            var records: [Record] = []
            for await result in group {
                records.append(contentsOf: result)
            }
            return records
        }
    }

    private func request<Value: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        as type: Value.Type,
        allowsNotFound: Bool = false
    ) async throws -> Value? {
        var components = URLComponents(string: "https://lrclib.net\(path)")
        components?.queryItems = queryItems
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("LyricFloat/1.1 (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        if allowsNotFound, httpResponse.statusCode == 404 {
            return nil
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func document(
        from record: Record,
        trackID: String,
        origin: LyricsOrigin = .lrclib
    ) -> LyricsDocument {
        LyricsDocument(
            trackID: trackID,
            origin: origin,
            lines: record.syncedLyrics.map(LRCParser.parse) ?? [],
            plainLyrics: record.plainLyrics,
            instrumental: record.instrumental
        )
    }

    private func uniqueRecords(_ records: [Record]) -> [Record] {
        var seen = Set<String>()
        return records.filter { seen.insert(candidateID(for: $0)).inserted }
    }

    private func candidateID(for record: Record) -> String {
        if let id = record.id {
            return "lrclib-\(id)"
        }
        return [
            record.trackName ?? "",
            record.artistName ?? "",
            record.albumName ?? "",
            record.duration.map { String(format: "%.3f", $0) } ?? ""
        ].joined(separator: "|")
    }

    private func hasLyrics(_ record: Record) -> Bool {
        record.syncedLyrics?.isEmpty == false
            || record.plainLyrics?.isEmpty == false
            || record.instrumental
    }
}

enum LRCLIBMatcher {
    struct SearchQuery: Equatable, Sendable {
        let trackName: String?
        let artistName: String?
        let freeText: String?

        var queryItems: [URLQueryItem] {
            if let freeText {
                return [URLQueryItem(name: "q", value: freeText)]
            }
            return [
                URLQueryItem(name: "track_name", value: trackName),
                URLQueryItem(name: "artist_name", value: artistName)
            ].filter { $0.value?.isEmpty == false }
        }
    }

    static func searchQueries(for snapshot: PlaybackSnapshot) -> [SearchQuery] {
        let cleanedTitle = cleanTitle(snapshot.title)
        let cleanedArtist = cleanArtist(snapshot.artist)
        var queries = [
            SearchQuery(trackName: snapshot.title, artistName: snapshot.artist, freeText: nil),
            SearchQuery(trackName: cleanedTitle, artistName: cleanedArtist, freeText: nil),
            SearchQuery(
                trackName: nil,
                artistName: nil,
                freeText: [cleanedTitle, cleanedArtist].filter { !$0.isEmpty }.joined(separator: " ")
            )
        ]

        var seen = Set<String>()
        queries = queries.filter { query in
            let key = query.queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            return !key.isEmpty && seen.insert(key).inserted
        }
        return queries
    }

    static func bestCandidate(
        for snapshot: PlaybackSnapshot,
        from candidates: [LRCLIBClient.Record]
    ) -> LRCLIBClient.Record? {
        candidates
            .filter { candidate in
                let titleSimilarity = similarity(snapshot.title, candidate.trackName ?? "")
                let artistSimilarity = similarity(snapshot.artist, candidate.artistName ?? "")
                guard let duration = candidate.duration else { return false }
                let durationDifference = abs(snapshot.duration - duration)
                return titleSimilarity >= 0.72
                    && (snapshot.artist.isEmpty || artistSimilarity >= 0.60)
                    && durationDifference <= 20
                    && (candidate.syncedLyrics?.isEmpty == false
                        || candidate.plainLyrics?.isEmpty == false
                        || candidate.instrumental)
            }
            .map { ($0, score(snapshot, $0)) }
            .filter { $0.1 >= 68 }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func cleanTitle(_ value: String) -> String {
        var result = value
        result = removingVersionGroups(from: result)
        result = result.replacingOccurrences(
            of: #"(?i)\s*[-–—]\s*(remaster(?:ed)?(?:\s+\d{2,4})?|live|radio edit|single version|album version|deluxe.*)$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)\s+(?:feat\.?|ft\.?|featuring)\s+.+$"#,
            with: "",
            options: .regularExpression
        )
        return collapsed(result)
    }

    static func cleanArtist(_ value: String) -> String {
        let result = value.replacingOccurrences(
            of: #"(?i)\s*(?:,|&|/|\s)+(?:feat\.?|ft\.?|featuring)\s+.+$"#,
            with: "",
            options: .regularExpression
        )
        return collapsed(result)
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return left == right ? 1 : 0 }
        if left == right { return 1 }

        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        let union = leftTokens.union(rightTokens)
        guard !union.isEmpty else { return 0 }
        return Double(leftTokens.intersection(rightTokens).count) / Double(union.count)
    }

    static func score(_ snapshot: PlaybackSnapshot, _ candidate: LRCLIBClient.Record) -> Double {
        let titleScore = similarity(snapshot.title, candidate.trackName ?? "") * 50
        let artistScore = similarity(snapshot.artist, candidate.artistName ?? "") * 24
        let albumScore = similarity(snapshot.album, candidate.albumName ?? "") * 8
        let durationScore: Double
        if let duration = candidate.duration {
            let difference = abs(snapshot.duration - duration)
            durationScore = switch difference {
            case 0...2: 24
            case 2...5: 18
            case 5...10: 10
            default: 0
            }
        } else {
            durationScore = 0
        }
        let lyricsScore = candidate.syncedLyrics?.isEmpty == false ? 10 : 3
        return min(100, titleScore + artistScore + albumScore + durationScore + Double(lyricsScore))
    }

    private static func removingVersionGroups(from value: String) -> String {
        value.replacingOccurrences(
            of: #"(?i)\s*[\(\[][^)\]]*(?:remaster|live|version|edit|mix|deluxe|bonus|explicit)[^)\]]*[\)\]]"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func normalized(_ value: String) -> String {
        let cleaned = collapsed(cleanTitle(value))
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
        return collapsed(cleaned)
    }

    private static func collapsed(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
