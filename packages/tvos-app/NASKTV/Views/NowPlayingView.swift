import SwiftUI

// MARK: - NowPlayingView (默认主页 - 参考安卓端 pages/NowPlaying.tsx)
struct NowPlayingView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showQueue = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.08, green: 0.06, blue: 0.18)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if viewModel.currentItem == nil {
                // 待机状态：显示二维码
                standbyView
            } else {
                // 播放状态
                playingView
            }
        }
    }

    // MARK: - Standby (待机二维码)
    private var standbyView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Logo + title
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Text("N")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                Text("NAS-KTV")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text("手机扫码点歌")
                .font(.headline)
                .foregroundColor(.secondary)

            // QR Code
            if !viewModel.qrText.isEmpty {
                QRCodeImageView(content: viewModel.qrText, size: 220)
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 244, height: 244)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("生成二维码中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            }

            // Room code
            if let room = viewModel.room {
                HStack(spacing: 4) {
                    Text("房间码:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(room.code)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                }
            }

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.wsStatus == .connected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(viewModel.wsStatus == .connected ? "已连接" : "连接中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Queue button
            Button(action: { showQueue = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                    Text("点歌队列 (\(viewModel.queue.count))")
                }
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
                .environmentObject(viewModel)
        }
    }

    // MARK: - Playing (播放状态)
    private var playingView: some View {
        VStack(spacing: 0) {
            // Top bar: song info + QR badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.currentItem?.songTitle ?? "未知歌曲")
                        .font(.title)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    Text(viewModel.currentItem?.songArtist ?? "未知歌手")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // QR code badge (播放时也显示扫码点歌)
                VStack(spacing: 4) {
                    if !viewModel.qrText.isEmpty {
                        QRCodeImageView(content: viewModel.qrText, size: 90)
                    }
                    Text("扫码点歌")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            .padding(.top, 30)

            Spacer()

            // Lyrics area
            lyricsView

            Spacer()

            // Progress bar + controls
            VStack(spacing: 16) {
                // Progress
                HStack(spacing: 12) {
                    Text(formatTime(viewModel.playerState?.currentTime ?? 0))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 4)
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * progressRatio, height: 4)
                        }
                        .cornerRadius(2)
                    }
                    .frame(height: 4)
                    Text(formatTime(viewModel.playerState?.duration ?? 0))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                }
                .padding(.horizontal, 40)

                // Controls
                HStack(spacing: 40) {
                    Button(action: { viewModel.sendPrev() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 28))
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.sendPlayPause() }) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 64, height: 64)
                            Image(systemName: (viewModel.playerState?.status ?? "playing") == "playing" ? "pause.fill" : "play.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.sendNext() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 28))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 30)
        }
    }

    // MARK: - Lyrics
    private var lyricsView: some View {
        VStack(spacing: 12) {
            if viewModel.lyrics.isEmpty {
                Text("暂无歌词")
                    .font(.title3)
                    .foregroundColor(.secondary.opacity(0.5))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            ForEach(Array(viewModel.lyrics.enumerated()), id: \.element.id) { index, line in
                                Text(line.text)
                                    .font(index == viewModel.currentLyricIndex ? .title2 : .body)
                                    .fontWeight(index == viewModel.currentLyricIndex ? .bold : .regular)
                                    .foregroundColor(index == viewModel.currentLyricIndex ? .white : .secondary.opacity(0.5))
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 100)
                    }
                    .onChange(of: viewModel.currentLyricIndex) { newIndex in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 300)
        .padding(.horizontal, 60)
    }

    // MARK: - Helpers
    private var progressRatio: Double {
        let duration = viewModel.playerState?.duration ?? 0
        let current = viewModel.playerState?.currentTime ?? 0
        guard duration > 0 else { return 0 }
        return min(max(current / duration, 0), 1)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
