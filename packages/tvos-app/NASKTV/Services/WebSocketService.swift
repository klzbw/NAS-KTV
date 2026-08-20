import Foundation
import Combine

final class WebSocketService: NSObject, ObservableObject {
    static let shared = WebSocketService()

    @Published var currentSongId: Int?
    @Published var isPlaying: Bool = false
    @Published var currentPosition: Double = 0
    @Published var queue: [QueueItem] = []

    private var webSocket: URLSessionWebSocketTask?
    private var baseURL: String = ""
    private var token: String = ""
    private var reconnectTimer: Timer?
    private var isConnected = false

    private override init() {
        super.init()
    }

    func configure(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    func connect() {
        guard let url = URL(string: "\(baseURL)/ws?token=\(token)") else { return }
        disconnect()

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        receiveMessage()
    }

    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()
            case .failure:
                self.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let message = try JSONDecoder().decode(WSMessage.self, from: data)
            DispatchQueue.main.async {
                switch message.type {
                case "play":
                    self.currentSongId = message.data?.songId
                    self.isPlaying = true
                case "pause":
                    self.isPlaying = false
                case "stop":
                    self.isPlaying = false
                    self.currentSongId = nil
                case "position":
                    self.currentPosition = message.data?.position ?? 0
                case "queue_update":
                    self.queue = message.data?.queue ?? []
                case "status":
                    if let status = message.data?.status {
                        self.isPlaying = (status == "playing")
                    }
                default:
                    break
                }
            }
        } catch {
            print("WebSocket parse error: \(error)")
        }
    }

    private func scheduleReconnect() {
        guard !isConnected else { return }
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate
extension WebSocketService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        isConnected = true
        print("WebSocket connected")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        print("WebSocket disconnected: \(closeCode)")
        scheduleReconnect()
    }
}
