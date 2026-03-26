import SwiftUI

struct ArticleListView: View {
    @StateObject private var viewModel = ArticleListViewModel()
    @State private var showSettings = false
    @State private var selectedArticle: ArticleWithFeed?
    @State private var dragOffset: CGFloat = 0
    @State private var dateId = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dateNavigationBar
                Divider()

                // Article content with drag-to-swipe
                GeometryReader { geo in
                    ZStack {
                        articleContent
                            .id(dateId)
                            .offset(x: dragOffset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                let threshold = geo.size.width * 0.25
                                let velocity = value.predictedEndTranslation.width

                                if value.translation.width > threshold || velocity > 300 {
                                    // Swipe right → previous day
                                    swipeOut(direction: .right, screenWidth: geo.size.width) {
                                        viewModel.goToPreviousDay()
                                    }
                                } else if value.translation.width < -threshold || velocity < -300 {
                                    // Swipe left → next day
                                    swipeOut(direction: .left, screenWidth: geo.size.width) {
                                        viewModel.goToNextDay()
                                    }
                                } else {
                                    // Snap back
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                FeedSettingsView()
                    .onDisappear {
                        Task { await viewModel.loadArticles() }
                    }
            }
            .sheet(item: $selectedArticle) { item in
                NavigationStack {
                    ArticleWebView(url: URL(string: item.article.articleUrl)!)
                        .navigationTitle(item.article.displayTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("閉じる") {
                                    selectedArticle = nil
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                ShareLink(item: URL(string: item.article.articleUrl)!) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                }
            }
            .task {
                await viewModel.loadArticles()
            }
        }
    }

    // MARK: - Swipe Animation

    private enum SwipeDirection { case left, right }

    private func swipeOut(direction: SwipeDirection, screenWidth: CGFloat, then action: @escaping () -> Void) {
        let exitX: CGFloat = direction == .right ? screenWidth : -screenWidth
        let enterX: CGFloat = direction == .right ? -screenWidth : screenWidth

        // 1. Slide current content off screen
        withAnimation(.easeIn(duration: 0.2)) {
            dragOffset = exitX
        }

        // 2. After exit, change date, reposition off-screen on opposite side, then slide in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            action()
            dateId = UUID()
            dragOffset = enterX

            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                dragOffset = 0
            }
        }
    }

    // MARK: - Article Content

    @ViewBuilder
    private var articleContent: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.articles.isEmpty {
            emptyStateView
        } else {
            articleList
        }
    }

    // MARK: - Date Navigation

    private var dateNavigationBar: some View {
        HStack {
            Button {
                swipeOut(direction: .right, screenWidth: UIScreen.main.bounds.width) {
                    viewModel.goToPreviousDay()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .padding(.horizontal, 12)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.dateDisplayText)
                    .font(.headline)
                Text(viewModel.relativeDateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                swipeOut(direction: .left, screenWidth: UIScreen.main.bounds.width) {
                    viewModel.goToNextDay()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Article List

    private var articleList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let first = viewModel.articles.first {
                    largeArticleCard(first)
                        .onTapGesture { selectedArticle = first }
                }

                ForEach(Array(viewModel.articles.dropFirst())) { item in
                    compactArticleCard(item)
                        .onTapGesture { selectedArticle = item }
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.loadArticles()
        }
    }

    // MARK: - Large Card

    private func largeArticleCard(_ item: ArticleWithFeed) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageUrl = item.article.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(height: 180).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(height: 180)
                            .overlay { Image(systemName: "newspaper").font(.largeTitle).foregroundStyle(.secondary) }
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 180)
                    .overlay {
                        Image(systemName: "newspaper")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }

            HStack {
                Text(item.feedName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())

                Spacer()

                if let date = item.article.publishedAt {
                    Text(timeString(from: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(item.article.displayTitle)
                .font(.headline)
                .lineLimit(3)

            if !item.article.displaySummary.isEmpty {
                Text(item.article.displaySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    // MARK: - Compact Card

    private func compactArticleCard(_ item: ArticleWithFeed) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let imageUrl = item.article.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 80, height: 80)
                            .overlay { Image(systemName: "doc.text").foregroundStyle(.secondary) }
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.feedName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())

                    Spacer()

                    if let date = item.article.publishedAt {
                        Text(timeString(from: date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.article.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if !item.article.displaySummary.isEmpty {
                    Text(item.article.displaySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("この日の記事はありません")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("左右にスワイプして別の日を見てみましょう")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
