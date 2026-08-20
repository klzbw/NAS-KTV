import Foundation
import Combine
import AVFoundation

final class PlayerViewModel: ObservableObject {
    @Published var currentSong: Song?
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var currentTrack: PlayerTrack = .original
    @Published var lyrics: [LyricLine] = []
    @Published var currentLyricIndex: Int = 0
    @Published var showPlayer: Bool = false

    private var playerService = PlayerService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
        setupNotifications()
    }

    private func setupBindings() {
        playerService.$currentSong
            .assign(to: &$currentSong)
        playerService.$isPlaying
            .assign(to: &$isPlaying)
        playerService.$currentTime
            .assign(to: &$currentTime)
        playerService.$duration
            .assign(to: &$duration)
        playerService.$currentTrack
            .assign(to: &$currentTrack)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .playerDidFinish,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.playNext()
        }
    }

    // MARK: - 播放控制
    func play(song: Song) {
        playerService.play(song: song)
        showPlayer = true
        loadLyrics(for: song)
    }

    func togglePlayPause() {
        playerService.togglePlayPause()
    }

    func seek(to time: Double) {
        playerService.seek(to: time)
    }

    func switchTrack(_ track: PlayerTrack) {
        playerService.switchTrack(track)
    }

    // MARK: - 队列控制
    func playNext() {
        Task {
            do {
                try await APIService.shared.playNext()
            } catch {
                print("Play next failed: \(error)")
            }
        }
    }

    func playPrevious() {
        Task {
            do {
                try await APIService.shared.playPrevious()
            } catch {
                print("Play previous failed: \(error)")
            }
        }
    }

    func addToQueue(song: Song) {
        Task {
            do {
                try await APIService.shared.addToQueue(songId: song.id)
            } catch {
                print("Add to queue failed: \(error)")
            }
        }
    }

    // MARK: - 歌词
    private func loadLyrics(for song: Song) {
        lyrics = []
        currentLyricIndex = 0

        Task {
            do {
                let lrcText = try await APIService.shared.fetchLyrics(songId: song.id)
                let lines = parseLRC(lrcText)
                await MainActor.run {
                    self.lyrics = lines
                }
            } catch {
                print("Load lyrics failed: \(error)")
            }
        }
    }

    private func parseLRC(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = "\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})\\](.*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in text.components(separatedBy: .newlines) {
            let nsRange = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: nsRange) {
                let minutes = (line as NSString).substring(with: match.range(at: 1))
                let seconds = (line as NSString).substring(with: match.range(at: 2))
                let milliseconds = (line as NSString).substring(with: match.range(at: 3))
                let text = (line as NSString).substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)

                let time = Double(minutes)! * 60 + Double(seconds)! + Double(milliseconds)! / 1000
                if !text.isEmpty {
                    lines.append(LyricLine(time: time, text: text))
                }
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    func updateCurrentLyric() {
        guard !lyrics.isEmpty else { return }
        var index = 0
        for (i, line) in lyrics.enumerated() {
            if currentTime >= line.time {
                index = i
            } else {
                break
            }
        }
        currentLyricIndex = index
    }
}

// MARK: - 歌词行
struct LyricLine: Identifiable, Hashable {
    let id = UUID()
    let time: Double
    let text: String
}
