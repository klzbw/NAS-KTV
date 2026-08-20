import Foundation
import Combine

final class LibraryViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var artists: [Artist] = []
    @Published var categories: [CategoryGroup] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var selectedArtist: Artist?
    @Published var selectedCategory: CategoryItem?
    @Published var currentPage: Int = 1
    @Published var totalPages: Int = 1
    @Published var hasMore: Bool = false

    private let pageSize = 50

    // MARK: - 加载数据
    func loadAll() {
        loadArtists()
        loadCategories()
        loadSongs()
    }

    func loadSongs(reset: Bool = true) {
        if reset {
            currentPage = 1
            songs = []
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let data = try await APIService.shared.fetchSongs(
                    page: currentPage,
                    pageSize: pageSize,
                    artistId: selectedArtist?.id,
                    categoryItemIds: selectedCategory.map { [$0.id] }
                )

                await MainActor.run {
                    if reset {
                        self.songs = data.items
                    } else {
                        self.songs.append(contentsOf: data.items)
                    }
                    self.totalPages = (data.total + pageSize - 1) / pageSize
                    self.hasMore = currentPage < totalPages
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func loadMoreSongs() {
        guard hasMore, !isLoading else { return }
        currentPage += 1
        loadSongs(reset: false)
    }

    func loadArtists() {
        Task {
            do {
                let artists = try await APIService.shared.fetchArtists()
                await MainActor.run {
                    self.artists = artists
                }
            } catch {
                print("Load artists failed: \(error)")
            }
        }
    }

    func loadCategories() {
        Task {
            do {
                let categories = try await APIService.shared.fetchCategories()
                await MainActor.run {
                    self.categories = categories
                }
            } catch {
                print("Load categories failed: \(error)")
            }
        }
    }

    // MARK: - 筛选
    func selectArtist(_ artist: Artist?) {
        selectedArtist = artist
        loadSongs()
    }

    func selectCategory(_ category: CategoryItem?) {
        selectedCategory = category
        loadSongs()
    }

    func clearFilters() {
        selectedArtist = nil
        selectedCategory = nil
        loadSongs()
    }

    // MARK: - 操作
    func addToQueue(song: Song) {
        Task {
            do {
                try await APIService.shared.addToQueue(songId: song.id)
            } catch {
                print("Add to queue failed: \(error)")
            }
        }
    }

    func playNow(song: Song) {
        PlayerService.shared.play(song: song)
    }
}
