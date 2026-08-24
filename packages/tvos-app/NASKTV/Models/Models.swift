import Foundation

// MARK: - Room
struct Room: Codable, Identifiable {
    let id: Int
    let code: String
    let deviceId: String
    let name: String?
    let authorized: Int
    let status: String
    let expiresAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, code, deviceId, name, authorized, status
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    var isAuthorized: Bool { authorized == 1 && status == "active" }
}

// MARK: - RoomJoinTicket
struct RoomJoinTicket: Codable {
    let authorizationCode: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case expiresAt = "expires_at"
    }
}

// MARK: - Song
struct Song: Codable, Identifiable {
    let id: Int
    let title: String
    let artist: String?
    let album: String?
    let duration: Int?
    let filePath: String?
    let coverPath: String?
    let hasVocals: Int?
    let hasInstrumental: Int?
    let language: String?
    let year: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, duration
        case filePath = "file_path"
        case coverPath = "cover_path"
        case hasVocals = "has_vocals"
        case hasInstrumental = "has_instrumental"
        case language, year
    }
}

// MARK: - Artist
struct Artist: Codable, Identifiable {
    let id: Int
    let name: String
    let songCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case songCount = "song_count"
    }
}

// MARK: - Category
struct Category: Codable, Identifiable {
    let id: Int
    let name: String
    let songCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case songCount = "song_count"
    }
}

// MARK: - QueueListItem
struct QueueListItem: Codable, Identifiable {
    let id: Int
    let songId: Int
    let songTitle: String
    let songArtist: String?
    let status: String
    let addedBy: String?
    let addedAt: String?
    let position: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case songId = "song_id"
        case songTitle = "song_title"
        case songArtist = "song_artist"
        case status
        case addedBy = "added_by"
        case addedAt = "added_at"
        case position
    }

    var isPlaying: Bool { status == "playing" }
}

// MARK: - PlayerState
struct PlayerStatePayload: Codable {
    let status: String?
    let currentTime: Double?
    let duration: Double?
    let volume: Float?
    let track: String?

    enum CodingKeys: String, CodingKey {
        case status
        case currentTime = "current_time"
        case duration
        case volume
        case track
    }
}

// MARK: - LyricLine
struct LyricLine: Codable, Identifiable {
    let id = UUID()
    let time: Double
    let text: String

    enum CodingKeys: String, CodingKey {
        case time, text
    }
}

// MARK: - ServerConfig
struct ServerConfig: Codable, Equatable {
    var apiUrl: String
    var wsUrl: String

    static let `default` = ServerConfig(apiUrl: "", wsUrl: "")
}

// MARK: - API Response wrapper
struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let message: String?
}
