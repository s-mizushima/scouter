import Foundation
import Supabase

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }

    // MARK: - Articles

    func fetchArticles(for date: Date, enabledFeedIds: [UUID]) async throws -> [Article] {
        let calendar = Calendar(identifier: .gregorian)
        var jstCalendar = calendar
        jstCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let startOfDay = jstCalendar.startOfDay(for: date)
        let endOfDay = jstCalendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let startStr = isoFormatter.string(from: startOfDay)
        let endStr = isoFormatter.string(from: endOfDay)

        if enabledFeedIds.isEmpty {
            return []
        }

        let feedIdStrings = enabledFeedIds.map { $0.uuidString.lowercased() }

        let articles: [Article] = try await client
            .from("articles")
            .select()
            .gte("published_at", value: startStr)
            .lt("published_at", value: endStr)
            .in("feed_id", values: feedIdStrings)
            .order("published_at", ascending: false)
            .execute()
            .value

        return articles
    }

    // MARK: - Feeds

    func fetchFeeds() async throws -> [Feed] {
        let feeds: [Feed] = try await client
            .from("feeds")
            .select()
            .order("created_at", ascending: true)
            .execute()
            .value

        return feeds
    }

    func updateFeedEnabled(id: UUID, isEnabled: Bool) async throws {
        try await client
            .from("feeds")
            .update(["is_enabled": isEnabled])
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    func deleteFeed(id: UUID) async throws {
        try await client
            .from("feeds")
            .delete()
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    // MARK: - Clips

    func fetchClips() async throws -> [Clip] {
        let clips: [Clip] = try await client
            .from("clips")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
        return clips
    }

    func fetchClippedArticleIds() async throws -> Set<UUID> {
        let clips: [Clip] = try await client
            .from("clips")
            .select("id, article_id, created_at")
            .execute()
            .value
        return Set(clips.map(\.articleId))
    }

    func addClip(articleId: UUID) async throws {
        try await client
            .from("clips")
            .insert(["article_id": articleId.uuidString.lowercased()])
            .execute()
    }

    func removeClip(articleId: UUID) async throws {
        try await client
            .from("clips")
            .delete()
            .eq("article_id", value: articleId.uuidString.lowercased())
            .execute()
    }

    func fetchClippedArticles() async throws -> [Article] {
        let clips: [Clip] = try await client
            .from("clips")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value

        if clips.isEmpty { return [] }

        let articleIds = clips.map { $0.articleId.uuidString.lowercased() }
        let articles: [Article] = try await client
            .from("articles")
            .select()
            .in("id", values: articleIds)
            .execute()
            .value

        // Maintain clip order
        let articleMap = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        return clips.compactMap { articleMap[$0.articleId] }
    }

    // MARK: - Feeds

    func updateFeedLanguage(id: UUID, language: String) async throws {
        try await client
            .from("feeds")
            .update(["language": language])
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    func addFeed(name: String, url: String, language: String) async throws {
        try await client
            .from("feeds")
            .insert(["name": name, "url": url, "language": language])
            .execute()
    }
}
