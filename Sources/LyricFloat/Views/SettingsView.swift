import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            appearanceTab(model.preferences)
                .tabItem { Label("外观", systemImage: "paintbrush") }

            behaviorTab(model.preferences)
                .tabItem { Label("行为", systemImage: "macwindow") }

            lyricsTab
                .tabItem { Label("歌词", systemImage: "text.quote") }

            sourceTab
                .tabItem { Label("来源", systemImage: "music.note") }
        }
        .padding(20)
        .frame(width: 560, height: 430)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func appearanceTab(_ preferences: AppPreferences) -> some View {
        Form {
            Picker("歌词显示范围", selection: Binding(
                get: { preferences.displayMode },
                set: { preferences.displayMode = $0 }
            )) {
                ForEach(LyricsDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("歌词字体", selection: Binding(
                get: { preferences.fontFamily },
                set: { preferences.fontFamily = $0 }
            )) {
                Text(LyricsFontCatalog.systemDisplayName)
                    .tag(LyricsFontCatalog.systemFamily)
                Divider()
                ForEach(LyricsFontCatalog.availableFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .pickerStyle(.menu)
            .help("显示本机已安装字体；字体在其他 Mac 上缺失时自动使用系统默认字体。")

            Slider(value: Binding(
                get: { preferences.fontSize },
                set: { preferences.fontSize = $0 }
            ), in: 16...64) {
                Text("歌词字号：\(Int(preferences.fontSize))")
            } minimumValueLabel: {
                Text("16")
            } maximumValueLabel: {
                Text("64")
            }

            Slider(value: Binding(
                get: { preferences.lineSpacing },
                set: { preferences.lineSpacing = $0 }
            ), in: 2...28) {
                Text("行间距")
            }

            Slider(value: Binding(
                get: { preferences.inactiveOpacity },
                set: { preferences.inactiveOpacity = $0 }
            ), in: 0.12...0.8) {
                Text("其他行透明度")
            }

            Section("歌词颜色") {
                LyricsColorPresetPicker(preferences: preferences)

                Button("自定义当前行颜色…") {
                    model.showLyricsColorPanel(for: .active)
                }

                Button("自定义其他行颜色…") {
                    model.showLyricsColorPanel(for: .inactive)
                }
            }

            Picker("文本对齐", selection: Binding(
                get: { preferences.alignment },
                set: { preferences.alignment = $0 }
            )) {
                ForEach(LyricsTextAlignment.allCases) { alignment in
                    Text(alignment.label).tag(alignment)
                }
            }

            Toggle("显示文字阴影", isOn: Binding(
                get: { preferences.useShadow },
                set: { preferences.useShadow = $0 }
            ))

            Toggle("显示浅色半透明背景", isOn: Binding(
                get: { preferences.showBackground },
                set: { preferences.showBackground = $0 }
            ))

            Slider(value: Binding(
                get: { preferences.backgroundOpacity },
                set: { preferences.backgroundOpacity = $0 }
            ), in: 0.08...1) {
                Text("背景透明度")
            }
        }
        .formStyle(.grouped)
    }

    private func behaviorTab(_ preferences: AppPreferences) -> some View {
        Form {
            Toggle("检测到播放时自动显示歌词框（手动隐藏后保持隐藏）", isOn: Binding(
                get: { preferences.autoShow },
                set: { preferences.autoShow = $0 }
            ))
            Toggle("锁定歌词框并穿透点击", isOn: Binding(
                get: { preferences.locked },
                set: { preferences.locked = $0 }
            ))
            Toggle("跟随当前桌面与全屏应用", isOn: Binding(
                get: { preferences.allSpaces },
                set: { preferences.allSpaces = $0 }
            ))
            Toggle("登录时启动", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            Section("显示/隐藏歌词快捷键") {
                Picker("按键", selection: Binding(
                    get: { preferences.hotKeyLetter },
                    set: { preferences.hotKeyLetter = $0 }
                )) {
                    ForEach(GlobalHotKeyLetter.allCases) { letter in
                        Text(letter.label).tag(letter)
                    }
                }

                HStack {
                    Toggle("Control ⌃", isOn: Binding(
                        get: { preferences.hotKeyUsesControl },
                        set: { preferences.hotKeyUsesControl = $0 }
                    ))
                    Toggle("Option ⌥", isOn: Binding(
                        get: { preferences.hotKeyUsesOption },
                        set: { preferences.hotKeyUsesOption = $0 }
                    ))
                    Toggle("Shift ⇧", isOn: Binding(
                        get: { preferences.hotKeyUsesShift },
                        set: { preferences.hotKeyUsesShift = $0 }
                    ))
                    Toggle("Command ⌘", isOn: Binding(
                        get: { preferences.hotKeyUsesCommand },
                        set: { preferences.hotKeyUsesCommand = $0 }
                    ))
                }

                LabeledContent(
                    "状态",
                    value: model.hotKeyRegistrationMessage
                )
            }
            Button("重置歌词窗口大小", action: model.resetOverlaySize)

            Text("开启“跟随当前桌面”后，切换桌面或进入全屏应用时歌词会继续显示。解锁歌词后，可拖动窗口任意位置移动，或拖动右下角的小图标改变宽度和高度。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var lyricsTab: some View {
        Form {
            LabeledContent("当前歌曲", value: model.snapshot?.displayTitle ?? "无")
            LabeledContent("歌词状态", value: lyricsStatus)
            LabeledContent("同步偏移", value: model.offsetLabel)

            HStack {
                Button("导入当前歌曲 LRC…", action: model.importLRC)
                Button("清除本地 LRC", action: model.clearLocalLyricsOverride)
                    .disabled(!model.hasLocalLyricsOverride)
                Button("重置当前歌曲偏移", action: model.resetOffset)
                Button("清除在线缓存", action: model.clearLyricsCache)
            }

            Text("匹配顺序：本地导入 → 手动选择的 LRCLIB 版本 → 本地缓存 → LRCLIB 自动匹配 → Apple Music 普通歌词。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var sourceTab: some View {
        Form {
            LabeledContent("媒体来源", value: "Apple Music")
            LabeledContent("同步歌词服务", value: "LRCLIB")

            Button("请求或验证 Apple Music 权限", action: model.requestAutomationAccess)

            Text("首次读取 Apple Music 时，macOS 会询问是否允许 LyricFloat 控制 Apple Music。LRCLIB 查询会发送歌曲名、歌手、专辑和时长；候选结果仅在标题、歌手和时长足够接近时采用。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var lyricsStatus: String {
        guard let lyrics = model.lyrics else { return "未找到" }
        if lyrics.instrumental { return "纯音乐" }
        if lyrics.isSynced { return "同步歌词 · \(lyrics.origin.rawValue)" }
        return "普通歌词 · \(lyrics.origin.rawValue)"
    }
}

struct LyricsColorPresetPicker: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LyricsColorPreset.allCases) { preset in
                Button {
                    preferences.activeColorHex = preset.rawValue
                    preferences.inactiveColorHex = preset.rawValue
                } label: {
                    Circle()
                        .fill(Color(hex: preset.rawValue))
                        .frame(width: 21, height: 21)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(isSelected(preset) ? 1 : 0.3), lineWidth: isSelected(preset) ? 3 : 1)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .help(preset.label)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("标准歌词颜色")
    }

    private func isSelected(_ preset: LyricsColorPreset) -> Bool {
        preferences.activeColorHex.caseInsensitiveCompare(preset.rawValue) == .orderedSame
            && preferences.inactiveColorHex.caseInsensitiveCompare(preset.rawValue) == .orderedSame
    }
}
