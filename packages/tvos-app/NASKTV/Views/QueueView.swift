import SwiftUI

struct QueueView: View {
    @StateObject private var viewModel = QueueViewModel()
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 标题
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("播放队列")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            Text("\(viewModel.queue.count) 首歌曲")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            viewModel.loadQueue()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.title)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 80)
                    .padding(.top, 40)

                    // 队列列表
                    if viewModel.isLoading {
                        ProgressView("加载中...")
                            .controlSize(.large)
                            .padding(.top, 80)
                    } else if viewModel.queue.isEmpty {
                        ContentUnavailableView(
                            "队列为空",
                            systemImage: "list.bullet",
                            description: Text("添加歌曲到播放队列")
                        )
                        .padding(.top, 80)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(viewModel.queue.enumerated()), id: \.element.id) { index, item in
                                QueueRow(
                                    item: item,
                                    index: index
                                ) {
                                    if let song = item.song {
                                        playerViewModel.play(song: song)
                                    }
                                } onRemove: {
                                    viewModel.removeItem(item)
                                }
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("队列")
            .onAppear {
                viewModel.loadQueue()
            }
        }
    }
}

// MARK: - 队列行
struct QueueRow: View {
    let item: QueueItem
    let index: Int
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 序号/状态
            ZStack {
                if item.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                        .font(.title2)
                } else {
                    Text("\(index + 1)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                }
            }
            .frame(width: 40)

            // 封面占位
            RoundedRectangle(cornerRadius: 8)
                .fill(.gray.opacity(0.2))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }

            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(item.song?.title ?? "未知歌曲")
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(item.isPlaying ? .tint : .primary)
                Text(item.song?.artistName ?? "未知歌手")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 状态
            if item.isPlaying {
                Text("播放中")
                    .font(.callout)
                    .foregroundStyle(.tint)
            } else if item.isPending {
                Text("等待中")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // 操作
            Menu {
                Button("播放", action: onPlay)
                Button("从队列移除", systemImage: "trash", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(item.isPlaying ? Color.tint.opacity(0.1) : .regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("播放", action: onPlay)
            Button("从队列移除", systemImage: "trash", role: .destructive, action: onRemove)
        }
    }
}

// MARK: - 队列视图模型
@MainActor
final class QueueViewModel: ObservableObject {
    @Published var queue: [QueueItem] = []
    @Published var isLoading: Bool = false

    func loadQueue() {
        isLoading = true
        Task {
            do {
                let queue = try await APIService.shared.fetchQueue()
                await MainActor.run {
                    self.queue = queue
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    func removeItem(_ item: QueueItem) {
        Task {
            do {
                try await APIService.shared.removeFromQueue(itemId: item.id)
                await MainActor.run {
                    self.queue.removeAll { $0.id == item.id }
                }
            } catch {
                print("Remove failed: \(error)")
            }
        }
    }
}
