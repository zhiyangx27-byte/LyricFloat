import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let preferences: AppPreferences

    @Published private(set) var snapshot: PlaybackSnapshot?
    @Published private(set) var lyrics: LyricsDocument?
    @Published private(set) var displayPosition: TimeInterval = 0
    @Published private(set) var lyricsOffset: TimeInterval = 0
    @Published private(set) var statusMessage: String?
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var hotKeyRegistrationMessage = ""
    @Published private(set) var lyricsCandidates: [LyricsCandidate] = []
    @Published private(set) var isLoadingLyricsCandidates = false
    @Published private(set) var lyricsCandidateMessage: String?
    @Published private(set) var hasManualLyricsSelection = false
    @Published private(set) var hasLocalLyricsOverride = false
    @Published private(set) var isLoadingLyrics = false
    @Published private(set) var isOverlayMoving = false

    private let mediaSource: any MediaSource
    private let lyricsRepository: LyricsRepository
    private let globalHotKeyController = GlobalHotKeyController()
    private var overlayController: OverlayPanelController?
    private var playbackTask: Task<Void, Never>?
    private var lyricsLoadTask: Task<Void, Never>?
    private var lyricsCandidateLoadTask: Task<Void, Never>?
    private var lyricsMutationTask: Task<Void, Never>?
    private var preferencesCancellable: AnyCancellable?
    private var lyricsColorPanelController: LyricsColorPanelController?
    private var interpolator: PlaybackPositionInterpolator?
    private var lastPollUptime: TimeInterval = 0
    private var overlayWasManuallyHidden: Bool
    private var started = false

    init(
        mediaSource: any MediaSource = AppleMusicSource(),
        lyricsRepository: LyricsRepository = LyricsRepository(),
        preferences: AppPreferences = AppPreferences()
    ) {
        self.mediaSource = mediaSource
        self.lyricsRepository = lyricsRepository
        self.preferences = preferences
        launchAtLogin = LaunchAtLoginController.isEnabled
        overlayWasManuallyHidden = !preferences.overlayVisible
        preferencesCancellable = preferences.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var activeLineIndex: Int? {
        lyrics?.activeLineIndex(at: displayPosition, offset: lyricsOffset)
    }

    var shortTrackTitle: String {
        guard let snapshot else { return L10n.text("等待 Apple Music") }
        let title = snapshot.displayTitle
        return title.count <= 34 ? title : String(title.prefix(31)) + "..."
    }

    var offsetLabel: String {
        L10n.format("%+.2f 秒", lyricsOffset)
    }

    func start() {
        guard !started else { return }
        started = true

        let controller = OverlayPanelController(model: self)
        overlayController = controller
        preferences.onWindowingChange = { [weak self] in
            self?.overlayController?.applyPreferences()
        }
        preferences.onHotKeyChange = { [weak self] in
            self?.refreshGlobalHotKey()
        }
        controller.applyPreferences()
        refreshGlobalHotKey()

        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                if self == nil { return }
                await self?.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        AppLog.playback.info("Playback monitoring started")
    }

    func toggleOverlay() {
        let willShow = !preferences.overlayVisible
        preferences.overlayVisible = willShow
        overlayWasManuallyHidden = !willShow
        AppLog.menuBar.info("Overlay visibility toggled")
    }

    func toggleLock() {
        preferences.locked.toggle()
        AppLog.menuBar.info("Overlay lock toggled")
    }

    func toggleAllSpaces() {
        preferences.allSpaces.toggle()
        AppLog.menuBar.info("Overlay space behavior toggled")
    }

    func beginOverlayResize() {
        overlayController?.beginResize()
    }

    func beginOverlayMove() -> Bool {
        guard overlayController?.beginMove() == true else { return false }
        isOverlayMoving = true
        return true
    }

    func endOverlayMove() {
        overlayController?.endMove()
        isOverlayMoving = false
        let uptime = ProcessInfo.processInfo.systemUptime
        displayPosition = interpolator?.position(at: uptime) ?? snapshot?.position ?? 0
    }

    func resizeOverlay(by translation: CGSize) {
        overlayController?.resize(by: translation)
    }

    func endOverlayResize() {
        overlayController?.endResize()
    }

    func resetOverlaySize() {
        overlayController?.resetSize()
    }

    func centerOverlayOnCurrentDisplay() {
        preferences.overlayVisible = true
        overlayWasManuallyHidden = false
        overlayController?.centerOnCurrentDisplay()
        statusMessage = L10n.text("歌词窗口已移回当前显示器中央。")
    }

    func showLyricsColorPanel(for target: LyricsColorTarget) {
        let controller = LyricsColorPanelController { [weak self] color in
            guard let self, let hex = color.hexRGB else { return }
            switch target {
            case .active:
                preferences.activeColorHex = hex
            case .inactive:
                preferences.inactiveColorHex = hex
            case .all:
                preferences.activeColorHex = hex
                preferences.inactiveColorHex = hex
            }
        }
        lyricsColorPanelController = controller

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(hex: colorHex(for: target)) ?? .white
        panel.setTarget(controller)
        panel.setAction(#selector(LyricsColorPanelController.colorDidChange(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func loadLyricsCandidates() {
        guard let snapshot else {
            lyricsCandidateLoadTask?.cancel()
            lyricsCandidates = []
            isLoadingLyricsCandidates = false
            lyricsCandidateMessage = L10n.text("请先在 Apple Music 中播放一首歌曲。")
            return
        }

        lyricsCandidateLoadTask?.cancel()
        isLoadingLyricsCandidates = true
        lyricsCandidateMessage = nil
        lyricsCandidates = []

        lyricsCandidateLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let candidates = lyricsRepository.candidates(for: snapshot)
                async let hasManualSelection = lyricsRepository.hasManualSelection(for: snapshot.trackID)
                let (loadedCandidates, loadedHasManualSelection) = try await (
                    candidates,
                    hasManualSelection
                )
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                lyricsCandidates = loadedCandidates
                hasManualLyricsSelection = loadedHasManualSelection
                lyricsCandidateMessage = loadedCandidates.isEmpty
                    ? L10n.text("LRCLIB 没有找到可供选择的歌词版本。")
                    : nil
            } catch {
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                lyricsCandidateMessage = L10n.text("无法连接 LRCLIB，请检查网络后重试。")
                AppLog.lyrics.error(
                    "Manual LRCLIB candidate search failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
            isLoadingLyricsCandidates = false
        }
    }

    func selectLyricsCandidate(_ candidate: LyricsCandidate) {
        guard let snapshot else { return }

        lyricsMutationTask?.cancel()
        lyricsMutationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await lyricsRepository.selectCandidate(candidate, for: snapshot)
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                lyricsLoadTask?.cancel()
                hasManualLyricsSelection = true
                await reloadResolvedLyrics(for: snapshot)
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                lyricsCandidateMessage = L10n.format("已选择“%@”的歌词版本。", candidate.trackName)
                statusMessage = L10n.text("已保存当前歌曲的手动歌词版本。")
            } catch {
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                lyricsCandidateMessage = L10n.format("保存歌词版本失败：%@", error.localizedDescription)
            }
        }
    }

    func clearManualLyricsSelection() {
        guard let snapshot else { return }

        lyricsMutationTask?.cancel()
        lyricsMutationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await lyricsRepository.clearManualSelection(for: snapshot.trackID)
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                lyricsLoadTask?.cancel()
                hasManualLyricsSelection = false
                await reloadResolvedLyrics(for: snapshot)
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                lyricsCandidateMessage = L10n.text("已清除手动选择，当前歌曲恢复自动匹配。")
                statusMessage = L10n.text("已清除当前歌曲的手动歌词版本。")
            } catch {
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                lyricsCandidateMessage = L10n.format("清除手动选择失败：%@", error.localizedDescription)
            }
        }
    }

    func clearLocalLyricsOverride() {
        guard let snapshot else { return }

        lyricsMutationTask?.cancel()
        lyricsMutationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await lyricsRepository.clearLocalOverride(for: snapshot.trackID)
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                lyricsLoadTask?.cancel()
                hasLocalLyricsOverride = false
                await reloadResolvedLyrics(for: snapshot)
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                statusMessage = L10n.text("已清除当前歌曲的本地 LRC，恢复其他歌词来源。")
            } catch {
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                statusMessage = L10n.format("清除本地 LRC 失败：%@", error.localizedDescription)
            }
        }
    }

    private func refreshGlobalHotKey() {
        guard preferences.isHotKeyValid else {
            globalHotKeyController.unregisterHotKey()
            hotKeyRegistrationMessage = L10n.text("请至少选择一个修饰键")
            return
        }
        let registered = globalHotKeyController.register(
            keyCode: preferences.hotKeyLetter.keyCode,
            modifiers: preferences.hotKeyCarbonModifiers
        ) { [weak self] in
            self?.toggleOverlay()
        }
        hotKeyRegistrationMessage = registered
            ? L10n.format("已启用 %@", preferences.hotKeyShortcutLabel)
            : L10n.text("注册失败，此组合可能已被其他应用占用")
    }

    func playPause() {
        mediaSource.playPause()
        Task { await refreshPlayback(force: true) }
    }

    func nextTrack() {
        mediaSource.nextTrack()
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            await refreshPlayback(force: true)
        }
    }

    func previousTrack() {
        mediaSource.previousTrack()
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            await refreshPlayback(force: true)
        }
    }

    func adjustOffset(by delta: TimeInterval) {
        guard let trackID = snapshot?.trackID else { return }
        lyricsOffset = min(max(lyricsOffset + delta, -30), 30)
        Task { await lyricsRepository.setOffset(lyricsOffset, for: trackID) }
    }

    func resetOffset() {
        guard let trackID = snapshot?.trackID else { return }
        lyricsOffset = 0
        Task { await lyricsRepository.clearOffset(for: trackID) }
    }

    func importLRC() {
        guard let snapshot else {
            statusMessage = L10n.text("请先在 Apple Music 中播放一首歌曲。")
            return
        }

        let panel = NSOpenPanel()
        panel.title = L10n.format("为 %@ 导入同步歌词", snapshot.title)
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        lyricsMutationTask?.cancel()
        lyricsMutationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let contents = try String(contentsOf: url, encoding: .utf8)
                let document = try await lyricsRepository.importLRC(contents, for: snapshot)
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                lyricsLoadTask?.cancel()
                lyrics = document
                hasLocalLyricsOverride = true
                isLoadingLyrics = false
                statusMessage = L10n.text("已导入同步歌词。")
                AppLog.lyrics.info("Imported local LRC")
            } catch {
                guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
                statusMessage = L10n.format("导入失败：%@", error.localizedDescription)
            }
        }
    }

    func clearLyricsCache() {
        Task {
            await lyricsRepository.clearCache()
            statusMessage = L10n.text("在线歌词缓存已清除；本地导入歌词保留。")
        }
    }

    func requestAutomationAccess() {
        do {
            _ = try mediaSource.snapshot()
            statusMessage = L10n.text("已成功读取 Apple Music。")
        } catch {
            statusMessage = L10n.format("Apple Music 访问失败：%@", error.localizedDescription)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            launchAtLogin = enabled
            statusMessage = enabled
                ? L10n.text("已设置登录时启动。")
                : L10n.text("已关闭登录时启动。")
        } catch {
            launchAtLogin = LaunchAtLoginController.isEnabled
            statusMessage = L10n.format("登录启动设置失败：%@", error.localizedDescription)
        }
    }

    private func tick() async {
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastPollUptime >= 0.5 {
            await refreshPlayback(force: false)
            lastPollUptime = uptime
        }
        if !isOverlayMoving {
            displayPosition = interpolator?.position(at: uptime) ?? snapshot?.position ?? 0
        }
    }

    private func refreshPlayback(force: Bool) async {
        do {
            guard let newSnapshot = try mediaSource.snapshot() else {
                snapshot = nil
                lyrics = nil
                resetLyricsCandidateState()
                lyricsLoadTask?.cancel()
                lyricsMutationTask?.cancel()
                hasLocalLyricsOverride = false
                isLoadingLyrics = false
                interpolator = nil
                displayPosition = 0
                return
            }

            let isNewTrack = snapshot?.trackID != newSnapshot.trackID
            snapshot = newSnapshot
            interpolator = PlaybackPositionInterpolator(
                snapshot: newSnapshot,
                uptime: ProcessInfo.processInfo.systemUptime
            )

            guard isNewTrack || force && lyrics == nil else { return }
            if isNewTrack, OverlayVisibilityPolicy.shouldAutoShow(
                autoShow: preferences.autoShow,
                manuallyHidden: overlayWasManuallyHidden
            ) {
                preferences.overlayVisible = true
            }
            if isNewTrack {
                lyricsMutationTask?.cancel()
                resetLyricsCandidateState()
            }
            loadLyrics(for: newSnapshot)
        } catch {
            statusMessage = L10n.format("Apple Music 读取失败：%@", error.localizedDescription)
            AppLog.playback.error("Apple Music read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadLyrics(for snapshot: PlaybackSnapshot) {
        lyricsLoadTask?.cancel()
        lyrics = nil
        lyricsOffset = 0
        hasLocalLyricsOverride = false
        isLoadingLyrics = true

        lyricsLoadTask = Task { [weak self] in
            guard let self else { return }
            async let loadedLyrics = lyricsRepository.lyrics(for: snapshot)
            async let loadedOffset = lyricsRepository.offset(for: snapshot.trackID)
            async let loadedHasLocalOverride = lyricsRepository.hasLocalOverride(for: snapshot.trackID)
            let (document, offset, hasLocalOverride) = await (
                loadedLyrics,
                loadedOffset,
                loadedHasLocalOverride
            )
            guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
            self.lyrics = document
            self.lyricsOffset = offset
            self.hasLocalLyricsOverride = hasLocalOverride
            self.isLoadingLyrics = false
            AppLog.lyrics.info("Lyrics resolved for current track")
        }
    }

    private func reloadResolvedLyrics(for snapshot: PlaybackSnapshot) async {
        isLoadingLyrics = true
        async let loadedDocument = lyricsRepository.lyrics(for: snapshot)
        async let loadedHasLocalOverride = lyricsRepository.hasLocalOverride(for: snapshot.trackID)
        let (document, hasLocalOverride) = await (loadedDocument, loadedHasLocalOverride)
        guard !Task.isCancelled, self.snapshot?.trackID == snapshot.trackID else { return }
        lyrics = document
        hasLocalLyricsOverride = hasLocalOverride
        isLoadingLyrics = false
    }

    private func resetLyricsCandidateState() {
        lyricsCandidateLoadTask?.cancel()
        lyricsCandidates = []
        isLoadingLyricsCandidates = false
        lyricsCandidateMessage = nil
        hasManualLyricsSelection = false
    }

    private func colorHex(for target: LyricsColorTarget) -> String {
        switch target {
        case .active, .all:
            preferences.activeColorHex
        case .inactive:
            preferences.inactiveColorHex
        }
    }
}

enum LyricsColorTarget {
    case active
    case inactive
    case all
}

enum OverlayVisibilityPolicy {
    static func shouldAutoShow(autoShow: Bool, manuallyHidden: Bool) -> Bool {
        autoShow && !manuallyHidden
    }
}

@MainActor
private final class LyricsColorPanelController: NSObject {
    private let onChange: (NSColor) -> Void

    init(onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
    }

    @objc func colorDidChange(_ sender: NSColorPanel) {
        onChange(sender.color)
    }
}

@MainActor
private final class GlobalHotKeyController {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var action: (@MainActor () -> Void)?

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping @MainActor () -> Void
    ) -> Bool {
        unregisterHotKey()
        self.action = action

        if eventHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, userData in
                    guard let userData else { return noErr }
                    let pointerValue = UInt(bitPattern: userData)
                    Task { @MainActor in
                        guard let pointer = UnsafeRawPointer(bitPattern: pointerValue) else { return }
                        let controller = Unmanaged<GlobalHotKeyController>
                            .fromOpaque(pointer)
                            .takeUnretainedValue()
                        controller.action?()
                    }
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )

            guard status == noErr else {
                AppLog.menuBar.error("Global hotkey handler registration failed: \(status)")
                return false
            }
        }

        let hotKeyID = EventHotKeyID(signature: 0x4C_59_52_46, id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        if hotKeyStatus == noErr {
            AppLog.menuBar.info("Global overlay hotkey registered")
            return true
        } else {
            AppLog.menuBar.error("Global hotkey registration failed: \(hotKeyStatus)")
            return false
        }
    }

    func unregisterHotKey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

}

private extension GlobalHotKeyLetter {
    var keyCode: UInt32 {
        let keyCodes: [GlobalHotKeyLetter: Int] = [
            .a: kVK_ANSI_A, .b: kVK_ANSI_B, .c: kVK_ANSI_C, .d: kVK_ANSI_D,
            .e: kVK_ANSI_E, .f: kVK_ANSI_F, .g: kVK_ANSI_G, .h: kVK_ANSI_H,
            .i: kVK_ANSI_I, .j: kVK_ANSI_J, .k: kVK_ANSI_K, .l: kVK_ANSI_L,
            .m: kVK_ANSI_M, .n: kVK_ANSI_N, .o: kVK_ANSI_O, .p: kVK_ANSI_P,
            .q: kVK_ANSI_Q, .r: kVK_ANSI_R, .s: kVK_ANSI_S, .t: kVK_ANSI_T,
            .u: kVK_ANSI_U, .v: kVK_ANSI_V, .w: kVK_ANSI_W, .x: kVK_ANSI_X,
            .y: kVK_ANSI_Y, .z: kVK_ANSI_Z
        ]
        return UInt32(keyCodes[self] ?? kVK_ANSI_L)
    }
}

private extension AppPreferences {
    var hotKeyCarbonModifiers: UInt32 {
        var modifiers = 0
        if hotKeyUsesControl { modifiers |= controlKey }
        if hotKeyUsesOption { modifiers |= optionKey }
        if hotKeyUsesShift { modifiers |= shiftKey }
        if hotKeyUsesCommand { modifiers |= cmdKey }
        return UInt32(modifiers)
    }
}
