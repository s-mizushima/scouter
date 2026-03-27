import Foundation

struct Feed: Codable, Identifiable {
    let id: UUID
    var name: String
    var url: String
    var isEnabled: Bool
    var language: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, url, language
        case isEnabled = "is_enabled"
        case createdAt = "created_at"
    }

    var needsTranslation: Bool {
        (language ?? "en") != "ja"
    }
}
