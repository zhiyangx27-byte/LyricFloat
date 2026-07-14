import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.snapshot?.title ?? "LyricFloat")
                    .font(.headline)
                    .lineLimit(1)
                Text(model.snapshot?.artist ?? "等待 Apple Music")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 22) {
                Button(action: model.previousTrack) {
                    Image(systemName: "backward.fill")
                }
                Button(action: model.playPause) {
                    Image(systemName: model.snapshot?.state == .playing ? "pause.fill" : "play.fill")
                }
                Button(action: model.nextTrack) {
                    Image(systemName: "forward.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.title3)
            .frame(maxWidth: .infinity)

            Divider()

            Button(action: model.toggleOverlay) {
                HStack {
                    Label(
                        model.preferences.overlayVisible ? "隐藏悬浮歌词" : "显示悬浮歌词",
                        systemImage: model.preferences.overlayVisible ? "eye.slash" : "eye"
                    )
                    Spacer()
                    Text(model.preferences.isHotKeyValid ? model.preferences.hotKeyShortcutLabel : "未设置")
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: model.toggleLock) {
                Label(
                    model.preferences.locked ? "解锁并移动歌词" : "锁定位置并穿透点击",
                    systemImage: model.preferences.locked ? "lock.open" : "lock"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("重置歌词窗口大小", action: model.resetOverlaySize)

            Button {
                model.centerOverlayOnCurrentDisplay()
            } label: {
                Label("移回显示器中央", systemImage: "scope")
            }

            Toggle(isOn: binding(\.allSpaces)) {
                Label("跟随当前桌面与全屏应用", systemImage: "rectangle.on.rectangle")
            }

            Picker("歌词显示", selection: Binding(
                get: { model.preferences.displayMode },
                set: { model.preferences.displayMode = $0 }
            )) {
                ForEach(LyricsDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            HStack {
                Text("字号")
                Slider(value: Binding(
                    get: { model.preferences.fontSize },
                    set: { model.preferences.fontSize = $0 }
                ), in: 16...64)
                Text("\(Int(model.preferences.fontSize))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("标准歌词颜色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LyricsColorPresetPicker(preferences: model.preferences)
            }

            Button {
                model.showLyricsColorPanel(for: .all)
            } label: {
                Label("自定义歌词颜色…", systemImage: "eyedropper")
            }

            HStack {
                Button("-0.25s") { model.adjustOffset(by: -0.25) }
                Text(model.offsetLabel)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: .infinity)
                Button("+0.25s") { model.adjustOffset(by: 0.25) }
            }

            HStack {
                Button("导入 LRC…", action: model.importLRC)
                Spacer()
                SettingsLink {
                    Text("设置…")
                }
            }

            Button {
                model.loadLyricsCandidates()
                openWindow(id: "lyrics-candidates")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("选择歌词版本…", systemImage: "text.magnifyingglass")
            }
            .disabled(model.snapshot == nil)

            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("退出 LyricFloat") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 300)
        .onAppear(perform: model.start)
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<AppPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { model.preferences[keyPath: keyPath] = $0 }
        )
    }
}
