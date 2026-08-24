import Foundation

// MARK: - APIService
final class APIService {
    static let shared = APIService()

    private(set) var baseURL: String = ""
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    func setBaseURL(_ url: String) {
        let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        self.baseURL = cleaned.hasSuffix("/api") ? cleaned : "\(cleaned)/api"
    }

    // MARK: - Rooms
    func registerDevice(deviceId: String, name: String?, deviceInfo: String?) async throws -> Room {
        let body: [String: Any] = [
            "deviceId": deviceId,
            "name": name ?? "Apple TV",
            "deviceInfo": deviceInfo ?? "tvOS/iOS"
        ]
        let response: APIResponse<Room> = try await post("/rooms/register", body: body)
        guard let data = response.data else { throw APIError.noData }
        return data
    }

    func getRoom(code: String) async throws -> Room? {
        let response: APIResponse<Room> = try await get("/rooms/\(code)")
        return response.data
    }

    func getH5Url() async throws -> String {
        let response: APIResponse<[String: String]> = try await get("/rooms/h5-url")
        return response.data?["h5BaseUrl"] ?? ""
    }

    func issueJoinTicket(roomId: Int, deviceId: String, forceRotate: Bool = false) async throws -> RoomJoinTicket {
        let body: [String: Any] = [
            "deviceId": deviceId,
            "forceRotate": forceRotate
        ]
        let response: APIResponse<RoomJoinTicket> = try await post("/rooms/\(roomId)/join-ticket", body: body)
        guard let data = response.data else { throw APIError.noData }
        return data
    }

    func rotateCode(roomId: Int, deviceId: String) async throws -> Room {
        let body: [String: Any] = ["deviceId": deviceId]
        let response: APIResponse<Room> = try await post("/rooms/\(roomId)/rotate-code", body: body)
        guard let data = response.data else { throw APIError.noData }
        return data
    }

    func getQRCodeURL(data: String) -> URL? {
        let encoded = data.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? data
        return URL(string: "\(baseURL)/rooms/qrcode?data=\(encoded)")
    }

    // MARK: - Songs
    func getLyrics(songId: Int) async throws -> [LyricLine] {
        let response: APIResponse<AnyCodable> = try await get("/songs/\(songId)/lyrics")
        // Backend returns { lines, wordTiming } or array
        guard let data = response.data?.value as? [String: Any],
              let lines = data["lines"] as? [[String: Any]] else {
            if let array = response.data?.value as? [[String: Any]] {
                return array.compactMap { dict in
                    guard let time = dict["time"] as? Double,
                          let text = dict["text"] as? String else { return nil }
                    return LyricLine(time: time, text: text)
                }
            }
            return []
        }
        return lines.compactMap { dict in
            guard let time = dict["time"] as? Double,
                  let text = dict["text"] as? String else { return nil }
            return LyricLine(time: time, text: text)
        }
    }

    func getSongs(limit: Int = 50, offset: Int = 0) async throws -> [Song] {
        let response: APIResponse<[Song]> = try await get("/songs?limit=\(limit)&offset=\(offset)")
        return response.data ?? []
    }

    func searchSongs(query: String) async throws -> [Song] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let response: APIResponse<[Song]> = try await get("/songs/search?q=\(encoded)")
        return response.data ?? []
    }

    // MARK: - Queue
    func getQueue(roomId: Int) async throws -> [QueueListItem] {
        let response: APIResponse<[QueueListItem]> = try await get("/rooms/\(roomId)/queue")
        return response.data ?? []
    }

    // MARK: - Generic
    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - APIError
enum APIError: Error, LocalizedError {
    case invalidURL
    case noData
    case httpError(Int)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .noData: return "无数据返回"
        case .httpError(let code): return "HTTP 错误: \(code)"
        case .decodingError(let msg): return "数据解析错误: \(msg)"
        }
    }
}
