import Foundation
import XCTest
@testable import LyricFloat

@MainActor
final class LyricsRepositoryTests: XCTestCase {
    func testRemoteResultIsCachedAfterFirstLookup() async {
        let counter = CallCounter()
        let remoteDocument = LyricsDocument(
            trackID: "track",
            origin: .lrclib,
            lines: [TimedLyricsLine(timestamp: 1, text: "Line")],
            plainLyrics: "Line",
            instrumental: false
        )
        let repository = makeRepository(
            client: MockLyricsClient(result: remoteDocument, counter: counter)
        )

        let first = await repository.lyrics(for: snapshot())
        let second = await repository.lyrics(for: snapshot())
        let lookupCount = await counter.value

        XCTAssertEqual(first, remoteDocument)
        XCTAssertEqual(second, remoteDocument)
        XCTAssertEqual(lookupCount, 1)
    }

    func testEmbeddedLyricsAreUsedWhenRemoteLookupMisses() async {
        let repository = makeRepository(
            client: MockLyricsClient(result: nil, counter: CallCounter())
        )

        let result = await repository.lyrics(for: snapshot(embeddedLyrics: "Plain lyrics"))

        XCTAssertEqual(result?.origin, .appleMusic)
        XCTAssertEqual(result?.plainLyrics, "Plain lyrics")
        XCTAssertFalse(result?.isSynced ?? true)
    }

    func testEmbeddedLyricsAreUsedWhenRemoteLookupFails() async {
        let repository = makeRepository(client: FailingLyricsClient())

        let result = await repository.lyrics(for: snapshot(embeddedLyrics: "Offline lyrics"))

        XCTAssertEqual(result?.origin, .appleMusic)
        XCTAssertEqual(result?.plainLyrics, "Offline lyrics")
        XCTAssertFalse(result?.isSynced ?? true)
    }

    func testManualSelectionOverridesAutomaticCacheAndClearingRestoresCache() async throws {
        let automatic = document(text: "Automatic", origin: .lrclib)
        let manual = candidate(text: "Manual")
        let repository = makeRepository(
            client: MockLyricsClient(result: automatic, counter: CallCounter())
        )

        let automaticResult = await repository.lyrics(for: snapshot())
        XCTAssertEqual(automaticResult?.plainLyrics, "Automatic")

        try await repository.selectCandidate(manual, for: snapshot())
        let selected = await repository.lyrics(for: snapshot())
        XCTAssertEqual(selected?.plainLyrics, "Manual")
        XCTAssertEqual(selected?.origin, .manualLRCLIB)

        try await repository.clearManualSelection(for: "track")
        let restored = await repository.lyrics(for: snapshot())
        XCTAssertEqual(restored?.plainLyrics, "Automatic")
        XCTAssertEqual(restored?.origin, .lrclib)
    }

    func testLocalOverrideHasPriorityOverManualSelection() async throws {
        let repository = makeRepository(
            client: MockLyricsClient(result: nil, counter: CallCounter())
        )

        try await repository.selectCandidate(candidate(text: "Manual"), for: snapshot())
        _ = try await repository.importLRC("[00:01.00]Local", for: snapshot())

        let result = await repository.lyrics(for: snapshot())

        XCTAssertEqual(result?.origin, .localOverride)
        XCTAssertEqual(result?.lines.first?.text, "Local")
    }

    func testInvalidLRCDoesNotReplaceResolvedLyrics() async throws {
        let repository = makeRepository(
            client: MockLyricsClient(
                result: document(text: "Automatic", origin: .lrclib),
                counter: CallCounter()
            )
        )

        do {
            _ = try await repository.importLRC("These are plain lyrics without timestamps", for: snapshot())
            XCTFail("Expected invalid LRC import to fail")
        } catch let error as LyricsRepositoryError {
            XCTAssertEqual(error.errorDescription, "文件中没有识别到 LRC 时间戳，未替换当前歌词。")
        }

        let result = await repository.lyrics(for: snapshot())
        XCTAssertEqual(result?.plainLyrics, "Automatic")
        let hasOverride = await repository.hasLocalOverride(for: "track")
        XCTAssertFalse(hasOverride)
    }

    func testLRCContainingOnlyEmptyTimedLinesIsRejected() async throws {
        let repository = makeRepository(
            client: MockLyricsClient(result: nil, counter: CallCounter())
        )

        do {
            _ = try await repository.importLRC("[00:01.00]   ", for: snapshot())
            XCTFail("Expected an empty timed LRC to fail")
        } catch let error as LyricsRepositoryError {
            XCTAssertEqual(error.errorDescription, "文件中没有识别到 LRC 时间戳，未替换当前歌词。")
        }

        let hasOverride = await repository.hasLocalOverride(for: "track")
        XCTAssertFalse(hasOverride)
    }

    func testClearingLocalOverrideRestoresManualSelection() async throws {
        let repository = makeRepository(
            client: MockLyricsClient(result: nil, counter: CallCounter())
        )
        try await repository.selectCandidate(candidate(text: "Manual"), for: snapshot())
        _ = try await repository.importLRC("[00:01.00]Local", for: snapshot())

        try await repository.clearLocalOverride(for: "track")
        let result = await repository.lyrics(for: snapshot())

        XCTAssertEqual(result?.plainLyrics, "Manual")
        XCTAssertEqual(result?.origin, .manualLRCLIB)
        let hasOverride = await repository.hasLocalOverride(for: "track")
        XCTAssertFalse(hasOverride)
    }

    func testManualSelectionPersistsInExistingLyricsStore() async throws {
        let fileURL = temporaryStoreURL()
        let firstRepository = LyricsRepository(
            remoteClient: MockLyricsClient(result: nil, counter: CallCounter()),
            store: JSONFileStore(fileURL: fileURL)
        )
        try await firstRepository.selectCandidate(candidate(text: "Persistent"), for: snapshot())

        let secondRepository = LyricsRepository(
            remoteClient: MockLyricsClient(result: nil, counter: CallCounter()),
            store: JSONFileStore(fileURL: fileURL)
        )
        let result = await secondRepository.lyrics(for: snapshot())

        XCTAssertEqual(result?.plainLyrics, "Persistent")
        XCTAssertEqual(result?.origin, .manualLRCLIB)
        let hasManualSelection = await secondRepository.hasManualSelection(for: "track")
        XCTAssertTrue(hasManualSelection)
    }

    func testClearingAutomaticCachePreservesManualSelection() async throws {
        let repository = makeRepository(
            client: MockLyricsClient(result: document(text: "Automatic", origin: .lrclib), counter: CallCounter())
        )
        _ = await repository.lyrics(for: snapshot())
        try await repository.selectCandidate(candidate(text: "Manual"), for: snapshot())

        await repository.clearCache()
        let result = await repository.lyrics(for: snapshot())

        XCTAssertEqual(result?.plainLyrics, "Manual")
        XCTAssertEqual(result?.origin, .manualLRCLIB)
    }

    func testExistingLyricsStoreWithoutManualSelectionsStillDecodes() throws {
        let data = Data(#"{"cache":{},"overrides":{},"offsets":{}}"#.utf8)

        let persisted = try JSONDecoder().decode(LyricsRepository.PersistedLyrics.self, from: data)

        XCTAssertTrue(persisted.manualSelections.isEmpty)
    }

    func testCorruptLyricsStoreIsPreservedBeforeRecovery() async throws {
        let fileURL = temporaryStoreURL()
        try Data("not valid json".utf8).write(to: fileURL)
        let store = JSONFileStore<LyricsRepository.PersistedLyrics>(fileURL: fileURL)

        let recovered = await store.load(default: LyricsRepository.PersistedLyrics())

        XCTAssertTrue(recovered.cache.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("corrupt").path))
    }

    func testCandidateSearchIsExposedThroughRepository() async throws {
        let expected = candidate(text: "Candidate")
        let repository = makeRepository(
            client: MockCandidateLyricsClient(candidates: [expected])
        )

        let result = try await repository.candidates(for: snapshot())

        XCTAssertEqual(result, [expected])
    }

    func testLRCLIBMatcherCleansVersionAndFeaturingMetadata() {
        XCTAssertEqual(
            LRCLIBMatcher.cleanTitle("Midnight Sky (2020 Remastered) [Explicit]"),
            "Midnight Sky"
        )
        XCTAssertEqual(
            LRCLIBMatcher.cleanTitle("Song Name feat. Guest Artist"),
            "Song Name"
        )
        XCTAssertEqual(
            LRCLIBMatcher.cleanArtist("Main Artist feat. Guest Artist"),
            "Main Artist"
        )
    }

    func testLRCLIBMatcherBuildsDistinctFallbackQueries() {
        let queries = LRCLIBMatcher.searchQueries(for: snapshot(
            title: "Song (Live)",
            artist: "Artist feat. Guest"
        ))

        XCTAssertEqual(queries.count, 3)
        XCTAssertEqual(queries[0].trackName, "Song (Live)")
        XCTAssertEqual(queries[1].trackName, "Song")
        XCTAssertEqual(queries[1].artistName, "Artist")
        XCTAssertEqual(queries[2].freeText, "Song Artist")
    }

    func testLRCLIBMatcherSelectsClosestReliableCandidate() throws {
        let target = snapshot(
            title: "Never Gonna Give You Up (Remastered 2022)",
            artist: "Rick Astley",
            album: "Whenever You Need Somebody",
            duration: 213
        )
        let candidates = try records(from: """
        [
          {
            "id": 1,
            "trackName": "Never Gonna Give You Up",
            "artistName": "Rick Astley",
            "albumName": "Whenever You Need Somebody",
            "duration": 214,
            "instrumental": false,
            "syncedLyrics": "[00:01.00]Correct"
          },
          {
            "id": 2,
            "trackName": "Never Gonna Give You Up",
            "artistName": "Rick Astley",
            "albumName": "Live",
            "duration": 260,
            "instrumental": false,
            "syncedLyrics": "[00:01.00]Wrong version"
          }
        ]
        """)

        let best = LRCLIBMatcher.bestCandidate(for: target, from: candidates)

        XCTAssertEqual(best?.id, 1)
    }

    func testLRCLIBMatcherRejectsUnreliableCandidates() throws {
        let candidates = try records(from: """
        [
          {
            "id": 3,
            "trackName": "Title",
            "artistName": "Different Artist",
            "albumName": "Album",
            "duration": 120,
            "instrumental": false,
            "syncedLyrics": "[00:01.00]Wrong artist"
          },
          {
            "id": 4,
            "trackName": "Title",
            "artistName": "Artist",
            "albumName": "Album",
            "duration": 180,
            "instrumental": false,
            "syncedLyrics": "[00:01.00]Wrong duration"
          }
        ]
        """)

        XCTAssertNil(LRCLIBMatcher.bestCandidate(for: snapshot(), from: candidates))
    }

    func testLRCLIBMatcherRejectsAutomaticCandidateWithoutDuration() throws {
        let candidates = try records(from: """
        [
          {
            "id": 5,
            "trackName": "Title",
            "artistName": "Artist",
            "albumName": "Album",
            "instrumental": false,
            "syncedLyrics": "[00:01.00]Unknown version"
          }
        ]
        """)

        XCTAssertNil(LRCLIBMatcher.bestCandidate(for: snapshot(), from: candidates))
    }

    func testLRCLIBCandidateScoreIsCappedAtOneHundred() throws {
        let candidate = try XCTUnwrap(records(from: """
        [
          {
            "id": 6,
            "trackName": "Title",
            "artistName": "Artist",
            "albumName": "Album",
            "duration": 120,
            "instrumental": false,
            "syncedLyrics": "[00:01.00]Exact"
          }
        ]
        """).first)

        XCTAssertEqual(LRCLIBMatcher.score(snapshot(), candidate), 100)
    }

    private func makeRepository(client: any LyricsRemoteClient) -> LyricsRepository {
        return LyricsRepository(
            remoteClient: client,
            store: JSONFileStore(fileURL: temporaryStoreURL())
        )
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricFloatTests-\(UUID().uuidString).json")
    }

    private func document(text: String, origin: LyricsOrigin) -> LyricsDocument {
        LyricsDocument(
            trackID: "track",
            origin: origin,
            lines: [],
            plainLyrics: text,
            instrumental: false
        )
    }

    private func candidate(text: String) -> LyricsCandidate {
        LyricsCandidate(
            id: text,
            trackName: "Title",
            artistName: "Artist",
            albumName: "Album",
            duration: 120,
            hasSyncedLyrics: false,
            score: 100,
            document: document(text: text, origin: .manualLRCLIB)
        )
    }

    private func snapshot(
        title: String = "Title",
        artist: String = "Artist",
        album: String = "Album",
        duration: TimeInterval = 120,
        embeddedLyrics: String? = nil
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            sourceID: "test",
            trackID: "track",
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: 0,
            state: .playing,
            embeddedLyrics: embeddedLyrics
        )
    }

    private func records(from json: String) throws -> [LRCLIBClient.Record] {
        try JSONDecoder().decode([LRCLIBClient.Record].self, from: Data(json.utf8))
    }
}

private actor CallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct MockLyricsClient: LyricsRemoteClient {
    let result: LyricsDocument?
    let counter: CallCounter

    func fetchLyrics(for snapshot: PlaybackSnapshot) async throws -> LyricsDocument? {
        await counter.increment()
        return result
    }
}

private struct FailingLyricsClient: LyricsRemoteClient {
    func fetchLyrics(for snapshot: PlaybackSnapshot) async throws -> LyricsDocument? {
        throw URLError(.badServerResponse)
    }
}

private struct MockCandidateLyricsClient: LyricsRemoteClient {
    let candidates: [LyricsCandidate]

    func fetchLyrics(for snapshot: PlaybackSnapshot) async throws -> LyricsDocument? {
        nil
    }

    func fetchCandidates(for snapshot: PlaybackSnapshot) async throws -> [LyricsCandidate] {
        candidates
    }
}
