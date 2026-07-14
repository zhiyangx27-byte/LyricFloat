import AppKit
import XCTest
@testable import LyricFloat

final class PlaybackPositionInterpolatorTests: XCTestCase {
    func testPlayingPositionAdvancesAndClamps() {
        let interpolator = PlaybackPositionInterpolator(
            snapshot: snapshot(state: .playing, position: 8, duration: 10),
            uptime: 100
        )

        XCTAssertEqual(interpolator.position(at: 101.25), 9.25, accuracy: 0.001)
        XCTAssertEqual(interpolator.position(at: 105), 10, accuracy: 0.001)
    }

    func testPausedPositionDoesNotAdvance() {
        let interpolator = PlaybackPositionInterpolator(
            snapshot: snapshot(state: .paused, position: 8, duration: 10),
            uptime: 100
        )

        XCTAssertEqual(interpolator.position(at: 105), 8, accuracy: 0.001)
    }

    func testOverlayResizePreservesTopLeftAndChangesWidthAndHeight() {
        let start = CGRect(x: 100, y: 200, width: 720, height: 340)

        let result = OverlayResizeGeometry.frame(
            startingAt: start,
            translation: CGSize(width: 80, height: 60),
            minimumSize: CGSize(width: 420, height: 180),
            maximumSize: CGSize(width: 1_600, height: 1_000)
        )

        XCTAssertEqual(result.minX, start.minX)
        XCTAssertEqual(result.maxY, start.maxY)
        XCTAssertEqual(result.width, 800)
        XCTAssertEqual(result.height, 400)
    }

    func testOverlayResizeClampsToMinimumSize() {
        let result = OverlayResizeGeometry.frame(
            startingAt: CGRect(x: 100, y: 200, width: 720, height: 340),
            translation: CGSize(width: -1_000, height: -1_000),
            minimumSize: CGSize(width: 420, height: 180),
            maximumSize: CGSize(width: 1_600, height: 1_000)
        )

        XCTAssertEqual(result.width, 420)
        XCTAssertEqual(result.height, 180)
    }

    func testOverlayInteractionStatePreventsOverlappingMoveAndResize() {
        var state = OverlayInteractionState()

        XCTAssertTrue(state.begin(.move))
        XCTAssertTrue(state.isActive(.move))
        XCTAssertFalse(state.begin(.resize))
        XCTAssertFalse(state.end(.resize))
        XCTAssertTrue(state.end(.move))
        XCTAssertFalse(state.isActive(.move))
        XCTAssertTrue(state.begin(.resize))
    }

    func testOverlayRecoveryCentersWindowWithoutChangingSize() {
        let result = OverlayRecoveryGeometry.centeredFrame(
            CGRect(x: -900, y: -500, width: 720, height: 340),
            in: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(result, CGRect(x: 360, y: 280, width: 720, height: 340))
    }

    func testOverlayCanMoveAboveVisibleFrameSoLyricsReachMenuBar() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 875)
        let result = OverlayVisibleGeometry.frame(
            CGRect(x: 300, y: 700, width: 720, height: 340),
            constrainedTo: visibleFrame,
            minimumVisibleSize: CGSize(width: 80, height: 48)
        )

        XCTAssertGreaterThan(result.maxY, visibleFrame.maxY)
        XCTAssertEqual(result, CGRect(x: 300, y: 700, width: 720, height: 340))
    }

    func testOverlayCanMoveMostlyOffscreenWhileKeepingControlsReachable() {
        let result = OverlayVisibleGeometry.frame(
            CGRect(x: -700, y: 1_000, width: 720, height: 340),
            constrainedTo: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            minimumVisibleSize: CGSize(width: 76, height: 48)
        )

        XCTAssertEqual(result.minX, -644)
        XCTAssertEqual(result.maxY, 1_192)
        XCTAssertEqual(result.intersection(CGRect(x: 0, y: 0, width: 1_440, height: 900)).width, 76)
        XCTAssertEqual(result.intersection(CGRect(x: 0, y: 0, width: 1_440, height: 900)).height, 48)
    }

    func testOverlayControlsStayOnscreenWhenOverlayMovesPastRightEdge() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let overlayFrame = CGRect(x: 1_380, y: 200, width: 720, height: 340)

        let result = OverlayControlsGeometry.frame(
            in: overlayFrame,
            visibleFrame: visibleFrame,
            isLocked: false
        )

        XCTAssertEqual(result.size, CGSize(width: 80, height: 40))
        XCTAssertLessThanOrEqual(result.maxX, visibleFrame.maxX - 8)
        XCTAssertGreaterThanOrEqual(result.minX, visibleFrame.minX + 8)
        XCTAssertTrue(result.intersects(overlayFrame.intersection(visibleFrame)))
    }

    func testOverlayControlsAnchorToBottomRight() {
        let overlayFrame = CGRect(x: 200, y: 300, width: 720, height: 340)

        let result = OverlayControlsGeometry.frame(
            in: overlayFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            isLocked: false
        )

        XCTAssertEqual(result.minX, overlayFrame.maxX - 88)
        XCTAssertEqual(result.minY, overlayFrame.minY + 8)
    }

    func testLockedControlsKeepSameHitArea() {
        XCTAssertEqual(
            OverlayControlsGeometry.size(isLocked: true),
            OverlayControlsGeometry.size(isLocked: false)
        )
    }

    func testManualHidePreventsAutomaticShowOnNextTrack() {
        XCTAssertFalse(OverlayVisibilityPolicy.shouldAutoShow(autoShow: true, manuallyHidden: true))
        XCTAssertTrue(OverlayVisibilityPolicy.shouldAutoShow(autoShow: true, manuallyHidden: false))
    }

    func testCustomColorRoundTripsThroughSystemColorPanelFormat() {
        XCTAssertEqual(NSColor(hex: "#12ABEF")?.hexRGB, "#12ABEF")
    }

    @MainActor
    func testPreferenceCallbacksOnlyRunForTheirRelevantSettings() {
        let suiteName = "LyricFloatPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        var windowingChanges = 0
        var hotKeyChanges = 0
        preferences.onWindowingChange = { windowingChanges += 1 }
        preferences.onHotKeyChange = { hotKeyChanges += 1 }

        preferences.fontSize = 42
        preferences.activeColorHex = "#12ABEF"
        XCTAssertEqual(windowingChanges, 0)
        XCTAssertEqual(hotKeyChanges, 0)

        preferences.locked.toggle()
        XCTAssertEqual(windowingChanges, 1)
        XCTAssertEqual(hotKeyChanges, 0)

        preferences.hotKeyUsesShift.toggle()
        XCTAssertEqual(windowingChanges, 1)
        XCTAssertEqual(hotKeyChanges, 1)
    }

    @MainActor
    func testFontFamilyResolutionUsesCanonicalInstalledNameAndFallsBack() {
        let installedFonts = ["Arial", "Helvetica Neue"]

        XCTAssertEqual(
            LyricsFontCatalog.resolvedFamily("arial", availableFamilies: installedFonts),
            "Arial"
        )
        XCTAssertEqual(
            LyricsFontCatalog.resolvedFamily("A Font That Is Not Installed", availableFamilies: installedFonts),
            LyricsFontCatalog.systemFamily
        )
    }

    @MainActor
    func testSelectedFontFamilyPersists() throws {
        let suiteName = "LyricFloatFontPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let installedFont = try XCTUnwrap(LyricsFontCatalog.availableFamilies.first)
        let preferences = AppPreferences(defaults: defaults)

        preferences.fontFamily = installedFont

        XCTAssertEqual(defaults.string(forKey: "fontFamily"), installedFont)
        XCTAssertEqual(AppPreferences(defaults: defaults).fontFamily, installedFont)
    }

    @MainActor
    func testUnavailableStoredFontFallsBackToSystemAndRepairsPreference() {
        let suiteName = "LyricFloatMissingFontPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("A Font That Is Not Installed", forKey: "fontFamily")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.fontFamily, LyricsFontCatalog.systemFamily)
        XCTAssertEqual(defaults.string(forKey: "fontFamily"), LyricsFontCatalog.systemFamily)
    }

    private func snapshot(
        state: PlaybackState,
        position: TimeInterval,
        duration: TimeInterval
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            sourceID: "test",
            trackID: "track",
            title: "Title",
            artist: "Artist",
            album: "Album",
            duration: duration,
            position: position,
            state: state,
            embeddedLyrics: nil
        )
    }
}
