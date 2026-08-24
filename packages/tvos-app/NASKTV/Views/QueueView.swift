import SwiftUI

// MARK: - QueueView (点歌队列 - 参考安卓端 pages/Queue.tsx)
struct QueueView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("点歌队列")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Text("\(viewModel.queue.count) 首")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)

                if viewModel.queue.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("队列为空")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("手机扫码点歌")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    Spacer()
                } else {
                    // Queue list
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(viewModel.queue.enumerated()), id: \.element.id) { index, item in
                                queueRow(item: item, index: index)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func queueRow(item: QueueListItem, index: Int) -> some View {
        HStack(spacing: 14) {
            // Position / playing indicator
            ZStack {
                if item.isPlaying {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                }
            }

            // Song info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.songTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(item.isPlaying ? .accentColor : .primary)
                HStack(spacing: 6) {
                    if let artist = item.songArtist, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let nickname = item.nickname, !nickname.isEmpty {
                        Text("· \(nickname)")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }

            Spacer()

            // Status
            if item.status == "waiting" {
                Text("等待中")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            } else if item.status == "playing" {
                Text("播放中")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(item.isPlaying ? Color.accentColor.opacity(0.05) : Color.clear)
        .cornerRadius(10)
    }
}
