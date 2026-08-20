import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索栏
                searchBar
                    .padding(.horizontal, 80)
                    .padding(.top, 40)
                    .padding(.bottom, 24)

                // 搜索结果
                ScrollView {
                    if viewModel.isSearching {
                        ProgressView("搜索中...")
                            .controlSize(.large)
                            .padding(.top, 80)
                    } else if viewModel.hasSearched && viewModel.results.isEmpty {
                        ContentUnavailableView(
                            "未找到歌曲",
                            systemImage: "magnifyingglass",
                            description: Text("尝试其他关键词")
                        )
                        .padding(.top, 80)
                    } else if !viewModel.results.isEmpty {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.results) { song in
                                SearchResultRow(song: song) {
                                    playerViewModel.play(song: song)
                                } onAddToQueue: {
                                    viewModel.addToQueue(song)
                                }
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.bottom, 100)
                    } else {
                        // 搜索提示
                        VStack(spacing: 20) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            Text("搜索歌曲、歌手")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 80)
                    }
                }
            }
            .navigationTitle("搜索")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("输入歌曲名或歌手", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.title3)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 搜索结果行
struct SearchResultRow: View {
    let song: Song
    let onPlay: () -> Void
    let onAddToQueue: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 封面占位
            RoundedRectangle(cornerRadius: 8)
                .fill(.gray.opacity(0.2))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }

            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artistName ?? "未知歌手")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 时长
            Text(song.durationText)
                .font(.callout)
                .foregroundStyle(.secondary)

            // 操作按钮
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
