import Foundation

struct Song: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let artistId: Int?
    let artistName: String?
    let album: String?
    let duration: Int?
    let filePath: String?
    let coverUrl: String?
    let lyricsPath: String?
    let vocalsPath: String?
    let instrumentalPath: String?
    let separationStatus: String?
    let language: String?
    let year: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, album, duration, filePath, coverUrl, lyricsPath
        case vocalsPath, instrumentalPath, separationStatus, language, year, createdAt
        case artistId = "artist_id"
        case artistName = "artist_name"
    }

    var durationText: String {
        guard let duration = duration else { return "--:--" }
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var hasSeparation: Bool {
        vocalsPath != nil && instrumentalPath != nil
    }

    var streamUrl: String? {
        guard let filePath = filePath else { return nil }
        return "/api/songs/\(id)/stream"
    }

    var vocalsStreamUrl: String? {
        guard vocalsPath != nil else { return nil }
        return "/api/songs/\(id)/vocals"
    }

    var instrumentalStreamUrl: String? {
        guard instrumentalPath != nil else { return nil }
        return "/api/songs/\(id)/instrumental"
    }
}

// MARK: - 歌曲列表响应
struct SongsResponse: Codable {
    let success: Bool
    let data: SongsData?
}

struct SongsData: Codable {
    let items: [Song]
    let total: Int
    let page: Int
    let pageSize: Int
}
