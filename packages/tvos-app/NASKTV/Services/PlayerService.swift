import Foundation
import AVFoundation
import Combine

final class PlayerService: ObservableObject {
    static let shared = PlayerService()

    @Published var currentSong: Song?
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var currentTrack: PlayerTrack = .original
    @Published var volume: Float = 1.0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerItem: AVPlayerItem?

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    // MARK: - 播放控制
    func play(song: Song, track: PlayerTrack = .original) {
        currentSong = song
        currentTrack = track
        playCurrentTrack()
    }

    private func playCurrentTrack() {
        guard let song = currentSong,
              let url = APIService.shared.streamURL(for: song, track: currentTrack) else {
            return
        }

        removeTimeObserver()

        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume

        addTimeObserver()
        player?.play()
        isPlaying = true

        // 监听播放结束
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }

    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        player?.volume = volume
    }

    // MARK: - 原伴唱切换
    func switchTrack(_ track: PlayerTrack) {
        guard currentSong != nil, track != currentTrack else { return }
        let currentTime = self.currentTime
        currentTrack = track
        playCurrentTrack()
        seek(to: currentTime)
    }

    // MARK: - 时间观察
    private func addTimeObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            if let item = self.playerItem {
                self.duration = item.duration.seconds
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    @objc private func playerDidFinish() {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = 0
            // 通知播放结束，由ViewModel处理下一首
            NotificationCenter.default.post(name: .playerDidFinish, object: nil)
        }
    }

    deinit {
        removeTimeObserver()
        NotificationCenter.default.removeObserver(self)
    }
}

extension Notification.Name {
    static let playerDidFinish = Notification.Name("playerDidFinish")
}
