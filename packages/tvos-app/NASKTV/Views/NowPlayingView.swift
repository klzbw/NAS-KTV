import SwiftUI

// MARK: - NowPlayingView
struct NowPlayingView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showLyrics = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let current = viewModel.currentItem {
                    // Song info
                    VStack(spacing: 12) {
                        Text(current.songTitle)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        if let artist = current.songArtist, !artist.isEmpty {
                            Text(artist)
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 40)
                    .padding(.horizontal, 40)

                    Spacer()

                    // Lyrics
                    if showLyrics && !viewModel.lyrics.isEmpty {
                        LyricsView()
                            .transition(.opacity)
                    } else if viewModel.lyrics.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("暂无歌词")
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Progress bar
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.playerState?.currentTime ?? 0,
                                     total: viewModel.playerState?.duration ?? 1)
                            .tint(.accentColor)
                        HStack {
                            Text(formatTime(viewModel.playerState?.currentTime ?? 0))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatTime(viewModel.playerState?.duration ?? 0))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 60)

                    // Controls
                    HStack(spacing: 40) {
                        Button(action: { viewModel.sendPrev() }) {
                            Image(systemName: "backward.fill")
                                .font(.title)
                        }
                        .buttonStyle(.plain)

                        Button(action: { viewModel.sendPlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 70, height: 70)
                                Image(systemName: (viewModel.playerState?.status == "playing") ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { viewModel.sendNext() }) {
                            Image(systemName: "forward.fill")
                                .font(.title)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 24)

                    // Track switcher
                    HStack(spacing: 16) {
                        TrackButton(title: "原唱", isActive: true) {}
                        TrackButton(title: "伴奏", isActive: false) {}
                        TrackButton(title: "人声", isActive: false) {}
                    }
                    .padding(.bottom, 30)

                } else {
                    // No song playing
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.tv")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary)
                        Text("暂无播放")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("使用手机扫码点歌，或在队列中选择歌曲")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("正在播放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showLyrics.toggle() }) {
                        Image(systemName: showLyrics ? "text.bubble.fill" : "text.bubble")
                    }
                }
            }
            .onChange(of: viewModel.currentItem?.songId) { _, newId in
                if let id = newId {
                    Task { await viewModel.loadLyrics(songId: id) }
                }
            }
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                if let time = viewModel.playerState?.currentTime {
                    viewModel.updateCurrentLyric(time: time)
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - TrackButton
struct TrackButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(isActive ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LyricsView
struct LyricsView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(Array(viewModel.lyrics.enumerated()), id: \.element.id) { index, line in
                        Text(line.text)
                            .font(index == viewModel.currentLyricIndex ? .title2 : .title3)
                            .fontWeight(index == viewModel.currentLyricIndex ? .bold : .regular)
                            .foregroundColor(index == viewModel.currentLyricIndex ? .accentColor : .secondary)
                            .id(index)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.currentLyricIndex)
                    }
                }
                .padding(.vertical, 100)
            }
            .onChange(of: viewModel.currentLyricIndex) { _, newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}
