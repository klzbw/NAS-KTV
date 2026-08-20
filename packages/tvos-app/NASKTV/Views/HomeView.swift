import SwiftUI

struct HomeView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var selectedSection: HomeSection = .recommend

    enum HomeSection: String, CaseIterable {
        case recommend = "推荐"
        case artists = "歌手"
        case categories = "分类"
        case recent = "最近"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // 顶部标题
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAS-KTV")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("家庭KTV点歌系统")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let server = libraryViewModel as AnyObject as? ServerViewModel,
                       let current = server.currentServer {
                        Text(current.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 40)

                // 分段选择
                Picker("浏览方式", selection: $selectedSection) {
                    ForEach(HomeSection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 80)

                // 内容区域
                switch selectedSection {
                case .recommend:
                    RecommendSection()
                case .artists:
                    ArtistsSection()
                case .categories:
                    CategoriesSection()
                case .recent:
                    RecentSection()
                }
            }
            .padding(.bottom, 100)
        }
        .onAppear {
            libraryViewModel.loadAll()
        }
    }
}

// MARK: - 推荐区域
struct RecommendSection: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("热门歌曲")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(libraryViewModel.songs.prefix(20)) { song in
                        SongCard(song: song) {
                            playerViewModel.play(song: song)
                        } onAddToQueue: {
                            libraryViewModel.addToQueue(song: song)
                        }
                    }
                }
                .padding(.horizontal, 80)
            }
        }
    }
}

// MARK: - 歌手区域
struct ArtistsSection: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("全部歌手")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 80)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 20)], spacing: 20) {
                ForEach(libraryViewModel.artists) { artist in
                    ArtistCard(artist: artist) {
                        libraryViewModel.selectArtist(artist)
                    }
                }
            }
            .padding(.horizontal, 80)
        }
    }
}

// MARK: - 分类区域
struct CategoriesSection: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            ForEach(libraryViewModel.categories) { group in
                VStack(alignment: .leading, spacing: 16) {
                    Text(group.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(group.items) { item in
                                CategoryChip(item: item) {
                                    libraryViewModel.selectCategory(item)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 80)
            }
        }
    }
}

// MARK: - 最近播放
struct RecentSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("最近播放")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 80)

            ContentUnavailableView(
                "暂无播放记录",
                systemImage: "clock",
                description: Text("播放过的歌曲会显示在这里")
            )
            .padding(.top, 60)
        }
    }
}

// MARK: - 歌曲卡片
struct SongCard: View {
    let song: Song
    let onPlay: () -> Void
    let onAddToQueue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)

                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                // 播放按钮覆盖层
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: onPlay) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(width: 180)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artistName ?? "未知歌手")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 180, alignment: .leading)
        }
        .contextMenu {
            Button("播放", action: onPlay)
            Button("加入队列", systemImage: "plus", action: onAddToQueue)
        }
    }
}

// MARK: - 歌手卡片
struct ArtistCard: View {
    let artist: Artist
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                Circle()
                    .fill(.gray.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }

                VStack(spacing: 4) {
                    Text(artist.name)
                        .font(.headline)
                        .lineLimit(1)
                    if let count = artist.songCount {
                        Text("\(count) 首歌曲")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.card)
    }
}

// MARK: - 分类标签
struct CategoryChip: View {
    let item: CategoryItem
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.headline)
                if let count = item.songCount {
                    Text("\(count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
