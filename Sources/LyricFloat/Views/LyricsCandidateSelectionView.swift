import SwiftUI

struct LyricsCandidateSelectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            trackHeader
            Divider()

            if model.isLoadingLyricsCandidates {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在从 LRCLIB 搜索歌词版本…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.lyricsCandidates.isEmpty {
                ContentUnavailableView(
                    "没有歌词候选",
                    systemImage: "text.magnifyingglass",
                    description: Text(model.lyricsCandidateMessage ?? "LRCLIB 没有返回可选择的版本。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.lyricsCandidates) { candidate in
                    Button {
                        model.selectLyricsCandidate(candidate)
                    } label: {
                        LyricsCandidateRow(candidate: candidate)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            if let message = model.lyricsCandidateMessage, !model.lyricsCandidates.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 460)
        .toolbar {
            ToolbarItemGroup {
                Button("重新搜索", systemImage: "arrow.clockwise", action: model.loadLyricsCandidates)
                    .disabled(model.isLoadingLyricsCandidates || model.snapshot == nil)

                Button(
                    "清除手动选择",
                    systemImage: "arrow.uturn.backward",
                    action: model.clearManualLyricsSelection
                )
                .disabled(!model.hasManualLyricsSelection)
            }
        }
        .onAppear {
            if model.lyricsCandidates.isEmpty, !model.isLoadingLyricsCandidates {
                model.loadLyricsCandidates()
            }
        }
    }

    private var trackHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("为当前歌曲选择歌词版本")
                .font(.title2.weight(.semibold))
            Text(model.snapshot?.title ?? "没有正在播放的歌曲")
                .font(.headline)
            if let snapshot = model.snapshot {
                Text([snapshot.artist, snapshot.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            Text("手动选择优先于自动匹配；用户导入的本地 LRC 仍拥有最高优先级。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LyricsCandidateRow: View {
    let candidate: LyricsCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.trackName)
                    .font(.headline)
                Text(candidate.artistName)
                    .foregroundStyle(.secondary)
                if let albumName = candidate.albumName, !albumName.isEmpty {
                    Text(albumName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Label(
                    candidate.hasSyncedLyrics ? "同步歌词" : "普通歌词",
                    systemImage: candidate.hasSyncedLyrics ? "clock.badge.checkmark" : "text.alignleft"
                )
                .font(.caption)
                .foregroundStyle(candidate.hasSyncedLyrics ? .green : .secondary)

                if let duration = candidate.duration {
                    Text(durationLabel(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text("匹配 \(Int(candidate.score.rounded())) · 可信度\(candidate.confidenceLabel)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(confidenceColor)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var confidenceColor: Color {
        switch candidate.score {
        case 90...: .green
        case 68...: .blue
        case 45...: .orange
        default: .red
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
