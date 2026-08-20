import Foundation

final class APIService {
    static let shared = APIService()

    private var baseURL: String = ""
    private var token: String = ""
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    func configure(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    // MARK: - 认证
    func login(host: String, port: Int, username: String, password: String) async throws -> LoginData {
        let url = URL(string: "http://\(host):\(port)/api/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["username": username, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(LoginResponse.self, from: data)
        guard result.success, let data = result.data else {
            throw APIError.loginFailed(result.error ?? "Unknown error")
        }

        self.baseURL = "http://\(host):\(port)"
        self.token = data.token
        return data
    }

    // MARK: - 歌曲
    func fetchSongs(page: Int = 1, pageSize: Int = 50,
                    keyword: String? = nil,
                    artistId: Int? = nil,
                    categoryItemIds: [Int]? = nil) async throws -> SongsData {
        var components = URLComponents(string: "\(baseURL)/api/songs")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        if let keyword = keyword, !keyword.isEmpty {
            queryItems.append(URLQueryItem(name: "keyword", value: keyword))
        }
        if let artistId = artistId {
            queryItems.append(URLQueryItem(name: "artistId", value: "\(artistId)"))
        }
        if let ids = categoryItemIds, !ids.isEmpty {
            queryItems.append(URLQueryItem(name: "categoryItemIds", value: ids.map { "\($0)" }.joined(separator: ",")))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let result = try JSONDecoder().decode(SongsResponse.self, from: data)
        guard result.success, let data = result.data else {
            throw APIError.requestFailed("Failed to fetch songs")
        }
        return data
    }

    // MARK: - 歌手
    func fetchArtists() async throws -> [Artist] {
        let url = URL(string: "\(baseURL)/api/artists")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let result = try JSONDecoder().decode(ArtistsResponse.self, from: data)
        return result.data ?? []
    }

    // MARK: - 分类
    func fetchCategories() async throws -> [CategoryGroup] {
        let url = URL(string: "\(baseURL)/api/categories")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let result = try JSONDecoder().decode(CategoriesResponse.self, from: data)
        return result.data ?? []
    }

    // MARK: - 队列
    func fetchQueue() async throws -> [QueueItem] {
        let url = URL(string: "\(baseURL)/api/queue")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let result = try JSONDecoder().decode(QueueResponse.self, from: data)
        return result.data ?? []
    }

    func addToQueue(songId: Int) async throws {
        let url = URL(string: "\(baseURL)/api/queue")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["song_id": songId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }

    func removeFromQueue(itemId: Int) async throws {
        let url = URL(string: "\(baseURL)/api/queue/\(itemId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - 播放控制
    func playNext() async throws {
        try await sendPlayerCommand("next")
    }

    func playPrevious() async throws {
        try await sendPlayerCommand("previous")
    }

    func togglePlayPause() async throws {
        try await sendPlayerCommand("toggle")
    }

    func seek(position: Double) async throws {
        let url = URL(string: "\(baseURL)/api/player/seek")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["position": position]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }

    private func sendPlayerCommand(_ command: String) async throws {
        let url = URL(string: "\(baseURL)/api/player/\(command)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - 歌词
    func fetchLyrics(songId: Int) async throws -> String {
        let url = URL(string: "\(baseURL)/api/songs/\(songId)/lyrics")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - 流地址
    func streamURL(for song: Song, track: PlayerTrack = .original) -> URL? {
        var path = ""
        switch track {
        case .original:
            path = "/api/songs/\(song.id)/stream"
        case .vocals:
            path = "/api/songs/\(song.id)/vocals"
        case .instrumental:
            path = "/api/songs/\(song.id)/instrumental"
        }
        return URL(string: "\(baseURL)\(path)?token=\(token)")
    }
}

// MARK: - 错误类型
enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case loginFailed(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器响应无效"
        case .httpError(let code):
            return "HTTP错误: \(code)"
        case .loginFailed(let msg):
            return "登录失败: \(msg)"
        case .requestFailed(let msg):
            return msg
        }
    }
}

enum PlayerTrack {
    case original
    case vocals
    case instrumental
}
