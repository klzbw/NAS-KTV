import Foundation

struct CategoryGroup: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let items: [CategoryItem]
}

struct CategoryItem: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let songCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case songCount = "song_count"
    }
}

struct CategoriesResponse: Codable {
    let success: Bool
    let data: [CategoryGroup]?
}
