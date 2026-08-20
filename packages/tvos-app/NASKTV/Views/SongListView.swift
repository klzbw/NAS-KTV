import SwiftUI

struct SongListView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    let title: String

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(libraryViewModel.songs) { song in
                    SongListRow(song: song) {
                        playerViewModel.play(song: song)
                    } onAddToQueue: {
                        libraryViewModel.addToQueue(song: song)
                    }
                    .onAppear {
                        if song.id == libraryViewModel.songs.last?.id {
                            libraryViewModel.loadMoreSongs()
                        }
                    }
                }

                if libraryViewModel.isLoading {
                    ProgressView()
                        .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 100)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if libraryViewModel.selectedArtist != nil {
                        Button("清除歌手筛选") {
                            libraryViewModel.selectArtist(nil)
                        }
                    }
                    if libraryViewModel.selectedCategory != nil {
                        Button("清除分类筛选") {
                            libraryViewModel.selectCategory(nil)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}

// MARK: - 歌曲列表行
struct SongListRow: View {
    let song: Song
    let onPlay: () -> Void
    let onAddToQueue: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 封面
            RoundedRectangle(cornerRadius: 8)
                .fill(.gray.opacity(0.2))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }

            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(song.artistName ?? "未知歌手")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if song.hasSeparation {
                        Image(systemName: "mic.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
            }

            Spacer()

            // 时长
            Text(song.durationText)
                .font(.callout)
                .foregroundStyle(.secondary)

            // 操作
            Menu {
                Button("播放", action: onPlay)
                Button("加入队列", systemImage: "plus", action: onAddToQueue)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("播放", action: onPlay)
            Button("加入队列", systemImage: "plus", action: onAddToQueue)
        }
    }
}
