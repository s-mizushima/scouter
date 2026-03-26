import Foundation

struct Article: Codable, Identifiable {
    let id: UUID
    let feedId: UUID
    let titleOriginal: String?
    let titleJa: String?
    let summaryOriginal: String?
    let summaryJa: String?
    let articleUrl: String
    let imageUrl: String?
    let publishedAt: Date?
    let fetchedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case feedId = "feed_id"
        case titleOriginal = "title_original"
        case titleJa = "title_ja"
        case summaryOriginal = "summary_original"
        case summaryJa = "summary_ja"
        case articleUrl = "article_url"
        case imageUrl = "image_url"
        case publishedAt = "published_at"
        case fetchedAt = "fetched_at"
    }

    var displayTitle: String {
        titleJa ?? titleOriginal ?? "No Title"
    }

    var displaySummary: String {
        summaryJa ?? summaryOriginal ?? ""
    }
}

struct ArticleWithFeed: Identifiable {
    let article: Article
    let feedName: String

    var id: UUID { article.id }
}
