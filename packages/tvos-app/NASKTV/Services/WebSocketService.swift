import Foundation

// MARK: - Connection Status
enum ConnectionStatus: String {
    case connected, connecting, disconnected
}

// MARK: - WebSocketService
final class WebSocketService: NSObject, URLSessionWebSocketDelegate {
    static let shared = WebSocketService()

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession!
    private var roomCode: String?
    private var deviceId: String?
    private var wsBaseURL: String = ""

    private(set) var status: ConnectionStatus = .disconnected
    private var reconnectAttempts = 0
    private var disposed = false
    private var heartbeatTimer: Timer?

    private let heartbeatInterval: TimeInterval = 25
    private let maxReconnectDelay: TimeInterval = 30

    // Message handlers
    private var handlers: [WsMessageType: [(WsMessage) -> Void]] = [:]
    private var statusHandlers: [(ConnectionStatus) -> Void] = []

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func setWSBaseURL(_ url: String) {
        self.wsBaseURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    }

    func connect(roomCode: String, deviceId: String?) {
        closeCurrent()
        self.disposed = false
        self.roomCode = roomCode
        self.deviceId = deviceId
        self.reconnectAttempts = 0
        doConnect()
    }

    private func doConnect() {
        guard let roomCode = roomCode, !disposed else { return }

        let wsBase = wsBaseURL.isEmpty ? "ws://192.168.3.16:3000" : wsBaseURL
        let deviceQuery = deviceId == nil ? "" : "&deviceId=\(deviceId!.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        let urlString = "\(wsBase)/ws/room?roomCode=\(roomCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&role=tv\(deviceQuery)"

        guard let url = URL(string: urlString) else {
            print("WebSocket invalid URL: \(urlString)")
            return
        }

        setStatus(.connecting)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        receiveMessage()
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
                // Connection closed, will be handled by delegate
                break
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let message = try JSONDecoder().decode(WsMessage.self, from: data)
            if message.type == .PONG { return }
            handlers[message.type]?.forEach { $0(message) }
        } catch {
            print("WebSocket parse error: \(error)")
        }
    }

    func send(_ message: WsMessage) {
        guard let webSocket = webSocket, webSocket.state == .running else { return }
        do {
            let data = try JSONEncoder().encode(message)
            if let text = String(data: data, encoding: .utf8) {
                webSocket.send(.string(text)) { _ in }
            }
        } catch {
            print("WebSocket send error: \(error)")
        }
    }

    func on(_ type: WsMessageType, handler: @escaping (WsMessage) -> Void) {
        if handlers[type] == nil { handlers[type] = [] }
        handlers[type]?.append(handler)
    }

    func onStatusChange(_ handler: @escaping (ConnectionStatus) -> Void) {
        statusHandlers.append(handler)
    }

    private func setStatus(_ status: ConnectionStatus) {
        self.status = status
        statusHandlers.forEach { $0(status) }
    }

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.send(WsMessage(type: .PING, payload: ["clientTime": AnyCodable(Int64(Date().timeIntervalSince1970 * 1000))], timestamp: Int64(Date().timeIntervalSince1970 * 1000)))
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func closeCurrent() {
        stopHeartbeat()
        webSocket?.cancel()
        webSocket = nil
    }

    func disconnect() {
        disposed = true
        setStatus(.disconnected)
        closeCurrent()
    }

    private func attemptReconnect() {
        if disposed || webSocket != nil { return }
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.doConnect()
        }
    }

    // MARK: - URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket connected to room: \(roomCode ?? "unknown")")
        reconnectAttempts = 0
        setStatus(.connected)
        startHeartbeat()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("WebSocket disconnected, code: \(closeCode.rawValue)")
        stopHeartbeat()
        webSocket = nil
        if !disposed {
            setStatus(.disconnected)
            attemptReconnect()
        }
    }
}
