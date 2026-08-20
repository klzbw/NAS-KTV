import Foundation

struct Artist: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let coverUrl: String?
    let songCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case coverUrl = "cover_url"
        case songCount = "song_count"
    }
}

struct ArtistsResponse: Codable {
    let success: Bool
    let data: [Artist]?
}
