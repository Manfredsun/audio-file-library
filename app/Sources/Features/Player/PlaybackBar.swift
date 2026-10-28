import SwiftUI

/// 播放列。選 A 播 A，選 B 立刻停 A 播 B——延遲比優雅重要（ROADMAP §32）。
struct PlaybackBar: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var preview: AudioPreviewEngine

    init(store: LibraryStore) {
        self.store = store
        self.preview = store.preview
    }

    /// 播放列跟著 barSound：有選取就是選取，換頁把選取清掉時退回正在播的那一個。
    private var sound: Sound? { store.barSound }

    var body: some View {
        VStack(spacing: 0) {
            MaRule()

            HStack(spacing: DS.Ma.group) {
                transport
                titleBlock
                scrubber
                timeBlock
                volumeBlock
                autoToggle
            }
            .padding(.horizontal, DS.Ma.group)
            .frame(height: DS.Metrics.playbackBarHeight)
        }
        .background(DS.Palette.kozumi)
    }

    // MARK: - 傳送控制

    private var transport: some View {
        HStack(spacing: DS.Ma.tight) {
            glyphButton("◁", enabled: sound != nil) { store.selectPrevious() }

            Button {
                store.togglePreview()
            } label: {
                Text(preview.state.isPlaying ? "❚❚" : "▶")
                    .font(.system(size: preview.state.isPlaying ? 13 : 16))
                    .foregroundStyle(sound == nil ? DS.Palette.textTertiary.opacity(0.4) : DS.Palette.asagi)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(sound == nil)
            .help(L10n.tr("播放 / 暫停（空白鍵）"))

            glyphButton("▷", enabled: sound != nil) { store.selectNext() }
        }
    }

    private func glyphButton(_ glyph: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(DS.TypeScale.glyph)
                .foregroundStyle(enabled ? DS.Palette.textSecondary : DS.Palette.textTertiary.opacity(0.4))
                .frame(width: DS.Metrics.hitTarget, height: DS.Metrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - 標題

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DS.Ma.hair) {
            Text(sound?.browserTitle ?? "—")
                .font(DS.TypeScale.rowTitle)
                .foregroundStyle(sound == nil ? DS.Palette.textTertiary : DS.Palette.textPrimary)
                .lineLimit(1)

            if case .failed(_, let reason) = preview.state {
                Text(reason)
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.hi)
                    .lineLimit(1)
            } else {
                Text(sound?.relativePath ?? " ")
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(width: 190, alignment: .leading)
    }

    // MARK: - 進度（可點擊跳轉）

    private var scrubber: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if let peaks = store.barWaveform, !peaks.isEmpty {
                    WaveformView(peaks: peaks,
                                 progress: preview.progress,
                                 played: DS.Palette.asagi,
                                 unplayed: DS.Palette.asagi.opacity(0.28),
                                 showsPlayhead: true)
                        .frame(height: 34)
                } else {
                    // 波形還在算，先用一條線撐住版面
                    Rectangle()
                        .fill(DS.Palette.hairlineFaint)
                        .frame(height: 1)
                    Rectangle()
                        .fill(DS.Palette.asagi.opacity(0.5))
                        .frame(width: max(0, geo.size.width * preview.progress), height: 2)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard geo.size.width > 0 else { return }
                        preview.seek(to: value.location.x / geo.size.width)
                    }
            )
        }
        .frame(height: 34)
    }

    // MARK: - 時間

    private var timeBlock: some View {
        HStack(spacing: DS.Ma.tight) {
            Text(Self.time(preview.currentTime))
                .font(DS.TypeScale.monoLarge)
                .foregroundStyle(DS.Palette.textPrimary)
            Text("/")
                .font(DS.TypeScale.mono)
                .foregroundStyle(DS.Palette.textTertiary)
            Text(Self.time(preview.duration > 0 ? preview.duration : (sound?.duration ?? 0)))
                .font(DS.TypeScale.mono)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(width: 104, alignment: .trailing)
    }

    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let fraction = Int((seconds - Double(total)) * 10)
        return String(format: "%d:%02d.%d", total / 60, total % 60, fraction)
    }

    // MARK: - 音量與自動預覽

    private var volumeBlock: some View {
        HStack(spacing: DS.Ma.inline) {
            SectionLabel(text: L10n.tr("vol"))
            Slider(value: Binding(
                get: { Double(preview.volume) },
                set: { preview.volume = Float($0) }
            ), in: 0...1)
            // mini 的滑桿頭只有 8pt 左右，很難抓（D-041）。
            .controlSize(.small)
            .frame(width: 80)
        }
    }

    private var autoToggle: some View {
        Button {
            store.autoPreview.toggle()
        } label: {
            HStack(spacing: DS.Ma.tight) {
                Rectangle()
                    .fill(store.autoPreview ? DS.Palette.asagi : DS.Palette.nezumi)
                    .frame(width: 14, height: 2)
                Text(L10n.tr("自動播放"))
                    .foregroundStyle(store.autoPreview ? DS.Palette.asagi : DS.Palette.textSecondary)
            }
        }
        .buttonStyle(.action)
        .help(L10n.tr("選取音效時自動播放"))
    }
}
