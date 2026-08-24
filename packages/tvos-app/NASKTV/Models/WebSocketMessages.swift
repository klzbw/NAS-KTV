import Foundation

// MARK: - WebSocket Message Types
enum WsMessageType: String, Codable {
    case ROOM_STATE_SNAPSHOT = "ROOM_STATE_SNAPSHOT"
    case QUEUE_UPDATED = "QUEUE_UPDATED"
    case PLAYER_STATE_UPDATED = "PLAYER_STATE_UPDATED"
    case ROOM_AUTHORIZED = "ROOM_AUTHORIZED"
    case ROOM_UNAUTHORIZED = "ROOM_UNAUTHORIZED"
    case ROOM_EXPIRING_SOON = "ROOM_EXPIRING_SOON"
    case ROOM_CLOSED = "ROOM_CLOSED"
    case PING = "PING"
    case PONG = "PONG"
    case ERROR = "ERROR"
}

// MARK: - WebSocket Message
struct WsMessage: Codable {
    let type: WsMessageType
    let payload: [String: AnyCodable]?
    let timestamp: Int64?
}

// MARK: - AnyCodable (for flexible payload)
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let string as String:
            try container.encode(string)
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Payload types
struct QueueUpdatedPayload: Codable {
    let queue: [QueueListItem]
    let queueVersion: Int?
}

struct RoomStateSnapshotPayload: Codable {
    let queue: [QueueListItem]
    let queueVersion: Int?
    let authorized: Bool
    let playerState: PlayerStatePayload?
}

struct RoomAuthorizedPayload: Codable {
    let roomCode: String
}

struct RoomUnauthorizedPayload: Codable {
    let reason: String?
}

struct RoomExpiringSoonPayload: Codable {
    let roomCode: String
    let expiresAt: String
}

struct RoomClosedPayload: Codable {
    let reason: String?
}
