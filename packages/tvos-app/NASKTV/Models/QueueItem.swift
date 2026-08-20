import Foundation

struct QueueItem: Identifiable, Codable, Hashable {
    let id: Int
    let songId: Int
    let song: Song?
    let status: String
    let addedBy: String?
    let addedAt: String?
    let position: Int?

    enum CodingKeys: String, CodingKey {
        case id, song, status, position
        case songId = "song_id"
        case addedBy = "added_by"
        case addedAt = "added_at"
    }

    var isPlaying: Bool {
        status == "playing"
    }

    var isPending: Bool {
        status == "pending"
    }
}

struct QueueResponse: Codable {
    let success: Bool
    let data: [QueueItem]?
}

// MARK: - WebSocket 消息
struct WSMessage: Codable {
    let type: String
    let data: WSMessageData?
}

struct WSMessageData: Codable {
    let songId: Int?
    let queue: [QueueItem]?
    let position: Double?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case queue, position, status
    }
}
