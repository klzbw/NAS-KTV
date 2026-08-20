import Foundation

struct ServerConfig: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String
    var isDefault: Bool

    var baseURL: String {
        "http://\(host):\(port)"
    }

    init(id: UUID = UUID(),
         name: String = "",
         host: String = "",
         port: Int = 3000,
         username: String = "admin",
         password: String = "",
         isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.isDefault = isDefault
    }

    static let placeholder = ServerConfig(name: "我的NAS", host: "192.168.1.100", port: 3000)
}

// MARK: - 登录响应
struct LoginResponse: Codable {
    let success: Bool
    let data: LoginData?
    let error: String?
}

struct LoginData: Codable {
    let token: String
    let user: UserInfo
}

struct UserInfo: Codable {
    let id: Int
    let username: String
    let role: String
}
