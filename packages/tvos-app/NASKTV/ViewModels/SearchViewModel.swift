import Foundation
import Combine

final class SearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var results: [Song] = []
    @Published var isSearching: Bool = false
    @Published var hasSearched: Bool = false

    private var searchTask: Task<Void, Never>?

    init() {
        // 监听搜索文本变化，防抖搜索
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.performSearch(text)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func performSearch(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            hasSearched = false
            return
        }

        searchTask?.cancel()
        isSearching = true
        hasSearched = true

        searchTask = Task {
            do {
                let data = try await APIService.shared.fetchSongs(
                    page: 1,
                    pageSize: 50,
                    keyword: text
                )
                await MainActor.run {
                    self.results = data.items
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.results = []
                    self.isSearching = false
                }
            }
        }
    }

    func clearSearch() {
        searchText = ""
        results = []
        hasSearched = false
    }

    func playSong(_ song: Song) {
        PlayerService.shared.play(song: song)
    }

    func addToQueue(_ song: Song) {
        Task {
            do {
                try await APIService.shared.addToQueue(songId: song.id)
            } catch {
                print("Add to queue failed: \(error)")
            }
        }
    }
}
