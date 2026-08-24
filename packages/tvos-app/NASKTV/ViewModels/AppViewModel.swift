import Foundation
import Combine
import UIKit

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
    @Published var bootstrapError: String?

    // QR Code / Join Ticket
    @Published var joinTicket: RoomJoinTicket?
    @Published var h5BaseUrl: String = ""

    // Device
    private(set) var deviceId: String = ""

    private var cancellables = Set<AnyCancellable>()
    private var lastQueueVersion: Int = 0
    private var isDeleting = false
    private var ticketRefreshTask: Task<Void, Never>?
    private var isTicketRefreshing = false
    private var isFirstTicketLoad = true
    private var wsHandlersSetup = false

    init() {
        loadConfig()
        loadDeviceId()
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
        self.room = nil
        self.authorized = false
        self.queue = []
        self.currentItem = nil
        WebSocketService.shared.disconnect()
        stopJoinTicketRefresh()
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

    // MARK: - Bootstrap (参考安卓端 App.tsx)
    func bootstrap() async {
        guard isConfigured, !isRegistering else { return }
        isRegistering = true
        bootstrapError = nil

        do {
            // 1. 健康检查
            let _ = try await APIService.shared.healthCheck()

            // 2. 验证缓存的 roomCode 是否仍存在
            if let storedCode = UserDefaults.standard.string(forKey: "nasktv_room_code") {
                do {
                    let _ = try await APIService.shared.getRoom(code: storedCode)
                } catch {
                    if case APIError.httpError(let code) = error, code == 404 {
                        clearDeviceId()
                    }
                }
            }

            // 3. 注册设备
            let deviceInfo = "tvOS \(UIDevice.current.model)"
            var roomData = try await APIService.shared.registerDevice(
                deviceId: deviceId,
                name: "Apple TV",
                deviceInfo: deviceInfo
            )

            // 4. 启动时轮换一次房间码（参考安卓端 sessionStorage 逻辑）
            let hasRotated = UserDefaults.standard.bool(forKey: "nasktv_code_rotated")
            if !hasRotated {
                do {
                    roomData = try await APIService.shared.rotateCode(roomData.id, deviceId: deviceId)
                    UserDefaults.standard.set(true, forKey: "nasktv_code_rotated")
                } catch {
                    print("Rotate code failed: \(error)")
                }
            }

            // 5. 设置 room（触发 WebSocket 连接）
            await MainActor.run {
                setRoom(roomData)
                UserDefaults.standard.set(roomData.code, forKey: "nasktv_room_code")
                self.isRegistering = false
            }

            // 6. 加载 H5 URL
            await loadH5Url()

        } catch {
            await MainActor.run {
                self.bootstrapError = error.localizedDescription
                self.isRegistering = false
            }
        }
    }

    private func setRoom(_ room: Room) {
        self.room = room
        self.authorized = room.isAuthorized
        // 无论授权状态都连接 WebSocket（参考安卓端 useRoomSync）
        setupWebSocketHandlersIfNeeded()
        WebSocketService.shared.connect(roomCode: room.code, deviceId: room.deviceId)
    }

    // MARK: - WebSocket Handlers (参考安卓端 useRoomSync.ts)
    private func setupWebSocketHandlersIfNeeded() {
        guard !wsHandlersSetup else { return }
        wsHandlersSetup = true

        WebSocketService.shared.onStatusChange { [weak self] status in
            DispatchQueue.main.async {
                self?.wsStatus = status
            }
        }

        // ROOM_STATE_SNAPSHOT
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
                    if snapshot.authorized {
                        self.loadH5Url()
                        self.startJoinTicketRefresh()
                    } else {
                        self.stopJoinTicketRefresh()
                        self.joinTicket = nil
                    }
                }
            }
        }

        // QUEUE_UPDATED
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

        // PLAYER_STATE_UPDATED
        WebSocketService.shared.on(.PLAYER_STATE_UPDATED) { [weak self] message in
            DispatchQueue.main.async {
                if let state = message.decodePayload(PlayerStatePayload.self) {
                    self?.playerState = state
                }
            }
        }

        // ROOM_AUTHORIZED
        WebSocketService.shared.on(.ROOM_AUTHORIZED) { [weak self] _ in
            DispatchQueue.main.async {
                self?.authorized = true
                self?.expiresAt = nil
                self?.loadH5Url()
                self?.startJoinTicketRefresh()
            }
        }

        // ROOM_EXPIRING_SOON
        WebSocketService.shared.on(.ROOM_EXPIRING_SOON) { [weak self] message in
            guard let payload = message.payload else { return }
            DispatchQueue.main.async {
                if let expiresAt = payload["expiresAt"]?.value as? String {
                    self?.expiresAt = expiresAt
                }
            }
        }

        // ROOM_UNAUTHORIZED
        WebSocketService.shared.on(.ROOM_UNAUTHORIZED) { [weak self] _ in
            DispatchQueue.main.async {
                self?.authorized = false
                self?.expiresAt = nil
                self?.stopJoinTicketRefresh()
                self?.joinTicket = nil
            }
        }

        // ROOM_CLOSED (设备被删除)
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
        joinTicket = nil
        UserDefaults.standard.removeObject(forKey: "nasktv_room_code")
    }

    // MARK: - QR Code / Join Ticket (参考安卓端 useJoinTicket.ts)
    var qrText: String {
        guard !h5BaseUrl.isEmpty, let ticket = joinTicket else { return "" }
        let base = h5BaseUrl.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        return "\(base)/join?authorizationCode=\(ticket.authorizationCode)"
    }

    func loadH5Url() {
        Task {
            do {
                let url = try await APIService.shared.getH5Url()
                await MainActor.run {
                    if !url.isEmpty {
                        self.h5BaseUrl = url
                    } else if !apiUrl.isEmpty {
                        let derived = apiUrl.replacingOccurrences(of: "/api/?$", with: "", options: .regularExpression) + "/h5"
                        self.h5BaseUrl = derived
                    }
                }
            } catch {
                await MainActor.run {
                    if !apiUrl.isEmpty {
                        let derived = apiUrl.replacingOccurrences(of: "/api/?$", with: "", options: .regularExpression) + "/h5"
                        self.h5BaseUrl = derived
                    }
                }
            }
        }
    }

    func startJoinTicketRefresh() {
        guard !isTicketRefreshing else { return }
        stopJoinTicketRefresh()
        isTicketRefreshing = true
        isFirstTicketLoad = true
        ticketRefreshTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.isTicketRefreshing = false }
            while !Task.isCancelled {
                guard let room = self.room, room.isAuthorized || self.authorized else {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                }
                do {
                    let ticket = try await APIService.shared.issueJoinTicket(
                        roomId: room.id,
                        deviceId: room.deviceId,
                        forceRotate: self.isFirstTicketLoad
                    )
                    self.isFirstTicketLoad = false
                    await MainActor.run {
                        self.joinTicket = ticket
                    }
                    let expiresAt = ISO8601DateFormatter().date(from: ticket.expiresAt) ?? Date().addingTimeInterval(60)
                    let delay = max(5.0, min(30.0, expiresAt.timeIntervalSinceNow - 60))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                }
            }
        }
    }

    func stopJoinTicketRefresh() {
        ticketRefreshTask?.cancel()
        ticketRefreshTask = nil
    }

    // MARK: - Lyrics
    func loadLyrics(songId: Int) async {
        do {
            let lines = try await APIService.shared.getLyrics(songId: songId)
            await MainActor.run {
                self.lyrics = lines
                self.currentLyricIndex = 0
            }
        } catch {
            print("Lyrics load error: \(error)")
        }
    }

    func updateCurrentLyric(time: Double) {
        guard !lyrics.isEmpty else { return }
        var newIndex = 0
        for (i, line) in lyrics.enumerated() {
            if line.time <= time {
                newIndex = i
            } else {
                break
            }
        }
        if newIndex != currentLyricIndex {
            currentLyricIndex = newIndex
        }
    }

    // MARK: - Player Control
    func sendPlayPause() {
        // WebSocket 通知服务端
    }

    func sendNext() {
        guard let room = room, let item = currentItem else { return }
        Task {
            do {
                try await APIService.shared.skipSong(roomId: room.id, deviceId: room.deviceId, queueItemId: item.id)
            } catch {
                print("Skip error: \(error)")
            }
        }
    }

    func sendPrev() {
        guard let room = room, let item = currentItem else { return }
        Task {
            do {
                try await APIService.shared.completeSong(roomId: room.id, deviceId: room.deviceId, queueItemId: item.id)
            } catch {
                print("Complete error: \(error)")
            }
        }
    }

    // MARK: - App Lifecycle
    func handleAppForeground() {
        Task {
            if isConfigured {
                if room == nil {
                    await bootstrap()
                } else {
                    setupWebSocketHandlersIfNeeded()
                    WebSocketService.shared.connect(roomCode: room!.code, deviceId: room!.deviceId)
                    if authorized {
                        loadH5Url()
                        startJoinTicketRefresh()
                    }
                }
            }
        }
    }

    func handleAppBackground() {
        stopJoinTicketRefresh()
        WebSocketService.shared.disconnect()
        wsStatus = .disconnected
    }
}
