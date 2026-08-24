import Foundation
import AVFoundation

// MARK: - Track Type
enum TrackType: String {
    case original = "original"
    case vocals = "vocals"
    case instrumental = "instrumental"
}

// MARK: - PlayerService
final class PlayerService: NSObject, ObservableObject {
    static let shared = PlayerService()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTrack: TrackType = .original
    @Published private(set) var currentSong: QueueListItem?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var currentURL: URL?

    private override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup error: \(error)")
        }
    }

    func play(url: URL, song: QueueListItem?) {
        currentSong = song
        currentURL = url
        currentTrack = .original

        let playerItem = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer()
        }
        player?.replaceCurrentItem(with: playerItem)

        // Observe duration
        playerItem.addObserver(self, forKeyPath: "duration", options: [.new, .initial], context: nil)

        // Time observer
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }

        player?.play()
        isPlaying = true
    }

    func playPause() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
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
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = time
    }

    func switchTrack(_ track: TrackType, baseURL: String, songId: Int) {
        currentTrack = track
        // Construct URL for different track
        let path: String
        switch track {
        case .original:
            path = "/api/songs/\(songId)/stream"
        case .vocals:
            path = "/api/songs/\(songId)/vocals"
        case .instrumental:
            path = "/api/songs/\(songId)/instrumental"
        }
        guard let url = URL(string: "\(baseURL)\(path)") else { return }
        let wasPlaying = isPlaying
        let currentPos = currentTime
        play(url: url, song: currentSong)
        seek(to: currentPos)
        if !wasPlaying { pause() }
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTime = 0
        duration = 0
        currentSong = nil
        currentTrack = .original
    }

    // MARK: - KVO
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "duration", let playerItem = object as? AVPlayerItem {
            duration = playerItem.duration.seconds
        }
    }

    deinit {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
    }
}
