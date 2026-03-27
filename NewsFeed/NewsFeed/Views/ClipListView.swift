import SwiftUI

struct ClipListView: View {
    @StateObject private var viewModel = ClipListViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedArticle: ArticleWithFeed?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.articles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("クリップした記事はありません")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.articles) { item in
                            Button {
                                selectedArticle = item
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.feedName)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(Capsule())

                                    Text(item.article.displayTitle)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)

                                    if !item.article.displaySummary.isEmpty {
                                        Text(item.article.displaySummary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let article = viewModel.articles[index].article
                                Task { await viewModel.removeClip(article) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("クリップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(item: $selectedArticle) { item in
                NavigationStack {
                    ArticleWebView(url: URL(string: item.article.articleUrl)!, needsTranslation: item.needsTranslation)
                        .navigationTitle(item.article.displayTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("閉じる") { selectedArticle = nil }
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
                await viewModel.loadClips()
            }
        }
    }
}
