import Foundation
import SwiftUI

@MainActor
final class ArticleListViewModel: ObservableObject {
    @Published var articles: [ArticleWithFeed] = []
    @Published var isLoading = false
    @Published var selectedDate: Date = Date()
    @Published var errorMessage: String?
    @Published var clippedArticleIds: Set<UUID> = []

    private var feeds: [Feed] = []

    private var jstCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        cal.locale = Locale(identifier: "ja_JP")
        return cal
    }

    var dateDisplayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "M月d日（E）"
        return formatter.string(from: selectedDate)
    }

    var relativeDateText: String {
        let today = jstCalendar.startOfDay(for: Date())
        let selected = jstCalendar.startOfDay(for: selectedDate)
        let diff = jstCalendar.dateComponents([.day], from: selected, to: today).day ?? 0

        switch diff {
        case 0: return "今日"
        case 1: return "昨日"
        default: return "\(diff)日前"
        }
    }

    func goToPreviousDay() {
        selectedDate = jstCalendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        Task { await loadArticles() }
    }

    func goToNextDay() {
        let today = jstCalendar.startOfDay(for: Date())
        let selected = jstCalendar.startOfDay(for: selectedDate)
        guard selected < today else { return }
        selectedDate = jstCalendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        Task { await loadArticles() }
    }

    func loadArticles() async {
        isLoading = true
        errorMessage = nil

        do {
            feeds = try await SupabaseService.shared.fetchFeeds()
            let enabledFeedIds = feeds.filter(\.isEnabled).map(\.id)
            let fetchedArticles = try await SupabaseService.shared.fetchArticles(
                for: selectedDate,
                enabledFeedIds: enabledFeedIds
            )

            let feedMap = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
            articles = fetchedArticles.map { article in
                let feed = feedMap[article.feedId]
                return ArticleWithFeed(
                    article: article,
                    feedName: feed?.name ?? "Unknown",
                    needsTranslation: feed?.needsTranslation ?? true
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadClipIds() async {
        do {
            clippedArticleIds = try await SupabaseService.shared.fetchClippedArticleIds()
        } catch {
            print("Failed to load clips: \(error)")
        }
    }

    func toggleClip(articleId: UUID) async {
        let isClipped = clippedArticleIds.contains(articleId)
        do {
            if isClipped {
                try await SupabaseService.shared.removeClip(articleId: articleId)
                clippedArticleIds.remove(articleId)
            } else {
                try await SupabaseService.shared.addClip(articleId: articleId)
                clippedArticleIds.insert(articleId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
