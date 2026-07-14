import XCTest
@testable import LyricFloat

final class LRCParserTests: XCTestCase {
    func testParsesAndSortsTimestamps() {
        let input = """
        [00:10.50]Second
        [00:02.125]First
        malformed
        """

        let lines = LRCParser.parse(input)

        XCTAssertEqual(lines.map(\.text), ["First", "Second"])
        XCTAssertEqual(lines[0].timestamp, 2.125, accuracy: 0.001)
        XCTAssertEqual(lines[1].timestamp, 10.5, accuracy: 0.001)
    }

    func testParsesMultipleTimestampsOnOneLine() {
        let lines = LRCParser.parse("[00:01.00][00:04.50]Again")

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.map(\.text), ["Again", "Again"])
        XCTAssertEqual(lines.map(\.timestamp), [1, 4.5])
    }

    func testActiveLineUsesOffset() {
        let document = LyricsDocument(
            trackID: "track",
            origin: .localOverride,
            lines: [
                TimedLyricsLine(timestamp: 1, text: "One"),
                TimedLyricsLine(timestamp: 3, text: "Two")
            ],
            plainLyrics: nil,
            instrumental: false
        )

        XCTAssertNil(document.activeLineIndex(at: 0.5))
        XCTAssertEqual(document.activeLineIndex(at: 2), 0)
        XCTAssertEqual(document.activeLineIndex(at: 2, offset: 1.1), 1)
    }

    func testCurrentLineDisplayModeShowsOnlyActiveLine() {
        let document = lyricsDocument()

        XCTAssertEqual(document.visibleLineIndices(around: 2, mode: .currentLine), [2])
    }

    func testSurroundingLineDisplayModeClampsAtEdges() {
        let document = lyricsDocument()

        XCTAssertEqual(document.visibleLineIndices(around: 0, mode: .surroundingLines), [0, 1])
        XCTAssertEqual(document.visibleLineIndices(around: 2, mode: .surroundingLines), [1, 2, 3])
        XCTAssertEqual(document.visibleLineIndices(around: 3, mode: .surroundingLines), [2, 3])
    }

    private func lyricsDocument() -> LyricsDocument {
        LyricsDocument(
            trackID: "track",
            origin: .localOverride,
            lines: [
                TimedLyricsLine(timestamp: 1, text: "One"),
                TimedLyricsLine(timestamp: 2, text: "Two"),
                TimedLyricsLine(timestamp: 3, text: "Three"),
                TimedLyricsLine(timestamp: 4, text: "Four")
            ],
            plainLyrics: nil,
            instrumental: false
        )
    }
}
