import Foundation

struct Clip: Codable, Identifiable {
    let id: UUID
    let articleId: UUID
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case articleId = "article_id"
        case createdAt = "created_at"
    }
}
