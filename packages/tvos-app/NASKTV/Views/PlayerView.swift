import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showControls: Bool = true

    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                colors: [.black, .gray.opacity(0.8), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let song = viewModel.currentSong {
                VStack(spacing: 0) {
                    // 顶部栏
                    topBar

                    Spacer()

                    // 歌词区域
                    lyricsArea

                    Spacer()

                    // 歌曲信息
                    songInfo(song)

                    // 播放控制
                    controls

                    // 进度条
                    progressBar
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 60)
            } else {
                ContentUnavailableView(
                    "暂无播放",
                    systemImage: "music.note",
                    description: Text("选择一首歌开始播放")
                )
            }
        }
        .onAppear {
            viewModel.showPlayer = true
        }
        .onDisappear {
            viewModel.showPlayer = false
        }
    }

    // MARK: - 顶部栏
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("正在播放")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            // 原伴唱切换
            Menu {
                Button("原唱") { viewModel.switchTrack(.original) }
                Button("人声") { viewModel.switchTrack(.vocals) }
                Button("伴奏") { viewModel.switchTrack(.instrumental) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                    Text(trackName)
                }
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .clipShape(Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 20)
    }

    private var trackName: String {
        switch viewModel.currentTrack {
        case .original: return "原唱"
        case .vocals: return "人声"
        case .instrumental: return "伴奏"
        }
    }

    // MARK: - 歌词区域
    private var lyricsArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 24) {
                    ForEach(Array(viewModel.lyrics.enumerated()), id: \.element.id) { index, line in
                        LyricLineView(
                            text: line.text,
                            isCurrent: index == viewModel.currentLyricIndex
                        )
                        .id(index)
                    }
                }
                .padding(.vertical, 200)
            }
            .onChange(of: viewModel.currentLyricIndex) { _, index in
                withAnimation {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .frame(maxHeight: 400)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            viewModel.updateCurrentLyric()
        }
    }

    // MARK: - 歌曲信息
    private func songInfo(_ song: Song) -> some View {
        VStack(spacing: 8) {
            Text(song.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(song.artistName ?? "未知歌手")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.bottom, 32)
    }

    // MARK: - 播放控制
    private var controls: some View {
        HStack(spacing: 48) {
            // 上一首
            Button {
                viewModel.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 40))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            // 播放/暂停
            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            // 下一首
            Button {
                viewModel.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 40))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .padding(.bottom, 24)
    }

    // MARK: - 进度条
    private var progressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: viewModel.currentTime, total: max(viewModel.duration, 1))
                .tint(.white)
                .scaleEffect(x: 1, y: 2)

            HStack {
                Text(formatTime(viewModel.currentTime))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(formatTime(viewModel.duration))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - 歌词行视图
struct LyricLineView: View {
    let text: String
    let isCurrent: Bool

    var body: some View {
        Text(text)
            .font(isCurrent ? .title : .title3)
            .fontWeight(isCurrent ? .bold : .regular)
            .foregroundStyle(isCurrent ? .white : .white.opacity(0.4))
            .animation(.easeInOut, value: isCurrent)
    }
}
