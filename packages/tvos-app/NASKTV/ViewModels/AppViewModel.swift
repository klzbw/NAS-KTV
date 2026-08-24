import Foundation
import Combine

// MARK: - AppViewModel
final class AppViewModel: ObservableObject {
    // Config
    @Published var apiUrl: String = ""
    @Published var wsUrl: String = ""
    @Published var isConfigured = false
    @Published var isLoaded = false

    // Room
    @Published var room: Room?
    @Published var authorized = false
    @Published var expiresAt: String?

    // Queue
    @Published var queue: [QueueListItem] = []
    @Published var currentItem: QueueListItem?

    // Player
    @Published var playerState: PlayerStatePayload?
    @Published var lyrics: [LyricLine] = []
    @Published var currentLyricIndex: Int = 0

    // Connection
    @Published var wsStatus: ConnectionStatus = .disconnected
    @Published var errorMessage: String?
    @Published var isRegistering = false

    // Device
    private(set) var deviceId: String = ""

    private var cancellables = Set<AnyCancellable>()
    private var lastQueueVersion: Int = 0
    private var isDeleting = false

    init() {
        loadConfig()
        loadDeviceId()
        setupWebSocketHandlers()
    }

    // MARK: - Config
    private func loadConfig() {
        if let apiUrl = UserDefaults.standard.string(forKey: "nasktv_api_url"),
           let wsUrl = UserDefaults.standard.string(forKey: "nasktv_ws_url"),
           !apiUrl.isEmpty {
            self.apiUrl = apiUrl
            self.wsUrl = wsUrl
            self.isConfigured = true
            APIService.shared.setBaseURL(apiUrl)
            WebSocketService.shared.setWSBaseURL(wsUrl)
        }
        self.isLoaded = true
    }

    func saveConfig(apiUrl: String, wsUrl: String) {
        self.apiUrl = apiUrl
        self.wsUrl = wsUrl
        self.isConfigured = true
        UserDefaults.standard.set(apiUrl, forKey: "nasktv_api_url")
        UserDefaults.standard.set(wsUrl, forKey: "nasktv_ws_url")
        APIService.shared.setBaseURL(apiUrl)
        WebSocketService.shared.setWSBaseURL(wsUrl)
    }

    func clearConfig() {
        UserDefaults.standard.removeObject(forKey: "nasktv_api_url")
        UserDefaults.standard.removeObject(forKey: "nasktv_ws_url")
        self.apiUrl = ""
        self.wsUrl = ""
        self.isConfigured = false
    }

    // MARK: - Device ID
    private func loadDeviceId() {
        if let id = UserDefaults.standard.string(forKey: "nasktv_device_id"), !id.isEmpty {
            self.deviceId = id
        } else {
            self.deviceId = UUID().uuidString
            UserDefaults.standard.set(self.deviceId, forKey: "nasktv_device_id")
        }
    }

    func clearDeviceId() {
        UserDefaults.standard.removeObject(forKey: "nasktv_device_id")
        self.deviceId = UUID().uuidString
        UserDefaults.standard.set(self.deviceId, forKey: "nasktv_device_id")
    }

    // MARK: - Registration
    func registerDevice() async {
        guard isConfigured else { return }
        isRegistering = true
        errorMessage = nil
        do {
            let deviceInfo = "tvOS/iOS \(UIDevice.current.model)"
            let room = try await APIService.shared.registerDevice(
                deviceId: deviceId,
                name: "Apple TV",
                deviceInfo: deviceInfo
            )
            await MainActor.run {
                self.room = room
                self.authorized = room.isAuthorized
                self.isRegistering = false
                if room.isAuthorized {
                    connectWebSocket()
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isRegistering = false
            }
        }
    }

    // MARK: - WebSocket
    private func connectWebSocket() {
        guard let room = room else { return }
        WebSocketService.shared.connect(roomCode: room.code, deviceId: room.deviceId)
    }

    private func setupWebSocketHandlers() {
        WebSocketService.shared.onStatusChange { [weak self] status in
            DispatchQueue.main.async {
                self?.wsStatus = status
            }
        }

        // Room state snapshot
        WebSocketService.shared.on(.ROOM_STATE_SNAPSHOT) { [weak self] message in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let snapshot = message.decodePayload(RoomStateSnapshotPayload.self) {
                    if let version = snapshot.queueVersion {
                        self.lastQueueVersion = version
                    }
                    self.queue = snapshot.queue
                    self.currentItem = snapshot.queue.first { $0.isPlaying }
                    self.authorized = snapshot.authorized
                    self.playerState = snapshot.playerState
                }
            }
        }

        // Queue updated
        WebSocketService.shared.on(.QUEUE_UPDATED) { [weak self] message in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let updated = message.decodePayload(QueueUpdatedPayload.self) {
                    if let version = updated.queueVersion, version < self.lastQueueVersion {
                        return
                    }
                    if let version = updated.queueVersion {
                        self.lastQueueVersion = max(self.lastQueueVersion, version)
                    }
                    self.queue = updated.queue
                    self.currentItem = updated.queue.first { $0.isPlaying }
                }
            }
        }

        // Player state updated
        WebSocketService.shared.on(.PLAYER_STATE_UPDATED) { [weak self] message in
            DispatchQueue.main.async {
                if let state = message.decodePayload(PlayerStatePayload.self) {
                    self?.playerState = state
                }
            }
        }

        // Authorized
        WebSocketService.shared.on(.ROOM_AUTHORIZED) { [weak self] _ in
            DispatchQueue.main.async {
                self?.authorized = true
                self?.expiresAt = nil
            }
        }

        // Expiring soon
        WebSocketService.shared.on(.ROOM_EXPIRING_SOON) { [weak self] message in
            guard let payload = message.payload else { return }
            DispatchQueue.main.async {
                if let expiresAt = payload["expiresAt"]?.value as? String {
                    self?.expiresAt = expiresAt
                }
            }
        }

        // Unauthorized
        WebSocketService.shared.on(.ROOM_UNAUTHORIZED) { [weak self] _ in
            DispatchQueue.main.async {
                self?.authorized = false
                self?.expiresAt = nil
            }
        }

        // Room closed (device deleted)
        WebSocketService.shared.on(.ROOM_CLOSED) { [weak self] message in
            guard let self = self, let payload = message.payload else { return }
            if let reason = payload["reason"]?.value as? String, reason == "deleted" {
                DispatchQueue.main.async {
                    self.isDeleting = true
                    WebSocketService.shared.disconnect()
                    self.clearDeviceId()
                    self.resetRoom()
                    self.isDeleting = false
                }
            }
        }
    }

    private func resetRoom() {
        room = nil
        authorized = false
        expiresAt = nil
        queue = []
        currentItem = nil
        playerState = nil
    }

    // MARK: - Lyrics
    func loadLyrics(songId: Int) async {
        do {
            let lines = try await APIService.shared.getLyrics(songId: songId)
            await MainActor.run {
                self.lyrics = lines
            }
        } catch {
            await MainActor.run {
                self.lyrics = []
            }
        }
    }

    func updateCurrentLyric(time: Double) {
        guard !lyrics.isEmpty else { return }
        var index = 0
        for (i, line) in lyrics.enumerated() {
            if line.time <= time {
                index = i
            } else {
                break
            }
        }
        if index != currentLyricIndex {
            currentLyricIndex = index
        }
    }

    // MARK: - Player Control (send to backend via WS)
    func sendPlayPause() {
        let message = WsMessage(
            type: .PLAYER_STATE_UPDATED,
            payload: ["action": AnyCodable("play_pause")],
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
        WebSocketService.shared.send(message)
    }

    func sendNext() {
        let message = WsMessage(
            type: .PLAYER_STATE_UPDATED,
            payload: ["action": AnyCodable("next")],
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
        WebSocketService.shared.send(message)
    }

    func sendPrev() {
        let message = WsMessage(
            type: .PLAYER_STATE_UPDATED,
            payload: ["action": AnyCodable("prev")],
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
        WebSocketService.shared.send(message)
    }
}

// MARK: - UIDevice helper (for tvOS/iOS compatibility)
#if os(tvOS)
import UIKit
#elseif os(iOS)
import UIKit
#endif
