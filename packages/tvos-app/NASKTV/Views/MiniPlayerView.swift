import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var showFullPlayer: Bool = false

    var body: some View {
        if let song = playerViewModel.currentSong {
            HStack(spacing: 16) {
                // 封面
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.white)
                    }

                // 歌曲信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song.artistName ?? "未知歌手")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                // 播放控制
                HStack(spacing: 20) {
                    Button {
                        playerViewModel.playPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)

                    Button {
                        playerViewModel.togglePlayPause()
                    } label: {
                        Image(systemName: playerViewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 40))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)

                    Button {
                        playerViewModel.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }

                // 展开按钮
                Button {
                    showFullPlayer = true
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            )
            .padding(.horizontal, 80)
            .fullScreenCover(isPresented: $showFullPlayer) {
                PlayerView()
                    .environmentObject(playerViewModel)
            }
        }
    }
}
