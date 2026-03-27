import Foundation

@MainActor
final class ClipListViewModel: ObservableObject {
    @Published var articles: [ArticleWithFeed] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadClips() async {
        isLoading = true
        errorMessage = nil

        do {
            let feeds = try await SupabaseService.shared.fetchFeeds()
            let feedMap = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
            let clippedArticles = try await SupabaseService.shared.fetchClippedArticles()

            articles = clippedArticles.map { article in
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

    func removeClip(_ article: Article) async {
        do {
            try await SupabaseService.shared.removeClip(articleId: article.id)
            articles.removeAll { $0.article.id == article.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
