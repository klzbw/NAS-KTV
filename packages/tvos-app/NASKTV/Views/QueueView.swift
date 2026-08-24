import SwiftUI

// MARK: - QueueView
struct QueueView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.queue.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 60))
                            .foregroundColor(.tertiary)
                        Text("队列为空")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("使用手机扫码点歌")
                            .font(.subheadline)
                            .foregroundColor(.tertiary)
                    }
                } else {
                    List {
                        ForEach(Array(viewModel.queue.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 16) {
                                // Position / status
                                ZStack {
                                    if item.isPlaying {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .foregroundColor(.accentColor)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                            .frame(width: 30)
                                    }
                                }
                                .frame(width: 40)

                                // Song info
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.songTitle)
                                        .font(.headline)
                                        .lineLimit(1)
                                    if let artist = item.songArtist, !artist.isEmpty {
                                        Text(artist)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                // Status badge
                                if item.isPlaying {
                                    Text("播放中")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.15))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("播放队列")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(viewModel.queue.count) 首")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - MiniPlayerView
struct MiniPlayerView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        if let current = viewModel.currentItem {
            HStack(spacing: 16) {
                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.songTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if let artist = current.songArtist, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Controls
                HStack(spacing: 20) {
                    Button(action: { viewModel.sendPrev() }) {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.sendPlayPause() }) {
                        Image(systemName: (viewModel.playerState?.status == "playing") ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.sendNext() }) {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal, 40)
        }
    }
}
