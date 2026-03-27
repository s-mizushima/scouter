import Foundation

@MainActor
final class FeedSettingsViewModel: ObservableObject {
    @Published var feeds: [Feed] = []
    @Published var isLoading = false
    @Published var newFeedName = ""
    @Published var newFeedURL = ""
    @Published var newFeedTranslate = true
    @Published var errorMessage: String?

    func loadFeeds() async {
        isLoading = true
        do {
            feeds = try await SupabaseService.shared.fetchFeeds()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func toggleFeed(_ feed: Feed) async {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        let newValue = !feeds[index].isEnabled
        feeds[index].isEnabled = newValue

        do {
            try await SupabaseService.shared.updateFeedEnabled(id: feed.id, isEnabled: newValue)
        } catch {
            feeds[index].isEnabled = !newValue
            errorMessage = error.localizedDescription
        }
    }

    func toggleTranslation(_ feed: Feed) async {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        let wasJa = (feeds[index].language ?? "en") == "ja"
        let newLang = wasJa ? "en" : "ja"
        feeds[index].language = newLang

        do {
            try await SupabaseService.shared.updateFeedLanguage(id: feed.id, language: newLang)
        } catch {
            feeds[index].language = wasJa ? "ja" : "en"
            errorMessage = error.localizedDescription
        }
    }

    func deleteFeed(_ feed: Feed) async {
        do {
            try await SupabaseService.shared.deleteFeed(id: feed.id)
            feeds.removeAll { $0.id == feed.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addFeed() async {
        let name = newFeedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = newFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty else { return }

        do {
            try await SupabaseService.shared.addFeed(name: name, url: url, language: newFeedTranslate ? "en" : "ja")
            newFeedName = ""
            newFeedURL = ""
            newFeedTranslate = true
            await loadFeeds()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
