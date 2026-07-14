import AppKit
import SwiftUI

struct LyricsOverlayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            if model.preferences.showBackground {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(max(0.06, model.preferences.backgroundOpacity * 0.42)))
            }

            Group {
                if let lyrics = model.lyrics, lyrics.instrumental {
                    statusText(L10n.text("纯音乐"))
                } else if let lyrics = model.lyrics, lyrics.isSynced {
                    syncedLyrics(lyrics, preferences: model.preferences)
                } else if let plainLyrics = model.lyrics?.plainLyrics, !plainLyrics.isEmpty {
                    plainLyricsView(plainLyrics, preferences: model.preferences)
                } else if let snapshot = model.snapshot, model.isLoadingLyrics {
                    statusText(L10n.format("正在查找《%@》的歌词…", snapshot.title))
                } else if model.snapshot != nil {
                    statusText(L10n.text("未找到歌词，可从菜单选择歌词版本"))
                } else {
                    statusText(L10n.text("在 Apple Music 中播放一首歌曲"))
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)

            if !model.preferences.locked {
                NativeOverlayDragSurface(
                    onBeginDrag: model.beginOverlayMove,
                    onEndDrag: model.endOverlayMove
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 420, minHeight: 180)
        .contentShape(Rectangle())
    }

    private func syncedLyrics(_ document: LyricsDocument, preferences: AppPreferences) -> some View {
        VStack(spacing: preferences.lineSpacing) {
            ForEach(visibleLines(in: document, mode: preferences.displayMode), id: \.index) { item in
                Text(item.line.text.isEmpty ? " " : item.line.text)
                    .font(LyricsFontCatalog.font(
                        family: preferences.fontFamily,
                        size: item.isActive ? preferences.fontSize : preferences.fontSize * 0.78,
                        weight: item.isActive ? .semibold : .regular
                    ))
                    .foregroundStyle(item.isActive
                        ? Color(hex: preferences.activeColorHex)
                        : Color(hex: preferences.inactiveColorHex).opacity(preferences.inactiveOpacity))
                    .multilineTextAlignment(preferences.alignment.textAlignment)
                    .frame(maxWidth: .infinity, alignment: frameAlignment(preferences.alignment))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .shadow(
                        color: preferences.useShadow
                            ? Color.lyricContrast(for: item.isActive
                                ? preferences.activeColorHex
                                : preferences.inactiveColorHex).opacity(0.92)
                            : .clear,
                        radius: 3,
                        y: 0
                    )
            }
        }
        .animation(model.isOverlayMoving ? nil : .easeInOut(duration: 0.3), value: model.activeLineIndex)
    }

    private func visibleLines(
        in document: LyricsDocument,
        mode: LyricsDisplayMode
    ) -> [(index: Int, line: TimedLyricsLine, isActive: Bool)] {
        let activeIndex = model.activeLineIndex
        return document.visibleLineIndices(around: activeIndex, mode: mode).map { index in
            (index, document.lines[index], index == activeIndex)
        }
    }

    private func plainLyricsView(_ lyrics: String, preferences: AppPreferences) -> some View {
        ScrollView {
            Text(lyrics)
                .font(LyricsFontCatalog.font(
                    family: preferences.fontFamily,
                    size: preferences.fontSize * 0.68,
                    weight: .medium
                ))
                .foregroundStyle(Color(hex: preferences.activeColorHex))
                .multilineTextAlignment(preferences.alignment.textAlignment)
                .frame(maxWidth: .infinity, alignment: frameAlignment(preferences.alignment))
                .textSelection(.enabled)
                .shadow(
                    color: preferences.useShadow
                        ? Color.lyricContrast(for: preferences.activeColorHex).opacity(0.92)
                        : .clear,
                    radius: 3,
                    y: 0
                )
        }
        .scrollIndicators(.hidden)
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(LyricsFontCatalog.font(
                family: model.preferences.fontFamily,
                size: 22,
                weight: .medium
            ))
            .foregroundStyle(.white.opacity(0.78))
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.92), radius: 3, y: 0)
    }

    private func frameAlignment(_ alignment: LyricsTextAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

private struct NativeOverlayDragSurface: NSViewRepresentable {
    let onBeginDrag: () -> Bool
    let onEndDrag: () -> Void

    func makeNSView(context: Context) -> NativeOverlayDragView {
        let view = NativeOverlayDragView()
        view.onBeginDrag = onBeginDrag
        view.onEndDrag = onEndDrag
        return view
    }

    func updateNSView(_ nsView: NativeOverlayDragView, context: Context) {
        nsView.onBeginDrag = onBeginDrag
        nsView.onEndDrag = onEndDrag
    }

    static func dismantleNSView(_ nsView: NativeOverlayDragView, coordinator: ()) {
        NSCursor.arrow.set()
    }
}

private final class NativeOverlayDragView: NSView {
    var onBeginDrag: () -> Bool = { false }
    var onEndDrag: () -> Void = {}
    private var isDragging = false

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isDragging ? .closedHand : .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0, onBeginDrag() else { return }
        isDragging = true
        window?.invalidateCursorRects(for: self)
        NSCursor.closedHand.set()

        window?.performDrag(with: event)

        isDragging = false
        onEndDrag()
        window?.invalidateCursorRects(for: self)
        NSCursor.openHand.set()
    }
}
