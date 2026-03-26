import Foundation

struct Feed: Codable, Identifiable {
    let id: UUID
    var name: String
    var url: String
    var isEnabled: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, url
        case isEnabled = "is_enabled"
        case createdAt = "created_at"
    }
}
