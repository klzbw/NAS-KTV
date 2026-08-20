import Foundation
import Combine

final class ServerViewModel: ObservableObject {
    @Published var servers: [ServerConfig] = []
    @Published var currentServer: ServerConfig?
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard
    private let serversKey = "saved_servers"

    init() {
        loadSavedServers()
    }

    // MARK: - 服务器管理
    func loadSavedServers() {
        guard let data = defaults.data(forKey: serversKey),
              let servers = try? JSONDecoder().decode([ServerConfig].self, from: data) else {
            return
        }
        self.servers = servers
        // 自动连接默认服务器
        if let defaultServer = servers.first(where: { $0.isDefault }) {
            connect(to: defaultServer)
        }
    }

    func saveServers() {
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: serversKey)
        }
    }

    func addServer(_ config: ServerConfig) {
        servers.append(config)
        saveServers()
    }

    func removeServer(_ config: ServerConfig) {
        servers.removeAll { $0.id == config.id }
        saveServers()
    }

    func setDefault(_ config: ServerConfig) {
        servers = servers.map {
            var s = $0
            s.isDefault = (s.id == config.id)
            return s
        }
        saveServers()
    }

    // MARK: - 连接
    func connect(to config: ServerConfig) {
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                let data = try await APIService.shared.login(
                    host: config.host,
                    port: config.port,
                    username: config.username,
                    password: config.password
                )

                await MainActor.run {
                    self.currentServer = config
                    self.isConnected = true
                    self.isConnecting = false

                    // 配置WebSocket
                    WebSocketService.shared.configure(
                        baseURL: config.baseURL.replacingOccurrences(of: "http", with: "ws"),
                        token: data.token
                    )
                    WebSocketService.shared.connect()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isConnecting = false
                }
            }
        }
    }

    func disconnect() {
        WebSocketService.shared.disconnect()
        currentServer = nil
        isConnected = false
    }

    func testConnection(host: String, port: Int, username: String, password: String) async -> Bool {
        do {
            _ = try await APIService.shared.login(host: host, port: port, username: username, password: password)
            return true
        } catch {
            return false
        }
    }
}
